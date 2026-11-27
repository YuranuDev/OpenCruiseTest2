/**
 * @file ThemeSettings.h
 * @brief アプリ全体の見た目(テーマ)と背景の設定。QML へは context property `themeSettings` として公開する。
 *
 *  - dayProfile / nightProfile: 昼夜ごとのテーマ(style / accent)と背景(background / image / fit / opacity)。
 *    古い共通設定は、新しいプロファイルが無い間は昼夜双方の初期値として読む。
 *  - style: 現在表示中のプロファイルのテーマ。"simple"(これまでの見た目)/ "classic"(ガンメタの面・控えめな立体感・
 *           アンバーの照明色)。色や形は Theme.qml が style に合わせて変える
 *  - background: 現在表示中のプロファイルの背景。"auto"(テーマに合わせる)/ "none"(無地)/ 模様・画像
 *  - 画像: backgroundFolder(~/.local/share/OpenCruise/backgrounds)に PNG / JPEG を置くと、選択肢(backgroundImages)に出る。
 *          表示のしかた(backgroundFit)は 0 = 並べる / 1 = 画面を埋める(はみ出しは切る)/ 2 = 引き伸ばす
 *  - backgroundOpacity: 模様・画像の濃さ(0〜100 %)。濃いと文字が読みにくくなるので、既定は控えめ
 *  - 飾りの画像(キャラなど): decorationFolder(~/.local/share/OpenCruise/decorations)に PNG / JPEG / WebP / GIF を置くと、
 *          初期画面の編集モード(「画像」)で選んで置ける(decorationImages)。置いた場所・大きさはページごとに WidgetPages が保存する。
 *          透過 PNG にすると、キャラだけを切り抜いて置ける
 */
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariant>
#include <QVariantMap>

namespace opencruise {

class ThemeSettings : public QObject {
    Q_OBJECT
    /** 現在表示中(Theme.night に追従)の昼夜テーマ。 */
    Q_PROPERTY(bool nightMode READ nightMode WRITE setNightMode NOTIFY changed)
    Q_PROPERTY(QString style READ style WRITE setStyle NOTIFY changed)
    Q_PROPERTY(int accentIndex READ accentIndex WRITE setAccentIndex NOTIFY changed)
    Q_PROPERTY(QString accentCustom READ accentCustom WRITE setAccentCustom NOTIFY changed)
    Q_PROPERTY(QString background READ background WRITE setBackground NOTIFY changed)
    Q_PROPERTY(QString backgroundImage READ backgroundImage WRITE setBackgroundImage NOTIFY changed)
    /// 選んだ画像のファイルの URL(画像を使わない・見つからないときは空)
    Q_PROPERTY(QString backgroundImageUrl READ backgroundImageUrl NOTIFY changed)
    Q_PROPERTY(int backgroundFit READ backgroundFit WRITE setBackgroundFit NOTIFY changed)
    Q_PROPERTY(int backgroundOpacity READ backgroundOpacity WRITE setBackgroundOpacity NOTIFY changed)
    /** 設定画面から昼夜どちらも編集できるプロファイル。 */
    Q_PROPERTY(QVariantMap dayProfile READ dayProfile WRITE setDayProfile NOTIFY changed)
    Q_PROPERTY(QVariantMap nightProfile READ nightProfile WRITE setNightProfile NOTIFY changed)
    Q_PROPERTY(QStringList backgroundImages READ backgroundImages NOTIFY imagesChanged)
    Q_PROPERTY(QString backgroundFolder READ backgroundFolder CONSTANT)
    Q_PROPERTY(QStringList decorationImages READ decorationImages NOTIFY decorationImagesChanged)
    Q_PROPERTY(QString decorationFolder READ decorationFolder CONSTANT)

public:
    explicit ThemeSettings(QObject *parent = nullptr);

    bool nightMode() const { return nightMode_; }
    void setNightMode(bool night);
    QString style() const;
    void setStyle(const QString &style);
    int accentIndex() const;
    void setAccentIndex(int index);
    QString accentCustom() const;
    void setAccentCustom(const QString &color);
    QString background() const;
    void setBackground(const QString &background);
    QString backgroundImage() const;
    void setBackgroundImage(const QString &fileName);
    QString backgroundImageUrl() const;
    int backgroundFit() const;
    void setBackgroundFit(int fit);
    int backgroundOpacity() const;
    void setBackgroundOpacity(int percent);
    QVariantMap dayProfile() const;
    void setDayProfile(const QVariantMap &profile);
    QVariantMap nightProfile() const;
    void setNightProfile(const QVariantMap &profile);
    QStringList backgroundImages() const { return images_; }
    QString backgroundFolder() const;
    QStringList decorationImages() const { return decorations_; }
    QString decorationFolder() const;
    /** @brief 飾りの画像のファイル名から URL を返す(見つからなければ空)。 */
    Q_INVOKABLE QString decorationUrl(const QString &fileName) const;
    /** @brief 飾りの画像のフォルダを読み直す(画像の追加パネルを開いたとき・「読み直す」ボタン)。 */
    Q_INVOKABLE void refreshDecorationImages();

    /** @brief 画像フォルダを読み直す(設定画面を開いたとき・「読み直す」ボタン)。 */
    Q_INVOKABLE void refreshBackgroundImages();

signals:
    void changed();
    void imagesChanged();
    void decorationImagesChanged();

private:
    QVariantMap readProfile(bool night) const;
    QVariantMap readStoredProfile(bool night) const;
    void writeProfile(bool night, const QVariantMap &profile);
    void setActiveValue(const QString &key, const QVariant &value);
    void savePendingAccentCustom();

    bool nightMode_ = true;
    bool profilesLoaded_ = false;
    QVariantMap dayProfile_;
    QVariantMap nightProfile_;
    bool dayAccentPending_ = false;
    bool nightAccentPending_ = false;
    QTimer accentSaveTimer_;
    QStringList images_;
    QStringList decorations_;
};

} // namespace opencruise
