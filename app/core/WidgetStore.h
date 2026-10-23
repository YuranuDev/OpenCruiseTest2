/**
 * @file WidgetStore.h
 * @brief ウィジェットの配置・設定(JSON 文字列)を保存するだけの薄いモデル。
 *
 * QML へは context property `widgetStore` として公開する。配置の意味づけ(グリッド・衝突・設定値)は
 * QML の WidgetArea が持ち、ここは他の設定と同じ QSettings(IniFormat, UserScope)へ読み書きするだけ。
 * 中身の形式は WidgetArea の saveLayout() を参照(version つきなので、将来の形式変更に対応できる)。
 */
#pragma once

#include <QObject>
#include <QString>

namespace opencruise {

class WidgetStore : public QObject {
    Q_OBJECT
    /** 保存済みの配置 JSON。未保存なら空文字(QML 側が初期配置を使う) */
    Q_PROPERTY(QString layoutJson READ layoutJson WRITE setLayoutJson NOTIFY layoutJsonChanged)

public:
    explicit WidgetStore(QObject *parent = nullptr);

    QString layoutJson() const { return layoutJson_; }
    /** @brief 配置 JSON を保存する。空文字なら保存を消し、次回は初期配置になる。 */
    void setLayoutJson(const QString &json);

signals:
    void layoutJsonChanged();

private:
    QString layoutJson_;
};

} // namespace opencruise
