/**
 * @file ThemeSettings.h
 * @brief アプリ全体の見た目(テーマ)と背景の設定。QML へは context property `themeSettings` として公開する。
 *
 *  - style: テーマ。"simple"(シンプル。これまでの見た目)/ "classic"(クラシック。2000 年代ごろの車の内装に合う、
 *           ガンメタの面・控えめな立体感・アンバーの照明色)。色や形は Theme.qml が style に合わせて変える
 *  - background: 背景。"auto"(テーマに合わせる: シンプルは無地、クラシックはカーボン)/ "none"(無地)/
 *           模様 "carbon"(カーボン)・"brushed"(ヘアライン)・"dots"(パンチング)・"stripes"(ストライプ)/ "image"(画像)
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
#include <QVariant>

namespace opencruise {

class ThemeSettings : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString style READ style WRITE setStyle NOTIFY changed)
    Q_PROPERTY(QString background READ background WRITE setBackground NOTIFY changed)
    Q_PROPERTY(QString backgroundImage READ backgroundImage WRITE setBackgroundImage NOTIFY changed)
    /// 選んだ画像のファイルの URL(画像を使わない・見つからないときは空)
    Q_PROPERTY(QString backgroundImageUrl READ backgroundImageUrl NOTIFY changed)
    Q_PROPERTY(int backgroundFit READ backgroundFit WRITE setBackgroundFit NOTIFY changed)
    Q_PROPERTY(int backgroundOpacity READ backgroundOpacity WRITE setBackgroundOpacity NOTIFY changed)
    Q_PROPERTY(QStringList backgroundImages READ backgroundImages NOTIFY imagesChanged)
    Q_PROPERTY(QString backgroundFolder READ backgroundFolder CONSTANT)
    Q_PROPERTY(QStringList decorationImages READ decorationImages NOTIFY decorationImagesChanged)
    Q_PROPERTY(QString decorationFolder READ decorationFolder CONSTANT)

public:
    explicit ThemeSettings(QObject *parent = nullptr);

    QString style() const { return style_; }
    void setStyle(const QString &style);
    QString background() const { return background_; }
    void setBackground(const QString &background);
    QString backgroundImage() const { return backgroundImage_; }
    void setBackgroundImage(const QString &fileName);
    QString backgroundImageUrl() const;
    int backgroundFit() const { return backgroundFit_; }
    void setBackgroundFit(int fit);
    int backgroundOpacity() const { return backgroundOpacity_; }
    void setBackgroundOpacity(int percent);
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
    void save(const QString &key, const QVariant &value);

    QString style_ = QStringLiteral("simple");
    QString background_ = QStringLiteral("auto");
    QString backgroundImage_;
    int backgroundFit_ = 1;
    int backgroundOpacity_ = 60;
    QStringList images_;
    QStringList decorations_;
};

} // namespace opencruise
