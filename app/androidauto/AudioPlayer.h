/**
 * @file AudioPlayer.h
 * @brief Android Auto から届いた PCM 音声を QAudioSink で再生するクラス。
 */
#pragma once

#include <memory>

#include <QAudioSink>
#include <QByteArray>
#include <QObject>

namespace opencruise {

/**
 * @brief 音声チャネル(0=System / 1=Media / 2=Guidance)ごとに出力を持つ再生器。UI スレッド専用。
 *
 * 形式は Service Discovery で申告した値(Media 48kHz/2ch、他 16kHz/1ch、16bit)に固定。
 * 遅延を溜めないため、出力バッファが埋まっている間に届いたデータは捨てる。
 */
class AudioPlayer : public QObject {
    Q_OBJECT
public:
    explicit AudioPlayer(QObject *parent = nullptr) : QObject(parent) {}

    /** @brief PCM を再生キューへ書き込む。出力は初回に作る。 */
    void write(int kind, const QByteArray &pcm);
    /** @brief 指定チャネルの出力を止めて破棄する(次のデータで作り直す)。 */
    void stop(int kind);
    /** @brief すべての出力を止める。切断時に呼ぶ。 */
    void stopAll();

private:
    struct Channel {
        std::unique_ptr<QAudioSink> sink;
        QIODevice *device = nullptr;
        bool failed = false; ///< 出力を作れなかった(ログの連発防止)
    };
    Channel channels_[3];
};

} // namespace opencruise
