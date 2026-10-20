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
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>

#include "androidauto/AndroidAutoController.h"
#include "core/ClockModel.h"
#include "core/DummyCanModel.h"

/**
 * @brief アプリを起動する。
 * @return QGuiApplication の終了コード。QML のロードに失敗した場合は -1
 */
int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
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
    parser.addOptions({testVideo, screenshot, screenshotDelay, fullscreen, openSettings});
    parser.process(app);

    opencruise::ClockModel clock;
    opencruise::DummyCanModel can;
    opencruise::AndroidAutoController androidAuto;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("clock"), &clock);
    engine.rootContext()->setContextProperty(QStringLiteral("can"), &can);
    engine.rootContext()->setContextProperty(QStringLiteral("androidAuto"), &androidAuto);
    engine.rootContext()->setContextProperty(QStringLiteral("startFullscreen"), parser.isSet(fullscreen));
    engine.rootContext()->setContextProperty(QStringLiteral("startOnSettings"), parser.isSet(openSettings));

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app, []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.load(QUrl(QStringLiteral("qrc:/OpenCruise/qml/Main.qml")));

    // 終了時は、接続層のスレッドを先に止めてから QML/ウィンドウを破棄する
    QObject::connect(&app, &QCoreApplication::aboutToQuit, &androidAuto, &opencruise::AndroidAutoController::stop);

    // UI が出た後に接続処理を始める（接続できなくても UI は動作する）
    QTimer::singleShot(0, &androidAuto, [&]() {
        if (parser.isSet(testVideo)) {
            androidAuto.playTestStream(parser.value(testVideo));
        } else {
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

    return app.exec();
}
