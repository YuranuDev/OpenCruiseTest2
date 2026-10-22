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
 */
#pragma once

#include <atomic>

#include <QAbstractListModel>
#include <QList>
#include <QString>

namespace opencruise {

/**
 * @brief 通知の一覧(同時表示は最大 3 件)を保持し、一定時間で自動的に消すモデル。
 */
class NotificationManager : public QAbstractListModel {
    Q_OBJECT

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
     * @return 通知ID（dismiss() で消すときに使う）
     */
    Q_INVOKABLE int show(const QString &title, const QString &message = QString(), int level = Info,
                         const QString &icon = QString(), int durationMs = 4000);

    /** @brief 指定IDの通知を消す。存在しなければ何もしない。 */
    Q_INVOKABLE void dismiss(int id);

    /** @brief すべての通知を消す。 */
    Q_INVOKABLE void clear();

    /**
     * @brief コードのどこからでも通知を出すための静的ヘルパ。インスタンスが無ければ何もしない。
     */
    static void notify(const QString &title, const QString &message = QString(), Level level = Info,
                       const QString &icon = QString(), int durationMs = 4000);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

private:
    struct Item {
        int id = 0;
        QString title;
        QString message;
        QString icon;
        int level = Info;
    };

    /** @brief UI スレッドで通知を一覧へ追加し、消去タイマーを仕掛ける。 */
    void add(const Item &item, int durationMs);

    /** @brief レベルに応じた既定アイコン名。 */
    static QString defaultIcon(int level);

    QList<Item> items_;
    std::atomic<int> nextId_{1};

    static constexpr int kMaxVisible = 3;
};

} // namespace opencruise
