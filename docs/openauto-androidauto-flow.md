# OpenAuto: スマホ接続から Android Auto 映像表示までの仕様メモ

対象ソース
- opencardev/openauto `main` @ `4cc739b`（`src/autoapp`, `src/btservice`）
- opencardev/aasdk `main`（USB / Messenger / Channel 層。openauto が依存するライブラリ）

このメモは AI にコードを書かせるための入力用。各項目は次のどちらか。
- **[確認済]** 上記ソースを実際に読んで確認した内容
- **[一般知識]** ソースでは確認していないが、Android Auto プロトコルとして一般に知られている内容

---

## 1. 全体像

OpenAuto は「ヘッドユニット（HU）側」の実装。スマホ（MD, Mobile Device）が Android Auto のサーバ役で、HU は映像を受信して表示し、タッチ・ボタン・センサー情報をスマホに返すクライアント役。

```
[スマホ]                                         [HU = openauto]
  |  (USB: AOAP)  または (BT でWiFi情報交換 → TCP:5000)
  v
Transport (USBTransport / TCPTransport)          <- aasdk
  v
Messenger (フレーム分割/結合 + TLS 暗号化)       <- aasdk (MessageInStream/OutStream, Cryptor)
  v
Channel (Control, Video, Input, Sensor, Audio..) <- aasdk が各チャンネルの送受信APIを提供
  v
Service (IService 実装)                          <- openauto/src/autoapp/Service
  v
Projection (VideoOutput, InputDevice, AudioOutput)<- openauto/src/autoapp/Projection
  v
Qt (QMediaPlayer + QVideoWidget で H.264 を再生)
```

責務の分担:
- **aasdk**: USB 検出・AOAP 切り替え、フレーミング、TLS、各チャンネルの protobuf 送受信
- **openauto**: どのサービスを持つかの組み立て、ハンドシェイクの進行管理、映像/音声/入力の実デバイスへの接続、UI

---

## 2. プロセスと起動順（`src/autoapp/autoapp.cpp`）[確認済]

1. `libusb_init`
2. `boost::asio::io_service` と `io_service::work` を作成
3. スレッド起動
   - **USB イベントスレッド x4**: `libusb_handle_events_timeout_completed(ctx, {180s})` を `ioService.stopped()` まで回す
   - **io_service スレッド x4**: `ioService.run()`
4. `QApplication` 生成（メインスレッド = Qt GUI スレッド）。プライマリ画面の幅・高さを取得
5. `Configuration`（INI 読み込み）、MainWindow / SettingsWindow / ConnectDialog などの UI を生成
6. 依存オブジェクトを組み立てる
   ```
   USBWrapper(usbContext)
   AccessoryModeQueryFactory(usbWrapper, ioService)
   AccessoryModeQueryChainFactory(usbWrapper, ioService, queryFactory)
   ServiceFactory(ioService, configuration)
   AndroidAutoEntityFactory(ioService, configuration, serviceFactory)
   USBHub(usbWrapper, ioService, queryChainFactory)
   ConnectedAccessoriesEnumerator(usbWrapper, ioService, queryChainFactory)
   App(ioService, usbWrapper, tcpWrapper, entityFactory, usbHub, enumerator)
   ```
7. `app->waitForUSBDevice()` を呼んでから `qApplication.exec()`

スレッド境界の要点: ネットワーク/USB/プロトコル処理は io_service スレッド、描画と入力イベントは Qt メインスレッド。両者の橋渡しは `Qt::BlockingQueuedConnection` / `QMetaObject::invokeMethod` で行う（映像出力側）。

---

## 3. 接続から映像表示までのフェーズ

### Phase A: USB でスマホを検出して AOAP モードに切り替える（aasdk/USB）[確認済]

`App::waitForUSBDevice()` → `waitForDevice()` + `enumerateDevices()`

- `waitForDevice()` は `usbHub_->start(promise)` を呼び、promise 成功時に `App::aoapDeviceHandler(DeviceHandle)`、失敗時に `App::onUSBHubError` を呼ぶ。続けて `startServerSocket()`（WiFi 用、後述）も開始する
- `USBHub::start` は libusb のホットプラグを登録する
  - イベント: `LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED`
  - フラグ: `LIBUSB_HOTPLUG_ENUMERATE`（既に挿さっているデバイスも通知される）
  - vendor / product / class はすべて MATCH_ANY
- 到着したデバイスごとに `USBHub::handleDevice`
  - デバイスをオープンし、descriptor を取得
  - **VID `0x18D1` かつ PID `0x2D00` または `0x2D01`** ならすでに AOAP モード。その `DeviceHandle` で hotplug promise を resolve
  - それ以外は `AccessoryModeQueryChain` を起動して AOAP モードへ切り替える（先頭に 1 秒の sleep がある。VMware 回避の workaround）
- `AccessoryModeQueryChain` の実行順（USB コントロール転送）
  1. プロトコルバージョン取得
  2. MANUFACTURER = `"Android"`
  3. MODEL = `"Android Auto"`
  4. DESCRIPTION = `"Android Auto"`
  5. VERSION = `"2.0.1"`
  6. URI = `"https://f1xstudio.com"`
  7. SERIAL = `"HU-AAAAAA001"`
  8. START（accessory mode 開始）
- START 後、スマホは USB を再列挙して `18D1:2D00/2D01` として現れる。これが再び hotplug の ARRIVED として `handleDevice` に入り、上記の AOAP 判定で promise が resolve される（クエリチェーンの完了時点では resolve しない点に注意）

### Phase B: （無線接続の場合）Bluetooth → WiFi → TCP:5000 [確認済]

USB と並行して、`App` のコンストラクタで `acceptor_` が **TCP 0.0.0.0:5000** を listen し、`startServerSocket()` が `async_accept` する。接続が来ると `handleNewClient` → `App::start(socket)` → `TCPEndpoint` を作って Entity 生成（Phase C 以降は USB と共通）。

TCP 接続を引き出すのは別プロセス `btservice`（`src/btservice`）。

- `BluetoothHandler`: Bluetooth をオン、discoverable にし、RFCOMM サーバを listen。ペアリング確認は自動で承認
- `AndroidBluetoothService`: SDP に UUID `4de17a00-52cb-11e6-bdf4-0800200c9a66` で登録（名前 "OpenAuto Bluetooth Service"）
- スマホが RFCOMM に接続すると `AndroidBluetoothServer::onClientConnected` が
  1. `WifiVersionRequest` を送る
  2. `WifiStartRequest{ip_address = wlan0 の IPv4, port = 5000}` を送る
- スマホからの `WIFI_INFO_REQUEST` に対し `WifiInfoResponse` を返す
  - `ssid` / `password`: `/etc/hostapd/hostapd.conf` の `ssid` / `wpa_passphrase`
  - `bssid`: wlan0 の MAC
  - `security_mode`: `WPA2_ENTERPRISE`、`access_point_type`: `STATIC`
- BT メッセージのフレーム形式: `uint16 length` + `uint16 messageId` + protobuf 本文（length は本文長）
- スマホは AP に接続し、`ip:5000` に TCP 接続してくる

なお `autoapp` 内にも `BluetoothService`（AA の Bluetooth チャンネル）がある。これは別物で、`getWirelessProjectionEnabled()` が真のときだけサービスリストに入り、ペアリング方式と car_address を Service Discovery で通知する役。

### Phase C: AndroidAutoEntity の生成 [確認済]

`App::aoapDeviceHandler`（USB）または `App::start(socket)`（TCP）が次を行う。

- すでに Entity があれば（USB の場合）警告して無視、TCP の場合は既存を `stop()`→`reset()`
- `disableAutostartEntity` が true なら自動開始しない（手動停止後の抑止用フラグ）
- USB: `connectedAccessoriesEnumerator_->cancel()` → `AOAPDevice::create(usbWrapper, ioService, deviceHandle)`
- `AndroidAutoEntityFactory::create(...)`
  1. Transport 作成: `USBTransport(ioService, aoapDevice)` または `TCPTransport(ioService, tcpEndpoint)`
  2. `SSLWrapper` → `Cryptor` → `cryptor->init()`
  3. `Messenger(ioService, MessageInStream(transport, cryptor), MessageOutStream(transport, cryptor))`
  4. `serviceFactory.create(messenger)` で `ServiceList` を作成
  5. `Pinger(ioService, 5000)`
  6. `AndroidAutoEntity(ioService, cryptor, transport, messenger, configuration, serviceList, pinger)`
- `entity->start(*this)`（`App` が `IAndroidAutoEntityEventHandler`）

`ServiceFactory::create` が作るサービス [確認済]
- MediaSink: Media audio（設定で有効時, 48kHz/16bit/2ch）、Guidance audio（有効時, 16kHz/1ch）、**System audio（常に有効。コメントに「MUST be enabled」）**、**Video**
- MediaSource: Microphone
- Sensor、InputSource
- Bluetooth（無線プロジェクション有効時のみ）
- 映像出力は `USE_OMX` 定義時は `OMXVideoOutput`、それ以外は `QtVideoOutput`
- Telephony audio と WifiProjectionService はコメントアウトされていて生成されない

### Phase D: 制御チャンネルのハンドシェイク（`AndroidAutoEntity.cpp` + aasdk Control）[確認済]

`AndroidAutoEntity::start`:
1. 全サービスの `start()`（各サービスは自分のチャンネルの `receive()` を開始して待機状態になる）
2. `ControlServiceChannel::sendVersionRequest`（平文。payload は message id + `major(uint16 BE)` + `minor(uint16 BE)`）
3. 制御チャンネルの `receive()` 開始

その後はスマホからのメッセージで進む。

| 受信 | HU の処理 |
|---|---|
| `VERSION_RESPONSE` | status が `NO_COMPATIBLE_VERSION` なら終了。それ以外は `cryptor->doHandshake()` して `readHandshakeBuffer()` を `ENCAPSULATED_SSL` で送る |
| `ENCAPSULATED_SSL` | `writeHandshakeBuffer(payload)` → `doHandshake()`。未完なら再度バッファを送る。完了したら `AuthResponse{STATUS_SUCCESS}` を `sendAuthComplete` で送る |
| `SERVICE_DISCOVERY_REQUEST` | Phase E |
| `AUDIO_FOCUS_REQUEST` | `AUDIO_FOCUS_RELEASE` なら `STATE_LOSS`、それ以外は `STATE_GAIN` を返す |
| `NAV_FOCUS_REQUEST` | 常に `NAV_FOCUS_PROJECTED` を返す |
| `PING_REQUEST` / `PING_RESPONSE` / `BATTERY_STATUS` / `VOICE_SESSION` | 受信を再アームするだけ（PING_RESPONSE は `pinger_->pong()`） |
| `BYEBYE_REQUEST` | `ByeByeResponse` を送ってから `triggerQuit()` |
| `BYEBYE_RESPONSE` | `triggerQuit()` |

TLS 完了後のメッセージは暗号化される（フレームヘッダの encryption フラグ）。TLS 自体は SSL ハンドシェイクのバイト列を Control メッセージに載せて往復する方式で、OpenSSL 側のバッファは `Cryptor` が持つ（`readHandshakeBuffer` / `writeHandshakeBuffer`）。

### Phase E: Service Discovery [確認済]

`onServiceDiscoveryRequest` で `ServiceDiscoveryResponse` を組み立てて返す。

- `driver_position = DRIVER_POSITION_RIGHT`、`display_name = "Crankshaft-NG"`、`probe_for_support = false`
- `connection_configuration.ping_configuration`: tracked_ping_count 5 / timeout_ms 3000 / interval_ms 1000 / high_latency_threshold_ms 200
- `headunit_info`: make `Crankshaft`、model `Universal`、year `2018`、vehicle_id、head_unit_make `f1x`、head_unit_model `Crankshaft-NG Autoapp`、software build `1` / version `1.0`
- 各サービスの `fillFeatures(response)` が `response.add_channels()` で自分のチャンネルを追加

映像サービスの `fillFeatures`（`VideoMediaSinkService.cpp`）:
- `channels[i].id = channel_->getId()`
- `media_sink_service.available_type = MEDIA_CODEC_VIDEO_H264_BP`
- `available_while_in_call = true`
- `video_configs[0]`: `codec_resolution`, `frame_rate`, `width_margin`, `height_margin`, `density`
  - 値は `Configuration` 由来。デフォルトは **800x480 / 30fps / density(DPI) 140 / margin 0x0**
  - 解像度 enum は `VIDEO_800x480` / `VIDEO_1280x720` / `VIDEO_1920x1080`

入力サービス: `keycodes_supported`（設定のボタンコード）、タッチスクリーンが有効なら `touchscreen{width,height}`。
センサーサービス: `SENSOR_DRIVING_STATUS_DATA`, `SENSOR_LOCATION`, `SENSOR_NIGHT_MODE`。

チャンネル ID は aasdk の `ChannelId` enum（CONTROL=0, SENSOR, MEDIA_SINK, MEDIA_SINK_VIDEO, MEDIA_SINK_MEDIA_AUDIO, … の連番）。スマホは Discovery で通知された ID を使うため、ID の値そのものは実装依存。[確認済: enum 定義のみ]

### Phase F: チャンネルを開き、映像をセットアップする [確認済]

Discovery 後、スマホが各チャンネルに対して要求を送る。映像チャンネルでの順序は次のとおり。

1. `ChannelOpenRequest` → HU は `videoOutput_->open()` を実行し、成功なら `ChannelOpenResponse{STATUS_SUCCESS}`、失敗なら `STATUS_INTERNAL_ERROR`
   - `QtVideoOutput::open()` は `SequentialBuffer` を ReadWrite で開くだけ
2. メディア `Setup`（コーデック種別）→ HU は `videoOutput_->init()`
   - 成功なら `Config{status=STATUS_READY, max_unacked=1, configuration_indices=[0]}`、失敗なら `STATUS_WAIT`
   - `QtVideoOutput::init()` は `startPlayback` シグナルを `BlockingQueuedConnection` で Qt スレッドに投げ、`onStartPlayback` が実行される
3. `Config` の送信が成功したら `VideoFocusNotification{focus=VIDEO_FOCUS_PROJECTED, unsolicited=false}` を送る
4. `Start{session_id}` を受信 → `session_` に保存
5. スマホが `VideoFocusRequest` を送ってきたら、HU は常に `PROJECTED` の focus 通知で返す（`mode == VIDEO_FOCUS_NATIVE` のときは `/tmp/entityexit` ファイルを作る。OS に戻るための合図）

`QtVideoOutput::onStartPlayback`（Qt スレッド）:
- `QVideoWidget` を `Qt::Window | FramelessWindowHint`、`IgnoreAspectRatio` で、プライマリ画面のジオメトリいっぱいに表示
- `QMediaPlayer(nullptr, StreamPlayback)` に `setVideoOutput(videoWidget)`、`setMedia(QMediaContent(), &videoBuffer_)`、`play()`
- `playerReady_ = true`

### Phase G: 映像ストリームの受信と再生 [確認済]

スマホは H.264 (Baseline) のバイトストリームを media データとして送ってくる。

`VideoMediaSinkService::onMediaWithTimestampIndication(timestamp, buffer)`:
1. `videoOutput_->write(timestamp, buffer)`
2. `Ack{session_id = session_, ack = 1}` を **1 フレームごとに** 返す（`max_unacked = 1` なので、ACK を返さないとスマホが次を送らない）
3. 次の `receive()` を再アーム

タイムスタンプ無しの `onMediaIndication` は timestamp=0 で同じ処理に流れる。

`QtVideoOutput::write`:
- `playerReady_` が false の間は**データを捨てる**
- `SequentialBuffer::write` でバッファに追記し `readyRead()` を emit
- `SequentialBuffer` は `QIODevice`（sequential）で、`cStaticDataSize`（30MB）分のバッファを持つ。読み出しは `QMediaPlayer` 側が行う

**アプリ自身は H.264 をデコードしない**。デコードは Qt Multimedia の GStreamer バックエンドが担当する。コーデックが無いと `QMediaPlayer::FormatError` になる（エラーログに `gstreamer1.0-libav` 等の案内あり）。`OMXVideoOutput`（Raspberry Pi 向け）を使う構成では別経路でデコードされる。

### Phase H: 入力とセンサーを返す [確認済]

**入力**（`InputSourceService`, `projection::InputDevice`）
- スマホから `KeyBindingRequest` が来たら、要求キーがすべて対応済みか確認し、OK なら `inputDevice_->start(*this)` で `QApplication` にイベントフィルタを仕込む。応答は `KeyBindingResponse{status}`
- タッチ: `QTouchEvent`（マルチタッチ）を優先、なければマウスイベントで代替。`InputReport{timestamp(µs), touch_event{action, action_index, pointer_data[{x,y,pointer_id}]}}` を送る
  - マウス代替では `x = pos.x / touchscreenGeometry.width * displayGeometry.width`（映像解像度の座標系にスケール）
- ボタン: `InputReport.key_event{keycode, down, longpress, metastate}`。ロータリーは `relative_event{delta ±1}`
- 注意: Discovery で通知するタッチ領域は `getTouchscreenGeometry()`（`ServiceFactory` では**物理画面の大きさ**を渡している）で、イベント座標のスケール先は映像解像度。再実装時はこの 2 つの座標系を揃えること

**センサー**（`SensorService`）
- `SensorStartRequest` に `STATUS_SUCCESS` を返してから、種別に応じて初期データを送る
  - `DRIVING_STATUS_DATA`: `DRIVE_STATUS_UNRESTRICTED`
  - `NIGHT_MODE`: `/tmp/night_mode_enabled` ファイルの有無で昼夜を判定
- 以降 250ms 周期でポーリングし、昼夜が変わったら再送。GPS は `gpsd`（127.0.0.1:2947）から取得し、2D/3D fix があるときに `location_data` を送る

### Phase I: 切断と再接続 [確認済]

- 切断のトリガー: `ByeBye`、チャンネルエラー（`OPERATION_ABORTED` は無視）、ping タイムアウト、バージョン不一致 → `AndroidAutoEntity::triggerQuit()` → `App::onAndroidAutoQuit()`
- `App::onAndroidAutoQuit()`: Entity を `stop()`（サービス停止 → `messenger->stop()` → `transport->stop()` → `cryptor->deinit()`）して `reset()`、`isStopped_` でなければ `waitForDevice()` に戻って次の接続を待つ
- `AndroidAutoEntity::stop()` は冒頭で `stopping_` を立て、停止中のエラー連鎖で `triggerQuit` が再入しないようにしている

---

## 4. 主要な定数・設定値

| 項目 | 値 | 出所 |
|---|---|---|
| AOAP VID/PID | `0x18D1` / `0x2D00`, `0x2D01` | aasdk `USBHub.hpp` |
| WiFi 接続待ち TCP ポート | 5000 | `App.cpp` |
| BT SDP UUID | `4de17a00-52cb-11e6-bdf4-0800200c9a66` | `AndroidBluetoothService.cpp` |
| 映像コーデック | `MEDIA_CODEC_VIDEO_H264_BP` | `VideoMediaSinkService.cpp` |
| 映像デフォルト | 800x480, 30fps, DPI 140, margin 0 | `Configuration.cpp` |
| 映像 ACK | フレームごと, `max_unacked = 1` | `VideoMediaSinkService.cpp` |
| フレーム最大ペイロード | `0x4000` | aasdk `MessageOutStream.hpp` |
| 受信バッファ | 30MB (`cStaticDataSize`) | aasdk `Data.hpp` |
| 音声 | Media 48kHz/16bit/2ch、Guidance/System 16kHz/16bit/1ch、Mic 16kHz/16bit/1ch | `ServiceFactory.cpp` |

メッセージ形式 [一般知識, aasdk の `FrameHeader` / `FrameSize` を参照]: フレームは `channel id` + フラグ（FIRST / LAST / BULK、暗号化の有無、CONTROL / SPECIFIC）+ サイズ。大きなメッセージは FIRST / MIDDLE / LAST に分割される。

---

## 5. 再実装のためのブループリント

別言語・別環境で作る場合でも、この順番と責務で組めば同じ挙動になる。

1. **Transport を抽象化する**: `send(bytes)` / `receive(n)` を持つインターフェースを作り、USB 実装（AOAP の bulk IN/OUT エンドポイント）と TCP 実装を差し替え可能にする
2. **USB 検出**: hotplug（既存デバイスの列挙込み）で到着を受ける → AOAP でなければ Phase A のクエリチェーンを実行 → AOAP の VID/PID で再到着したデバイスを採用する
3. **Messenger**: フレームの分割/結合、チャンネル ID ごとの受信キュー、TLS（OpenSSL のメモリ BIO など。ハンドシェイクのバイト列を Control メッセージで運ぶ）
4. **Control 状態機械**: `VersionRequest 送信 → VersionResponse 受信 → TLS ハンドシェイク往復 → AuthComplete 送信 → ServiceDiscoveryRequest 受信 → Response 送信`
5. **Service インターフェース**（openauto の `IService` と同じ）
   ```cpp
   struct IService {
     virtual void start() = 0;   // 自チャンネルの receive を開始
     virtual void stop() = 0;
     virtual void pause() = 0;
     virtual void resume() = 0;
     virtual void fillFeatures(ServiceDiscoveryResponse&) = 0;
   };
   ```
6. **最小構成のサービス**: Control + Video + Input + Sensor + System audio（System audio は実装上「必須」扱い）
7. **Video サービスの手順**:
   ```
   onChannelOpenRequest  -> output.open()  -> ChannelOpenResponse
   onSetupRequest        -> output.init()  -> Config{READY, max_unacked=1, indices=[0]}
                            -> VideoFocus{PROJECTED, unsolicited=false}
   onStart(session_id)   -> session = session_id
   onMediaData(ts, buf)  -> output.write(ts, buf); send Ack{session, 1}
   onVideoFocusRequest   -> send VideoFocus{PROJECTED}
   ```
8. **映像出力**: H.264 バイトストリームを GStreamer / FFmpeg / ハードウェアデコーダに流し、ウィジェットに描画する。デコーダが準備できるまでは受信データを捨てるか溜めるかを決めておく。ACK は書き込み後すぐ返してよい（元実装はそうしている）
9. **切断処理**: どの層のエラーでも「Entity を作り直して USB / TCP 待ちに戻る」に集約する。停止中のエラーは無視して再入を防ぐ

AI に依頼するときのプロンプトの骨子:
```
OpenAuto (opencardev) の接続フローを再現するヘッドユニット実装を書く。
- Transport: USB(AOAP)。VID 0x18D1 / PID 0x2D00,0x2D01 が来るまで待つ。AOAP でなければ
  protocol version → manufacturer → model → description → version → uri → serial → start の順で送る
- 制御: Version → TLS handshake → AuthComplete → ServiceDiscovery の順
- Discovery には Video(H264_BP, 800x480, 30fps, dpi 140), Input(touch), Sensor, System audio を載せる
- Video は Setup で READY(max_unacked=1) を返し、データ 1 フレームごとに Ack を返す
- 受信した H.264 をデコードして全画面表示する
```

---

## 6. 読んでいて気づいた点（再実装時の注意）

いずれもこのコミット時点のソースの観察。挙動への影響は実機で未検証。

1. **HU 発の ping が動いていない可能性**: `AndroidAutoEntity::schedulePing()` / `sendPing()` は定義されているが、リポジトリ内に呼び出し箇所がない（`grep` で確認）。Discovery では ping_configuration（interval 1000ms, timeout 3000ms）を通知している
2. **`onPingRequest` は応答を返さない**: 受信を再アームするだけで `PingResponse` を送っていない。aasdk の `ControlServiceChannel` も受信時に自動応答はせず（`sendPingResponse` は定義のみ）、openauto 側から呼ぶ箇所もない。再実装では PingRequest を受けたら PingResponse を返す実装にしておくのが安全
3. **VideoFocus の応答が固定**: スマホが `VIDEO_FOCUS_NATIVE` を要求しても、応答は常に `PROJECTED`。NATIVE のときは `/tmp/entityexit` を作るだけで、OS 側がこれを監視して画面を切り替える前提
4. **Bluetooth 認証データが固定値**: `sendBluetoothAuthenticationData` の `auth_data` は `"123456"` 固定（コード中に TODO あり）
5. **`WifiInfoResponse` の security_mode が `WPA2_ENTERPRISE` 固定**: コメントに「AAP と WifiProjection で値が違う」との TODO がある
6. **タッチ座標系**: 4 節 Phase H のとおり、広告するタッチ領域とイベントのスケール先が別
7. **`write()` はプレイヤー準備前のデータを捨てる**: 最初の IDR フレームを取りこぼすと、次の IDR まで映らない可能性がある
8. **外部依存**: `/tmp/*` のフラグファイル（`night_mode_enabled`, `android_device`, `entityexit`, `shutdown`, `reboot`）、`/opt/crankshaft/*.sh|py`、`/usr/local/bin/autoapp_helper`、`/etc/hostapd/hostapd.conf` に依存している。Crankshaft（Raspberry Pi 用 OS）前提の部分なので、他環境ではここを置き換える
9. **ビルド依存**: aasdk と aap_protobuf（必須）、Boost（system, log）、libusb-1.0、Qt5（Multimedia, MultimediaWidgets, Bluetooth, Network, DBus）、OpenSSL、rtaudio、taglib、blkid、gps

---

## 7. 読むべきファイル一覧

openauto（`src/autoapp`）
- `autoapp.cpp` … 組み立てと起動
- `App.cpp` … USB / TCP の接続待ち、Entity のライフサイクル
- `Service/AndroidAutoEntityFactory.cpp` … Transport → Cryptor → Messenger → Entity
- `Service/AndroidAutoEntity.cpp` … 制御チャンネルの状態機械
- `Service/ServiceFactory.cpp` … 有効にするサービスの選択
- `Service/MediaSink/VideoMediaSinkService.cpp` … 映像チャンネルの全手順
- `Projection/QtVideoOutput.cpp`, `Projection/SequentialBuffer.cpp` … 映像の実出力
- `Service/InputSource/InputSourceService.cpp`, `Projection/InputDevice.cpp` … タッチ / ボタン
- `Service/Sensor/SensorService.cpp` … 昼夜 / GPS / 走行状態
- `src/btservice/*` … 無線接続（BT → WiFi）

aasdk
- `src/USB/USBHub.cpp`, `AccessoryModeQueryChain.cpp`, `AccessoryModeQueryFactory.cpp` … AOAP
- `src/Messenger/*`, `src/Transport/*` … フレーミング、TLS、USB / TCP Transport
- `src/Channel/Control/ControlServiceChannel.cpp` … 制御メッセージの振り分け
