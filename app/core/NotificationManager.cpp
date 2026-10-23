/**
 * @file NotificationManager.cpp
 * @brief NotificationManager の実装。
 */
#include "NotificationManager.h"

#include <QDateTime>
#include <QMetaObject>
#include <QThread>
#include <QTimer>

namespace opencruise {

namespace {
std::atomic<NotificationManager *> g_instance{nullptr}; ///< notify() の宛先
} // namespace

NotificationManager::NotificationManager(QObject *parent) : QAbstractListModel(parent), history_(this) {
    NotificationManager *expected = nullptr;
    g_instance.compare_exchange_strong(expected, this);
}

NotificationManager::~NotificationManager() {
    NotificationManager *self = this;
    g_instance.compare_exchange_strong(self, nullptr);
}

int NotificationManager::show(const QString &title, const QString &message, int level, const QString &icon,
                              int durationMs) {
    Item item;
    item.id = nextId_.fetch_add(1);
    item.title = title;
    item.message = message;
    item.level = qBound(static_cast<int>(Info), level, static_cast<int>(Error));
    item.icon = icon.isEmpty() ? defaultIcon(item.level) : icon;

    if (QThread::currentThread() == thread()) {
        add(item, durationMs);
    } else {
        // 接続層などのワーカースレッドから呼ばれた場合は、UI スレッドへ渡してから追加する
        QMetaObject::invokeMethod(
            this, [this, item, durationMs]() { add(item, durationMs); }, Qt::QueuedConnection);
    }
    return item.id;
}

void NotificationManager::add(const Item &item, int durationMs) {
    if (items_.size() >= kMaxVisible) {
        const Item pushedOut = items_.first();
        beginRemoveRows(QModelIndex(), 0, 0); // 古いものから押し出す
        items_.removeFirst();
        endRemoveRows();
        archive(pushedOut); // 操作されずに消えるので履歴へ残す
    }
    beginInsertRows(QModelIndex(), static_cast<int>(items_.size()), static_cast<int>(items_.size()));
    items_.append(item);
    endInsertRows();

    if (durationMs > 0) {
        const int id = item.id;
        QTimer::singleShot(durationMs, this, [this, id]() { expire(id); });
    }
}

void NotificationManager::expire(int id) {
    for (int row = 0; row < items_.size(); ++row) {
        if (items_.at(row).id == id) {
            const Item item = items_.at(row);
            beginRemoveRows(QModelIndex(), row, row);
            items_.removeAt(row);
            endRemoveRows();
            archive(item);
            return;
        }
    }
}

void NotificationManager::archive(const Item &item) {
    NotificationHistoryModel::Entry entry;
    entry.title = item.title;
    entry.message = item.message;
    entry.icon = item.icon;
    entry.level = item.level;
    entry.time = QDateTime::currentDateTime();
    history_.append(entry, historyOpen_); // 履歴パネルを開いている間に届いた分は、すでに見えているので既読扱い
}

void NotificationManager::setHistoryOpen(bool open) {
    if (open == historyOpen_) {
        return;
    }
    historyOpen_ = open;
    if (open) {
        history_.markAllRead();
    }
    emit historyOpenChanged();
}

void NotificationManager::dismiss(int id) {
    for (int row = 0; row < items_.size(); ++row) {
        if (items_.at(row).id == id) {
            beginRemoveRows(QModelIndex(), row, row);
            items_.removeAt(row);
            endRemoveRows();
            return;
        }
    }
}

void NotificationManager::clear() {
    if (items_.isEmpty()) {
        return;
    }
    beginRemoveRows(QModelIndex(), 0, static_cast<int>(items_.size()) - 1);
    items_.clear();
    endRemoveRows();
}

void NotificationManager::notify(const QString &title, const QString &message, Level level, const QString &icon,
                                 int durationMs) {
    if (NotificationManager *manager = g_instance.load()) {
        manager->show(title, message, level, icon, durationMs);
    }
}

int NotificationManager::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : static_cast<int>(items_.size());
}

QVariant NotificationManager::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= items_.size()) {
        return {};
    }
    const Item &item = items_.at(index.row());
    switch (role) {
    case IdRole: return item.id;
    case TitleRole: return item.title;
    case MessageRole: return item.message;
    case IconRole: return item.icon;
    case LevelRole: return item.level;
    default: return {};
    }
}

QHash<int, QByteArray> NotificationManager::roleNames() const {
    return {{IdRole, "notificationId"},
            {TitleRole, "title"},
            {MessageRole, "message"},
            {IconRole, "icon"},
            {LevelRole, "level"}};
}

QString NotificationManager::defaultIcon(int level) {
    switch (level) {
    case Success: return QStringLiteral("check_circle");
    case Warning: return QStringLiteral("warning");
    case Error: return QStringLiteral("error");
    default: return QStringLiteral("info");
    }
}

} // namespace opencruise
