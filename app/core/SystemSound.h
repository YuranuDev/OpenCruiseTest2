/**
 * @file SystemSound.h
 * @brief アプリのシステム音声(操作音・起動音)を鳴らす。
 *
 * 音は同梱の WAV(app/sounds/Click.wav・Start.wav。リソースへ埋め込む)を QSoundEffect で再生する。
 * 音量と出力先は AudioSettings の「システム」の設定に従い、設定が変わると再生器へ反映する。
 * 操作音(click)は、パネルに指が 1 本触れた時点で 1 回だけ鳴らす。すべての指が離れるまでは「鳴らし済み」の
 * 状態(ラッチ)を保ち、指を足しても・動かしても・ボタンをまたいでも再度は鳴らさない。
 * 触れた/離れたはアプリ全体のイベントフィルタで検知する(QML 側で呼ぶ必要はない)。
 * QML へは context property `systemSound` として公開する。
 *   systemSound.play("click")  操作音
 *   systemSound.play("start")  起動音
 */
#pragma once

#include <QElapsedTimer>
#include <QEvent>
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

protected:
    /** @brief パネルへの触れ/離れを監視し、触れた瞬間に 1 回だけ操作音を鳴らす。常に false(イベントは消費しない)。 */
    bool eventFilter(QObject *watched, QEvent *event) override;

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

    /** @brief 指/マウスの押下状態からラッチを更新する。押下が始まった瞬間だけ操作音を鳴らし、全部離れたら解除する。 */
    void updateTouchLatch();
    bool touchDown_ = false; ///< タッチで触れている指が 1 本以上ある
    bool mouseDown_ = false; ///< マウスの左ボタンが押されている(タッチ由来の合成イベントは除く)
    bool latched_ = false;   ///< 操作音を鳴らし済みで、まだ全部離れていない
};

} // namespace opencruise
