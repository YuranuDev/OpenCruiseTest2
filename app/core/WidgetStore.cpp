/**
 * @file WidgetStore.cpp
 * @brief WidgetStore の実装。
 */
#include "WidgetStore.h"

#include <QSettings>

#include <algorithm>

namespace opencruise {

namespace {
QSettings openStore() {
    return QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"),
                     QStringLiteral("OpenCruise"));
}
const QString kKey = QStringLiteral("widgets/layout");
const QString kAaKey = QStringLiteral("widgets/aaLayout");
const QString kAaCornerKey = QStringLiteral("widgets/aaCorner");
const QString kAaColsKey = QStringLiteral("widgets/aaCols");
const QString kAaRowsKey = QStringLiteral("widgets/aaRows");
constexpr int kGridCols = 12;
constexpr int kGridRows = 6;
constexpr int kAaMinCols = 4;
constexpr int kAaMinRows = 2;
} // namespace

WidgetStore::WidgetStore(QObject *parent) : QObject(parent) {
    QSettings store = openStore();
    layoutJson_ = store.value(kKey).toString();
    aaLayoutJson_ = store.value(kAaKey).toString();
    aaCorner_ = std::clamp(store.value(kAaCornerKey, 0).toInt(), 0, 3);
    aaCols_ = std::clamp(store.value(kAaColsKey, 9).toInt(), kAaMinCols, kGridCols);
    aaRows_ = std::clamp(store.value(kAaRowsKey, kGridRows).toInt(), kAaMinRows, kGridRows);
}

void WidgetStore::setAaLayoutJson(const QString &json) {
    if (aaLayoutJson_ == json) {
        return;
    }
    aaLayoutJson_ = json;
    QSettings store = openStore();
    if (json.isEmpty()) {
        store.remove(kAaKey);
    } else {
        store.setValue(kAaKey, json);
    }
    emit aaLayoutJsonChanged();
}

void WidgetStore::setAaCorner(int corner) {
    corner = std::clamp(corner, 0, 3);
    if (corner == aaCorner_) {
        return;
    }
    aaCorner_ = corner;
    openStore().setValue(kAaCornerKey, corner);
    emit aaFrameChanged();
}

void WidgetStore::setAaCols(int cols) {
    cols = std::clamp(cols, kAaMinCols, kGridCols);
    if (cols == aaCols_) {
        return;
    }
    aaCols_ = cols;
    openStore().setValue(kAaColsKey, cols);
    emit aaFrameChanged();
}

void WidgetStore::setAaRows(int rows) {
    rows = std::clamp(rows, kAaMinRows, kGridRows);
    if (rows == aaRows_) {
        return;
    }
    aaRows_ = rows;
    openStore().setValue(kAaRowsKey, rows);
    emit aaFrameChanged();
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
