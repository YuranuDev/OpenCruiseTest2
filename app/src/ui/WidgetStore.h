/**
 * @file WidgetStore.h
 * @brief ウィジェットの配置・設定(JSON 文字列)を保存するだけの薄いモデル。
 *
 * QML へは context property `widgetStore` として公開する。配置の意味づけ(グリッド・衝突・設定値)は
 * QML の WidgetArea が持ち、ここは他の設定と同じ QSettings(IniFormat, UserScope)へ読み書きするだけ。
 * 中身の形式は WidgetPages(ページの一覧)と WidgetArea の saveLayout()(1 ページ分)を参照
 * (version つき。version 1 = 1 ページだけの以前の形式、version 2 = ページつき。どちらも読める)。
 *
 * Android Auto 画面(フルスクリーンでないとき)のウィジェットは、初期画面とは別に aaLayoutJson に保存する
 * (形式は version 1 = 1 ページ分)。映像を置く場所(グリッドの角と、幅・高さのマス数)も、ここに保存する。
 */
#pragma once

#include <QObject>
#include <QString>

namespace opencruise {

class WidgetStore : public QObject {
    Q_OBJECT
    /** 保存済みの配置 JSON。未保存なら空文字(QML 側が初期配置を使う) */
    Q_PROPERTY(QString layoutJson READ layoutJson WRITE setLayoutJson NOTIFY layoutJsonChanged)
    /** Android Auto 画面のウィジェットの配置 JSON。未保存なら空文字 */
    Q_PROPERTY(QString aaLayoutJson READ aaLayoutJson WRITE setAaLayoutJson NOTIFY aaLayoutJsonChanged)
    /** Android Auto の映像を置く角。0 = 左上 / 1 = 右上 / 2 = 左下 / 3 = 右下 */
    Q_PROPERTY(int aaCorner READ aaCorner WRITE setAaCorner NOTIFY aaFrameChanged)
    /** Android Auto の映像の幅・高さ(グリッドのマス数。横 12 × 縦 6 マスのうち) */
    Q_PROPERTY(int aaCols READ aaCols WRITE setAaCols NOTIFY aaFrameChanged)
    Q_PROPERTY(int aaRows READ aaRows WRITE setAaRows NOTIFY aaFrameChanged)

public:
    explicit WidgetStore(QObject *parent = nullptr);

    QString layoutJson() const { return layoutJson_; }
    /** @brief 配置 JSON を保存する。空文字なら保存を消し、次回は初期配置になる。 */
    void setLayoutJson(const QString &json);

    QString aaLayoutJson() const { return aaLayoutJson_; }
    void setAaLayoutJson(const QString &json);
    int aaCorner() const { return aaCorner_; }
    void setAaCorner(int corner);
    int aaCols() const { return aaCols_; }
    void setAaCols(int cols);
    int aaRows() const { return aaRows_; }
    void setAaRows(int rows);

signals:
    void layoutJsonChanged();
    void aaLayoutJsonChanged();
    void aaFrameChanged();

private:
    QString layoutJson_;
    QString aaLayoutJson_;
    int aaCorner_ = 0;
    int aaCols_ = 9;
    int aaRows_ = 6;
};

} // namespace opencruise
