/**
 * @file ShutdownManager.h
 * @brief 車両の終了(ACC OFF)に合わせた、アプリ主導のシャットダウン。
 *
 * QML へは context property `shutdownManager` として公開する。
 *
 * 流れ:
 *  1. 終了の要求(requestShutdown)。将来は外部マイコンが ACC OFF を確定したときの `EVT SHUTDOWN_REQUEST` で呼ぶ。
 *     今はダミーで、キーボードの Ctrl+Shift+P(Main.qml)から呼ぶ
 *  2. 画面を終了の画面(ShutdownScreen.qml。起動画面と同じロゴだけ)に切り替え、裏で登録した終了処理(addTask)を順に行う
 *     (例: 設定の保存、Android Auto の切断、今後はドアロックの自動解除など)。処理ごとに時間の上限があり、
 *     上限を過ぎた処理は「時間切れ」として次へ進む。全体の上限(timeoutSec)を過ぎたら、残りを飛ばして終わる
 *  3. 全部済んだら state が "ready" になる。終了の画面(ロゴだけ)をフェードアウトし、描き終えたら QML が finish() を呼ぶ
 *  4. finish(): 設定(afterAction)に従い、PC の電源を切る(systemctl poweroff)か、アプリだけを終了する。
 *     電源を切る命令に失敗したら、state を "failed" にして画面に出し、しばらくしてアプリを終了する
 * 一度始めたら取り消さない(外部マイコンの仕様: 終了中に ACC が戻っても、終了を済ませてから再起動する)。
 * ログは [SHUTDOWN] に英語で出す。
 */
#pragma once

#include <QElapsedTimer>
#include <QList>
#include <QObject>
#include <QString>
#include <QTimer>
#include <QVariantList>

#include <functional>

namespace opencruise {

class ShutdownManager : public QObject {
    Q_OBJECT
    /** "idle"(通常)/ "preparing"(終了処理中)/ "ready"(済んだ。フェードアウトして finish() へ)/ "stopping"(電源を切っている)/ "failed" */
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    /** 終了の理由(画面表示用。例「ACC OFF(テスト)」) */
    Q_PROPERTY(QString reason READ reason NOTIFY stateChanged)
    /** 終了処理の一覧と状態。{ id, label, status, detail }。status: "waiting" / "running" / "done" / "skipped" / "failed" / "timeout" */
    Q_PROPERTY(QVariantList tasks READ tasks NOTIFY tasksChanged)
    /** 失敗したときの内容(画面表示用) */
    Q_PROPERTY(QString errorText READ errorText NOTIFY stateChanged)
    /** 終了処理が済んだら: 0 = PC の電源を切る / 1 = アプリだけ終了する */
    Q_PROPERTY(int afterAction READ afterAction WRITE setAfterAction NOTIFY settingsChanged)
    /** 終了処理全体の上限(秒)。外部マイコンが電源を切るまでの待ち(既定 30 秒)より短くすること */
    Q_PROPERTY(int timeoutSec READ timeoutSec WRITE setTimeoutSec NOTIFY settingsChanged)
    /** Linux の終了画面(Plymouth)の画像の URL(無ければ空) */
    Q_PROPERTY(QString screenImageUrl READ screenImageUrl CONSTANT)

public:
    /** 終了処理が済んだら呼ぶ。ok が false なら失敗(detail に理由) */
    using Done = std::function<void(bool ok, const QString &detail)>;
    /** 終了処理の本体。済んだら done を呼ぶ(すぐ済むなら、その場で呼んでよい)。呼ばずに放っておくと時間切れになる */
    using Task = std::function<void(Done done)>;

    explicit ShutdownManager(QObject *parent = nullptr);

    /**
     * @brief 終了処理を登録する(登録順に行う)。
     * @param id ログ用の名前(英語) / label 画面に出す名前 / timeoutMs この処理の上限
     */
    void addTask(const QString &id, const QString &label, Task task, int timeoutMs = 5000);

    QString state() const { return state_; }
    QString reason() const { return reason_; }
    QVariantList tasks() const;
    QString errorText() const { return errorText_; }
    int afterAction() const { return afterAction_; }
    void setAfterAction(int action);
    int timeoutSec() const { return timeoutSec_; }
    void setTimeoutSec(int seconds);
    QString screenImageUrl() const;

    /** @brief 終了を始める(すでに始めていれば何もしない)。 */
    Q_INVOKABLE void requestShutdown(const QString &reason);
    /** @brief 終了画面を描き終えたら QML が呼ぶ。電源を切る / アプリを終了する。 */
    Q_INVOKABLE void finish();

signals:
    void stateChanged();
    void tasksChanged();
    void settingsChanged();

private:
    struct Entry {
        QString id;
        QString label;
        Task task;
        int timeoutMs = 5000;
        QString status = QStringLiteral("waiting");
        QString detail;
    };
    void setState(const QString &state);
    void runNext();
    void completeCurrent(int serial, bool ok, const QString &detail, bool timedOut);
    void allDone();

    QList<Entry> entries_;
    QString state_ = QStringLiteral("idle");
    QString reason_;
    QString errorText_;
    int afterAction_ = 0;
    int timeoutSec_ = 20;
    int current_ = -1;
    int serial_ = 0;            // 今の処理の番号(時間切れの後に遅れて来た完了の知らせを無視するため)
    QTimer taskTimer_;
    QTimer overallTimer_;
    QElapsedTimer elapsed_;
    bool finished_ = false;
};

} // namespace opencruise
