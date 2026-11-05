# デスクトップアプリ（Windows / Linux）に Android Auto ヘッドユニットを実装する手順（USB / AOAP 専用）

前提メモ: `openauto-androidauto-flow.md`（接続〜映像表示の仕様）。このガイドはそれを「自分のアプリにどう組み込むか」に絞った実装編。

表記
- **[確認済]** opencardev/openauto・opencardev/aasdk の main を読んで確認した内容
- **[推奨]** 実装上の判断（こう作るのがよい、という提案）
- **[未検証]** 一般知識や推測。実機で確認が必要
- コードは骨子。コンパイルは未実施で、API 名は上記リポジトリのヘッダから拾っている

---

## 0. 方針

**USB / AOAP のプロトコルスタックは自作せず、aasdk をそのまま使う。アプリ側で書くのは「サービス層」と「映像表示・入力」だけ。** [推奨]

理由: USB ホットプラグ、AOAP 切り替え、フレーム分割、TLS、各チャンネルの protobuf 送受信は aasdk に揃っている [確認済]。ここを自作すると工数の大半を占める。openauto の `src/autoapp` も同じ使い方をしている。

| 層 | 誰が用意するか |
|---|---|
| USB 検出 / AOAP 切り替え (`USBHub`, `AccessoryModeQueryChain`) | aasdk |
| Transport / TLS / Messenger | aasdk (`USBTransport`, `Cryptor`, `Messenger`) |
| 各チャンネルの送受信 API (`ControlServiceChannel`, `VideoChannel`, `InputSourceService`, ...) | aasdk |
| **ハンドシェイク進行 (Control の状態機械)** | **自分のアプリ** |
| **映像: H.264 デコード + 表示** | **自分のアプリ** |
| **入力: マウス/タッチ → InputReport** | **自分のアプリ** |
| **Service Discovery の中身 (どのチャンネルを持つか)** | **自分のアプリ** |
| 音声 (System audio は最低限のスタブが必要) | 自分のアプリ |

---

## 1. 環境構築

### 1.1 依存ライブラリ

- aasdk と aap_protobuf（`find_package(aasdk)` / `find_package(aap_protobuf)`。openauto の CMake も同じ）[確認済]
- aasdk の依存: Boost (system, log)、libusb-1.0、OpenSSL、protobuf [確認済]
- アプリ側: FFmpeg（libavcodec / libavutil / libswscale）+ SDL2 [推奨]

### 1.2 Linux（先にこちらで作るのを推奨）

- aasdk は Linux 前提でテストされている。Ubuntu/Debian なら `libboost-all-dev libusb-1.0-0-dev libssl-dev libprotobuf-dev protobuf-compiler` を入れて CMake でビルド [確認済: aasdk Readme]
- USB デバイスを一般ユーザーで開くには udev ルールが必要。aasdk の TROUBLESHOOTING には `SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev"` のようなメーカー別ルールの例がある [確認済]
  - 注意: AOAP 切り替え前のスマホはメーカー固有の VID で見える。**接続するスマホのメーカーの VID も許可する**こと（上のルールは 18d1 = Google 用、ほか 22b8 / 04e8 / 0bb4 の例が載っている）

### 1.3 Windows（要注意）

- aasdk 付属の `build.ps1` / `build.bat` は実際のビルドを WSL / Git Bash / DevContainer に委ねる作りで、**ネイティブ MSVC ビルドが公式に整っているとは読み取れない** [確認済]。BUILD.md には vcpkg（boost-system, boost-log, libusb, openssl, protobuf）で入れる手順が載っているが、動作確認までは分からない [確認済: 記載のみ]
- WSL 上では USB を `usbipd` で渡す必要があり（TROUBLESHOOTING に記載 [確認済]）、デスクトップアプリとしては現実的でない
- **[推奨]** 最初は Linux で完成させ、Windows は「vcpkg で aasdk を MSVC ビルドできるか」を別タスクで検証する。ビルドが通らなければ、aasdk に Windows 向けの修正を入れる覚悟が要る
- **[未検証]** Windows では libusb がデバイスを開くために WinUSB 等のドライバが必要になる。通常モード（MTP など）のスマホには Zadig で WinUSB を当て、AOAP 切り替え後の `18D1:2D00/2D01` にも別途ドライバが必要になる可能性が高い。ユーザー配布するなら、ドライバ導入手順の案内が必要

---

## 2. アプリの構成

```
app/
  main.cpp                 ... スレッド起動、依存組み立て、待機ループ
  HeadUnit.{hpp,cpp}       ... USB 待機 + Session のライフサイクル (openauto の App に相当)
  Session.{hpp,cpp}        ... 1 回の接続 (openauto の AndroidAutoEntity に相当)
  services/
    IService.hpp           ... start/stop/fillFeatures (openauto の IService と同じ形)
    VideoService.{hpp,cpp} ... 映像チャンネル
    InputService.{hpp,cpp} ... 入力チャンネル
    SensorService.{hpp,cpp}... センサーチャンネル
    SystemAudioService.{hpp,cpp} ... 最低限のスタブ
  video/
    H264Decoder.{hpp,cpp}  ... FFmpeg デコード
    VideoWindow.{hpp,cpp}  ... SDL2 描画 + 入力取得
```

### スレッドモデル [推奨]

| スレッド | 役割 |
|---|---|
| libusb イベントスレッド（1〜数本） | `libusb_handle_events_timeout_completed` を回す。openauto は 4 本 [確認済] |
| io_service スレッド（1〜数本） | aasdk の非同期処理とすべての Service ハンドラ。openauto は 4 本 [確認済] |
| デコードスレッド（1 本） | 映像データをキューから取り出して FFmpeg でデコード |
| メインスレッド | SDL2 の描画とイベントループ（SDL はメインスレッド必須の環境が多い） |

ルール:
- チャンネルの `send*` / `receive` は、そのサービスの `strand` 上から呼ぶ（aasdk のチャンネルは `strand` を受け取って作る [確認済]）
- 映像の `write()` は **io_service スレッドで待たされないこと**。キューに積んで即 return し、ACK はすぐ返す（openauto も write 直後に ACK [確認済]）

---

## 3. 実装手順

### M1. USB 待機から Session 生成まで

openauto の `autoapp.cpp` / `App.cpp` と同じ流れ [確認済]。

```cpp
// main.cpp（骨子）
libusb_context* usb = nullptr;
libusb_init(&usb);

boost::asio::io_service io;
boost::asio::io_service::work work(io);
std::vector<std::thread> threads;
threads.emplace_back([&]{                       // libusb イベント
    timeval t{180, 0};
    while (!io.stopped()) libusb_handle_events_timeout_completed(usb, &t, nullptr);
});
threads.emplace_back([&]{ io.run(); });          // asio

aasdk::usb::USBWrapper usbWrapper(usb);
aasdk::usb::AccessoryModeQueryFactory qf(usbWrapper, io);
aasdk::usb::AccessoryModeQueryChainFactory qcf(usbWrapper, io, qf);
auto hub = std::make_shared<aasdk::usb::USBHub>(usbWrapper, io, qcf);

auto hu = std::make_shared<HeadUnit>(io, usbWrapper, hub /*, video window など*/);
hu->waitForDevice();
// ... SDL のメインループ（Phase M5 参照）
```

```cpp
// HeadUnit::waitForDevice（App::waitForDevice 相当）
void HeadUnit::waitForDevice() {
    auto p = aasdk::usb::IUSBHub::Promise::defer(strand_);
    p->then([this, self = shared_from_this()](aasdk::usb::DeviceHandle h) { onDevice(std::move(h)); },
            [](const aasdk::error::Error& e) { /* OPERATION_ABORTED 以外はログ */ });
    hub_->start(std::move(p));
}

void HeadUnit::onDevice(aasdk::usb::DeviceHandle h) {
    if (session_) return;                         // 既に接続中
    auto aoap = aasdk::usb::AOAPDevice::create(usbWrapper_, io_, h);
    session_ = Session::create(io_, std::move(aoap), config_, video_);
    session_->start(*this);                       // HeadUnit が onQuit を受ける
}

void HeadUnit::onSessionQuit() {                  // Session から呼ばれる
    strand_.dispatch([this, self = shared_from_this()] {
        if (session_) { session_->stop(); session_.reset(); }
        waitForDevice();                          // 再接続待ちへ戻る
    });
}
```

M1 の完了条件: スマホを挿すと、ログに「AOAP モードへ切り替え → `18D1:2D00/2D01` で再到着 → `onDevice` が呼ばれた」が出る。**ここまでは Session の中身が空でも確認できる。**

### M2. Session（Transport → Cryptor → Messenger → Control）

`AndroidAutoEntityFactory::create` と同じ組み立て [確認済]。

```cpp
// Session::create の中身
auto transport = std::make_shared<aasdk::transport::USBTransport>(io, std::move(aoap));
auto ssl       = std::make_shared<aasdk::transport::SSLWrapper>();
auto cryptor   = std::make_shared<aasdk::messenger::Cryptor>(std::move(ssl));
cryptor->init();
auto messenger = std::make_shared<aasdk::messenger::Messenger>(io,
    std::make_shared<aasdk::messenger::MessageInStream>(io, transport, cryptor),
    std::make_shared<aasdk::messenger::MessageOutStream>(io, transport, cryptor));
```

Session は `IControlServiceChannelEventHandler` を実装する。実装すべきハンドラは 12 個 [確認済: ヘッダ]。

```cpp
class Session : public aasdk::channel::control::IControlServiceChannelEventHandler,
                public std::enable_shared_from_this<Session> {
    // メンバ: strand_, cryptor_, transport_, messenger_, control_(ControlServiceChannel), services_
public:
    void start(IQuitHandler& q) {
        strand_.dispatch([this, self = shared_from_this(), &q] {
            quit_ = &q;
            for (auto& s : services_) s->start();               // 各チャンネルの receive 開始
            control_->sendVersionRequest(sendOk());
            control_->receive(shared_from_this());
        });
    }

    // 1) バージョン
    void onVersionResponse(uint16_t maj, uint16_t min, aap_protobuf::shared::MessageStatus st) override {
        if (st == aap_protobuf::shared::MessageStatus::STATUS_NO_COMPATIBLE_VERSION) { quit(); return; }
        cryptor_->doHandshake();
        control_->sendHandshake(cryptor_->readHandshakeBuffer(), sendOk());
        control_->receive(shared_from_this());
    }

    // 2) TLS（完了するまで往復）
    void onHandshake(const aasdk::common::DataConstBuffer& payload) override {
        cryptor_->writeHandshakeBuffer(payload);
        if (!cryptor_->doHandshake()) {
            control_->sendHandshake(cryptor_->readHandshakeBuffer(), sendOk());
        } else {
            aap_protobuf::service::control::message::AuthResponse r;
            r.set_status(aap_protobuf::shared::MessageStatus::STATUS_SUCCESS);
            control_->sendAuthComplete(r, sendOk());
        }
        control_->receive(shared_from_this());
    }

    // 3) Service Discovery
    void onServiceDiscoveryRequest(const ServiceDiscoveryRequest&) override {
        ServiceDiscoveryResponse resp;
        resp.set_display_name("MyHeadUnit");
        resp.set_driver_position(DRIVER_POSITION_RIGHT);        // 左ハンドル圏なら LEFT に
        resp.set_probe_for_support(false);
        auto* ping = resp.mutable_connection_configuration()->mutable_ping_configuration();
        ping->set_tracked_ping_count(5);  ping->set_timeout_ms(3000);
        ping->set_interval_ms(1000);      ping->set_high_latency_threshold_ms(200);
        auto* hu = resp.mutable_headunit_info();
        hu->set_make("MyMake"); hu->set_model("MyModel"); hu->set_year("2026");
        hu->set_vehicle_id("0000000000000001");
        hu->set_head_unit_make("MyMake"); hu->set_head_unit_model("MyHU");
        hu->set_head_unit_software_build("1"); hu->set_head_unit_software_version("1.0");
        for (auto& s : services_) s->fillFeatures(resp);
        control_->sendServiceDiscoveryResponse(resp, sendOk());
        control_->receive(shared_from_this());
    }

    // 4) 定型応答
    void onAudioFocusRequest(const AudioFocusRequest& req) override {
        AudioFocusNotification n;
        n.set_focus_state(req.audio_focus_type() == AUDIO_FOCUS_RELEASE
                              ? AUDIO_FOCUS_STATE_LOSS : AUDIO_FOCUS_STATE_GAIN);
        control_->sendAudioFocusResponse(n, sendOk());
        control_->receive(shared_from_this());
    }
    void onNavigationFocusRequest(const NavFocusRequestNotification&) override {
        NavFocusNotification n; n.set_focus_type(NAV_FOCUS_PROJECTED);
        control_->sendNavigationFocusResponse(n, sendOk());
        control_->receive(shared_from_this());
    }

    // 5) Ping: 元実装に無い応答を、ここでは返す
    void onPingRequest(const PingRequest& req) override {
        PingResponse r; r.set_timestamp(req.timestamp());
        control_->sendPingResponse(r, sendOk());
        control_->receive(shared_from_this());
    }
    void onPingResponse(const PingResponse&) override { control_->receive(shared_from_this()); }

    // 6) 受け流すもの
    void onBatteryStatusNotification(const BatteryStatusNotification&) override { control_->receive(shared_from_this()); }
    void onVoiceSessionRequest(const VoiceSessionNotification&) override        { control_->receive(shared_from_this()); }

    // 7) 終了
    void onByeByeRequest(const ByeByeRequest&) override {
        ByeByeResponse r;
        auto p = aasdk::channel::SendPromise::defer(strand_);
        p->then([this, self = shared_from_this()] { quit(); },
                [this, self = shared_from_this()](auto& e) { onChannelError(e); });
        control_->sendShutdownResponse(r, std::move(p));
    }
    void onByeByeResponse(const ByeByeResponse&) override { quit(); }

    void onChannelError(const aasdk::error::Error& e) override {
        if (e.getCode() == aasdk::error::ErrorCode::OPERATION_ABORTED) return;   // 停止中は無視
        if (stopping_) return;                                                   // 再入防止
        quit();
    }

private:
    aasdk::channel::SendPromise::Pointer sendOk() {
        auto p = aasdk::channel::SendPromise::defer(strand_);
        p->then([] {}, [this, self = shared_from_this()](const aasdk::error::Error& e) { onChannelError(e); });
        return p;
    }
};
```

ポイント:
- **各ハンドラの最後で必ず `control_->receive(...)` を呼び直す**。呼ばないと次のメッセージを受け取れず、そこで止まる [確認済: openauto のどのハンドラも末尾で receive を再アームしている。ByeByeRequest だけは終了なので呼ばない]
- `PingRequest` に応答する実装は元の openauto には無い（5 節の観察）。ここでは返す形にしてある [推奨]
- `stop()` は `stopping_` を先に立ててから、`services` の stop → `messenger->stop()` → `transport->stop()` → `cryptor->deinit()` の順 [確認済]

M2 の完了条件: ログに `Version → Handshake completed → ServiceDiscoveryRequest` が出る。サービスが空でも、Discovery に応答できるところまでは進む（ただしスマホはその後すぐ切断する）。

### M3. 映像サービス（これが本体）

`IVideoMediaSinkServiceEventHandler` を実装する。aasdk 側のチャンネルは `aasdk::channel::mediasink::video::channel::VideoChannel(strand, messenger)` [確認済]。

```cpp
class VideoService : public aasdk::channel::mediasink::video::IVideoMediaSinkServiceEventHandler,
                     public IService, public std::enable_shared_from_this<VideoService> {
    boost::asio::io_service::strand strand_;
    aasdk::channel::mediasink::video::IVideoMediaSinkService::Pointer channel_;   // VideoChannel
    IVideoSink& sink_;        // デコード + 表示（M4）
    int32_t session_ = -1;
public:
    void start() override { strand_.dispatch([this, self = shared_from_this()] { channel_->receive(self); }); }
    void stop()  override { strand_.dispatch([this, self = shared_from_this()] { sink_.stop(); }); }

    void fillFeatures(ServiceDiscoveryResponse& resp) override {
        auto* svc = resp.add_channels();
        svc->set_id(static_cast<uint32_t>(channel_->getId()));
        auto* v = svc->mutable_media_sink_service();
        v->set_available_type(MEDIA_CODEC_VIDEO_H264_BP);
        v->set_available_while_in_call(true);
        auto* cfg = v->add_video_configs();
        cfg->set_codec_resolution(VIDEO_1280x720);      // 800x480 / 1280x720 / 1920x1080 のいずれか
        cfg->set_frame_rate(VIDEO_FPS_30);               // 60fps を使うなら VIDEO_FPS_60（要実機確認）
        cfg->set_width_margin(0);  cfg->set_height_margin(0);
        cfg->set_density(160);                           // 画面サイズに合わせて調整（openauto は 140）
    }

    void onChannelOpenRequest(const ChannelOpenRequest&) override {
        ChannelOpenResponse r;
        r.set_status(sink_.open() ? STATUS_SUCCESS : STATUS_INTERNAL_ERROR);
        channel_->sendChannelOpenResponse(r, sendOk());
        channel_->receive(shared_from_this());
    }

    void onMediaChannelSetupRequest(const Setup&) override {
        Config c;
        c.set_status(sink_.init() ? Config::STATUS_READY : Config::STATUS_WAIT);
        c.set_max_unacked(1);
        c.add_configuration_indices(0);
        auto p = aasdk::channel::SendPromise::defer(strand_);
        p->then([this, self = shared_from_this()] { sendVideoFocus(); },     // Config 送信成功後にフォーカス通知
                [this, self = shared_from_this()](auto& e) { onChannelError(e); });
        channel_->sendChannelSetupResponse(c, std::move(p));
        channel_->receive(shared_from_this());
    }

    void onMediaChannelStartIndication(const Start& s) override { session_ = s.session_id(); channel_->receive(shared_from_this()); }
    void onMediaChannelStopIndication(const Stop&) override     { channel_->receive(shared_from_this()); }

    void onMediaWithTimestampIndication(aasdk::messenger::Timestamp::ValueType ts,
                                        const aasdk::common::DataConstBuffer& buf) override {
        sink_.write(ts, buf.cdata, buf.size);            // 必ず即 return（キュー投入のみ）
        Ack a; a.set_session_id(session_); a.set_ack(1);
        channel_->sendMediaAckIndication(a, sendOk());
        channel_->receive(shared_from_this());
    }
    void onMediaIndication(const aasdk::common::DataConstBuffer& b) override { onMediaWithTimestampIndication(0, b); }

    void onVideoFocusRequest(const VideoFocusRequestNotification&) override {
        sendVideoFocus();
        channel_->receive(shared_from_this());
    }
    void sendVideoFocus() {
        VideoFocusNotification n;
        n.set_focus(VIDEO_FOCUS_PROJECTED);
        n.set_unsolicited(false);
        channel_->sendVideoFocusIndication(n, sendOk());
    }
};
```

M3 の完了条件: `ChannelOpen → Setup → VideoFocus → Start → 映像データ受信` のログが出て、受信バイト数が増え続ける。

**ここでまず、受け取った H.264 をファイルに書き出す**（7 節のデバッグ手順）。デコーダ実装より先に、データが正しく届いているかを `ffplay` で確かめられる。

### M4. 映像デコードと表示（FFmpeg + SDL2）[推奨]

openauto は Qt の `QMediaPlayer` に H.264 のバイトストリームを流し、デコードを GStreamer に任せている [確認済]。デスクトップの新規アプリでは、FFmpeg で自前デコードしたほうが、プラットフォーム差とバッファ挙動を制御しやすい。

```cpp
struct IVideoSink {
    virtual bool open() = 0;                          // ChannelOpenRequest 時
    virtual bool init() = 0;                          // Setup 時（デコーダ準備）
    virtual void write(uint64_t ts, const uint8_t* d, size_t n) = 0;   // 即 return
    virtual void stop() = 0;
};
```

デコーダ側（概念コード）:

```cpp
// 初期化
const AVCodec* codec = avcodec_find_decoder(AV_CODEC_ID_H264);
parser_ = av_parser_init(AV_CODEC_ID_H264);
ctx_    = avcodec_alloc_context3(codec);
ctx_->flags  |= AV_CODEC_FLAG_LOW_DELAY;              // 遅延を減らす
ctx_->flags2 |= AV_CODEC_FLAG2_FAST;
avcodec_open2(ctx_, codec, nullptr);

// write(): ネットワークスレッド側。キューに積むだけ
void write(uint64_t ts, const uint8_t* d, size_t n) {
    std::lock_guard lk(m_);
    if (q_.size() > kMaxQueued) { q_.clear(); needKeyframe_ = true; }   // 溜まりすぎたら破棄して次の IDR 待ち
    q_.emplace_back(d, d + n);
    cv_.notify_one();
}

// デコードスレッド
while (running_) {
    auto chunk = popBlocking();
    const uint8_t* p = chunk.data(); int left = chunk.size();
    while (left > 0) {
        int used = av_parser_parse2(parser_, ctx_, &pkt_->data, &pkt_->size, p, left,
                                    AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0);
        p += used; left -= used;
        if (pkt_->size > 0 && avcodec_send_packet(ctx_, pkt_) == 0) {
            while (avcodec_receive_frame(ctx_, frame_) == 0) presentFrame(frame_);   // 最新フレームだけ保持
        }
    }
}
```

表示側（SDL2、メインスレッド）:
- ウィンドウ作成後、`SDL_CreateTexture(renderer, SDL_PIXELFORMAT_IYUV, SDL_TEXTUREACCESS_STREAMING, w, h)`
- デコードスレッドは「最新フレーム」を共有バッファに置く。メインループが `SDL_UpdateYUVTexture` → `SDL_RenderCopy` → `SDL_RenderPresent`
- 遅延重視なら、メインループは常に最新 1 枚だけ描画し、古いフレームは捨てる

運用上のポイント:
- **SPS/PPS を含む最初のデータが先に届く**（コーデック設定）。`av_parser_parse2` に順に流せば、デコーダが自動で取り込む [未検証: 実機のデータ形式。openauto は同じバイト列を `QMediaPlayer` に流しているだけなので、Annex B 形式のバイトストリームとして扱えると考えられる]
- デコーダ準備前に届いたデータを捨てるか溜めるか: openauto の `QtVideoOutput` は準備完了までのデータを**捨てる**ので、最初のキーフレームを取りこぼすことがある [確認済]。自前実装では、`init()` 時点でデコーダを作り、届いたデータは**最初から全部キューに入れる**ほうが安全 [推奨]
- ハードウェアデコード（VAAPI / D3D11VA など）は、まずソフトウェアデコードで動かしてから足す。720p30 なら CPU デコードで通常は足りる [未検証]
- 画面サイズが映像解像度と違うときは、SDL の論理サイズ（`SDL_RenderSetLogicalSize`）でレターボックスにすると、入力座標の変換が楽になる

### M5. 入力サービス（タッチ / ボタン）

チャンネル: `aasdk::channel::inputsource::InputSourceService(strand, messenger)`。ハンドラは 3 つ（`onChannelOpenRequest`, `onKeyBindingRequest`, `onChannelError`）[確認済]。

```cpp
void fillFeatures(ServiceDiscoveryResponse& resp) override {
    auto* svc = resp.add_channels();
    svc->set_id(static_cast<uint32_t>(channel_->getId()));
    auto* in = svc->mutable_input_source_service();
    for (auto k : {KEYCODE_BACK, KEYCODE_HOME, KEYCODE_DPAD_UP, KEYCODE_DPAD_DOWN,
                   KEYCODE_DPAD_LEFT, KEYCODE_DPAD_RIGHT, KEYCODE_DPAD_CENTER})
        in->add_keycodes_supported(k);
    auto* ts = in->add_touchscreen();
    ts->set_width(videoWidth);  ts->set_height(videoHeight);   // ★映像解像度と同じにする
}

void onKeyBindingRequest(const KeyBindingRequest& req) override {
    KeyBindingResponse r; r.set_status(STATUS_SUCCESS);        // 要求キーが対応済みか確認し、違えば STATUS_KEYCODE_NOT_BOUND
    channel_->sendKeyBindingResponse(r, sendOk());
    channel_->receive(shared_from_this());
    started_ = true;                                           // 以降、入力を送ってよい
}

void sendTouch(PointerAction action, int actionIndex, const std::vector<Pointer>& pts) {
    strand_.dispatch([=, self = shared_from_this()] {
        InputReport rep;
        rep.set_timestamp(nowMicros());
        auto* t = rep.mutable_touch_event();
        t->set_action(action);  t->set_action_index(actionIndex);
        for (auto& p : pts) { auto* d = t->add_pointer_data(); d->set_x(p.x); d->set_y(p.y); d->set_pointer_id(p.id); }
        channel_->sendInputReport(rep, sendOk());
    });
}
```

座標変換（ウィンドウ座標 → 映像座標）:

```cpp
// SDL_RenderSetLogicalSize(r, videoW, videoH) を使うなら
float lx, ly;  SDL_RenderWindowToLogical(renderer, mouseX, mouseY, &lx, &ly);
x = clamp((int)lx, 0, videoW - 1);  y = clamp((int)ly, 0, videoH - 1);
```

- マウス: `SDL_MOUSEBUTTONDOWN` → `ACTION_DOWN`、`SDL_MOUSEMOTION`（左ボタン押下中）→ `ACTION_MOVED`、`SDL_MOUSEBUTTONUP` → `ACTION_UP`（openauto のマウス代替と同じ割り当て [確認済]）
- マルチタッチ（タッチパネルのある PC）は `SDL_FINGERDOWN/MOTION/UP` を `pointer_id` 付きで複数送る。2 本目以降の指には `ACTION_POINTER_DOWN`(5) / `ACTION_POINTER_UP`(6) を使い、`action_index` に動いた指の番号を入れる [確認済: enum 定義 / 未検証: 実機での挙動]
- **タッチ領域の座標系**: openauto は Discovery でタッチ領域に**物理画面サイズ**を通知する一方、送る座標は映像解像度に変換している [確認済]。自前実装では、通知値と送る座標を**同じ映像解像度**に揃える [推奨]
- ボタン: `InputReport.key_event.add_keys()` に `keycode / down / longpress=false / metastate=0` [確認済]

### M6. センサー / System audio（最低限）

**センサー**: `aasdk::channel::sensorsource::SensorSourceService(strand, messenger)`。最小実装は、Discovery で 3 種類を宣言し、`SensorStartRequest` に成功を返してから初期値を 1 回送る [確認済]。

```cpp
void fillFeatures(ServiceDiscoveryResponse& resp) override {
    auto* svc = resp.add_channels();
    svc->set_id(static_cast<uint32_t>(channel_->getId()));
    auto* s = svc->mutable_sensor_source_service();
    s->add_sensors()->set_sensor_type(SENSOR_DRIVING_STATUS_DATA);
    s->add_sensors()->set_sensor_type(SENSOR_NIGHT_MODE);
    // GPS が不要なら SENSOR_LOCATION は宣言しなくてよい
}

void onSensorStartRequest(const SensorRequest& req) override {
    SensorStartResponseMessage r; r.set_status(STATUS_SUCCESS);
    auto p = aasdk::channel::SendPromise::defer(strand_);
    if (req.type() == SENSOR_DRIVING_STATUS_DATA)
        p->then([this, s = shared_from_this()] { sendDrivingUnrestricted(); }, errHandler());
    else if (req.type() == SENSOR_NIGHT_MODE)
        p->then([this, s = shared_from_this()] { sendNight(false); }, errHandler());
    else
        p->then([] {}, errHandler());
    channel_->sendSensorStartResponse(r, std::move(p));
    channel_->receive(shared_from_this());
}
// sendDrivingUnrestricted: SensorBatch.add_driving_status_data()->set_status(DRIVE_STATUS_UNRESTRICTED)
// sendNight:               SensorBatch.add_night_mode_data()->set_night_mode(isNight)
```

openauto は GPS（gpsd）と、昼夜を `/tmp/night_mode_enabled` ファイルで切り替える実装 [確認済]。デスクトップでは、昼夜は OS のテーマや UI ボタンから `sendNight` を呼べばよい。

**System audio**: 元実装は「常に有効にすること（MUST）」とコメントしている [確認済]。最小のスタブ:

- チャンネル: `aasdk::channel::mediasink::audio::channel::SystemAudioChannel(strand, messenger)`（ハンドラは映像と同じ形で 7 つ。映像フォーカス用の `onVideoFocusRequest` だけ無い）[確認済]
- `fillFeatures`: `available_type = MEDIA_CODEC_AUDIO_PCM`、`audio_type = AUDIO_STREAM_SYSTEM_AUDIO`、`available_while_in_call = true`、`audio_configs[0]` = 16000Hz / 16bit / 1ch [確認済]
- `onChannelOpenRequest` → SUCCESS、`onMediaChannelSetupRequest` → `Config{READY, max_unacked=1, indices=[0]}`、メディアデータは**捨てて ACK だけ返す**
- 音を出したい場合は、Media(48kHz/16bit/2ch) と Guidance(16kHz/16bit/1ch) のチャンネルを同じ形で足し、PCM を SDL_audio や miniaudio に流す [確認済: 形式 / 推奨: 出力ライブラリ]

### M7. 切断と再接続

- 切断要因: `ByeByeRequest/Response`、チャンネルエラー、USB 抜去 → すべて `Session::quit()` に集約し `HeadUnit::onSessionQuit()` へ [確認済: openauto と同じ設計]
- `onSessionQuit` で Session を stop → reset → `waitForDevice()` で再度ホットプラグ待ち。`USBHub::start` は新しい promise を受け取り直せる（前の promise は OPERATION_ABORTED で reject される）[確認済]
- 映像ウィンドウは Session より長生きさせ、切断中は「接続待ち」画面に戻す [推奨]

---

## 4. 動作確認の進め方（ログで段階を切る）

1. M1: AOAP 切り替えと `onDevice` 呼び出し
2. M2: Version → TLS 完了 → ServiceDiscoveryRequest 受信
3. M3: ChannelOpen → Setup → VideoFocus → Start → 映像データ受信
4. M4: 映像が表示される
5. M5: タッチが効く
6. M6: センサー / audio スタブで切断されずに安定動作

どの段階で止まったかが分かるよう、Control のハンドラ名と Service のハンドラ名をそのままログに出す（openauto は `[AndroidAutoEntity] onVersionResponse()` のように出している [確認済]）。

## 5. デバッグ手順

- **映像が出ないとき、デコーダ側の問題か受信側の問題かを切り分ける**: `VideoService::onMediaWithTimestampIndication` で受信データを `dump.h264` に追記し、`ffplay -f h264 dump.h264`（または `ffmpeg -f h264 -i dump.h264 out.mp4`）で再生できるか見る。再生できれば受信は正しく、問題は自前デコーダ/表示にある [推奨]
- スマホの接続が数秒で切れる: ping 応答、ACK の返し忘れ、`receive()` の再アーム漏れを疑う（どれも切断やストールにつながる）
- 画面が真っ黒だがデータは来ている: 最初の SPS/PPS/IDR を取りこぼしていないか。デコーダ準備前のデータを捨てていないか
- 画面が歪む / 黒い帯が出る: Discovery の解像度と margin、描画側のアスペクト比処理を確認
- aasdk は Boost.Log を使うので、ログレベルを debug にすると Messenger / Channel 層のやり取りが追える [確認済: aasdk に Boost.Log 依存あり]

## 6. 落とし穴チェックリスト

1. 各ハンドラの末尾で `receive()` を再アームしているか（`ByeBye` を除く）
2. `strand` を使わずにチャンネル API を呼んでいないか（io_service を複数スレッドで回す場合は特に）
3. 映像の `write()` 内で重い処理（デコードや描画）をしていないか。ACK が遅れるとスマホが送信を止める（`max_unacked = 1`）
4. Discovery に `System audio` を入れ忘れていないか
5. タッチ領域の通知値と送信座標が同じ座標系か
6. 切断時に `stopping_` を立ててからエラーを無視し、`triggerQuit` が再入しないか
7. Session を作り直したときに、古い Session のコールバックが生きていないか（`shared_from_this` の循環と、`stop()` 時の参照解放）
8. Linux の udev / Windows のドライバ（1 節）
9. aasdk のバージョン差: このガイドは main の API で書いている。タグ付きリリースやディストリのパッケージ版はインターフェースが異なる可能性がある [未検証]

## 7. AI にこのガイドを渡すときのプロンプト例

```
デスクトップ(Linux 先行)向けの Android Auto ヘッドユニットを C++ で実装する。
- USB(AOAP)のみ。USB/AOAP/TLS/Messenger/各チャンネルは opencardev/aasdk を使い、自作しない
- 構成: main.cpp, HeadUnit, Session(IControlServiceChannelEventHandler), VideoService, InputService, SensorService, SystemAudioService(スタブ), H264Decoder(FFmpeg), VideoWindow(SDL2)
- 手順は M1→M7 の順。各マイルストーンの完了条件(ログ出力)を満たすコードを出す
- 全ハンドラの末尾で receive() を再アーム。PingRequest には PingResponse を返す
- 映像: H.264 を受けたらキューに積み即 return し ACK を返す。デコードは別スレッド、表示は SDL2 メインスレッド
- 入力: タッチ領域の通知値と送信座標を映像解像度に統一
- まず受信 H.264 を dump.h264 に書き出すデバッグオプションを付ける
```

---

## 8. 参照（このガイドで根拠にしたファイル）

openauto: `src/autoapp/autoapp.cpp`, `App.cpp`, `Service/AndroidAutoEntity.cpp`, `AndroidAutoEntityFactory.cpp`, `ServiceFactory.cpp`, `Service/MediaSink/VideoMediaSinkService.cpp`, `AudioMediaSinkService.cpp`, `Service/InputSource/InputSourceService.cpp`, `Service/Sensor/SensorService.cpp`, `Projection/QtVideoOutput.cpp`, `Projection/InputDevice.cpp`
aasdk: `include/aasdk/Channel/**/I*ServiceEventHandler.hpp`, `I*Service.hpp`, `src/USB/USBHub.cpp`, `src/Channel/Control/ControlServiceChannel.cpp`, `BUILD.md`, `TROUBLESHOOTING.md`, `build.ps1`
