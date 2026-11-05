/**
 * @file AppInfo.h
 * @brief アプリと動作環境(Linux)の情報を QML に提供する。設定「情報」が表示する。
 */
#pragma once

#include <QObject>
#include <QString>
#include <QTimer>

namespace opencruise {

/**
 * @brief アプリ(バージョン・Qt・ビルド・ログ)と OS(ディストリビューション・カーネルなど)の情報。
 *
 * 起動ログ(log::describeEnvironment)と同じ情報源を使う。ほとんどは起動中に変わらないので CONSTANT。
 * 稼働時間だけは 1 秒ごとに更新する。
 */
class AppInfo : public QObject {
    Q_OBJECT
    // ---- アプリ ----
    Q_PROPERTY(QString appName READ appName CONSTANT)
    Q_PROPERTY(QString appVersion READ appVersion CONSTANT)
    Q_PROPERTY(QString qtVersion READ qtVersion CONSTANT)
    Q_PROPERTY(QString buildInfo READ buildInfo CONSTANT)
    Q_PROPERTY(bool aasdkEnabled READ aasdkEnabled CONSTANT)
    Q_PROPERTY(QString platformName READ platformName CONSTANT)
    Q_PROPERTY(qint64 processId READ processId CONSTANT)
    Q_PROPERTY(QString startedAt READ startedAt CONSTANT)
    Q_PROPERTY(QString appUptime READ appUptime NOTIFY uptimeChanged)
    Q_PROPERTY(bool fileLogging READ fileLogging CONSTANT)
    Q_PROPERTY(QString logFile READ logFile CONSTANT)
    Q_PROPERTY(QString logDirectory READ logDirectory CONSTANT)
    // ---- Linux ----
    Q_PROPERTY(QString osName READ osName CONSTANT)
    Q_PROPERTY(QString kernel READ kernel CONSTANT)
    Q_PROPERTY(QString cpuArchitecture READ cpuArchitecture CONSTANT)
    Q_PROPERTY(QString hostName READ hostName CONSTANT)
    Q_PROPERTY(QString libcVersion READ libcVersion CONSTANT)
    Q_PROPERTY(QString session READ session CONSTANT)
    Q_PROPERTY(QString locale READ locale CONSTANT)
    Q_PROPERTY(QString systemUptime READ systemUptime NOTIFY uptimeChanged)

public:
    /**
     * @brief 情報を集め、稼働時間の更新を始める。
     * @param parent 親オブジェクト
     */
    explicit AppInfo(QObject *parent = nullptr);

    QString appName() const;
    QString appVersion() const;
    /** @brief 実行中の Qt と、ビルドに使った Qt のバージョン。 */
    QString qtVersion() const;
    /** @brief コンパイラ・ABI・ビルド日時。 */
    QString buildInfo() const;
    bool aasdkEnabled() const;
    /** @brief Qt の描画プラットフォーム(xcb / wayland / eglfs など)。 */
    QString platformName() const;
    qint64 processId() const;
    QString startedAt() const { return startedAt_; }
    QString appUptime() const { return appUptime_; }
    bool fileLogging() const;
    QString logFile() const;
    QString logDirectory() const;

    QString osName() const;
    /** @brief カーネルの種類とバージョン(例: "linux 6.8.0-45-generic")。 */
    QString kernel() const;
    QString cpuArchitecture() const;
    QString hostName() const;
    /** @brief C ライブラリ(glibc)のバージョン。取得できなければ "--"。 */
    QString libcVersion() const;
    /** @brief デスクトップ環境とセッションの種類(XDG_CURRENT_DESKTOP / XDG_SESSION_TYPE)。 */
    QString session() const;
    QString locale() const;
    QString systemUptime() const { return systemUptime_; }

signals:
    /** @brief 稼働時間の表示が変わったとき。 */
    void uptimeChanged();

private:
    /**
     * @brief アプリと OS の稼働時間を作り直す。
     */
    void refreshUptime();

    QTimer timer_;
    qint64 startedMs_ = 0;
    QString startedAt_;
    QString appUptime_;
    QString systemUptime_;
};

} // namespace opencruise
