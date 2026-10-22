/**
 * @file AndroidAutoController.h
 * @brief Android Auto の接続状態・映像を QML へ橋渡しする Qt 側の窓口。
 *
 * 接続処理そのもの(aabackend/)とは分離している。接続層が使えない/接続できない場合でも
 * このクラスは正常に動作し、状態として「利用不可」「待機中」を UI に出し続ける。
 */
#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <thread>

#include <atomic>

#include <QObject>
#include <QString>
#include <QTimer>
#include <QVariantList>

#include "AasdkBackend.h"
#include "StreamSettings.h"
#include "AudioPlayer.h"
#include "H264Decoder.h"
#include "TestVideoFeeder.h"

namespace opencruise {

class VideoSurfaceItem;
class VehicleDataManager;

/**
 * @brief QML 向けの Android Auto 状態モデル兼コントローラ。
 */
class AndroidAutoController : public QObject {
    Q_OBJECT
    /** "unavailable" / "waiting" / "connecting" / "connected" / "streaming"（色分け等に使う） */
    Q_PROPERTY(QString stateKey READ stateKey NOTIFY stateChanged)
    Q_PROPERTY(QString stateText READ stateText NOTIFY stateChanged)
    Q_PROPERTY(QString detailText READ detailText NOTIFY stateChanged)
    /** 直近の切断理由/エラー。無ければ空 */
    Q_PROPERTY(QString lastIssue READ lastIssue NOTIFY lastIssueChanged)
    Q_PROPERTY(qulonglong frameCount READ frameCount NOTIFY videoStatsChanged)
    Q_PROPERTY(QString videoInfo READ videoInfo NOTIFY videoStatsChanged)
    Q_PROPERTY(bool aasdkEnabled READ aasdkEnabled CONSTANT)
    /** 接続処理を試みた回数（待機に戻るたびに増える） */
    Q_PROPERTY(int attemptCount READ attemptCount NOTIFY stateChanged)
    /** デコード前に受信した映像メッセージ数 */
    Q_PROPERTY(qulonglong videoPacketCount READ videoPacketCount NOTIFY videoStatsChanged)
    /** 解像度の選択肢番号 (0=800x480 / 1=1280x720 / 2=1920x1080)。変更すると接続中でも切断→再接続待機する */
    Q_PROPERTY(int resolutionIndex READ resolutionIndex WRITE setResolutionIndex NOTIFY settingsChanged)
    /** フレームレート (30 / 60)。変更時の挙動は resolutionIndex と同じ */
    Q_PROPERTY(int fps READ fps WRITE setFps NOTIFY settingsChanged)
    /** テーマ: 0=昼 / 1=夜 / 2=自動(時刻で切替)。アプリ表示と Android Auto の昼夜モードに反映される */
    Q_PROPERTY(int themeMode READ themeMode WRITE setThemeMode NOTIFY themeChanged)
    /** 現在実際に夜として表示しているか（themeMode=自動のときは時刻から決まる） */
    Q_PROPERTY(bool nightActive READ nightActive NOTIFY themeChanged)
    /** アクセント色のプリセット番号（色の実体は QML の Theme が持つ） */
    Q_PROPERTY(int accentIndex READ accentIndex WRITE setAccentIndex NOTIFY themeChanged)
    /** Android Auto の昼夜モードをアプリのテーマに連動させるか（OFF なら常に昼） */
    Q_PROPERTY(bool aaFollowsTheme READ aaFollowsTheme WRITE setAaFollowsTheme NOTIFY themeChanged)
    /** 映像表示中にウィンドウ全体を映像にする */
    Q_PROPERTY(bool fullscreenOnStream READ fullscreenOnStream WRITE setFullscreenOnStream NOTIFY settingsChanged)
    /** 動作確認用: ダミーの車両データ(速度・回転数・燃料・ギア・位置)を Android Auto へ送る。位置は実際の位置ではない */
    Q_PROPERTY(bool mockVehicleData READ mockVehicleData WRITE setMockVehicleData NOTIFY settingsChanged)
    /** モック送信中に Android Auto へ送っている値の一覧。[{label, value}, ...](表示用の文字列)。OFF の間は空 */
    Q_PROPERTY(QVariantList mockVehicleItems READ mockVehicleItems NOTIFY mockVehicleChanged)

public:
    /**
     * @brief 状態を「待機準備中(利用不可)」で初期化する。まだ接続処理は始めない。
     * @param parent 親オブジェクト
     */
    explicit AndroidAutoController(QObject *parent = nullptr);

    /** @brief 接続処理を停止してから破棄する。 */
    ~AndroidAutoController() override;

    QString stateKey() const { return stateKey_; }
    QString stateText() const { return stateText_; }
    QString detailText() const { return detailText_; }
    QString lastIssue() const { return lastIssue_; }
    qulonglong frameCount() const { return frameCount_; }
    QString videoInfo() const { return videoInfo_; }
    int attemptCount() const { return attemptCount_; }
    qulonglong videoPacketCount() const { return videoPackets_.load(); }

    int resolutionIndex() const { return settings_.resolution; }
    int fps() const { return settings_.fps; }
    bool fullscreenOnStream() const { return fullscreenOnStream_; }
    bool mockVehicleData() const { return mockVehicleData_; }
    QVariantList mockVehicleItems() const { return mockVehicleItems_; }
    int themeMode() const { return themeMode_; }
    bool nightActive() const { return nightActive_; }
    int accentIndex() const { return accentIndex_; }
    bool aaFollowsTheme() const { return aaFollowsTheme_; }
    void setThemeMode(int mode);
    void setAccentIndex(int index);
    void setAaFollowsTheme(bool enabled);

    /** @brief モックの車両データ送信を切り替えて保存する。ON のとき、接続中の Android Auto へ約 0.5 秒ごとに送る。 */
    void setMockVehicleData(bool enabled);

    /**
     * @brief 車両データの取得元を登録する(所有はしない。アプリ終了まで有効なこと)。
     */
    void setVehicleSource(VehicleDataManager *source) { vehicleSource_ = source; }

    /** @brief 解像度を変更して保存する。接続処理が動作中なら切断して再接続待機へ入る。 */
    void setResolutionIndex(int index);
    /** @brief fps(30/60)を変更して保存する。接続処理が動作中なら切断して再接続待機へ入る。 */
    void setFps(int fps);
    /** @brief 接続後フルスクリーン表示の設定を変更して保存する（再接続は不要）。 */
    void setFullscreenOnStream(bool enabled);

    /** @brief aasdk 接続層がビルドに含まれているか。 */
    bool aasdkEnabled() const;

    /**
     * @brief 映像を描画するアイテムを登録する。QML から呼ぶ。
     *
     * あわせて、そのアイテム上のタッチ操作をスマートフォンへ送る経路もつなぐ。
     * @param surface 描画先
     */
    Q_INVOKABLE void attachSurface(opencruise::VideoSurfaceItem *surface);

    /**
     * @brief スマートフォンの接続待ちを開始する。失敗しても状態に反映するだけで例外は投げない。
     */
    Q_INVOKABLE void start();

    /**
     * @brief 接続待ち・セッションを停止する。アプリ終了時に呼ばれる。
     */
    Q_INVOKABLE void stop();

    /**
     * @brief 開発用: H.264 ファイルを映像として流し込む（aasdk 経由ではない）。
     * @param path H.264 Annex-B ファイル
     */
    void playTestStream(const QString &path);

signals:
    /** @brief 接続状態(stateKey/stateText/detailText)が変わったとき。 */
    void stateChanged();
    /** @brief lastIssue が変わったとき。 */
    void lastIssueChanged();
    /** @brief 受信フレーム数または映像サイズ表示が変わったとき。 */
    void videoStatsChanged();
    /** @brief 解像度・fps・フルスクリーン設定が変わったとき。 */
    void settingsChanged();
    /** @brief テーマ(昼夜・色)の設定、または実際の昼夜状態が変わったとき。 */
    void themeChanged();
    /** @brief モック送信中の値の一覧(mockVehicleItems)が更新されたとき。 */
    void mockVehicleChanged();

private:
    /**
     * @brief 状態を UI スレッドで反映する。
     * @param state 接続層の状態(aa::LinkState を int 化したもの)
     * @param detail 詳細メッセージ
     */
    void applyState(int state, const QString &detail);

    /**
     * @brief アイテム上のタッチ操作を接続層へ渡す。接続層が無ければ捨てる。GUI スレッドから呼ばれる。
     */
    void sendTouch(const aa::TouchEvent &event);

    /**
     * @brief 接続層のスレッドから受け取った映像データをデコーダへ渡す。
     */
    void handleVideoData(const std::uint8_t *data, std::size_t size);

    /**
     * @brief デコード済みフレームを描画アイテムへ渡し、統計を更新する（デコードしたスレッドで呼ばれる）。
     */
    void handleDecodedFrame(const QImage &image);

    /**
     * @brief 映像設定を変更する。接続処理が動作中なら ByeBye で正規に切断してから、新設定で待機を再開する。
     */
    void changeStreamSettings(const aa::StreamSettings &next);

    /**
     * @brief 接続層の停止(ByeBye 待ち)を別スレッドで行い、終わったら UI スレッドで待機を再開する。
     *        UI を止めないための処理。
     */
    void restartBackendAsync();

    aa::StreamSettings settings_;
    bool fullscreenOnStream_ = false;

    /** @brief 車両データ(現状はダミー)から送信用の状態を作り、接続中なら Android Auto へ送る。 */
    void pushVehicleData();

    bool mockVehicleData_ = false;
    QVariantList mockVehicleItems_;               ///< 画面表示用: 送信中の値の一覧
    VehicleDataManager *vehicleSource_ = nullptr; ///< 車両データの取得元(非所有)
    QTimer vehicleTimer_;                         ///< 車両データ送信の周期タイマー
    double mockAngleRad_ = 0.0;                   ///< モック位置: 周回コース上の現在角度
    qint64 mockLastMs_ = 0;                       ///< モック位置: 前回計算した時刻
    /** @brief 設定と時刻から昼夜を再計算し、変化があれば通知して Android Auto へ送る。 */
    void updateNight();
    /** @brief 現在の昼夜を接続層へ渡す（Android Auto が連動しない設定なら常に昼）。 */
    void pushNightToBackend();

    int themeMode_ = 2;
    int accentIndex_ = 0;
    bool aaFollowsTheme_ = true;
    bool nightActive_ = false;
    QTimer themeTimer_; ///< 自動モードの昼夜判定を定期的に見直す
    bool restarting_ = false;       ///< 非同期の再起動中(UI スレッドでのみ触る)
    std::thread restartThread_;     ///< 再起動中の停止処理スレッド

    QString stateKey_;
    QString stateText_;
    QString detailText_;
    QString lastIssue_;
    QString videoInfo_ = QStringLiteral("-");
    std::atomic<qulonglong> frameCount_{0};
    std::atomic<bool> decoderErrorReported_{false};
    int currentState_ = static_cast<int>(aa::LinkState::Unavailable);

    std::atomic<qulonglong> videoPackets_{0}; ///< デコード前に受信した映像メッセージ数
    std::atomic<qulonglong> videoBytes_{0};   ///< 受信した映像データの累計バイト数
    int attemptCount_ = 0;                    ///< 接続処理を開始/再試行した回数
    qint64 startedAtMs_ = 0;                  ///< 接続処理を開始した実時刻 (エポックミリ秒)
    QTimer watchdog_;                         ///< 進まない状態を記録する定期タイマー

    std::mutex surfaceMutex_;
    VideoSurfaceItem *surface_ = nullptr; ///< surfaceMutex_ で保護

    std::unique_ptr<aa::AasdkBackend> backend_;
    H264Decoder decoder_;
    AudioPlayer audioPlayer_; ///< 音声出力（UI スレッド専用）
    TestVideoFeeder testFeeder_;
};

} // namespace opencruise
