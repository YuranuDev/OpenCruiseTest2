/**
 * @file NotificationManager.h
 * @brief 画面上部のポップアップ通知を管理するモデル。コード側から通知を出すための窓口。
 *
 * C++ からの使い方（どのスレッドからでも呼べる）:
 * @code
 *   opencruise::NotificationManager::notify(QStringLiteral("接続しました"), QStringLiteral("Pixel 8a"),
 *                                           opencruise::NotificationManager::Success);
 * @endcode
 * アイコンは Material Icons の名前（例: "usb", "directions_car"）。省略するとレベルに応じた既定のアイコンになる。
 * QML からは context property `notifications` の show() も使える。
 *
 * 通知履歴: ユーザーが操作せずに消えた通知(表示時間の経過・同時表示数の超過)は history に残る。
 * ポップアップをタップして閉じた通知(dismiss)・clear() で消した通知は残さない。
 * show() で keepHistory = false にした通知(途中経過を書き換え続けるメーターの警告など)も残さない。
 * その場合は、終わったときに addHistory() でまとめを 1 件だけ残す。
 *
 * 表示中の通知の書き換え: update() で表示中の中身(タイトル・本文・レベル)を書き換えられ、durationMs を渡すと
 * 表示時間もそこから数え直す(0 なら自動では消えなくなる)。メーターの警告通知が値を更新し続けるのに使う。
 * タップすれば消せ、消えたかどうかは update() / contains() の戻り値で分かる。
 */
#pragma once

#include <atomic>

#include <QAbstractListModel>
#include <QList>
#include <QString>

#include "NotificationHistoryModel.h"

namespace opencruise {

/**
 * @brief 通知の一覧(同時表示は最大 3 件)を保持し、一定時間で自動的に消すモデル。
 */
class NotificationManager : public QAbstractListModel {
    Q_OBJECT
    /** 通知履歴(操作されずに消えた通知。新しい順)。件数・未読件数も持つ */
    Q_PROPERTY(NotificationHistoryModel *history READ history CONSTANT)
    /** 通知履歴パネルを開いているか。ベルボタンで切り替え、画面側のパネルがこれに従って表示する */
    Q_PROPERTY(bool historyOpen READ historyOpen WRITE setHistoryOpen NOTIFY historyOpenChanged)

public:
    /// 通知の種類。色と既定アイコンが決まる
    enum Level { Info = 0, Success = 1, Warning = 2, Error = 3 };
    Q_ENUM(Level)

    enum Roles { IdRole = Qt::UserRole + 1, TitleRole, MessageRole, IconRole, LevelRole };

    /**
     * @brief 生成する。最初に作ったインスタンスが notify() の宛先になる。
     */
    explicit NotificationManager(QObject *parent = nullptr);
    ~NotificationManager() override;

    /**
     * @brief 通知を表示する。どのスレッドからでも呼べる。
     * @param title タイトル（1 行）
     * @param message 本文（省略可）
     * @param level Level の値
     * @param icon Material Icons のアイコン名。空ならレベル別の既定
     * @param durationMs 表示時間(ms)。0 以下なら自動では消えない
     * @param keepHistory false なら、操作されずに消えても履歴に残さない
     * @return 通知ID（dismiss() で消すときに使う）
     */
    Q_INVOKABLE int show(const QString &title, const QString &message = QString(), int level = Info,
                         const QString &icon = QString(), int durationMs = 4000, bool keepHistory = true);

    /**
     * @brief ポップアップは出さずに、履歴へ 1 件だけ残す(UI スレッドから呼ぶ)。
     * @param icon Material Icons のアイコン名。空ならレベル別の既定
     */
    Q_INVOKABLE void addHistory(const QString &title, const QString &message = QString(), int level = Info,
                                const QString &icon = QString());

    NotificationHistoryModel *history() { return &history_; }

    bool historyOpen() const { return historyOpen_; }
    /** @brief 履歴パネルの開閉。開くと未読をすべて既読にし、開いている間に届いた分も既読として記録する。 */
    void setHistoryOpen(bool open);

    /** @brief 指定IDの通知を消す(履歴には残さない。ポップアップのタップで閉じる操作もこれ)。存在しなければ何もしない。 */
    Q_INVOKABLE void dismiss(int id);

    /**
     * @brief 表示中の通知の中身を書き換える(UI スレッドから呼ぶ)。
     * @param durationMs 0 以上なら、表示時間を今から数え直す(0 = 自動では消さない)。負なら表示時間はそのまま
     * @return 書き換えたら true。その通知がもう無い(タップで閉じられた・押し出された)なら false
     */
    Q_INVOKABLE bool update(int id, const QString &title, const QString &message, int level, int durationMs = -1);

    /** @brief その通知がまだ表示されているか。 */
    Q_INVOKABLE bool contains(int id) const;

    /** @brief すべての通知を消す(履歴には残さない)。 */
    Q_INVOKABLE void clear();

    /**
     * @brief コードのどこからでも通知を出すための静的ヘルパ。インスタンスが無ければ何もしない。
     */
    static void notify(const QString &title, const QString &message = QString(), Level level = Info,
                       const QString &icon = QString(), int durationMs = 4000);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

signals:
    void historyOpenChanged();

private:
    struct Item {
        int id = 0;
        QString title;
        QString message;
        QString icon;
        int level = Info;
        qint64 expiresAt = 0; ///< 自動で消す時刻(エポック ms)。0 なら自動では消さない
        bool keepHistory = true; ///< 操作されずに消えたとき、履歴へ残すか
    };

    /** @brief 消す時刻の確認を仕掛ける(update() で延びていたら、その時刻に確認し直す)。 */
    void scheduleExpire(int id, int delayMs);

    /** @brief UI スレッドで通知を一覧へ追加し、消去タイマーを仕掛ける。 */
    void add(const Item &item, int durationMs);

    /** @brief 表示時間が過ぎた通知を消して、履歴へ残す。すでに無ければ何もしない。 */
    void expire(int id);

    /** @brief 操作されずに消えた通知を、履歴へ残す。 */
    void archive(const Item &item);

    /** @brief レベルに応じた既定アイコン名。 */
    static QString defaultIcon(int level);

    QList<Item> items_;
    NotificationHistoryModel history_;
    bool historyOpen_ = false;
    std::atomic<int> nextId_{1};

    static constexpr int kMaxVisible = 3;
};

} // namespace opencruise
