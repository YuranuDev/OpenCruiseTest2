/**
 * @file MicrophoneInput.h
 * @brief Android Auto の音声入力用に、車載機のマイクを録音するクラス。
 */
#pragma once

#include <memory>

#include <QAudioSource>
#include <QByteArray>
#include <QObject>
#include <QPointer>
#include <QString>

#include "core/AudioSettings.h"

namespace opencruise {

/**
 * @brief マイクの録音を、必要なときだけ行う。UI スレッド専用。
 *
 * 録音するのは「スマートフォンがマイクを開いている(setRequested(true))」かつ
 * 「設定でマイクを使う(AudioSettings::micEnabled)」の両方を満たす間だけ。
 * どちらかが外れると、録音デバイスを閉じる。入力元の変更は、録音中なら作り直して反映する。
 *
 * 形式は Service Discovery で申告した値(16kHz / 16bit / 1ch)に固定。
 * 録音した PCM は captured() で渡す。
 */
class MicrophoneInput : public QObject {
    Q_OBJECT
public:
    explicit MicrophoneInput(QObject *parent = nullptr);
    ~MicrophoneInput() override;

    /** @brief マイクの設定を結びつける(所有はしない)。設定が変わると録音へ反映する。未設定のときは常に使用可・既定デバイス。 */
    void setSettings(AudioSettings *settings);

    /** @brief スマートフォンがマイクを開いている(true)/閉じた(false)。 */
    void setRequested(bool requested);

    /** @brief 画面表示用の状態文字列。 */
    QString statusText() const { return statusText_; }

signals:
    /** @brief 録音した PCM(16kHz / 16bit / 1ch)。UI スレッドで出る。 */
    void captured(const QByteArray &pcm);
    /** @brief statusText が変わった。 */
    void statusChanged();

private:
    /** @brief 設定と要求状態から、録音すべきかを判断して開始/停止/作り直しをする。何度呼んでもよい。 */
    void reconcile();
    /**
     * @brief 録音を開始する。失敗したら状態にエラーを出して録音しない。
     * @param announce true なら、録音が始まったことを画面上部のポップアップで知らせる
     */
    void startCapture(bool announce);
    /** @brief 録音を止めてデバイスを閉じる。 */
    void stopCapture();
    void onReadyRead();
    /** @brief 状態文字列を作り直し、変化があれば通知する。 */
    void refreshStatus();

    QPointer<AudioSettings> settings_;
    bool requested_ = false;
    std::unique_ptr<QAudioSource> source_;
    QIODevice *io_ = nullptr; ///< source_ が所有
    QByteArray currentDeviceId_;
    QString currentDeviceName_;
    QString errorText_; ///< 直近の開始失敗/録音エラー。次に録音を始めるときに消す
    QString statusText_;
};

} // namespace opencruise
