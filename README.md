# OpenCruise — Qt + aasdk 車載システム 簡易プロトタイプ

x86_64 PC 向けの車載システム試作。Qt Quick(QML) + C++ + CMake。Android Auto の接続・映像は同梱の `aasdk` を利用する。
**完成品ではなく、各機能を最低限つないだ動作確認用の仮システム**。

## 構成

```
OpenCruise/
├── CMakeLists.txt            トップ。aasdk をサブプロジェクトとして取り込み、app/ をビルド
├── aasdk/                    既存の aasdk（※ USB/USBWrapper.cpp のみ 1 か所修正。後述）
├── patches/                  aasdk に当てた修正の diff
├── scripts/make_test_stream.sh   開発用テスト映像(H.264)の生成
└── app/
    ├── main.cpp              起動・モデル生成・QML 公開・開発用オプション
    ├── core/                 ClockModel(時計) / DummyCanModel(ダミーCAN)
    ├── androidauto/          Qt 側: AndroidAutoController / H264Decoder / VideoSurfaceItem / TestVideoFeeder
    ├── aabackend/            Qt 非依存の aasdk 接続層（UI と分離。無効時はスタブ）
    │   ├── AasdkBackend.*    libusb・ioスレッド・USBHub、待機→接続→切断→待機のループ
    │   ├── AasdkSession.*    1接続ぶん。制御チャネル(バージョン/SSL/認証/サービス探索/Ping/切断)
    │   ├── AasdkVideoHandler.* 映像チャネル(Open/Setup/Start/データ受信/ACK/フォーカス)
    │   └── AasdkConfig.h     車載機として申告する値（解像度 dpi 等、暫定値を1か所に集約）
    └── qml/                  Main / HomeScreen / SettingsScreen / CanPanel / ConnectionBadge / ActionButton / Theme
        └── widgets/          ウィジェット基盤と各ウィジェット(下の「ウィジェット」参照)
```

接続層 (`aabackend`) は Qt を一切含まず、UI は `AasdkBackend` の公開ヘッダだけを見る。
そのため aasdk が無い/接続できない環境でもアプリ全体が起動する（状態は「利用不可」「待機中」と表示）。

## ビルド

Ubuntu 24.04 で確認。必要パッケージ:

```bash
sudo apt install build-essential cmake ninja-build pkg-config \
  qt6-base-dev qt6-declarative-dev qml6-module-qtquick qml6-module-qtquick-controls \
  qml6-module-qtquick-layouts qml6-module-qtquick-window qml6-module-qtquick-templates \
  qml6-module-qtqml qml6-module-qtqml-workerscript \
  libavcodec-dev libavutil-dev libswscale-dev \
  libboost-system-dev libboost-log-dev libprotobuf-dev protobuf-compiler libusb-1.0-0-dev libssl-dev
# 日本語表示用フォント（例）
sudo apt install fonts-noto-cjk

cmake -G Ninja -S . -B build -DCMAKE_BUILD_TYPE=Release
ninja -C build            # aasdk(約300ファイル)を含むため初回は数分〜十数分
./build/app/opencruise
```

- aasdk なしで UI だけビルド: `-DOPENCRUISE_ENABLE_AASDK=OFF`（Boost/libusb/protobuf 不要）
- aasdk は同梱のものを `SKIP_BUILD_PROTOBUF=ON` / `SKIP_BUILD_ABSL=ON`（システムの protobuf 3.21 を使用）でビルドする。
  Abseil が必要な新しい protobuf を使う場合はこの設定の見直しが必要。
- 実機接続には USB 権限が必要。aasdk の `DOCUMENTATION.md` にある udev ルール
  (`SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev"`) を設定する。
  権限が無い場合、aasdk の `USBHub` は **エラーを出さず黙って無視する**ため、「待機中」のまま進まない。

### 開発用オプション

| オプション | 内容 |
|---|---|
| `--test-video <file>` | H.264 ファイルを映像として表示（スマホ無しでデコード/表示を確認）。`scripts/make_test_stream.sh` で生成 |
| `--screenshot <png> [--screenshot-delay <ms>]` | 画面を保存して終了 |
| `--open-settings` | 設定画面を開いた状態で起動 |
| `--fullscreen` | 全画面 |

ヘッドレス確認例: `QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software ./build/app/opencruise --screenshot out.png`

## 音量・明るさ

設定の「サウンド」「表示」から変更できるほか、キーボード(将来はステアリングスイッチ等)のショートカットで操作できる。

| ショートカット | 内容 |
|---|---|
| `Ctrl+Shift+V` / `Ctrl+Shift+B` | マスター音量を 5 % 下げる / 上げる(V = Volume。押しっぱなしで連続)。マスター音量と、マップ音声・音楽音声・システムの各音量バーをまとめて表示し、約 2.5 秒で自動で閉じる。表示中のバーはすべてタッチ/ドラッグで直接変更でき、押している間は閉じない |
| `Ctrl+Shift+K` / `Ctrl+Shift+L` | 画面の明るさを 10 % 下げる / 上げる(L = Light)。現在値のバーを表示し、約 2 秒で自動で閉じる |

すべて `Ctrl+Shift+文字` で統一している(将来の物理ボタンも、同じキーイベントを送れば同じ動作になる)。
音量・明るさは、隣り合う 2 つのキーで「左のキー = 下げる、右のキー = 上げる」にそろえている。
既存のキー(`Esc` / `F10` / `Menu` / `Meta`・`Super` / `Ctrl+Shift+D`)とは重ならない組み合わせにしてある。
メディアキーや `Ctrl+Alt+矢印` は、OS 側の音量・画面回転と二重に動くため使っていない。

- **マスター音量**(`core/AudioSettings`): 3 つの音声系統すべてに掛かる共通の倍率(0〜100 %)。各系統の個別音量の設定値は変えずに保持する。
  再生器へ渡す値は `AudioSettings::gain(group)` の 1 か所で「個別 × マスター」に合成しており、`AudioPlayer` / `SystemSound` はこれだけを使う
  (マスターを別に掛けないこと。二重になる)。マイク(入力)は対象外。保存キーは `audio/masterVolume`。
- **画面の明るさ**(`core/BrightnessController`): 10〜100 %(0 にして画面が見えなくなるのを防ぐ)。保存キーは `display/brightness`。
  - Linux で `/sys/class/backlight/*/brightness` に書き込める場合は、バックライトを直接制御する。
  - 書き込めない場合(Windows、権限なし、外部ディスプレイなど)や書き込みに失敗した場合は、画面全体に黒い幕を重ねて暗くする方式に自動で切り替わる。
    どちらか一方だけを使うので、二重に暗くはならない。
  - バックライトを制御するには、そのファイルへ書き込める権限が必要(例: udev ルールでグループ書き込みを許可)。
  - バックライトは、保存された設定がある場合だけ起動時に値を反映する。終了時に元の値へは戻さない。

## テーマと背景

設定「表示 > テーマ」でアプリ全体の見た目を選べる(`core/ThemeSettings`、QML では `themeSettings`。色と形は `qml/Theme.qml`)。

| テーマ | 内容 |
|---|---|
| シンプル | これまでの見た目(平らな面・大きめの角丸・青のアクセント) |
| クラシック | 2000 年代ごろの車の内装に合う見た目。ガンメタ(夜)/シルバー(昼)の面に、ゆるいグラデーションと内側の細いハイライト、小さめの角丸。アクセント色(照明色)はアンバー・赤・青・緑・アイボリー・シアン |

背景(設定「表示 > 背景」): テーマに合わせる(シンプルは無地、クラシックはカーボン)/ 無地 / 模様(カーボン・ヘアライン・パンチング・ストライプ)/ 画像。
画像は `~/.local/share/OpenCruise/backgrounds` に PNG / JPEG を置くと選べる(並べる・画面を埋める・引き伸ばす)。濃さも変えられる。
面(カード・ボタン・ダイアログ)は `qml/Panel.qml` を使うと、テーマに合わせて描き分けられる。

### 飾りの画像(キャラなど)

初期画面のページごとに、好きな画像を好きな場所へ置ける(ウィジェットの後ろ・パネルの上・前、ステータスバーやナビバーの上も)。

1. `~/.local/share/OpenCruise/decorations` に画像(PNG / JPEG / WebP / GIF。キャラだけを置くなら透過 PNG)を入れる
2. 初期画面の「編集」→ 上のバーの「画像」→「画像を追加」で選ぶ(今のページの中央に置かれる)
3. ドラッグで移動(画面の中央・端に近づくと吸い付いて線が出る)。大きさは右下のつまみか、2 本指でつまむ(縦横比はそのまま)
4. 選ぶと下に操作パネルが出る: 濃さ・左右反転・重ね方・いちばん上へ・複製・削除(2 回押し)。上のバーの「元に戻す」で 1 つずつ戻せる

重ね方:

| 重ね方 | 出る場所 |
|---|---|
| 奥 | ウィジェット・バーの後ろ(ウィジェットの隙間から見える) |
| パネル | 各ウィジェットのパネル(カード)の上、メーターや文字の下。画面の同じ所にある画像が、パネルの形に切り抜かれて見える |
| 手前 | ウィジェットの前(タッチは下のウィジェットへ通す) |

「パネル」の角丸の切り抜きは、Qt 6.5 以降の MultiEffect、無ければ Qt5Compat の OpacityMask(`qml6-module-qt5compat-graphicaleffects`)を使う。
どちらも無いとき・ソフトウェア描画のときは四角く切り抜く(パネルの角の丸みの外へ少しはみ出る)。

置いた場所は `widgetStore.layoutJson` のページごとの `decor` に、画面に対する割合で保存する(画面の大きさが変わっても同じ所に出る)。
画像が見つからないものは、編集中だけ赤い枠で出る(消せる)。Android Auto 画面には出ない。
実装: `qml/widgets/DecorationStore.qml`(今のページの一覧・元に戻す)/ `DecorationLayer.qml`(奥・手前の表示)/
`DecorationPanelLayer.qml`(パネルの層。WidgetBase の中)/ `DecorationEditor.qml`・`DecorationPanel.qml`(置き直す操作)/
`DecorationPicker.qml`(追加パネル)。

## ウィジェット

初期画面の中央領域は、12 × 6 マスのウィジェット配置エリアになっている(時計・あいさつも、その中のウィジェット)。

| 操作 | 内容 |
|---|---|
| 長押し(約 0.3 秒)→ドラッグ | 持ち上げて移動。移動中だけ配置エリア(グリッド)と移動先の枠が滑らかに現れ、離すと最寄りの空きマスへスナップ。空きマスが無ければ元の位置へ戻る |
| ダブルタップ | 設定画面を持つウィジェットは設定ダイアログ(固有の設定 + サイズ + 削除)を開く |
| ナビバーの「編集」 | 編集モードに入る・出る(下記) |

編集モード(ナビバーの「編集」。Android Auto 画面ではメニューの「編集」):

| 操作 | 内容 |
|---|---|
| 上の編集バー | 「編集中」・ページの切り替え・選んだ数と操作(まとめて設定・削除・選択を解除)・このページを選択・全ページを選択・追加・完了。削除は 2 回押し |
| ページをまたいだ選択 | ページを移っても選択は残る(選んだ数は全ページの分。「2 個選択中(2 ページ)」)。「全ページを選択」→「まとめて設定」で、全ページのウィジェットの見た目をまとめて変えられる |
| ウィジェットをタップ | 選択 / 解除(グリッドが出て、各ウィジェットに名前と大きさ「3 x 2」が出る。中身は操作できない) |
| ウィジェットをドラッグ | すぐ移動(長押しは要らない)。選んだものの 1 つを動かすと、選択中のものが並びを保ってまとめて動く |
| 左上の丸いボタン(歯車) | そのウィジェットの設定 |
| 右上の丸いボタン(×) | 削除(1 回目で赤い「削除」に広がり、0.4〜3 秒の間にもう一度押すと消す) |
| まとめて設定 | 選んだウィジェットに同じ値を入れる。同じ種類だけならその種類の設定すべて、混ざっていれば共通の項目(枠・上部タイトル)だけ。範囲・単位・警告値・注意値・目盛り間隔・タイトル文字・サイズはそれぞれのまま |
| Android Auto の映像(Android Auto 画面) | ドラッグで置く角を、内側の角のつまみで大きさ(マス数)を変える。離したときに決まる |

追加パネル(編集バーの「追加」)は、ジャンル別タブ。「初期配置に戻す」も、ここ(2 回押しで実行)。

配置と設定は `QSettings`(`widgets/layout`、version つき JSON)へ保存する。

### ファイル構成(`app/qml/widgets/`)

| 役割 | ファイル |
|---|---|
| 登録(新しいウィジェットを足すときに触る唯一の場所) | `WidgetRegistry.qml`(ジャンル・種類・既定サイズ/設定・初期配置) |
| 共通基盤 | `WidgetBase`(ウィジェットの土台) / `WidgetHost`(ドラッグ・スナップ・タップ振り分け・表示アニメーション) / `WidgetArea`(グリッド・衝突・保存) |
| 設定・追加 UI | `WidgetSettingsBase` / `WidgetSettingsDialog` / `WidgetPicker` / `WSStepper` / `WSTextField` |
| 時計・あいさつ | `ClockWidget` / `GreetingWidget`(+ 各 `*Settings`) |
| 車載連携 | `GaugeWidget` / `GaugeSettings`(メーター共通。ターボ圧計・タコメーター・スピードメーター・水温計・燃料計。計測値の定義は `WidgetRegistry.gaugeSpecs`。アナログ+デジタル、単位切替、警告値・警告メッセージ。**モックデータ**) |
| Android Auto 連携 | `PhoneStatusWidget`(スマホ状態。バッテリー残量は実データ、電波はモック) |
| 通知連携 | `PhoneNoticeWidget`(スマホ通知。表示方法・カテゴリ別メッセージを設定可能。**モックの通知**) |

新しいウィジェットの追加手順: ① `WidgetBase` を継承した qml を作る ② 設定が要るなら `WidgetSettingsBase` を継承した qml を作る
③ `WidgetRegistry.qml` に Component と `types` の 1 項目を足す ④ `app/CMakeLists.txt` の `QML_FILES` に足す。
設定が不要なウィジェットは `settings: null` にする(ダブルタップは何もしない)。独自のダブルタップ動作が欲しい場合は
`doubleTapAction: "custom"` にして `doubleTapped()` を受ける。

### Android Auto から取れる情報(`aasdk_phone_data.csv` の確認結果)

- 実データ: スマホのバッテリー(残量・残り時間・危険フラグ。`BatteryStatusNotification`。サービス宣言なしで届く)。`AasdkSession` →
  `AndroidAutoController` → `PhoneStatus::setBattery()`。バッテリー残量の単位(%)は実機での確認が必要。
- 未宣言のため届かない(現状モック): 電波強度(PhoneStatus サービス)、通知(GenericNotification サービス: id / text / icon のみ)、
  ナビ・再生中の曲。宣言を足したら `PhoneStatus::setSignal()` / `ingestNotice()` を呼ぶだけでウィジェットは実データに切り替わる。
- そもそも取れない: 通知の送信元アプリ名・本文、連絡先・通話履歴・メッセージ本文(プロトコルに無い)。通知のカテゴリは文面から推定する。

## 実装状況

### 実装済み

| 機能 | 状態 | 検証 |
|---|---|---|
| Qt Quick メイン画面（暗色、時計、接続状態、AA表示領域、CANパネル、設定ボタン） | 実装 | ビルド・起動・画面保存で確認 |
| 現在時刻表示 | 実装(時計ウィジェットへ移行) | 画面で確認(旧実装) |
| ウィジェットシステム(配置エリア・ドラッグ・スナップ・設定ダイアログ・追加パネル、時計/あいさつ/ターボ圧計/スマホ状態/スマホ通知) | コード実装 | **ビルド・実行とも未検証** |
| CAN 情報の仮表示（速度/回転数/水温/燃料、「ダミーデータ」と明示） | 実装 | 画面で確認 |
| 設定画面への遷移（StackView） | 実装 | 設定画面の描画を確認。ボタンのタップ操作は未確認 |
| 接続状態表示（利用不可/待機中/接続中/接続済み/映像受信中、切断理由の保持） | 実装 | 「利用不可」「待機中」「映像受信中(テスト)」を画面で確認 |
| 未接続・失敗時でもアプリ全体が起動 | 実装 | aasdk 無効/有効(USB機器なし)の両方で確認 |
| H.264 デコード → QImage → QML 表示 | 実装 | テスト映像(800x480)で表示を確認（aasdk 非経由） |
| aasdk 接続層（USBHub→AOAP→Messenger→制御/映像チャネル→切断→待機復帰） | **コード実装・ビルド成功** | **実機未検証** |
| 終了処理（スレッド停止・libusb 解放） | 実装 | 待機中の終了(約0.2秒)を確認。セッション中の終了は未検証 |
| マスター音量・音量ショートカット・音量表示 | コード実装 | **ビルド・実行とも未検証** |
| 画面の明るさ(設定・ショートカット・表示。バックライト/暗幕の自動切替) | コード実装 | **ビルド・実行とも未検証** |

### 検証できたこと / できていないこと

確認できた: aasdk を含むフルビルド成功(自作コードの警告 0)、起動と待機状態への遷移、10秒間の待機稼働、
サービス探索応答が protobuf として必須フィールドを満たすこと(`IsInitialized()`)、デコード/表示経路。

**未検証（実機が必要。「動作済み」とは扱わない）**: スマートフォンの検出、AOAP 切替、SSL ハンドシェイク、サービス探索の受理、
映像チャネルのセットアップ、実際の H.264 受信と表示、ACK の運用、切断時の復帰、再接続。

### aasdk が提供するもの / 追加実装したもの

| aasdk が提供 | 本プロジェクトで追加実装 |
|---|---|
| USB ホットプラグ検出・AOAP 切替 (`USBHub`) | libusb の初期化と **イベントループ専用スレッド**、io スレッド、待機⇄接続のループ |
| USB 転送・フレーム化・SSL 暗号化 (`USBTransport`/`Messenger`/`Cryptor`) | セッションの組み立てと終了処理 |
| チャネルの送受信と protobuf デコード（制御/映像） | **各メッセージへの応答ロジック**（ハンドシェイク手順、サービス探索応答の内容、Open/Setup/Start 応答、ACK、フォーカス応答、Ping） |
| 映像データの受信（H.264 の生バイト列まで） | **H.264 デコード**（FFmpeg）と画面表示 |

同梱の `aasdk/tools/simple` は AOAP ハンドシェイクのスタブで、Messenger/映像は含まない。完全なセッションの手順は
ヘッダ・実装・`.proto` から読み取った（根拠は各 `.cpp` 冒頭のコメントに記載）。

### 未実装

- 実 CAN 通信（ダミーのみ）
- タッチ入力・ステアリング操作の転送（InputSource）、センサー(走行状態等)、音声（再生/マイク）、Bluetooth、無線接続(Wi-Fi/TCP)
- 車載機側からの Ping 送信・タイムアウト検出
- 解像度/dpi の最適化（800x480・140dpi の暫定値。`AasdkConfig.h`）、GPU 描画（現状は `QQuickPaintedItem` のソフトウェア描画）
- 設定の保存、画面の多言語化（UI 文字列は日本語直書き）

## aasdk で見つけた問題と対処

1. **`USBWrapper::hotplugRegisterCallback` のダングリングポインタ（修正済み）**
   スタック上のハンドルのアドレスを `shared_ptr` に渡していたため、`USBHub::cancel()` でホットプラグコールバックが解除されず、
   破棄済みの `USBHub` に通知が飛ぶ恐れがあった。切断後に `USBHub` を作り直す設計に必須のため、ヒープ確保に修正
   （`patches/aasdk-usb-hotplug-handle.patch`。aasdk を更新する場合は再適用が必要）。
2. `Messenger::stop()` は受信キューを空にするだけで保留中の Promise を失敗させない → `transport->stop()` によるキャンセル経由で終了を伝播させている。
3. `Cryptor::deinit()` 後に `encrypt()` が呼ばれると `SSL*` が null でクラッシュし得る → 最後の参照者が消えた時に `deinit()` する（カスタムデリータ）。
4. バージョン応答の status は `uint16` を `MessageStatus` に単純キャストしており不一致値が `-1` にならない → 「`STATUS_SUCCESS` 以外は失敗」で判定。
5. `USBHub` は USB 機器の open 失敗を黙殺し、非 AOAP 機器の検出ごとに 1 秒 sleep する → io スレッドを 2 本にして影響を緩和。権限エラーは UI から判別できない。
6. `ControlServiceChannel::sendVoiceSessionFocusResponse` は実装が空（Promise が解決されない）→ 使っていない。

## 実機検証の際の見どころ（リスク）

- サービス探索で**映像サービスのみ**申告している。センサー/入力サービスが無いとスマートフォンが接続を維持しない可能性がある（未確認）。
  切断された場合は `AasdkVideoHandler::fillFeatures` と同様に `SensorSource`/`InputSource` の追加を検討する。
- `driver_position` は右ハンドル、音声フォーカス要求には「喪失」、ナビフォーカスには PROJECTED を返す暫定実装。
- ログは `[aa] [session] ...` `[aa] [video] ...` として標準エラーに出る。どこまで進んだかの切り分けに使える。
- `--test-video` で映像が出ても aasdk の受信が動いた証拠にはならない（状態表示に「aasdk 経由ではありません」と出る）。

## 使用素材・ライセンス

### 効果音: OtoLogic

アプリの効果音(`app/sounds/`)には、[OtoLogic](https://otologic.jp) が配布している素材音源を使用しています。

- 素材: OtoLogic (https://otologic.jp)
- ライセンス: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.ja)
- 利用規約: https://otologic.jp/free/license.html

素材を再配布するとき(このリポジトリを配布する場合も含む)は、このクレジット表記を引き継いでください。

### 音声: AivisSpeech

起動時のあいさつなどの音声(`app/sounds/start/` の読み上げ音声)は、[AivisSpeech](https://aivis-project.com) で作成しました。

- AivisSpeech 本体: 生成した音声にクレジット表記の義務はありません(任意のクレジットとして記載しています)
- 音声合成モデル: 使ったモデルごとのライセンスに従います。AivisHub などで公開されている ACML / ACML-NC / CC0 のモデルは
  クレジット表記の義務がありません。ACML-NC のモデルは非商用に限られるため、商用で配布する場合はモデルのライセンスを確認してください
- 使用した音声合成モデル: (モデル名とライセンスを記入)

### クレジットの表示場所

アプリの画面内にも、同じクレジットを表示しています(設定 > 情報 > 使用素材・ライセンス)。
