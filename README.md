# OpenCruise — Linux デスクトップ向け Android Auto プレイヤー

車載ディスプレイやホームサーバー向けの Android Auto 機能を、Qt6 + C++ で Linux デスクトップで実装するアプリケーション。スマホの Android Auto を Linux マルチメディアプレーヤーとして動作させます。

- **プラットフォーム**: Linux（Ubuntu / Debian / Yocto）が主目標。Windows/MacOS も対応可能（ALSA は OS に依存）。
- **メイン言語**: C++17 + Qt6（QML 主体）。
- **ライブラリ・依存**: AASDK（Android Auto SDK）、libusb-1.0、Boost、Protobuf、OpenSSL、H.264 デコーダー。

## プロジェクト概要

OpenCruise は Android Auto を Linux で動かす「車載ディスプレイ・マルチメディアプレーヤー」を目指します。同梱した **AASDK**（Android Auto SDK）を USB 接続層として利用し、スマホの映像・音声・車両データ・通話・通知などを Linux デスクトップで制御・表示します。

- **Android Auto 接続**: スマホの Android Auto と「接続」して H.264 映像・PCM 音声・車両情報・ナビゲーション・通話・バッテリー状態を受け取り、QML UI で制御。
- **車両データ**: 速度・回転数・燃料・ギア・位置などを実車の ECU（K-Line）から取得するほか、モックデータのダミー送信も可能。
- **UI 構成**: QML ウィジェットシステムで現在地・車両情報・ナビゲーション・スマホ状態（通話/通知/再生曲）などをホーム画面に配置表示。
- **起動画面管理**: フォント読み込み / 音声設定 / AA 接続待ちなどを BootManager で進捗管理（GUI の起動画面に表示）。
- **終了処理**: ShutdownManager で電源オフ時の処理順を制御（設定保存 → AA 切断 → ドア解除 → 電源プロファイル復元）。
- **DRM/外部出力**: eglfs を経由で DRM/KMS 機器への外部モニターミラー可能。
- **音声直接出力**: ALSA を使うと PulseAudio/PipeWire を通さず直接音出し・録音（Windows/MacOS では Qt 音声用）。

## プロジェクト構成

```
OpenCruiseTest2ForAI/
├── CMakeLists.txt           # 頂上ビルド：aasdk と app/ をサブプロジェクトとしてビルド
├── aasdk/                   # Android Auto SDK リポジトリ（同梱ライブラリ）
│   ├── CMakeLists.txt       # Protobuf / Boost / OpenSSL / libusb の依存、クロスコンパイル対応
│   ├── include/aasdk/       # 公開ヘッダ（AASDK:: namespace）
│   └── src/                  # AASDK 実装（Android Auto プラットフォームへ接続・データ受け取り）
│       ├── AasdkBackend.*    # USB ホットプラグ検出・io スレッド・待機→接続→切断→待機ループ
│       ├── AasdkSession.*    # 単一セッション。制御チャネル (バージョン/SSL/認証/サービス探索/Ping)
│       ├── AasdkVideoHandler.*  # 映像チャネル (Open/Setup/Start/データ受信/ACK/フォーカス)
│       ├── AasdkSensorHandler.* # センサーチャネル（車両情報）
│       ├── AasdkInputHandler.*  # 入力チャネル（タッチ操作転送）
│       └── ...               # Microphone / PhoneStatus / SystemAudio など
├── app/                     # OpenCruise アプリ本体
│   ├── CMakeLists.txt       # Qt6 + aasdk の依存指定、ソース・QML・リソースの登録
│   ├── src/                 # アプリ実装（メインループ・設定管理・接続層・車両データ）
│   │   ├── main.cpp         # 起動・オプション処理・QML ロード・開発用コマンド
│   │   ├── core/            # アプリ基盤：AppInfo / AppSettings / BootManager / Log / UiText
│   │   ├── aabackend/       # Qt 非依存の aasdk 接続層（UI と分離。無効時はスタブ）
│   │   ├── androidauto/     # Qt 側：AndroidAutoController / H264Decoder / VideoSurfaceItem
│   │   ├── audio/           # 音：AudioSettings / SystemSound / (AlsaAudio)
│   │   ├── display/         # 画面：BrightnessController / DisplaySettings / DrmDisplay
│   │   ├── ui/              # UI 支援：ThemeSettings / WidgetStore / ClockModel
│   │   ├── vehicle/         # 車両：VehicleDataManager / EcuData / ReverseCamera
│   │   ├── system/          # SystemStats / ShutdownManager / UpdateManager / WifiManager
│   │   ├── notification/     # NotificationManager / NotificationHistoryModel
│   │   └── ...              # PhoneStatus / AlbumArtProvider など
│   ├── qml/                 # QML（1 つのモジュール OpenCruise。他フォルダの型使う場合は `import OpenCruise`）
│   │   ├── Main.qml         # ルート画面（暗色・時計・AA 接続状態表示・CAN データパネル）
│   │   ├── theme/           # Theme(シングルトン) / ThemeBackground
│   │   ├── screens/         # 画面：HomeScreen / SettingsScreen / VehicleScreen / SplashScreen
│   │   ├── settings/        # 設定の部品（Settings* / WSStepper / WSTextField）と各ページ
│   │   ├── widgets/         # ウィジェット（配置・設定・データモデル）
│   │   ├── osd/             # OSD（音量・明るさ）・通知（Popup / HistoryPanel）
│   │   ├── services/        # 画面を持たないシングルトン：VehicleHistory / WarningAlarm
│   │   └── components/      # 共通部品（Panel / ActionButton / MaterialIcon / GaugeWidget など）
│   └── resources/           # フォント / 効果音 / DTC リスト（実行時コピー・qrc 埋め込み）
├── docs/                    # ドキュメント・設計メモ・スクリーンショット・調査データ
├── patches/                 # aasdk や OS 向け修正の diff ファイル
├── scripts/                 # インストーラー / テスト映像生成 / Plymouth 起動画面作成
└── yocto/                   # Yocto 向けビルド設定
```

## まとめに入れる（インストーラー）

Debian/Ubuntu 系で、パッケージ・ビルド・権限・タッチパネル・音・起動画面などをウィザード形式でまとめて入れる。

```bash
sudo scripts/install.sh          # 入れるものを選んで質問に答えて、最後にまとめて入れる
sudo scripts/install.sh --check  # 権限などの状態を確かめるだけ（何も変えない）
sudo scripts/install.sh --uninstall   # このインストーラーが入れた設定を外す
```

| 項目 | 内容 |
|---|---|
| **パッケージ** | ビルド・実行に要るもの（その Debian にないものは飛ばして知らせる） |
| **ビルド** | `build/app/opencruise`（Android Auto の接続を含めるか選べる） |
| **権限** | グループ (video/render/input/audio/plugdev/dialout)、電源を切る・再起動・電源モードをパスワードなしで (polkit)、バックライトへの書き込み (udev)、蓋を閉じても・放っておいてもスリープしない (logind) |
| **Android Auto** | スマホを USB で開ける権限 (udev)。主なメーカーだけ / すべての USB 機器。無いと aasdk は黙って無視し「待機中」のまま |
| **タッチパネル** | 向きの補正（回転・反転。libinput の補正を udev で入れる）と、触って試す |
| **音** | audio グループ、PipeWire / PulseAudio を止める (ALSA を直接使うため)、音を出して試す |
| **起動画面** | `scripts/bootsplash/install.sh`（自動起動・メッセージを隠す・起動中の明るさを選べる） |
| **CF-MX5** | AC を挿したら起動する (`scripts/cf-mx5/install-afterg3.sh`。CF-MX5 のときだけ出る) |

入れたものは `/etc/opencruise/install.state`、ログは `/var/log/opencruise-install.log`。グループは次のログイン（自動起動ならアプリの次の起動）から効く。
`--yes` で質問せずにおすすめの内容を入れる、`--no-tui` でダイアログを使わず文字だけで進める、`--user <名前>` でアプリを動かすユーザーを決める。

## ビルド条件

Ubuntu 24.04 で確認。必要パッケージ：

```bash
sudo apt install build-essential cmake ninja-build pkg-config \
  qt6-base-dev qt6-declarative-dev qml6-module-qtquick qml6-module-qtquick-controls \
  qml6-module-qtquick-layouts qml6-module-qtquick-window qml6-module-qtquick-templates \
  qml6-module-qtqml qml6-module-qtqml-workerscript qml6-module-qtmultimedia \
  qt6-multimedia-dev libopenh264-dev \
  libboost-system-dev libboost-log-dev libprotobuf-dev protobuf-compiler libusb-1.0-0-dev libssl-dev \
  libasound2-dev fonts-noto-cjk
```

CMake：

```bash
cmake -G Ninja -S . -B build \
  -DOPENCRUISE_ENABLE_AASDK=ON \
  -DCMAKE_BUILD_TYPE=Release
ninja -C build              # aasdk(約 300 ファイル)を含むため初回は数分〜十数分

# aasdk なしで UI だけビルド:
cmake ... -DOPENCRUISE_ENABLE_AASDK=OFF \
  naga...
./build/app/opencruise
```

- **aasdk オプション**: `SKIP_BUILD_PROTOBUF=ON` / `SKIP_BUILD_ABSL=ON`（システムの protobuf / Abseil を使用）。
- **ALSA**: `-DOPENCRUISE_ENABLE_ALSA=OFF` で Windows/MacOS でもビルド可（Qt 音声入出力用）。
- **DRM/KMS**: `pkg_check_modules(LIBDRM ...)` で自動検出。
- **クロスコンパイル**: Yocto 向けには `coreboot/`, `yocto/` の設定を参照、ARM アーキテクチャ対応。

### 開発用オプション

| オプション | 内容 |
|---|---|
| `--test-video <file>` | H.264 ファイルを映像として表示（スマホ無しでデコード/表示を確認）。`scripts/make_test_stream.sh` で生成 |
| `--screenshot <png> [--screenshot-delay <ms>]` | 画面を保存して終了 |
| `--open-settings` | 設定画面を開いた状態で起動 |
| `--fullscreen` | 全画面 |
| `--skip-boot` | 起動（オープニング）画面を出さずに起動 |
| `--log-dir <path>` / `--log-level <level>` | ログの保存先と最小レベル指定 |
| `--export-splash <dir>` | Linux の Plymouth 起動画面用画像を書き出して終了 |

ヘッドレス確認例：`QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software ./build/app/opencruise --screenshot out.png`

## 音量・明るさの設定とショートカット

設定の「音 > 音量・出力先」「表示と操作 > 画面」から変更できるほか、キーボードショートカットで操作可能。画面端の物理ボタン（OSD）でも操作可能。

### キーボードショートカット

| ショートカット | 内容 |
|---|---|
| `Ctrl+Shift+V` / `Ctrl+Shift+B` | マスター音量を 5 % 下げる / 上げる（押しっぱなしで連続）。音量バー表示、約 2.5 秒で閉じる |
| `Ctrl+Shift+K` / `Ctrl+Shift+L` | 画面の明るさを 10 % 下げる / 上げる。現在値バー表示、約 2 秒で閉じる |

### マスター音量 (`audio/AudioSettings`)

- 3 つの音声系統（マップ・音楽・システム）すべてに掛かる共通倍率 (0〜100 %)。
- 各系統の個別音量の設定値は変えずに保持する。再生器へ渡す値は「個別 × マスター」で合成。
- 保存キー：`audio/masterVolume`

### 画面の明るさ (`display/BrightnessController`)

- 10〜100 % (0 にすると画面が見えなくなる)。保存キー：`display/brightness`。
- Linux で `/sys/class/backlight/*/brightness` へ書き込める場合は、バックライトを直接制御。
- 書き込めない場合（Windows/権限なし）は、黒い暗幕で暗くする方式に自動切り替え。
- バックライト制御にはそのファイルへの書き込み権限が必要（udev で許可可能）。

## テーマと背景

設定「表示と操作 > テーマ・背景」でアプリ全体の見た目を選べる (`ui/ThemeSettings`)。

| テーマ | 内容 |
|---|---|
| **シンプル** | これまでの見た目（平らな面・大きめの角丸・青のアクセント） |
| **クラシック** | 2000 年代車の内装に合う見た目。ガンメタ (夜)/シルバー(昼)の面に、ゆるいグラデーションと内側の細いハイライト、小さめの角丸。アンバー・赤・青・緑・アイボリー・シエンなど。 |

### 背景画像

- テーマに合わせる（シンプルは無地 / クラシックはカーボン）／無地／模様（カーボン・ヘアライン・パンチング・ストライプ）／画像。
- `~/.local/share/OpenCruise/backgrounds` に PNG/JPEG を置くと選べる（並べ方：並べる・画面を埋める・引き伸ばし）。濃さも変えられる。
- **USB メモリから取り込み** (`ui/ImageImporter`)：「設定 > 表示と操作 > テーマ・背景」のチェックで有効。USB メモリは読み取り専用でつなぐ（`opencruise-usb-mount`）。更新時はコピーになるため「移動」不可。
- 1 枚最大 32 MB・縦横 8192 px。本体の空きが 256 MB を下回る取り込みはしない。

### 飾りの画像 (Decoration)

初期画面（ウィジェット配置エリア）ごとに、好きな画像を好きな場所へ置く（ウィジェットの後ろ・パネルの上・前、ステータスバーやナビバーの上）。

| 操作 | 内容 |
|---|---|
| **追加** | `~/.local/share/OpenCruise/decorations` に PNG/JPEG/WebP/GIF を置く。初期画面「編集」→「画像を追加」で選ぶ（現在のページの中央に置かれる） |
| **移動・配置調整** | ドラッグで移動。大きさは右下のつまみか 2 本指でつまむ。 |
| **操作パネル** | 選ぶと濃さ・反転・重ね方・位置・複製・削除等操作が出る。 |
| **重ね方** | 奥（ウィジェット/バーの後ろ）／パネル（WidgetBase の中）／手前（タッチは通す）。「パネル」層ではパネルの形に切り抜かれる。 |

配置と設定は `QSettings` (`widgets/layout`) に保存（画面サイズ変化しても同じ位置）。画像が見つからない場合は編集中だけ赤い枠で表示。Android Auto 画面には出ない。

## バックカメラ

バック信号が入ると、どの画面でもカメラ映像（全面）に切り替わり、切れると設定秒数後に元の画面に戻る (`vehicle/ReverseCamera`)。

| 機能 | 内容 |
|---|---|
| **バック信号** | 今はダミー（`Ctrl+Shift+R` か設定でオンオフ）。将来的な外部マイコンからの入力も可能（通信未実装） |
| **カメラ** | Qt Multimedia による V4L2/USB カメラ設定。1280x720 以下の最大解像度・高フレームレートを優先選出 |
| **映し方** | 左右反転・ガイド線（距離の目安）・画面埋め込み・即映像モード |
| **表示内容** | 左上にギア表示 (R・バック)、上に「周囲の安全を直接確認してください」 |
| **実行要件** | `qml6-module-qtmultimedia`。ログは `[CAMERA]` |

## 車両データと ECU 診断情報

車両のデータはノード別に届くが、画面・メーター・グラフ・警告では 1 つの車両データとして扱う (`qml/services/VehicleSignals.qml`)。分類：走行・エンジン・燃料・吸気・スロットル・排気・EVAP・電装。

### データ元選択

| データ項目 | VIN/SEN | DIAG(ECU) | 選択方法 |
|---|---|---|---|
| **車速** | ヨット（既定） | 車両信号優先 / ECU 優先 / 双方のみ / ECU のみ | 「設定 > 車両 > 車両データ」で項目ごとに選べる |
| **回転数** | 車両信号優先 | 同上 | 項目ごとの選択・すべての項目をまとめて上書き可能 (`ecu.sourceOverride`) |
| **水温・電圧・アクセル** | ヨット | 同上 | 同上 |

- **値の表示**: どのノードから来たか（VIN / SEN / ECU）を示す小さな印が車両画面に。
- **メーター**: ウィジェット追加で車両ジャンルで絞り込み。隠せる項目あり。針のなめらかさは 120ms/340ms に追従、オフも可能。

### 故障コード (DTC)

| 機能 | 内容 |
|---|---|
| **表示** | 車両メニューの「故障コード」で現在・過去を分けて一覧（日本語説明）。消去はしない。 |
| **情報** | 状態バイトからの推定（ビット 6〜5=現在/過去、チェックランプ=2100 位置 7 のビット 7）※実車で未確認 |
| **ルール** | 「車両異常」分類で警告・注意を出し、音也奏する。説明は `resources/data/suzuki_dtc_list.csv`（スズキの日本語訳）。 |

### データダミーモード

現時点では VIN/SEN/DIAG はすべてダミー（`VehicleDataManager` / `EcuData` はモック車両データの動きから応答を作る）。「設定 > 車両 > 車両データ」で「なし」「過去のみ」「現在・過去あり」を選べる。

## ウィジェットシステム

初期画面の中央領域は 12×6 マスの配置エリア（時計・あいさつもその中）。

| 操作 | 内容 |
|---|---|
| **ドラッグ移動** | 長押し→ドラッグで持ち上げて移動。空きマスのない場合は元の位置に戻る。 |
| **ダブルタップ** | 設定画面を持つウィジェットは設定ダイアログを開く（固有設定＋サイズ＋削除）。 |
| **編集モード** | ナビバーの「編集」で進入。上・下へページ切り替え、選択・まとめて設定・削除・追加操作可能。 |

### ウィジェットリスト (`app/qml/widgets/`)

| カテゴリ | ウィジェット | 機能 |
|---|---|---|
| **framework/** | `WidgetRegistry` | 新しいウィジェットの登録（ジャンル・種類・既定サイズ/設定） |
| **framework/** | `WidgetBase`, `WidgetHost` | 共通基盤（ドラッグ・スナップ・タップ振り分け） |
| **framework/** | `WidgetArea`, `WidgetPages` | グリッド配置、ページ切り替え |
| **gauge/** | `GaugeWidget`, `GraphWidget` | タコメーター・水温計・速度メーターなど。モックデータ |
| **phonestatus/** | `PhoneStatusWidget` | バッテリー残量（実データ）、電波強度（モック） |
| **phonenotice/phonecall/** | `PhoneNoticeWidget`, `PhoneCallWidget` | スマホ通知・通話表示（モック） |
| **nowplaying/** | `NowPlayingWidget` | 再生中の曲情報 |
| **navigation/** | `NavigationWidget` | ルート・目的地経路図 |

新しいウィジェットの追加手順：① `widgets/<名前>/` フォルダを作り、`WidgetBase` を継承した QML を置く → ② 設定が必要なら `WidgetSettingsBase` の子を作る → ③ `WidgetRegistry.qml` に登録 → ④ `CMakeLists.txt` の `QML_FILES` に追加。

## aasdk（Android Auto SDK）との連携

| aasdk が提供する機能 | OpenCruise での実装内容 |
|---|---|
| **USB ホットプラグ検出・AOAP 切替** (`USBHub`) | libusb の初期化・イベントループ専用スレッド・io スレッド・待機⇄接続・切断ループ。非 AOAP 機器のフィルタリングも実装。 |
| **USB 転送・フレーム化・SSL 暗号化** (`USBTransport`/`Messenger`/`Cryptor`) | セッションの組み立て・終了処理 |
| **チャネル送受信 & デコード**（制御/映像） | ハンドシェイク手順、サービス探索応答、Open/Setup/Start 応答、ACK の運用、フォーカス対応など |
| **映像データ受信（H.264）** | OpenH264 のデコード → QImage → QML(`VideoSurfaceItem`)表示 |
| **音声・マイク入力** | PCM データを受け取り再生器へ渡す（Android Auto 側で混成） |
| **車両情報送受信** | `VehicleSnapshot`（速度・回転数・燃料・ギア・位置など）を EcuData から送信。スマホのセンサーもダミー。 |
| **スマホ状態（通話/通知/バッテリー）** | `PhoneStatusWidget` へ反映（バッテリーは実データ、電波/通知はモック宣言済み）。 |

## ロジカル設計のポイント

1. **接続層の独立**: aasdk はサブプロジェクトとしてビルド。OpenCruise アプリと UI は AASDK 側から「公開ヘッダ」のみで制御される。
2. **BootManager（起動画面）**: フォント・音声・AA 接続待ちなどを段階的に表示し、進捗管理。各ステップの完了状況は GUI で表示可能。
3. **ShutdownManager（終了処理）**: 電源オフ時の処理順を制御（設定保存→AA 切断→ドア解除→電源プロファイル復元）。
4. **QML ウィジェットシステム**: `WidgetStore` に配置・設定を保存し、共通のデータモデルを持つ。新しいウィジェットの追加は「登録」のみで済む。
5. **昼夜モード連動**: アプリテーマに基づき Android Auto の NIGHT_MODE が送信される（自動/手動切り替え）。
6. **音声・明るさの階層制御**: マスター音量と個別音量、バックライト・暗幕を互いに干渉せず独立操作可能。

## ビルド・デプロイの注意点

| 注意点 | 内容 |
|---|---|
| **aasdk の修正パッチ** | `patches/` に aasdk 向け修正（Boost/system、Asio API、protobuf CMake など）。aasdk を更新する場合は再適用が必要。 |
| **USB 権限の必要性** | スマホを検出するには udev ルールで「plugdev」グループへの書込み権限が必要（`scripts/install.sh` で一括設定可能） |
| **ALSA の依存** | Windows/MacOS では `-DOPENCRUISE_ENABLE_ALSA=OFF` で Qt 音声入出力へ回帰 |
| **クロスコンパイル** | Yocto 向けには `yocto/`, `coreboot/` の設定を参照、ARM アーキテクチャ対応 |
| **開発オプション** | `--test-video <file>` でスマホ無しでのデコード確認。`--screenshot` で起動後スクリーンショット取得 |

## ライセンスとクレジット

### 本プロジェクト
OpenCruise は **GNU General Public License バージョン 3 またはそれ以降 (GPL-3.0-or-later)** で公開しています。全文は [LICENSE](LICENSE) です。

Android、Android Auto は Google LLC の商標です。このプロジェクトは Google LLC と提携・承認の関係にありません。

### aasdk（Android Auto SDK）
同梱ライブラリ `aasdk/` も GPL-3.0-or-later です。OpenCruise 全体として GPL-3.0-or-later の条件が適用されます。

### H.264 パッセンジャー
アプリは Android Auto の映像（H.264）をデコードします。**OpenH264** を使用しています。Cisco が配布するビルド済みバイナリではなく、ソースからビルドされたものです。
- **非商用**：個人・趣味での利用を対象とします。販売・業務利用・製品組み込みは想定していません。
- **特許許諾**: 取っていません。使う・配る場合は自己責任でお願いします。

### 効果音：OtoLogic
アプリの効果音 (`app/resources/sounds/`) は [OtoLogic](https://otologic.jp) から提供されています。
- ライセンス: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- クレジット表示場所：設定 > システム > 情報 > 使用素材・ライセンス

### 音声合成：AivisSpeech
起動時のあいさつなど（`app/resources/sounds/start/`）は [AivisSpeech](https://aivis-project.com) で生成されています。
- 合成モデル：コハク (ACML 1.0)
- クレジット表示場所：同上

### OS イメージの配布
開発用の設定（SSH・パスワードなしの root ログイン）はリリースには含めません。`.wic` イメージを配布する場合は：
1. `scripts/build-os.sh --release`（ライセンス文入れ、GPL/LGPL のソース集める）
2. `scripts/build-os.sh --release-pack`（イメージ・license.manifest・ソース・チェックサムをまとめ）

リリースには、`license.manifest` / `licenses.tar.xz` / `sources.tar` も添付してください。

---

**開発者**: YuranuDev
**最終更新**: 2026-11-27
