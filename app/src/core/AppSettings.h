/**
 * @file AppSettings.h
 * @brief アプリ共通のユーザー設定(ユーザー名・表示フォント)と、同梱フォントの読み込み。
 *
 * QML へは context property `appSettings` として公開する。設定は他の設定と同じ
 * QSettings(IniFormat, UserScope, "OpenCruise"/"OpenCruise")に保存する。
 */
#pragma once

#include <QHash>
#include <QList>
#include <functional>
#include <QObject>
#include <QString>
#include <QStringList>

class QProcess;
class QThread;

namespace opencruise {

/**
 * @brief ユーザー名と表示フォントの設定モデル。
 *
 * 同梱フォント(`fonts/` 配下の .otf/.ttf)は全部で 150MB ほどあり、全部を起動時に読むと、起動画面が出るまでに
 * 何秒もかかる。そこで:
 *  - 起動時: 選んでいるフォントの通常の太さ(Regular)だけを読んで登録する(太字は届くまで合成で表示)
 *  - その後: 同じフォントの残りの太さを、別スレッドでファイルを読み、読めたものから登録する(画面は止めない)
 *  - ほかのフォント: 設定で選ばれたときに、同じく別スレッドで読み、読み終わったら切り替える
 * ファイルを読む時間がほとんどで、登録(addApplicationFontFromData)自体はすぐ終わる。
 * 選択肢(fontFamilies)は、同梱ファイルがあるものになる。
 * 電源モード(powerprofilesctl)の適用も、起動を止めないよう、別プロセスの完了を待たずに進める。
 */
class AppSettings : public QObject {
    Q_OBJECT
    /** 挨拶に使うユーザー名。空なら名前なしの挨拶になる */
    Q_PROPERTY(QString userName READ userName WRITE setUserName NOTIFY userNameChanged)
    /** 表示フォントのファミリ名。空なら OS 既定のフォント */
    Q_PROPERTY(QString fontFamily READ fontFamily WRITE setFontFamily NOTIFY fontFamilyChanged)
    /** 数値(メーターの値・目盛り、グラフ、時計)に使うフォントのファミリ名。空なら文章と同じ(fontFamily) */
    Q_PROPERTY(QString numberFontFamily READ numberFontFamily WRITE setNumberFontFamily NOTIFY numberFontFamilyChanged)
    /** メーター・グラフの値を斜体にするか(既定: する) */
    Q_PROPERTY(bool numberItalic READ numberItalic WRITE setNumberItalic NOTIFY numberItalicChanged)
    /** 選択できるフォントのファミリ名(読み込めた同梱フォントのみ) */
    Q_PROPERTY(QStringList fontFamilies READ fontFamilies CONSTANT)
    /** アプリが選択する電源モード(0:標準、1:省電力、2:高性能) */
    Q_PROPERTY(int powerMode READ powerMode WRITE setPowerMode NOTIFY powerModeChanged)
    Q_PROPERTY(QString powerModeStatus READ powerModeStatus NOTIFY powerModeChanged)
    /** スマートフォン通知を画面上部のポップアップにも表示するか */
    Q_PROPERTY(bool phoneNoticePopupEnabled READ phoneNoticePopupEnabled WRITE setPhoneNoticePopupEnabled
                   NOTIFY phoneNoticePopupEnabledChanged)

public:
    /**
     * @brief 同梱フォントを読み込み、保存済みの設定を復元する。
     * @param parent 親オブジェクト
     */
    explicit AppSettings(QObject *parent = nullptr);
    ~AppSettings() override;

    QString userName() const { return userName_; }
    QString fontFamily() const { return fontFamily_; }
    QStringList fontFamilies() const { return fontFamilies_; }
    QString numberFontFamily() const { return numberFontFamily_; }
    bool numberItalic() const { return numberItalic_; }
    int powerMode() const { return powerMode_; }
    QString powerModeStatus() const { return powerModeStatus_; }
    bool phoneNoticePopupEnabled() const { return phoneNoticePopupEnabled_; }
    /** @brief そのフォントを別スレッドで読み込み中か(起動画面の「フォント」の段階の表示に使う)。 */
    bool isFontLoading(const QString &family) const { return loadingFamilies_.contains(family); }

    /** @brief ユーザー名を変更して保存する(前後の空白は除く)。 */
    void setUserName(const QString &name);

    /** @brief フォントを変更して保存する。選択肢にないファミリ名は無視する。アプリ既定フォントにも反映する。 */
    void setFontFamily(const QString &family);
    /** @brief 数値用のフォントを変更して保存する。空なら文章と同じ。選択肢にないファミリ名は無視する。 */
    void setNumberFontFamily(const QString &family);
    /** @brief 数値を斜体にするかを変更して保存する。 */
    void setNumberItalic(bool italic);
    /** @brief アプリの電源モードを変更して保存する。 */
    void setPowerMode(int mode);
    /** @brief スマートフォン通知のポップアップ表示を保存する。既定はオフ。 */
    void setPhoneNoticePopupEnabled(bool enabled);
    void applyPowerMode();
    void restorePowerMode();

signals:
    void userNameChanged();
    void fontFamilyChanged();
    void numberFontFamilyChanged();
    void numberItalicChanged();
    void powerModeChanged();
    void phoneNoticePopupEnabledChanged();
    /** 別スレッドでのフォントの読み込みが終わった(files: 読んだファイル数、ms: かかった時間) */
    void fontLoadFinished(const QString &family, int files, qint64 ms);

private:
    /**
     * @brief フォントの探索先を返す。
     *
     * 優先順: 環境変数 OPENCRUISE_FONT_DIR → 実行ファイルと同じ階層の fonts/ → ../share/opencruise/fonts/
     */
    static QStringList fontSearchDirs();

    /**
     * @brief 探索先のフォントを調べ、選択肢の一覧(fontFamilies_)を作る。カタログ外のフォント(アイコンなど)は
     * その場で登録し、カタログのフォントはファミリごとに覚えておく(読み込みは ensureFontLoaded)。
     * 見つかったフォントファイルの数を返す。
     */
    int loadBundledFonts();
    /**
     * @brief そのファミリのフォントのうち、filter に合うファイルを今すぐ読んで登録する(起動時の分)。
     * そのファミリが登録済み・登録できたら true。
     */
    bool loadFontNow(const QString &family, bool essentialOnly);
    /**
     * @brief そのファミリの残りのファイルを別スレッドで読み、読み終わったら登録する。
     * then(登録できたか)は、登録し終えたときに UI スレッドで呼ぶ。
     */
    void loadFontInBackground(const QString &family, std::function<void(bool)> then = {});
    /**
     * @brief そのファミリを読み込み、読み終わったら then(登録できたか)を UI スレッドで呼ぶ。
     * ほかの設定(文章・数値)のために読んでいる途中なら、それが終わるのを待つ。
     */
    void whenFontLoaded(const QString &family, std::function<void(bool)> then);
    /** @brief 登録できたフォントを選ぶ(保存・アプリ既定フォントへの反映・通知)。 */
    void applyFontFamily(const QString &family);
    /** @brief powerprofilesctl を別プロセスで動かし、終わったら次の手順へ進む(待たない)。 */
    void runPowerStep();

    QString userName_;
    QString fontFamily_;
    QStringList fontFamilies_;
    QString numberFontFamily_;
    bool numberItalic_ = true;
    int powerMode_ = 0;
    QString powerModeStatus_;
    bool phoneNoticePopupEnabled_ = false;
    QString originalPowerProfile_;
    /// まだ登録していない同梱フォントのファイル(ファミリ名 → ファイル)
    QHash<QString, QStringList> pendingFontFiles_;
    /// 登録できたファミリ
    QStringList registeredFamilies_;
    /// 設定で選ばれ、読み込みを待っているファミリ(読み終わったら切り替える。空なら無し)
    QString requestedFamily_;
    /// 数値用に選ばれ、読み込みを待っているファミリ
    QString requestedNumberFamily_;
    /// フォントを読んでいるスレッド(終了時に待つ)と、読んでいるファミリ
    QList<QThread *> fontThreads_;
    QStringList loadingFamilies_;
    /// 電源モードの適用中のプロセス(無ければ nullptr)と、適用中にもう一度頼まれたか
    QProcess *powerProcess_ = nullptr;
    bool powerReapply_ = false;
    bool powerOriginalTried_ = false; ///< 今のプロファイルを読みに行ったか(終了時に戻すため。1 回だけ)
};

} // namespace opencruise
