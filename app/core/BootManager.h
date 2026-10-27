/**
 * @file BootManager.h
 * @brief 起動(オープニング)画面の進行を管理するモデル。外部機器(ESP32 など)や各種初期化の「待ち」を一括で扱う。
 *
 * 考え方:
 *  - 起動時に待ちたい処理を「ステップ」として登録する(例: Android Auto 接続層、ESP32 との接続)。
 *  - 各処理は完了・失敗などを report() で知らせる。どのスレッドからでも呼べる。
 *  - 応答が無いまま timeoutMs を過ぎたステップは、必須なら Failed、任意なら Warning にして先へ進む(起動は止めない)。
 *  - すべてのステップが確定し、最低表示時間を過ぎたら finished() を出して通常画面へ移る。
 *    確定したステップに失敗/警告があるときは、状況を読めるよう少し長く表示する。
 *  - 画面全体の上限時間(maxMs)を過ぎたら、未確定のステップを時間切れとして扱って必ず起動する。
 *  - 起動完了後の report() も受け付ける(後から ESP32 がつながった場合など)。状態の更新は stepReported() で分かる。
 *
 * C++ からの使い方:
 * @code
 *   boot.addStep("esp32", "外部機器 (ESP32)", false, 6000);   // 任意・6 秒で時間切れ
 *   boot.start();
 *   // ... ESP32 とのハンドシェイクが進んだら(時間切れの期限が延びる)
 *   boot.report("esp32", BootManager::Running, "バージョン確認中");
 *   // ... 完了したら
 *   boot.report("esp32", BootManager::Ready, "fw 1.2.0");
 * @endcode
 * QML からは context property `boot` の report() / skip() と、active / progress / summaryText などを使う。
 */
#pragma once

#include <QAbstractListModel>
#include <QElapsedTimer>
#include <QList>
#include <QString>
#include <QTimer>

namespace opencruise {

class BootManager : public QAbstractListModel {
    Q_OBJECT
    /// 起動待ちの最中か
    Q_PROPERTY(bool active READ active NOTIFY phaseChanged)
    /// 起動待ちが終わったか(通常画面へ移ってよい)
    Q_PROPERTY(bool done READ done NOTIFY phaseChanged)
    /// 確定したステップの割合(0..1)
    Q_PROPERTY(qreal progress READ progress NOTIFY changed)
    /// 画面に出す一文(待っている相手や結果)
    Q_PROPERTY(QString summaryText READ summaryText NOTIFY changed)
    /// 失敗または警告のステップがあるか
    Q_PROPERTY(bool hasProblem READ hasProblem NOTIFY changed)
    /// 起動画面と注意事項が終わり、メイン画面の動き(ゲージの動き・点滅・警告・警告音など)を始めてよいか。
    /// メイン画面は注意事項の前に作っておくが、動きは release() まで始めない
    Q_PROPERTY(bool released READ released NOTIFY releasedChanged)

public:
    /// ステップの状態
    enum StepState {
        Pending = 0,  ///< 開始前
        Running,      ///< 応答待ち・処理中
        Ready,        ///< 完了
        Warning,      ///< 任意の機器が使えない(起動は続ける)
        Failed,       ///< 必須の処理が失敗または時間切れ(起動は続けるが、画面に明示する)
        Skipped       ///< 行わない(未実装・設定で無効・スキップ操作)
    };
    Q_ENUM(StepState)

    enum Roles { StepIdRole = Qt::UserRole + 1, TitleRole, DetailRole, StateKeyRole, RequiredRole };

    explicit BootManager(QObject *parent = nullptr);

    /**
     * @brief 待つステップを登録する。start() の前でも後でもよい。
     * @param id 識別子(report() で指す)
     * @param title 画面に出す名前
     * @param required 必須か。時間切れ時に Failed(必須)/ Warning(任意)になる
     * @param timeoutMs 応答待ちの上限(ms)。0 以下なら個別の上限なし(全体の上限だけで打ち切る)
     */
    void addStep(const QString &id, const QString &title, bool required = true, int timeoutMs = 5000);

    /**
     * @brief 表示時間の調整。
     * @param minDisplayMs 最低表示時間(一瞬で消えるのを防ぐ)
     * @param problemHoldMs 失敗/警告があるとき、確定後にさらに表示する時間
     * @param maxMs 画面全体の上限時間
     */
    void setTiming(int minDisplayMs, int problemHoldMs, int maxMs);

    bool active() const { return phase_ == Active; }
    bool done() const { return phase_ == Done; }
    qreal progress() const;
    QString summaryText() const;
    bool hasProblem() const;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

public slots:
    /** @brief 待ちを始める。登録済みで開始前のステップは Running(応答待ち)になる。 */
    void start();

    /**
     * @brief ステップの状態を知らせる。どのスレッドからでも呼べる。
     * @param id addStep() で登録した識別子
     * @param state StepState の値。Running を送ると、そのステップの時間切れの期限が延びる(途中経過の通知に使う)
     * @param detail 画面に出す補足(バージョン、エラー内容など)
     */
    void report(const QString &id, int state, const QString &detail = QString());

    /** @brief 待ちを打ち切って先へ進む(スキップ操作)。未確定のステップは Skipped になる。 */
    void skip();

    /** @brief 起動画面を出さずに完了扱いにする(開発用の --skip-boot)。 */
    void bypass();

    bool released() const { return released_; }
    /** @brief 起動画面と注意事項が終わったことを知らせる(メイン画面の動きを始める合図)。2 回目以降は何もしない。 */
    Q_INVOKABLE void release();

signals:
    void phaseChanged();
    void releasedChanged();
    /// 進行度・文言・問題の有無のいずれかが変わった
    void changed();
    /// 起動待ちが終わった(通常画面へ移る合図)
    void finished();
    /// report() または時間切れでステップの状態が変わった(起動完了後も出る)
    void stepReported(const QString &id, int state, const QString &detail);

private:
    enum Phase { Idle, Active, Done }; // 注意: Running は StepState と衝突するので使わない

    struct Step {
        QString id;
        QString title;
        QString detail;
        StepState state = Pending;
        bool required = true;
        int timeoutMs = 0;
        qint64 deadlineMs = -1; ///< 開始からの経過時間での期限(-1 は期限なし)
    };

    static bool isSettled(StepState s) { return s != Pending && s != Running; }
    static QString keyFor(StepState s);
    int indexOf(const QString &id) const;
    qint64 elapsed() const { return phase_ == Active ? clock_.elapsed() : 0; }
    StepState timeoutState(const Step &s) const { return s.required ? Failed : Warning; }
    void onTick();
    void evaluate();
    void finish(bool bySkip);

    QList<Step> steps_;
    Phase phase_ = Idle;
    QElapsedTimer clock_;
    QTimer tick_;
    qint64 settledAtMs_ = -1; ///< 全ステップが確定した時刻(-1 は未確定)
    int minDisplayMs_ = 1800;
    int problemHoldMs_ = 2200;
    int maxMs_ = 15000;
    bool released_ = false;
};

} // namespace opencruise
