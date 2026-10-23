/**
 * @file NotificationHistoryModel.h
 * @brief 通知履歴(操作されずに消えたポップアップ通知の記録)のモデル。
 */
#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QList>
#include <QString>

namespace opencruise {

/**
 * @brief 通知履歴の一覧(新しい順)と、未読件数を保持する。UI スレッド専用。
 *
 * 追加するのは NotificationManager で、ユーザーが操作せずに消えた通知(表示時間の経過・同時表示数の超過)だけ。
 * 件数は kMaxEntries までで、超えた分は古いものから捨てる。アプリを終了すると消える(保存はしない)。
 */
class NotificationHistoryModel : public QAbstractListModel {
    Q_OBJECT
    /** 履歴の件数 */
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    /** 未読の件数。履歴パネルを開くと 0 になる */
    Q_PROPERTY(int unreadCount READ unreadCount NOTIFY unreadCountChanged)

public:
    enum Roles { TitleRole = Qt::UserRole + 1, MessageRole, IconRole, LevelRole, TimeTextRole };

    /// 履歴 1 件分。level は NotificationManager::Level の値
    struct Entry {
        QString title;
        QString message;
        QString icon;
        int level = 0;
        QDateTime time;
    };

    explicit NotificationHistoryModel(QObject *parent = nullptr);

    int count() const { return static_cast<int>(entries_.size()); }
    int unreadCount() const { return unreadCount_; }

    /**
     * @brief 先頭(いちばん新しい位置)へ追加する。
     * @param read true なら、すでに見ているものとして未読に数えない(履歴パネルを開いている間に届いた分)
     */
    void append(const Entry &entry, bool read);

    /** @brief すべて既読にする(履歴パネルを開いたとき)。 */
    Q_INVOKABLE void markAllRead();

    /** @brief 履歴をすべて消す。 */
    Q_INVOKABLE void clear();

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

signals:
    void countChanged();
    void unreadCountChanged();

private:
    /** @brief 表示用の時刻文字列。今日なら「HH:mm」、それ以前なら「M/d HH:mm」。 */
    static QString timeText(const QDateTime &time);

    QList<Entry> entries_;
    int unreadCount_ = 0;

    static constexpr int kMaxEntries = 100;
};

} // namespace opencruise
