/**
 * @file AppSettings.h
 * @brief アプリ共通のユーザー設定(ユーザー名・表示フォント)と、同梱フォントの読み込み。
 *
 * QML へは context property `appSettings` として公開する。設定は他の設定と同じ
 * QSettings(IniFormat, UserScope, "OpenCruise"/"OpenCruise")に保存する。
 */
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QString>

namespace opencruise {

/**
 * @brief ユーザー名と表示フォントの設定モデル。
 *
 * 同梱フォント(`fonts/` 配下の .otf/.ttf)は生成時に QFontDatabase へ登録する。
 * 選択肢(fontFamilies)は、実際に読み込めたものだけになる。
 */
class AppSettings : public QObject {
    Q_OBJECT
    /** 挨拶に使うユーザー名。空なら名前なしの挨拶になる */
    Q_PROPERTY(QString userName READ userName WRITE setUserName NOTIFY userNameChanged)
    /** 表示フォントのファミリ名。空なら OS 既定のフォント */
    Q_PROPERTY(QString fontFamily READ fontFamily WRITE setFontFamily NOTIFY fontFamilyChanged)
    /** 選択できるフォントのファミリ名(読み込めた同梱フォントのみ) */
    Q_PROPERTY(QStringList fontFamilies READ fontFamilies CONSTANT)
    /** アプリが選択する電源モード(0:標準、1:省電力、2:高性能) */
    Q_PROPERTY(int powerMode READ powerMode WRITE setPowerMode NOTIFY powerModeChanged)
    Q_PROPERTY(QString powerModeStatus READ powerModeStatus NOTIFY powerModeChanged)

public:
    /**
     * @brief 同梱フォントを読み込み、保存済みの設定を復元する。
     * @param parent 親オブジェクト
     */
    explicit AppSettings(QObject *parent = nullptr);

    QString userName() const { return userName_; }
    QString fontFamily() const { return fontFamily_; }
    QStringList fontFamilies() const { return fontFamilies_; }
    int powerMode() const { return powerMode_; }
    QString powerModeStatus() const { return powerModeStatus_; }

    /** @brief ユーザー名を変更して保存する(前後の空白は除く)。 */
    void setUserName(const QString &name);

    /** @brief フォントを変更して保存する。選択肢にないファミリ名は無視する。アプリ既定フォントにも反映する。 */
    void setFontFamily(const QString &family);
    /** @brief アプリの電源モードを変更して保存する。 */
    void setPowerMode(int mode);
    void applyPowerMode();

signals:
    void userNameChanged();
    void fontFamilyChanged();
    void powerModeChanged();

private:
    /**
     * @brief フォントの探索先を返す。
     *
     * 優先順: 環境変数 OPENCRUISE_FONT_DIR → 実行ファイルと同じ階層の fonts/ → ../share/opencruise/fonts/
     */
    static QStringList fontSearchDirs();

    /** @brief 探索先のフォントを登録し、選択肢の一覧(fontFamilies_)を作る。読み込んだファイル数を返す。 */
    int loadBundledFonts();

    QString userName_;
    QString fontFamily_;
    QStringList fontFamilies_;
    int powerMode_ = 0;
    QString powerModeStatus_;
};

} // namespace opencruise
