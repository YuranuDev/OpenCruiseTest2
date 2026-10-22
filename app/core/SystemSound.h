/**
 * @file SystemSound.h
 * @brief アプリのシステム音声(操作音・起動音)を鳴らす。
 *
 * 音は同梱の WAV(app/sounds/Click.wav・Start.wav。リソースへ埋め込む)を QSoundEffect で再生する。
 * 音量と出力先は AudioSettings の「システム」の設定に従い、設定が変わると再生器へ反映する。
 * QML へは context property `systemSound` として公開する。
 *   systemSound.play("click")  操作音
 *   systemSound.play("start")  起動音
 */
#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QPointer>
#include <QSoundEffect>
#include <QString>

namespace opencruise {

class AudioSettings;

/**
 * @brief 操作音・起動音の再生窓口。UI スレッド専用。
 */
class SystemSound : public QObject {
    Q_OBJECT

public:
    /**
     * @param settings 音量・出力先の設定(所有しない。アプリ終了まで有効なこと)
     * @param parent 親オブジェクト
     */
    explicit SystemSound(AudioSettings *settings, QObject *parent = nullptr);

    /**
     * @brief 名前の音を鳴らす。未知の名前は無視する。操作音は連打時に間引く。
     * @param name "click"(操作音)/ "start"(起動音)
     */
    Q_INVOKABLE void play(const QString &name);

private:
    /** @brief 設定の音量・出力先を、両方の再生器へ反映する。 */
    void applySettings();
    /** @brief 再生器を作って WAV を読み込む。読み込み中に play() されたときは、読み込み完了後に鳴らす。 */
    void setupEffect(QSoundEffect &effect, bool &pending, const QString &resourcePath);
    /** @brief 再生する。読み込み中なら完了後に回し、読み込みに失敗していれば何もしない。 */
    void playEffect(QSoundEffect &effect, bool &pending);

    QPointer<AudioSettings> settings_;
    QSoundEffect click_;
    QSoundEffect start_;
    bool clickPending_ = false;
    bool startPending_ = false;
    QElapsedTimer sinceClick_;
};

} // namespace opencruise
