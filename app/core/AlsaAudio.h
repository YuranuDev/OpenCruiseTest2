/**
 * @file AlsaAudio.h
 * @brief ALSA の機器へ直接(PulseAudio / PipeWire を通さず)音を出す・録る。アプリ内の音は、ここで混ぜてから出す。
 *
 * ALSA の機器(plughw:…)は 1 つのアプリしか開けない(開くと占有する)。アプリ内の音(マップ・音楽・システム・効果音)は
 * 出力先ごとに 1 つの Output(専用スレッド)へまとめ、そこで足し合わせて(ミキシング)1 本で書き込む。
 * だから、同じ機器を選んだ音も同時に鳴り、音量も音ごとに変えられる。違う機器を選んだ音は、別々の Output から出る。
 *
 *  - Output: 機器 1 つ分。48kHz / 2ch / 16bit で開く(plughw なので、機器の形式への変換は ALSA が行う)。
 *    音(Source)が 1 つも無い状態が 3 秒続いたら機器を閉じる(ほかのアプリも使えるように)。開けないときは 2 秒おきに試す
 *  - QueueSource: 届いた PCM を順に流す(Android Auto の音声)。形式(16kHz / 1ch など)は 48kHz / 2ch へ直す
 *  - ClipSource: 読み込んだ音(効果音)を頭から流す。繰り返しもできる
 *  - Capture: 録音(マイク)。16kHz / 1ch / 16bit で開き、届いた分を受け取り先へ渡す(専用スレッド)
 *  - outputDevices() / inputDevices(): 選べる機器の一覧(サウンドカードの PCM ごと)。id は "plughw:CARD=<名前>,DEV=<番号>"。
 *    "default" は ALSA の既定(環境によっては PulseAudio / PipeWire を通る)
 * ログは [AUDIO] に英語で出す。
 */
#pragma once

#include <QByteArray>
#include <QList>
#include <QObject>
#include <QString>
#include <QVector>

#include <atomic>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

namespace opencruise::alsa {

constexpr int kRate = 48000;     ///< 出力の形式(混ぜる形式)
constexpr int kChannels = 2;

struct DeviceInfo {
    QString id;     ///< ALSA の機器名(snd_pcm_open に渡す)
    QString name;   ///< 表示名
};
/** @brief 再生できる機器(サウンドカードの PCM ごと)。 */
QList<DeviceInfo> outputDevices();
/** @brief 録音できる機器。 */
QList<DeviceInfo> inputDevices();
/** @brief サウンドカードの構成を表す文字列(抜き差しの検出用。変わったら一覧を読み直す)。 */
QString cardsSignature();

/** @brief 混ぜる音 1 つ分。Output のスレッドから mixInto() が呼ばれる。 */
class Source {
public:
    virtual ~Source() = default;
    /** @brief out(48kHz / 2ch の float、frames 個)へ足し込む。もう鳴らすものが無ければ false(取り除かれる)。 */
    virtual bool mixInto(float *out, int frames) = 0;
    std::atomic<float> gain{1.0f};
};

/** @brief 届いた PCM(16bit)を順に流す。溜まりすぎたら古い方を捨てる。データが無い間は無音(取り除かれない)。 */
class QueueSource : public Source {
public:
    /** @param rate / channels 届く PCM の形式 */
    QueueSource(int rate, int channels);
    void push(const QByteArray &pcm);
    void clear();
    /** @brief まだ流していないフレーム数(48kHz)。 */
    qint64 queuedFrames() const;
    bool mixInto(float *out, int frames) override;
    /** @brief これを呼ぶと、溜まった分を流し切ったら取り除かれる。 */
    void finish() { finishing_ = true; }

private:
    mutable std::mutex mutex_;
    std::deque<float> buffer_;   // 48kHz / 2ch の float(左右交互)
    int rate_;
    int channels_;
    double phase_ = 0.0;         // 変換(リサンプル)の位置
    float lastL_ = 0.f, lastR_ = 0.f;
    std::atomic<bool> finishing_{false};
};

/** @brief 読み込んだ音(48kHz / 2ch の 16bit)を流す。loops: 回数(-1 なら止めるまで繰り返す)。 */
class ClipSource : public Source {
public:
    ClipSource(std::shared_ptr<const std::vector<int16_t>> clip, int loops);
    bool mixInto(float *out, int frames) override;
    void stop() { stopped_ = true; }
    bool finished() const { return finished_; }

private:
    std::shared_ptr<const std::vector<int16_t>> clip_;
    int loops_;
    size_t pos_ = 0;   // 次に流すサンプルの位置
    std::atomic<bool> stopped_{false};
    std::atomic<bool> finished_{false};
};

/** @brief 機器 1 つ分の出力(専用スレッドで混ぜて書き込む)。outputFor() で取る。 */
class Output {
public:
    /** @param start false なら機器を開かない(終了後に使われる、何もしない出力) */
    explicit Output(QString device, bool start = true);
    ~Output();
    void add(const std::shared_ptr<Source> &source);
    void remove(const std::shared_ptr<Source> &source);
    QString device() const { return device_; }

private:
    void run();
    QString device_;
    std::mutex mutex_;
    std::vector<std::shared_ptr<Source>> sources_;
    std::atomic<bool> quit_{false};
    std::thread thread_;
};
/** @brief 機器の Output(無ければ作る。アプリの終わりまで残る)。 */
Output *outputFor(const QString &device);
/** @brief すべての Output を止めて機器を閉じる(アプリの終わりに呼ぶ。以後の outputFor() は何もしない出力を返す)。 */
void shutdown();

/** @brief 録音(16kHz / 1ch / 16bit)。start() で専用スレッドが動き、届いた分を onData へ渡す(そのスレッドから呼ぶ)。 */
class Capture {
public:
    Capture(QString device, std::function<void(const QByteArray &)> onData, std::function<void(const QString &)> onError);
    ~Capture();
    /** @brief 機器を開いて録音を始める。開けなければ false(理由は error())。 */
    bool start();
    void stop();
    QString error() const { return error_; }

private:
    QString device_;
    std::function<void(const QByteArray &)> onData_;
    std::function<void(const QString &)> onError_;
    void *pcm_ = nullptr;
    std::atomic<bool> quit_{false};
    std::thread thread_;
    QString error_;
};

} // namespace opencruise::alsa
