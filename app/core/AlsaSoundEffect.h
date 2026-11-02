/**
 * @file AlsaSoundEffect.h
 * @brief 効果音(操作音・警告音・起動音・試聴)を、ALSA の出力(AlsaAudio。アプリ内で混ぜる)で鳴らす再生器。
 *
 * QSoundEffect と同じ使い方ができるようにしてある(SystemSound は、ALSA で鳴らすときはこれを使う)。
 *  - setSource() で読み込む(WAV は自分で読み、MP3 などは QAudioDecoder で読む)。読み込んだ音は 48kHz / 2ch にして覚えておく
 *    (同じファイルは、ほかの再生器とも共有する)
 *  - play() で頭から鳴らす(鳴っている途中なら頭から鳴らし直す)。setLoopCount(Infinite) で止めるまで繰り返す
 *  - 出力先(ALSA の機器名)は setOutputDevice() で決める。鳴っている途中に変えると、続きは新しい出力先で鳴る
 * 作ったスレッド(SystemSound の再生用スレッド)で使うこと。
 */
#pragma once

#include <QObject>
#include <QString>
#include <QUrl>

#include <cstdint>
#include <memory>
#include <vector>

class QAudioDecoder;
class QIODevice;

namespace opencruise {

namespace alsa { class ClipSource; }

class AlsaSoundEffect : public QObject {
    Q_OBJECT
public:
    enum Status { Null, Loading, Ready, Error };
    Q_ENUM(Status)
    enum Loop { Infinite = -2 };

    explicit AlsaSoundEffect(QObject *parent = nullptr);
    ~AlsaSoundEffect() override;

    QUrl source() const { return source_; }
    void setSource(const QUrl &url);
    Status status() const { return status_; }
    void setLoopCount(int count) { loopCount_ = count; }
    int loopCount() const { return loopCount_; }
    void setVolume(float volume);
    float volume() const { return volume_; }
    void setOutputDevice(const QString &device);
    QString outputDevice() const { return device_; }
    bool isPlaying() const;

public slots:
    void play();
    void stop();

signals:
    void statusChanged();

private:
    void setStatus(Status status);
    void decodeWithQt(const QUrl &url);

    QUrl source_;
    Status status_ = Null;
    int loopCount_ = 1;
    float volume_ = 1.0f;
    QString device_;
    std::shared_ptr<const std::vector<int16_t>> clip_;
    std::shared_ptr<alsa::ClipSource> playing_;
    QAudioDecoder *decoder_ = nullptr;
    QIODevice *decoderInput_ = nullptr;
    std::vector<int16_t> decoded_;   // QAudioDecoder の途中結果(48kHz / 2ch)
};

} // namespace opencruise
