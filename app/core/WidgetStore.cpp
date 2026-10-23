/**
 * @file WidgetStore.cpp
 * @brief WidgetStore の実装。
 */
#include "WidgetStore.h"

#include <QSettings>

namespace opencruise {

namespace {
QSettings openStore() {
    return QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"),
                     QStringLiteral("OpenCruise"));
}
const QString kKey = QStringLiteral("widgets/layout");
} // namespace

WidgetStore::WidgetStore(QObject *parent) : QObject(parent) {
    layoutJson_ = openStore().value(kKey).toString();
}

void WidgetStore::setLayoutJson(const QString &json) {
    if (layoutJson_ == json) {
        return;
    }
    layoutJson_ = json;
    QSettings store = openStore();
    if (json.isEmpty()) {
        store.remove(kKey);
    } else {
        store.setValue(kKey, json);
    }
    emit layoutJsonChanged();
}

} // namespace opencruise
