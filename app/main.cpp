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
 *  --skip-boot           起動(オープニング)画面を出さずに起動
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
#include "core/AppInfo.h"
#include "core/AppSettings.h"
#include "core/AudioSettings.h"
#include "core/BrightnessController.h"
#include "core/BootManager.h"
#include "core/DisplaySettings.h"
#include "core/DrmDisplay.h"
#include "core/ClockModel.h"
#include "core/SystemStats.h"
#include "core/VehicleDataManager.h"
#include "core/Log.h"
#include "core/NotificationManager.h"
#include "core/PhoneStatus.h"
#include "core/AlbumArtProvider.h"
#include "core/WidgetStore.h"
#include "core/SystemSound.h"

/**
 * @brief アプリを起動する。
 * @return QGuiApplication の終了コード。QML のロードに失敗した場合は -1
 */
int main(int argc, char *argv[]) {
    // eglfs(DRM/KMS)なら、プラットフォームを読み込む前(QGuiApplication の前)に、操作する画面だけを Qt に使わせる設定を作る
    opencruise::DrmDisplay::prepare(argc, argv);
    QGuiApplication app(argc, argv);
    QGuiApplication::setOverrideCursor(Qt::ArrowCursor);
    QGuiApplication::setApplicationName(QStringLiteral("OpenCruise"));
    QGuiApplication::setApplicationVersion(QStringLiteral("0.1.0")); // 起動ログと設定「情報」に出る
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
    const QCommandLineOption skipBoot(QStringLiteral("skip-boot"), QStringLiteral("起動(オープニング)画面を出さずに起動"));
    const QCommandLineOption logDir(QStringLiteral("log-dir"), QStringLiteral("ログの保存先ディレクトリ"),
                                    QStringLiteral("path"));
    const QCommandLineOption logLevel(QStringLiteral("log-level"),
                                      QStringLiteral("記録する最小レベル (debug/info/warn/error/fatal)"),
                                      QStringLiteral("level"));
    parser.addOptions({testVideo, screenshot, screenshotDelay, fullscreen, openSettings, skipBoot, logDir, logLevel});
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
    // 描画方式・垂直同期は、ウィンドウ(QML)を作る前にしか変えられないので、ここで適用する
    opencruise::DisplaySettings::applyStartupSettings();

    opencruise::ClockModel clock;
    opencruise::AppInfo appInfo; // アプリと Linux の情報(設定「情報」)
    opencruise::DisplaySettings displaySettings; // 表示する画面・回転・描画の設定(設定「表示」)
    opencruise::DrmDisplay drmDisplay;           // eglfs での操作する画面と外部モニターへのミラー(設定「表示 > 外部モニター」)
    opencruise::VehicleDataManager can;
    opencruise::SystemStats systemStats; // CPU / GPU / メモリの使用状況(設定「システム」とフルスクリーンのメニュー)
    opencruise::NotificationManager notifications;
    opencruise::PhoneStatus phoneStatus;   // スマホのバッテリー・電波・通知(ウィジェット「スマホ状態」「スマホ通知」が読む)
    opencruise::WidgetStore widgetStore;   // ウィジェットの配置・設定の保存先
    opencruise::BootManager boot; // 起動(オープニング)画面の待ち管理。外部機器の接続待ちなどもここへ登録する
    // 同梱フォントの読み込みと既定フォントの設定は、QML を読み込む前に済ませる
    opencruise::AppSettings appSettings;
    // 音量(マップ音声・音楽音声・システム)と出力先の設定。AndroidAutoController より先に作る(寿命を app に合わせる)
    auto* audioSettings = new opencruise::AudioSettings(&app);
    opencruise::SystemSound systemSound(audioSettings); // 操作音・起動音(音量・出力先は「システム」の設定に従う)
    opencruise::BrightnessController brightnessController; // 画面の明るさ(バックライト or 暗幕。未対応環境でも動く)
    auto* androidAuto = new opencruise::AndroidAutoController(&app);
    androidAuto->setAudioSettings(audioSettings);
    androidAuto->setVehicleSource(&can); // モックの車両データ送信の取得元(ダミーの CAN データ)
    androidAuto->setPhoneStatus(&phoneStatus); // スマホのバッテリー通知の反映先
    // AndroidAutoController オブジェクトを QGuiApplication の子オブジェクトとして関連付けることで
    // オブジェクトの寿命管理を強化し、QTimer::singleShot 使用時のダングリングポインタアクセスを回避
    app.setOrganizationName(QStringLiteral("OpenCruise"));
    app.setApplicationName(QStringLiteral("OpenCruise"));

    opencruise::log::info("APP", QStringLiteral("aasdk 接続層: ") +
                                      (androidAuto->aasdkEnabled() ? QStringLiteral("有効")
                                                                  : QStringLiteral("無効(スタブ)")));
    if (!androidAuto->lastIssue().isEmpty()) {
        opencruise::log::warn("APP", QStringLiteral("初期化時の問題: ") + androidAuto->lastIssue());
    }

    // ---- 起動時に待つステップの登録 ----
    // 外部機器やサービスを増やすときは addStep() で足し、準備ができたら boot.report(id, Ready, ...) を呼ぶだけでよい。
    // 応答が無くても timeoutMs で打ち切って先へ進む(必須でも起動は止まらず、画面に失敗として表示する)。
    // 警告(実際の交通規制に従う旨)を読めるよう、起動画面の最低表示時間を長めにする
    boot.setTiming(5000, 2200, 15000);
    boot.addStep(QStringLiteral("system"), QStringLiteral("システム初期化"), true, 0);
    boot.addStep(QStringLiteral("vehicle"), QStringLiteral("車両データ"), false, 3000);
    boot.addStep(QStringLiteral("aa"), QStringLiteral("Android Auto 接続層"), true, 8000);
    boot.addStep(QStringLiteral("esp32"), QStringLiteral("外部機器 (ESP32)"), false, 6000);
    if (parser.isSet(testVideo)) {
        boot.report(QStringLiteral("aa"), opencruise::BootManager::Skipped, QStringLiteral("テスト映像モード"));
    } else if (!androidAuto->aasdkEnabled()) {
        boot.report(QStringLiteral("aa"), opencruise::BootManager::Warning, QStringLiteral("aasdk 無効(スタブ)"));
    } else {
        // 接続待ち(待機中)に入った時点で、接続層は準備完了とみなす(スマホの接続自体は待たない)
        QObject::connect(androidAuto, &opencruise::AndroidAutoController::stateChanged, &boot, [&boot, androidAuto]() {
            if (androidAuto->stateKey() != QStringLiteral("unavailable")) {
                boot.report(QStringLiteral("aa"), opencruise::BootManager::Ready, androidAuto->stateText());
            }
        });
    }

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("clock"), &clock);
    engine.rootContext()->setContextProperty(QStringLiteral("appInfo"), &appInfo);
    engine.rootContext()->setContextProperty(QStringLiteral("displaySettings"), &displaySettings);
    engine.rootContext()->setContextProperty(QStringLiteral("drmDisplay"), &drmDisplay);
    engine.rootContext()->setContextProperty(QStringLiteral("can"), &can);
    engine.rootContext()->setContextProperty(QStringLiteral("systemStats"), &systemStats);
    engine.rootContext()->setContextProperty(QStringLiteral("notifications"), &notifications);
    engine.rootContext()->setContextProperty(QStringLiteral("phoneStatus"), &phoneStatus);
    // ジャケット画像(image://albumart/...)。エンジンが所有して破棄する
    engine.addImageProvider(QStringLiteral("albumart"), new opencruise::AlbumArtProvider(&phoneStatus));
    engine.rootContext()->setContextProperty(QStringLiteral("widgetStore"), &widgetStore);
    engine.rootContext()->setContextProperty(QStringLiteral("boot"), &boot);
    engine.rootContext()->setContextProperty(QStringLiteral("androidAuto"), androidAuto);
    engine.rootContext()->setContextProperty(QStringLiteral("appSettings"), &appSettings);
    engine.rootContext()->setContextProperty(QStringLiteral("audioSettings"), audioSettings);
    engine.rootContext()->setContextProperty(QStringLiteral("systemSound"), &systemSound);
    engine.rootContext()->setContextProperty(QStringLiteral("brightnessController"), &brightnessController);
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
        // 描画が終わるたびに、外部モニターへのミラーを更新する(eglfs のときだけ動く)
        drmDisplay.attach(qobject_cast<QQuickWindow *>(engine.rootObjects().first()));
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
    QObject::connect(&app, &QCoreApplication::aboutToQuit, androidAuto, &opencruise::AndroidAutoController::stop);
    // 外部モニターの表示を消してから終わる(Qt が DRM を閉じる前に)
    QObject::connect(&app, &QCoreApplication::aboutToQuit, &drmDisplay, &opencruise::DrmDisplay::stop);

    // UI が出た後に接続処理を始める（接続できなくても UI は動作する）
    // QTimer::singleShot の第1引数がオブジェクトのポインタであるため、渡すオブジェクトが無効になることを防ぐために
    // androidAuto をスタック上ではなくヒープ上に作成し、親子関係で管理します。
    QTimer::singleShot(0, androidAuto, [&]() {
        if (parser.isSet(skipBoot)) {
            boot.bypass();
        } else {
            boot.start();
        }
        boot.report(QStringLiteral("system"), opencruise::BootManager::Ready, QStringLiteral("起動処理が完了"));
        boot.report(QStringLiteral("vehicle"), opencruise::BootManager::Ready, can.sourceText());
        // TODO(ESP32): 接続機能を作ったら、ここをその通知に置き換える。例:
        //   connect(esp32Link, &Esp32Link::handshake, &boot, [&](const QString &s) { boot.report("esp32", BootManager::Running, s); });
        //   connect(esp32Link, &Esp32Link::ready,     &boot, [&](const QString &fw) { boot.report("esp32", BootManager::Ready, fw); });
        //   connect(esp32Link, &Esp32Link::failed,    &boot, [&](const QString &e)  { boot.report("esp32", BootManager::Failed, e); });
        // 通知が来ない場合は timeoutMs(6 秒)で警告にして先へ進む。
        boot.report(QStringLiteral("esp32"), opencruise::BootManager::Skipped, QStringLiteral("未実装(接続機能の追加待ち)"));
        if (parser.isSet(testVideo)) {
            opencruise::log::info("APP", QStringLiteral("テスト映像を再生します: %1").arg(parser.value(testVideo)));
            androidAuto->playTestStream(parser.value(testVideo));
        } else {
            opencruise::log::info("APP", QStringLiteral("Android Auto の接続待ちを開始します"));
            androidAuto->start();
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
