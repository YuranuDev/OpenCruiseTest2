/**
 * @file NotificationManager.cpp
 * @brief NotificationManager の実装。
 */
#include "NotificationManager.h"

#include <QDateTime>
#include <QMetaObject>
#include <QThread>
#include <QTimer>

#include <algorithm>

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
                              int durationMs, bool keepHistory) {
    Item item;
    item.id = nextId_.fetch_add(1);
    item.keepHistory = keepHistory;
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
    Item added = item;
    added.expiresAt = durationMs > 0 ? QDateTime::currentMSecsSinceEpoch() + durationMs : 0;
    beginInsertRows(QModelIndex(), static_cast<int>(items_.size()), static_cast<int>(items_.size()));
    items_.append(added);
    endInsertRows();

    if (durationMs > 0) {
        scheduleExpire(item.id, durationMs);
    }
}

void NotificationManager::scheduleExpire(int id, int delayMs) {
    QTimer::singleShot(std::max(0, delayMs), this, [this, id]() { expire(id); });
}

void NotificationManager::expire(int id) {
    for (int row = 0; row < items_.size(); ++row) {
        if (items_.at(row).id == id) {
            const qint64 expiresAt = items_.at(row).expiresAt;
            if (expiresAt == 0) {
                return; // update() で「自動では消さない」になった
            }
            const qint64 left = expiresAt - QDateTime::currentMSecsSinceEpoch();
            if (left > 20) {
                scheduleExpire(id, static_cast<int>(left)); // update() で表示時間が延びた
                return;
            }
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
    if (!item.keepHistory) {
        return; // 途中経過の通知は残さない(終わったときに addHistory() でまとめを残す)
    }
    NotificationHistoryModel::Entry entry;
    entry.title = item.title;
    entry.message = item.message;
    entry.icon = item.icon;
    entry.level = item.level;
    entry.time = QDateTime::currentDateTime();
    history_.append(entry, historyOpen_); // 履歴パネルを開いている間に届いた分は、すでに見えているので既読扱い
}

void NotificationManager::addHistory(const QString &title, const QString &message, int level, const QString &icon) {
    Item item;
    item.title = title;
    item.message = message;
    item.level = qBound(static_cast<int>(Info), level, static_cast<int>(Error));
    item.icon = icon.isEmpty() ? defaultIcon(item.level) : icon;
    archive(item);
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

bool NotificationManager::update(int id, const QString &title, const QString &message, int level, int durationMs) {
    for (int row = 0; row < items_.size(); ++row) {
        Item &item = items_[row];
        if (item.id != id) {
            continue;
        }
        const int lv = qBound(static_cast<int>(Info), level, static_cast<int>(Error));
        if (durationMs >= 0) {
            const qint64 before = item.expiresAt;
            item.expiresAt = durationMs > 0 ? QDateTime::currentMSecsSinceEpoch() + durationMs : 0;
            if (durationMs > 0 && before == 0) {
                scheduleExpire(id, durationMs); // 消えない通知だったので、確認がまだ仕掛かっていない
            }
        }
        if (item.title != title || item.message != message || item.level != lv) {
            item.title = title;
            item.message = message;
            item.level = lv;
            const QModelIndex idx = index(row);
            emit dataChanged(idx, idx, {TitleRole, MessageRole, LevelRole});
        }
        return true;
    }
    return false;
}

bool NotificationManager::contains(int id) const {
    for (const Item &item : items_) {
        if (item.id == id) {
            return true;
        }
    }
    return false;
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
