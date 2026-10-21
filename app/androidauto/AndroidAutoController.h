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

#include <atomic>

#include <QObject>
#include <QString>
#include <QTimer>

#include "AasdkBackend.h"
#include "H264Decoder.h"
#include "TestVideoFeeder.h"

namespace opencruise {

class VideoSurfaceItem;

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
    TestVideoFeeder testFeeder_;
};

} // namespace opencruise
