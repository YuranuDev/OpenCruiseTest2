/**
 * @file SystemSound.h
 * @brief アプリのシステム音声(操作音・起動音)を鳴らす。鳴らす音は、フォルダ分けされた WAV から選べる。
 *
 * 効果音の種類(カテゴリ)ごとにフォルダを分け、その中の WAV を設定「サウンド」の一覧から選ぶ。
 *   同梱フォルダ   : <実行ファイルの場所>/sounds/<カテゴリ>/        (ビルド時に app/sounds からコピー)
 *                    <実行ファイルの場所>/../share/opencruise/sounds/<カテゴリ>/  (インストール時)
 *   ユーザーフォルダ: ~/.local/share/OpenCruise/sounds/<カテゴリ>/  (起動時に作る。ここへ WAV を置くと一覧に出る)
 *   カテゴリ: click(操作音) / start(起動音)
 * 選んだ音は QSettings(sound/<カテゴリ>)に保存する。既定は同梱の Click.wav / Start.wav で、
 * 同梱フォルダが見つからないときはリソースに埋め込んだ同じ音で鳴らす。「なし」を選ぶと鳴らさない。
 * 再生は QSoundEffect なので、使えるのは WAV だけ。
 *
 * 音量と出力先は AudioSettings の「システム」の設定に従い、設定が変わると再生器へ反映する。
 * 操作音(click)は、パネルに指が 1 本触れた時点で 1 回だけ鳴らす。すべての指が離れるまでは「鳴らし済み」の
 * 状態(ラッチ)を保ち、指を足しても・動かしても・ボタンをまたいでも再度は鳴らさない。
 * 触れた/離れたはアプリ全体のイベントフィルタで検知する(QML 側で呼ぶ必要はない)。
 * QML へは context property `systemSound` として公開する。
 *   systemSound.play("click")  操作音
 *   systemSound.play("start")  起動音
 *   systemSound.soundOptions("click") / selectedSound / setSelectedSound / preview / rescan  設定画面用
 */
#pragma once

#include <QElapsedTimer>
#include <QEvent>
#include <QObject>
#include <QPointer>
#include <QSoundEffect>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>

namespace opencruise {

class AudioSettings;

/**
 * @brief 操作音・起動音の再生窓口。UI スレッド専用。
 */
class SystemSound : public QObject {
    Q_OBJECT
    /// 一覧や選択が変わるたびに増える(QML の束縛が soundOptions などを読み直すため)
    Q_PROPERTY(int revision READ revision NOTIFY soundsChanged)
    /// ユーザーフォルダ(WAV を置く場所)
    Q_PROPERTY(QString userSoundDirectory READ userSoundDirectory CONSTANT)
    /// 見つかった同梱フォルダ(無ければ空)
    Q_PROPERTY(QString builtinSoundDirectory READ builtinSoundDirectory NOTIFY soundsChanged)

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

    /**
     * @brief カテゴリで選べる音の一覧。先頭は「なし」。
     * @param category "click" / "start"
     * @return { id, name, folder } の配列。folder は "同梱" / "ユーザー" / ""(なし)
     */
    Q_INVOKABLE QVariantList soundOptions(const QString &category) const;

    /** @brief カテゴリで選んでいる音の id("none" / "builtin:<ファイル名>" / "user:<ファイル名>")。 */
    Q_INVOKABLE QString selectedSound(const QString &category) const;

    /** @brief カテゴリの音を選んで保存し、次から鳴らす音を切り替える。 */
    Q_INVOKABLE void setSelectedSound(const QString &category, const QString &id);

    /** @brief id の音を 1 回鳴らす(一覧で選んだときの試聴)。 */
    Q_INVOKABLE void preview(const QString &category, const QString &id);

    /** @brief フォルダを読み直す(ユーザーフォルダへ WAV を足したとき)。 */
    Q_INVOKABLE void rescan();

    int revision() const { return revision_; }
    QString userSoundDirectory() const;
    QString builtinSoundDirectory() const;

signals:
    /** @brief 一覧または選択が変わったとき。 */
    void soundsChanged();

protected:
    /** @brief パネルへの触れ/離れを監視し、触れた瞬間に 1 回だけ操作音を鳴らす。常に false(イベントは消費しない)。 */
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    /** @brief 設定の音量・出力先を、すべての再生器へ反映する。 */
    void applySettings();
    /** @brief 再生器の読み込み完了・失敗の通知をつなぐ。読み込み中に play() されたときは、読み込み完了後に鳴らす。 */
    void setupEffect(QSoundEffect &effect, bool &pending);
    /** @brief 再生する。読み込み中なら完了後に回し、読み込みに失敗していれば何もしない。 */
    void playEffect(QSoundEffect &effect, bool &pending);
    /** @brief カテゴリの選択に従って再生器へ音を読み込む(「なし」なら空にする)。 */
    void loadCategory(const QString &category);
    /** @brief id を再生する URL にする。見つからなければ空(既定の音だけはリソースの音を返す)。 */
    QUrl urlFor(const QString &category, const QString &id) const;
    /** @brief フォルダ内の WAV のファイル名(名前順)。 */
    static QStringList wavFiles(const QString &directory);

    QPointer<AudioSettings> settings_;
    QSoundEffect click_;
    QSoundEffect start_;
    QSoundEffect preview_;
    bool clickPending_ = false;
    bool startPending_ = false;
    bool previewPending_ = false;
    bool clickMuted_ = false;  ///< 操作音に「なし」を選んでいる
    bool startMuted_ = false;  ///< 起動音に「なし」を選んでいる
    QElapsedTimer sinceClick_;
    int revision_ = 0;

    /** @brief 指/マウスの押下状態からラッチを更新する。押下が始まった瞬間だけ操作音を鳴らし、全部離れたら解除する。 */
    void updateTouchLatch();
    bool touchDown_ = false; ///< タッチで触れている指が 1 本以上ある
    bool mouseDown_ = false; ///< マウスの左ボタンが押されている(タッチ由来の合成イベントは除く)
    bool latched_ = false;   ///< 操作音を鳴らし済みで、まだ全部離れていない
};

} // namespace opencruise
