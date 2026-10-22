/**
 * @file main.cpp
 * @brief OpenCruise のエントリポイント。モデルを生成して QML に公開し、画面を起動する。
 *
 * 開発用オプション:
 *  --test-video <file>   H.264 ファイルを Android Auto 映像の代わりに表示（デコード/表示経路の確認用）
 *  --screenshot <file>   起動後に画面を PNG 保存して終了（動作確認の自動化用）
 *  --screenshot-delay <ms>  --screenshot の待ち時間（既定 3000）
 *  --fullscreen          全画面表示
 *  --open-settings       設定画面を開いた状態で起動（画面遷移の確認用）
 */
#include <QCommandLineParser>
#include <QGuiApplication>
#include <QImage>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlError>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>


#include <cstdlib>
#include <exception>

#include "androidauto/AndroidAutoController.h"
#include "core/ClockModel.h"
#include "core/VehicleDataManager.h"
#include "core/Log.h"

/**
 * @brief アプリを起動する。
 * @return QGuiApplication の終了コード。QML のロードに失敗した場合は -1
 */
int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    QGuiApplication::setOverrideCursor(Qt::ArrowCursor);
    QGuiApplication::setApplicationName(QStringLiteral("OpenCruise"));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    QCommandLineParser parser;
    parser.addHelpOption();
    const QCommandLineOption testVideo(QStringLiteral("test-video"), QStringLiteral("開発用: 映像として流す H.264 ファイル"),
                                       QStringLiteral("file"));
    const QCommandLineOption screenshot(QStringLiteral("screenshot"), QStringLiteral("起動後に画面を保存して終了"),
                                        QStringLiteral("file"));
    const QCommandLineOption screenshotDelay(QStringLiteral("screenshot-delay"), QStringLiteral("保存までの待ち(ms)"),
                                             QStringLiteral("ms"), QStringLiteral("3000"));
    const QCommandLineOption fullscreen(QStringLiteral("fullscreen"), QStringLiteral("全画面表示"));
    const QCommandLineOption openSettings(QStringLiteral("open-settings"), QStringLiteral("設定画面を開いた状態で起動"));
    const QCommandLineOption logDir(QStringLiteral("log-dir"), QStringLiteral("ログの保存先ディレクトリ"),
                                    QStringLiteral("path"));
    const QCommandLineOption logLevel(QStringLiteral("log-level"),
                                      QStringLiteral("記録する最小レベル (debug/info/warn/error/fatal)"),
                                      QStringLiteral("level"));
    parser.addOptions({testVideo, screenshot, screenshotDelay, fullscreen, openSettings, logDir, logLevel});
    parser.process(app);

    // ログ基盤を最初に立ち上げる。以降の qDebug/qInfo/qWarning も同じ形式でファイルに残る。
    opencruise::log::Options logOptions = opencruise::log::defaultOptions();
    if (parser.isSet(logDir)) {
        logOptions.directory = parser.value(logDir);
    }
    if (parser.isSet(logLevel)) {
        bool levelOk = false;
        const opencruise::log::Level level = opencruise::log::parseLevel(parser.value(logLevel), &levelOk);
        if (levelOk) {
            logOptions.minLevel = level;
        } else {
            qWarning().noquote() << "--log-level の値が不正です:" << parser.value(logLevel) << "(info を使用します)";
        }
    }
    QString logError;
    if (!opencruise::log::initialize(logOptions, &logError)) {
        qWarning().noquote() << "ファイルへのログ出力を開始できません:" << logError;
    }
    opencruise::log::info("APP", QStringLiteral("OpenCruise を起動しました"));
    opencruise::log::info("APP", opencruise::log::describeEnvironment());
    opencruise::log::info("APP", QStringLiteral("ログ出力先: ") + opencruise::log::currentFilePath());
    opencruise::log::info("APP", QStringLiteral("コマンドライン: ") + app.arguments().join(QStringLiteral(" ")));

    opencruise::ClockModel clock;
    opencruise::VehicleDataManager can;
    opencruise::AndroidAutoController androidAuto;
    opencruise::log::info("APP", QStringLiteral("aasdk 接続層: ") +
                                      (androidAuto.aasdkEnabled() ? QStringLiteral("有効")
                                                                  : QStringLiteral("無効(スタブ)")));
    if (!androidAuto.lastIssue().isEmpty()) {
        opencruise::log::warn("APP", QStringLiteral("初期化時の問題: ") + androidAuto.lastIssue());
    }

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("clock"), &clock);
    engine.rootContext()->setContextProperty(QStringLiteral("can"), &can);
    engine.rootContext()->setContextProperty(QStringLiteral("androidAuto"), &androidAuto);
    engine.rootContext()->setContextProperty(QStringLiteral("startFullscreen"), parser.isSet(fullscreen));
    engine.rootContext()->setContextProperty(QStringLiteral("startOnSettings"), parser.isSet(openSettings));

    // QML の警告もファイルに残す（バインディング・描画まわりの失敗を追跡するため）
    QObject::connect(&engine, &QQmlApplicationEngine::warnings, &app, [](const QList<QQmlError> &warnings) {
        for (const QQmlError &warning : warnings) {
            opencruise::log::warn("QML", warning.toString());
        }
    });

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        []() {
            opencruise::log::error("QML", QStringLiteral("ルートオブジェクトの生成に失敗しました"));
            QCoreApplication::exit(-1);
        },
        Qt::QueuedConnection);

    const opencruise::log::Stopwatch qmlLoadTimer;
    engine.load(QUrl(QStringLiteral("qrc:/OpenCruise/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        opencruise::log::error("QML", QStringLiteral("QML の読み込みに失敗しました (qrc:/OpenCruise/qml/Main.qml)"));
    } else {
        opencruise::log::info("QML", QStringLiteral("メイン画面を読み込みました (%1 ms)").arg(qmlLoadTimer.elapsedMs()));
    }

    // 捕捉されない例外で異常終了する場合も、理由をログに残してから停止する
    std::set_terminate([]() {
        opencruise::log::fatal("APP", QStringLiteral("捕捉されない例外により異常終了します"));
        opencruise::log::shutdown();
        std::abort();
    });

    QObject::connect(&app, &QCoreApplication::aboutToQuit, &app, []() {
        opencruise::log::info("APP", QStringLiteral("終了要求を受け取りました"));
    });

    // 終了時は、接続層のスレッドを先に止めてから QML/ウィンドウを破棄する
    QObject::connect(&app, &QCoreApplication::aboutToQuit, &androidAuto, &opencruise::AndroidAutoController::stop);

    // UI が出た後に接続処理を始める（接続できなくても UI は動作する）
    QTimer::singleShot(0, &androidAuto, [&]() {
        if (parser.isSet(testVideo)) {
            opencruise::log::info("APP", QStringLiteral("テスト映像を再生します: %1").arg(parser.value(testVideo)));
            androidAuto.playTestStream(parser.value(testVideo));
        } else {
            opencruise::log::info("APP", QStringLiteral("Android Auto の接続待ちを開始します"));
            androidAuto.start();
        }
    });

    if (parser.isSet(screenshot)) {
        QTimer::singleShot(parser.value(screenshotDelay).toInt(), &app, [&]() {
            const auto windows = app.allWindows();
            if (!windows.isEmpty()) {
                if (auto *quickWindow = qobject_cast<QQuickWindow *>(windows.first())) {
                    quickWindow->grabWindow().save(parser.value(screenshot));
                }
            }
            app.quit();
        });
    }

    const int exitCode = app.exec();

    opencruise::log::info("APP", QStringLiteral("イベントループを終了しました (コード %1)").arg(exitCode));
    opencruise::log::shutdown();
    return exitCode;
}
