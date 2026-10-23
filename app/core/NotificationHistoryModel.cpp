/**
 * @file NotificationHistoryModel.cpp
 * @brief NotificationHistoryModel の実装。
 */
#include "NotificationHistoryModel.h"

#include <QDate>

namespace opencruise {

NotificationHistoryModel::NotificationHistoryModel(QObject *parent) : QAbstractListModel(parent) {}

void NotificationHistoryModel::append(const Entry &entry, bool read) {
    const int oldCount = count();
    const int oldUnread = unreadCount_;

    beginInsertRows(QModelIndex(), 0, 0);
    entries_.prepend(entry);
    endInsertRows();
    if (!read) {
        ++unreadCount_;
    }

    if (entries_.size() > kMaxEntries) {
        // 古いものから捨てる。未読のまま捨てる分は、未読件数の上限(=保持件数)で頭打ちにする
        const int last = static_cast<int>(entries_.size()) - 1;
        beginRemoveRows(QModelIndex(), last, last);
        entries_.removeLast();
        endRemoveRows();
        unreadCount_ = qMin(unreadCount_, count());
    }

    if (count() != oldCount) {
        emit countChanged();
    }
    if (unreadCount_ != oldUnread) {
        emit unreadCountChanged();
    }
}

void NotificationHistoryModel::markAllRead() {
    if (unreadCount_ != 0) {
        unreadCount_ = 0;
        emit unreadCountChanged();
    }
}

void NotificationHistoryModel::clear() {
    if (entries_.isEmpty()) {
        return;
    }
    beginRemoveRows(QModelIndex(), 0, static_cast<int>(entries_.size()) - 1);
    entries_.clear();
    endRemoveRows();
    emit countChanged();
    markAllRead();
}

int NotificationHistoryModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : static_cast<int>(entries_.size());
}

QVariant NotificationHistoryModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= entries_.size()) {
        return {};
    }
    const Entry &entry = entries_.at(index.row());
    switch (role) {
    case TitleRole: return entry.title;
    case MessageRole: return entry.message;
    case IconRole: return entry.icon;
    case LevelRole: return entry.level;
    case TimeTextRole: return timeText(entry.time);
    default: return {};
    }
}

QHash<int, QByteArray> NotificationHistoryModel::roleNames() const {
    return {{TitleRole, "title"},
            {MessageRole, "message"},
            {IconRole, "icon"},
            {LevelRole, "level"},
            {TimeTextRole, "timeText"}};
}

QString NotificationHistoryModel::timeText(const QDateTime &time) {
    return time.date() == QDate::currentDate() ? time.toString(QStringLiteral("HH:mm"))
                                               : time.toString(QStringLiteral("M/d HH:mm"));
}

} // namespace opencruise
