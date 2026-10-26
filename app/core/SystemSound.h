/**
 * @file SystemSound.h
 * @brief アプリのシステム音声(操作音・起動音)を鳴らす。鳴らす音は、フォルダ分けされた WAV(起動音は MP3 も)から選べる。
 *
 * 効果音の種類(カテゴリ)ごとにフォルダを分け、その中の WAV を設定「サウンド」の一覧から選ぶ。
 *   同梱フォルダ   : <実行ファイルの場所>/sounds/<カテゴリ>/        (ビルド時に app/sounds からコピー)
 *                    <実行ファイルの場所>/../share/opencruise/sounds/<カテゴリ>/  (インストール時)
 *   ユーザーフォルダ: ~/.local/share/OpenCruise/sounds/<カテゴリ>/  (起動時に作る。ここへ WAV を置くと一覧に出る)
 *   カテゴリ: click(操作音) / start(起動音) / alert(警告音: メーターのしきい値超えのビープ。鳴らすのは WarningAlarm だけ) /
 *             caution(注意音: メーターが注意値を超えたときに 1 回だけ鳴らす。鳴らすのは WarningAlarm だけ)
 * 選んだ音は QSettings(sound/<カテゴリ>)に保存する。既定は同梱の Click.wav / Start.wav / Beep.wav / Caution.wav で、
 * 同梱フォルダが見つからないときはリソースに埋め込んだ同じ音で鳴らす。「なし」を選ぶと鳴らさない。
 * 再生は QSoundEffect なので、操作音・警告音に使えるのは WAV だけ(すぐ鳴らす・繰り返すため)。
 * 起動音だけは MP3 も選べる(MP3 を選んだときは QMediaPlayer で鳴らす。鳴り始めまで少し時間がかかってもよいため)。
 * 試聴も、MP3 なら QMediaPlayer で鳴らす。
 * 警告音(alert)は WAV のほかに「合成音」を選べる。波形・高さ(2 音目で交互にも)・回数・長さ・間隔・
 * フェード・音量を設定でき、その設定から WAV をキャッシュフォルダに作って鳴らす(設定を変えるたびに作り直す)。
 * 警告音を繰り返す間隔(alertInterval)は、WAV・合成音のどちらにも効く(繰り返すのは WarningAlarm)。
 * 鳴らし方(alertContinuous)を「ずっと鳴らす」にすると、警告がある間(alertActive が true の間)は警告音を
 * 途切れずにループ再生し続ける。合成音はつなぎ目で途切れないよう、末尾の無音を付けず、1 音の長さを波の周期に合わせる。
 *
 * 音量と出力先は AudioSettings の「システム」の設定に従い、設定が変わると再生器へ反映する。
 * 操作音(click)は、パネルに指が 1 本触れた時点で 1 回だけ鳴らす。すべての指が離れるまでは「鳴らし済み」の
 * 状態(ラッチ)を保ち、指を足しても・動かしても・ボタンをまたいでも再度は鳴らさない。
 * 触れた/離れたはアプリ全体のイベントフィルタで検知する(QML 側で呼ぶ必要はない)。
 * QML へは context property `systemSound` として公開する。
 *   systemSound.play("click")  操作音
 *   systemSound.play("start")  起動音
 *   systemSound.play("alert")  警告音(1 回分。繰り返しは WarningAlarm が受け持つ)
 *   systemSound.play("caution") 注意音(1 回。続けて呼ばれても kCautionMinIntervalMs の間は鳴らし直さない)
 *   systemSound.soundOptions("click") / selectedSound / setSelectedSound / preview / rescan  設定画面用
 */
#pragma once

#include <QAudioOutput>
#include <QElapsedTimer>
#include <QEvent>
#include <QMediaPlayer>
#include <QObject>
#include <QPointer>
#include <QSoundEffect>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

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
    /**
     * 警告音の合成音の設定:
     *   waveform 0=サイン 1=矩形 2=三角 3=のこぎり / frequency 1 音目の高さ[Hz] / frequency2 2 音目の高さ[Hz](0 = 1 音目と同じ。
     *   違う高さにすると 1 音ごとに交互に鳴らす) / pulses 1 回に鳴らす音の数 / pulseMs 1 音の長さ[ms] / gapMs 音と音の間[ms] /
     *   fadeMs 1 音の立ち上がり・消え際[ms] / volume 合成音の音量[%](システムの音量にさらに掛ける)
     */
    Q_PROPERTY(QVariantMap synth READ synth NOTIFY synthChanged)
    /// 合成音 1 回分の長さ[ms]
    Q_PROPERTY(int synthLengthMs READ synthLengthMs NOTIFY synthChanged)
    /// 警告音を繰り返す間隔[ms](WarningAlarm が使う)
    Q_PROPERTY(int alertInterval READ alertInterval WRITE setAlertInterval NOTIFY synthChanged)
    /// 警告音の鳴らし方。false: 間隔をあけて繰り返す / true: 警告がある間ずっと鳴らし続ける(保存する)
    Q_PROPERTY(bool alertContinuous READ alertContinuous WRITE setAlertContinuous NOTIFY synthChanged)
    /// 警告が鳴っている(確認されていない警告がある)か。「ずっと鳴らす」のとき、true の間ループ再生する(Main.qml が流し込む)
    Q_PROPERTY(bool alertActive READ alertActive WRITE setAlertActive NOTIFY alertActiveChanged)

public:
    /**
     * @param settings 音量・出力先の設定(所有しない。アプリ終了まで有効なこと)
     * @param parent 親オブジェクト
     */
    explicit SystemSound(AudioSettings *settings, QObject *parent = nullptr);

    /**
     * @brief 名前の音を鳴らす。未知の名前は無視する。操作音は連打時に間引く。
     * @param name "click"(操作音)/ "start"(起動音)/ "alert"(警告音)
     */
    Q_INVOKABLE void play(const QString &name);

    /**
     * @brief カテゴリで選べる音の一覧。先頭は「なし」。
     * @param category "click" / "start" / "alert"
     * @return { id, name, folder } の配列。folder は "同梱" / "ユーザー" / ""(なし)
     */
    Q_INVOKABLE QVariantList soundOptions(const QString &category) const;

    /** @brief カテゴリで選んでいる音の id("none" / "builtin:<ファイル名>" / "user:<ファイル名>")。 */
    Q_INVOKABLE QString selectedSound(const QString &category) const;

    /** @brief カテゴリの音を選んで保存し、次から鳴らす音を切り替える。 */
    Q_INVOKABLE void setSelectedSound(const QString &category, const QString &id);

    /** @brief id の音を 1 回鳴らす(一覧で選んだときの試聴)。 */
    Q_INVOKABLE void preview(const QString &category, const QString &id);

    /** @brief 合成音の設定を 1 つ変える(範囲に丸めて保存し、音を作り直す)。key は synth の項目名。 */
    Q_INVOKABLE void setSynthValue(const QString &key, const QVariant &value);
    /**
     * @brief 合成音の設定をまとめて切り替える(繰り返す間隔も変える)。
     * @param name "pipi"(ピピッ)/ "pii"(ピー)/ "pipo"(ピポピポ)/ "fast"(速い連打)/ "chime"(チャイム)/
     *             "continuous"(警告中ずっと「ピーー」と鳴り続ける。鳴らし方も「ずっと鳴らす」にする)/
     *             "continuousPipo"(警告中ずっと「ピポピポ」と鳴り続ける)
     */
    Q_INVOKABLE void applySynthPreset(const QString &name);
    /** @brief 今の合成音を 1 回鳴らす(設定画面の試聴)。 */
    Q_INVOKABLE void previewSynth();

    QVariantMap synth() const { return synth_; }
    int synthLengthMs() const;
    int alertInterval() const { return alertInterval_; }
    void setAlertInterval(int ms);
    bool alertContinuous() const { return alertContinuous_; }
    void setAlertContinuous(bool on);
    bool alertActive() const { return alertActive_; }
    void setAlertActive(bool on);

    /** @brief フォルダを読み直す(ユーザーフォルダへ WAV を足したとき)。 */
    Q_INVOKABLE void rescan();

    int revision() const { return revision_; }
    QString userSoundDirectory() const;
    QString builtinSoundDirectory() const;

signals:
    /** @brief 一覧または選択が変わったとき。 */
    void soundsChanged();
    /** @brief 合成音の設定・繰り返す間隔が変わったとき。 */
    void synthChanged();
    void alertActiveChanged();

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
    /** @brief カテゴリの再生器・読み込み待ち・「なし」の状態(未知のカテゴリは操作音の分を返す) */
    QSoundEffect &effectOf(const QString &category);
    bool &pendingOf(const QString &category);
    bool &mutedOf(const QString &category);
    /** @brief カテゴリの選択に従って再生器へ音を読み込む(「なし」なら空にする)。 */
    void loadCategory(const QString &category);
    /** @brief id を再生する URL にする。見つからなければ空(既定の音だけはリソースの音を返す)。 */
    QUrl urlFor(const QString &category, const QString &id) const;
    /** @brief 保存した合成音の設定を読む(無い項目は既定値)。 */
    void loadSynth();
    /** @brief 合成音の設定から WAV を作り、警告音に合成音を選んでいれば読み込み直す。 */
    void rebuildSynth();
    /** @brief 「ずっと鳴らす」のループ再生を、alertActive / alertContinuous に合わせて始める・止める。 */
    void updateAlertLoop();
    /** @brief フォルダ内の、カテゴリで使える音のファイル名(名前順)。起動音は WAV と MP3、ほかは WAV だけ。 */
    static QStringList soundFiles(const QString &directory, const QString &category);
    /** @brief カテゴリで MP3 を使えるか(起動音だけ)。 */
    static bool allowsMp3(const QString &category);
    /** @brief QSoundEffect では鳴らせない形式(MP3)か。 */
    static bool isMp3(const QUrl &url);
    /** @brief QMediaPlayer の再生器を用意する(読み込み失敗をログに出す)。 */
    void setupPlayer(QMediaPlayer &player, QAudioOutput &output);

    QPointer<AudioSettings> settings_;
    QSoundEffect click_;
    QSoundEffect start_;
    QSoundEffect alert_;
    QSoundEffect caution_;
    QSoundEffect preview_;
    // MP3 の起動音・試聴用(QSoundEffect は WAV しか鳴らせないため)
    QAudioOutput startOutput_;
    QMediaPlayer startPlayer_;
    QAudioOutput previewOutput_;
    QMediaPlayer previewPlayer_;
    bool startUsesPlayer_ = false; ///< 起動音に MP3 を選んでいる(startPlayer_ で鳴らす)
    bool clickPending_ = false;
    bool startPending_ = false;
    bool alertPending_ = false;
    bool cautionPending_ = false;
    bool previewPending_ = false;
    bool clickMuted_ = false;  ///< 操作音に「なし」を選んでいる
    bool startMuted_ = false;  ///< 起動音に「なし」を選んでいる
    bool alertMuted_ = false;  ///< 警告音に「なし」を選んでいる
    bool cautionMuted_ = false; ///< 注意音に「なし」を選んでいる
    QElapsedTimer sinceCaution_; ///< 前に注意音を鳴らしてから(いくつものメーターが同時に注意になっても 1 回だけ鳴らす)
    QElapsedTimer sinceClick_;
    int revision_ = 0;

    QVariantMap synth_;
    int alertInterval_ = 1400;
    bool alertContinuous_ = false;
    bool alertActive_ = false;
    bool alertLooping_ = false; ///< 「ずっと鳴らす」でループ再生している
    int synthSerial_ = 0;   ///< 作り直すたびに増やす(同じファイル名だと再生器が読み直さないため、名前を変える)
    QString synthPath_;     ///< 今の合成音の WAV

    /** @brief 指/マウスの押下状態からラッチを更新する。押下が始まった瞬間だけ操作音を鳴らし、全部離れたら解除する。 */
    void updateTouchLatch();
    bool touchDown_ = false; ///< タッチで触れている指が 1 本以上ある
    bool mouseDown_ = false; ///< マウスの左ボタンが押されている(タッチ由来の合成イベントは除く)
    bool latched_ = false;   ///< 操作音を鳴らし済みで、まだ全部離れていない
};

} // namespace opencruise
