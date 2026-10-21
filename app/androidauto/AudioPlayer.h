/**
 * @file AudioPlayer.h
 * @brief Android Auto から届いた PCM 音声を QAudioSink で再生するクラス。
 */
#pragma once

#include <memory>

#include <QAudioSink>
#include <QByteArray>
#include <QElapsedTimer>
#include <QIODevice>
#include <QMutex>
#include <QObject>
#include <QTimer>

namespace opencruise {

/**
 * @brief PCM を溜めておき、シンクの要求に応じて渡す pull 型デバイス。
 *
 * データ不足(アンダーラン)時は無音を返してシンクを動かし続ける。
 * こうしないとバックエンドによっては Idle のまま再開せず、最初の一瞬しか鳴らなくなる。
 */
class PcmQueueDevice : public QIODevice {
public:
    PcmQueueDevice(int bytesPerSecond, QObject *parent = nullptr);

    /** @brief PCM を末尾へ追加する。溜まりすぎた分は古い方から捨てる。 */
    void push(const QByteArray &pcm);
    /** @brief 未再生のバイト数。 */
    qint64 queuedBytes() const;
    /** @brief 最後に push された時刻からの経過ミリ秒。 */
    qint64 msSinceLastPush() const;

    bool isSequential() const override { return true; }
    qint64 bytesAvailable() const override;

protected:
    qint64 readData(char *data, qint64 maxlen) override;
    qint64 writeData(const char *, qint64) override { return -1; }

private:
    mutable QMutex mutex_;
    QByteArray buffer_;
    qint64 readPos_ = 0;
    int bytesPerSecond_;
    QElapsedTimer sinceLastPush_;
    bool pushedOnce_ = false;
};

/**
 * @brief 音声チャネル(0=System / 1=Media / 2=Guidance)ごとに出力を持つ再生器。UI スレッド専用。
 *
 * 形式は Service Discovery で申告した値(Media 48kHz/2ch、他 16kHz/1ch、16bit)に固定。
 */
class AudioPlayer : public QObject {
    Q_OBJECT
public:
    explicit AudioPlayer(QObject *parent = nullptr);

    /** @brief PCM を再生キューへ書き込む。出力は初回に作る。 */
    void write(int kind, const QByteArray &pcm);
    /** @brief ストリーム停止。再生待ちの音を鳴らし切ってから出力を破棄する。 */
    void stop(int kind);
    /** @brief すべての出力を即座に止める。切断時に呼ぶ。 */
    void stopAll();

private:
    struct Channel {
        std::unique_ptr<QAudioSink> sink;
        std::unique_ptr<PcmQueueDevice> device;
        bool failed = false;   ///< 出力を作れなかった(ログの連発防止)
        bool draining = false; ///< 停止通知済み。キューが空になったら破棄する
    };
    void destroy(Channel &ch);
    void housekeeping();

    Channel channels_[3];
    QTimer timer_;
};

} // namespace opencruise
