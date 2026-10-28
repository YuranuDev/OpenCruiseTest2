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
 *  --export-splash <dir> 起動画面の見た目を、Linux の起動画面(Plymouth)用の画像として書き出して終了
 *                        (tools/bootsplash/install.sh が使う。background.png / progress-fill.png / splash.conf)
 *
 * Linux の起動画面(Plymouth)からの引き継ぎ(scripts/bootsplash の自動起動のサービスで動かすとき):
 *  Plymouth の操作は root でしかできないので、サービス(systemd)が行う。アプリは画面を開いて最初の 1 枚を描くだけ。
 *   1. サービスが plymouth deactivate(Plymouth は画面(DRM)を手放すが、最後の画面は出したまま)
 *   2. アプリが画面を開いて最初の 1 枚を描き、systemd へ READY=1 を送る
 *   3. サービスが plymouth quit --retain-splash(この時点で画面はアプリのもの。黒くならない)
 *  Plymouth の画像はこのアプリの起動画面から作るので、同じ見た目のまま途切れずにアプリの起動画面へ移る。
 *  サービスは環境変数 OPENCRUISE_SPLASH_HANDOFF=1 を付けて起動する(変わらない部分をフェードせずに最初から出す)。
 */
#include <QCommandLineParser>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QJSValue>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlError>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSocketNotifier>
#include <QTextStream>
#include <QTimer>
#include <QUrl>


#include <cstdlib>
#ifdef Q_OS_LINUX
#include <csignal>
#include <cstddef>
#include <cstring>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#endif
#include <exception>
#include <memory>

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
 * @brief systemd へ準備ができたこと(READY=1)を知らせる(Type=notify のサービスで動いているときだけ)。
 *
 * 自動起動のサービス(scripts/bootsplash)は、これを受けてから Plymouth を終わらせる(plymouth quit --retain-splash)。
 * 最初の 1 枚を描いた後に送るので、Plymouth が消えても画面は黒くならず、アプリの画面のまま続く。
 * libsystemd は使わず、NOTIFY_SOCKET(Unix ドメインのデータグラム)へ直接送る。
 */
static void notifySystemdReady() {
#ifdef Q_OS_LINUX
    const QByteArray path = qgetenv("NOTIFY_SOCKET");
    if (path.isEmpty() || (path[0] != '/' && path[0] != '@') || path.size() >= int(sizeof(sockaddr_un::sun_path))) {
        return;
    }
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    memcpy(addr.sun_path, path.constData(), path.size());
    if (addr.sun_path[0] == '@') {
        addr.sun_path[0] = '\0'; // 抽象名前空間
    }
    const int fd = ::socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (fd < 0) {
        return;
    }
    static const char kMessage[] = "READY=1";
    ::sendto(fd, kMessage, sizeof(kMessage) - 1, 0, reinterpret_cast<const sockaddr *>(&addr),
             static_cast<socklen_t>(offsetof(sockaddr_un, sun_path) + path.size()));
    ::close(fd);
#endif
}

#ifdef Q_OS_LINUX
/// 終了の合図(SIGTERM / SIGINT)を、シグナルハンドラからイベントループへ渡すためのソケットの組
static int g_termFds[2] = {-1, -1};
/// シグナルハンドラ: ソケットへ 1 バイト書くだけ(ここでは Qt を触れない)
static void onTermSignal(int) {
    const char c = 1;
    const ssize_t written = ::write(g_termFds[1], &c, 1);
    (void)written;
}
#endif

/**
 * @brief 終了の合図(SIGTERM / SIGINT)を受けたら、終了画面を出してから終わるようにする。
 *
 * シャットダウン・再起動・systemctl stop のとき、systemd はアプリに SIGTERM を送る。既定のままだと、描画の途中で
 * いきなり終わり、画面に最後の画が止まったまま残る(そのまま時間がたつと、パネルの色がおかしくなっていく)。
 * ここでは合図を受けたら、QML(Main.qml の showShutdownScreen)で今の画面を Linux の終了画面(Plymouth)と同じ画像へ
 * 切り替え、それを描き終えてから普通に終わる(後片付けもする)。その後は Plymouth が同じ画像を出す
 * (自動起動のサービスは、Plymouth の終了画面より先に止まるように順番を決めている)。
 * 2 回目の合図か、3 秒たっても終われないときは、すぐに終わる。
 */
static void installTermHandler(QGuiApplication &app, QQmlApplicationEngine &engine) {
#ifdef Q_OS_LINUX
    if (::socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0, g_termFds) != 0) {
        opencruise::log::warn("APP", QStringLiteral("終了の合図を受ける準備ができませんでした(終了画面は出しません)"));
        return;
    }
    struct sigaction action {};
    action.sa_handler = onTermSignal;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESTART;
    ::sigaction(SIGTERM, &action, nullptr);
    ::sigaction(SIGINT, &action, nullptr);

    auto *notifier = new QSocketNotifier(g_termFds[0], QSocketNotifier::Read, &app);
    auto stopping = std::make_shared<bool>(false);
    QObject::connect(notifier, &QSocketNotifier::activated, &app, [&app, &engine, stopping]() {
        char buffer[16];
        while (::read(g_termFds[0], buffer, sizeof(buffer)) > 0) {
        }
        if (*stopping) {
            opencruise::log::info("APP", QStringLiteral("もう一度終了の合図を受けたので、すぐに終わります"));
            app.quit();
            return;
        }
        *stopping = true;
        // Plymouth のテーマの画像(install.sh が入れる)。Plymouth が終了時に出すのと同じ画像
        const QString image = QStringLiteral("/usr/share/plymouth/themes/opencruise/background.png");
        const QString url = QFile::exists(image) ? QUrl::fromLocalFile(image).toString() : QString();
        QObject *root = engine.rootObjects().isEmpty() ? nullptr : engine.rootObjects().first();
        opencruise::log::info("APP", QStringLiteral("終了の合図(SIGTERM)を受けました。終了画面に切り替えてから終わります%1")
                                         .arg(url.isEmpty() ? QStringLiteral("(Plymouth の画像が無いので背景色のみ)") : QString()));
        if (!root || !QMetaObject::invokeMethod(root, "showShutdownScreen", Q_ARG(QVariant, url))) {
            app.quit();
            return;
        }
        QTimer::singleShot(3000, &app, [&app]() {
            opencruise::log::warn("APP", QStringLiteral("終了画面を描き終えられなかったので、そのまま終わります"));
            app.quit();
        });
    });
#else
    Q_UNUSED(app);
    Q_UNUSED(engine);
#endif
}

/**
 * @brief 起動画面の見た目を、Plymouth のテーマ用に書き出す(--export-splash)。
 *
 * 書き出すもの(dir の中):
 *  - background.png    起動画面のうち、変わらない部分(背景・タイトル・警告・進行バーの溝)だけを描いた全画面の画像
 *  - progress-fill.png 進行バーの塗り(幅 1px。Plymouth が伸ばして使う)
 *  - splash.conf       画面の大きさ・進行バーの位置・色(install.sh がテーマのスクリプトへ埋め込む)
 * @return 書き出せたら true
 */
static bool exportBootSplash(QQuickWindow *window, const QString &dir) {
    if (!window || !QDir().mkpath(dir)) {
        return false;
    }
    QObject *splash = window->findChild<QObject *>(QStringLiteral("splash"));
    if (!splash) {
        opencruise::log::error("SPLASH", QStringLiteral("起動画面が見つかりません"));
        return false;
    }
    QVariant geometry;
    QMetaObject::invokeMethod(splash, "bootImageGeometry", Q_RETURN_ARG(QVariant, geometry));
    // QML の関数が返す JS のオブジェクトは QJSValue で届くので、QVariantMap に直す
    const QVariantMap g = geometry.userType() == qMetaTypeId<QJSValue>()
                              ? geometry.value<QJSValue>().toVariant().toMap()
                              : geometry.toMap();
    const QImage image = window->grabWindow();
    if (image.isNull() || g.isEmpty() || !image.save(dir + QStringLiteral("/background.png"))) {
        opencruise::log::error("SPLASH", QStringLiteral("起動画面の画像を保存できません: ") + dir);
        return false;
    }
    const int barH = qMax(1, qRound(g.value(QStringLiteral("barH")).toReal()));
    QImage fill(1, barH, QImage::Format_ARGB32);
    fill.fill(QColor(g.value(QStringLiteral("fillColor")).toString()));
    fill.save(dir + QStringLiteral("/progress-fill.png"));

    QFile conf(dir + QStringLiteral("/splash.conf"));
    if (!conf.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        return false;
    }
    const auto color = [&g](const QString &key) { return QColor(g.value(key).toString()); };
    const auto rgb = [](const QColor &c) {
        return QStringLiteral("%1 %2 %3").arg(c.redF(), 0, 'f', 3).arg(c.greenF(), 0, 'f', 3).arg(c.blueF(), 0, 'f', 3);
    };
    QTextStream out(&conf);
    out << "width=" << image.width() << "\n"
        << "height=" << image.height() << "\n"
        << "bar_x=" << qRound(g.value(QStringLiteral("barX")).toReal()) << "\n"
        << "bar_y=" << qRound(g.value(QStringLiteral("barY")).toReal()) << "\n"
        << "bar_w=" << qRound(g.value(QStringLiteral("barW")).toReal()) << "\n"
        << "bar_h=" << barH << "\n"
        << "background_rgb=" << rgb(color(QStringLiteral("backgroundColor"))) << "\n"
        << "text_rgb=" << rgb(color(QStringLiteral("textColor"))) << "\n";
    opencruise::log::info("SPLASH", QStringLiteral("起動画面を書き出しました: %1 (%2 x %3)")
                                        .arg(dir).arg(image.width()).arg(image.height()));
    return true;
}

/**
 * @brief アプリを起動する。
 * @return QGuiApplication の終了コード。QML のロードに失敗した場合は -1
 */
int main(int argc, char *argv[]) {
    // Linux の起動画面(Plymouth)から引き継ぐか(自動起動のサービスが付ける。Plymouth の操作はサービスが行う)
    const bool splashHandoff = qgetenv("OPENCRUISE_SPLASH_HANDOFF") == "1";
#ifdef Q_OS_LINUX
    if (splashHandoff) {
        // Plymouth は終わるときに tty1 を手放し、そのとき tty1 を使っているこのアプリに SIGHUP(端末の切断)が届く。
        // 既定では SIGHUP で終了してしまう(画面が真っ暗になる)ので、無視する。止めるのは systemd(SIGTERM)
        std::signal(SIGHUP, SIG_IGN);
    }
#endif
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
    const QCommandLineOption exportSplash(QStringLiteral("export-splash"),
                                          QStringLiteral("起動画面を Linux の起動画面(Plymouth)用に書き出して終了"),
                                          QStringLiteral("dir"));
    const QCommandLineOption logDir(QStringLiteral("log-dir"), QStringLiteral("ログの保存先ディレクトリ"),
                                    QStringLiteral("path"));
    const QCommandLineOption logLevel(QStringLiteral("log-level"),
                                      QStringLiteral("記録する最小レベル (debug/info/warn/error/fatal)"),
                                      QStringLiteral("level"));
    parser.addOptions({testVideo, screenshot, screenshotDelay, fullscreen, openSettings, skipBoot, exportSplash, logDir, logLevel});
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
    if (splashHandoff) {
        opencruise::log::info("APP", QStringLiteral("Linux の起動画面(Plymouth)から画面を引き継ぎます"));
    }
    const bool exportingSplash = parser.isSet(exportSplash);
    // 描画方式・垂直同期は、ウィンドウ(QML)を作る前にしか変えられないので、ここで適用する
    const opencruise::log::Stopwatch stageTimer; // 起動の段階ごとの時間(起動画面とログに出す)
    qint64 stageStartMs = 0;
    // 前の段階の終わりからの時間を返し、次の段階の計測を始める
    const auto lapMs = [&stageTimer, &stageStartMs]() {
        const qint64 now = stageTimer.elapsedMs();
        const qint64 lap = now - stageStartMs;
        stageStartMs = now;
        return lap;
    };
    const auto msText = [](qint64 ms) { return QStringLiteral("%1 ms").arg(ms); };
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

    // ---- 起動の段階(起動画面に一覧で出し、どこまで進んだか分かるようにする) ----
    // 外部機器やサービスを増やすときは addStep() で足し、準備ができたら boot.report(id, Ready, ...) を呼ぶだけでよい。
    // 応答が無くても timeoutMs で打ち切って先へ進む(必須でも起動は止まらず、画面に失敗として表示する)。
    // 画面が出る前に終わる段階(設定〜画面の読み込み)も、かかった時間を残すために並べる。
    // 起動画面の最低表示時間は 2 秒(準備ができても、この時間は起動画面を見せる)。問題があっても、それ以上は長く止めない。
    // 警告・注意事項は、起動画面のあとの「注意事項」の画面(SplashScreen)で読ませる。問題のあるステップはそこにも出す
    boot.setTiming(3000, 0, 15000);
    boot.addStep(QStringLiteral("system"), QStringLiteral("設定・表示"), true, 0);
    boot.addStep(QStringLiteral("fonts"), QStringLiteral("フォント"), false, 10000);
    boot.addStep(QStringLiteral("audio"), QStringLiteral("音声・明るさ"), true, 0);
    boot.addStep(QStringLiteral("aa"), QStringLiteral("Android Auto 接続層"), true, 8000);
    boot.addStep(QStringLiteral("ui"), QStringLiteral("画面の読み込み"), true, 0);
    boot.addStep(QStringLiteral("home"), QStringLiteral("メイン画面"), true, 0);         // Main.qml が知らせる
    boot.addStep(QStringLiteral("widgets"), QStringLiteral("ウィジェット"), false, 10000); // Main.qml が知らせる
    boot.addStep(QStringLiteral("vehicle"), QStringLiteral("車両データ"), false, 3000);
    boot.addStep(QStringLiteral("esp32"), QStringLiteral("外部機器 (ESP32)"), false, 6000);
    boot.report(QStringLiteral("system"), opencruise::BootManager::Ready, msText(lapMs()));

    // 同梱フォントの読み込みと既定フォントの設定は、QML を読み込む前に済ませる
    opencruise::AppSettings appSettings;
    {
        const QString family = appSettings.fontFamily();
        const qint64 ms = lapMs();
        if (family.isEmpty()) {
            boot.report(QStringLiteral("fonts"), opencruise::BootManager::Warning, QStringLiteral("同梱フォントなし(OS 既定)"));
        } else if (appSettings.isFontLoading(family)) {
            // 通常の太さだけ読み終わっている。残りの太さは別スレッドで読み込み中(終わったら完了にする)
            boot.report(QStringLiteral("fonts"), opencruise::BootManager::Running,
                        QStringLiteral("残りの太さを読み込み中(基本 %1)").arg(msText(ms)));
            auto once = std::make_shared<QMetaObject::Connection>();
            *once = QObject::connect(&appSettings, &opencruise::AppSettings::fontLoadFinished, &boot,
                                     [&boot, family, ms, msText, once](const QString &f, int files, qint64 bgMs) {
                                         if (f != family) return;
                                         QObject::disconnect(*once);
                                         boot.report(QStringLiteral("fonts"), opencruise::BootManager::Ready,
                                                     QStringLiteral("%1(基本 %2 + 残り %3 ファイル %4)")
                                                         .arg(family, msText(ms), QString::number(files), msText(bgMs)));
                                     });
        } else {
            boot.report(QStringLiteral("fonts"), opencruise::BootManager::Ready,
                        QStringLiteral("%1(%2)").arg(family, msText(ms)));
        }
    }
    // 音量(マップ音声・音楽音声・システム)と出力先の設定。AndroidAutoController より先に作る(寿命を app に合わせる)
    auto* audioSettings = new opencruise::AudioSettings(&app);
    opencruise::SystemSound systemSound(audioSettings); // 操作音・起動音(音量・出力先は「システム」の設定に従う)
    opencruise::BrightnessController brightnessController; // 画面の明るさ(バックライト or 暗幕。未対応環境でも動く)
    boot.report(QStringLiteral("audio"), opencruise::BootManager::Ready, msText(lapMs()));
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

    // Android Auto 接続層: 作るところまで(接続待ちに入ったら完了にする)
    const qint64 aaInitMs = lapMs();
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
        boot.report(QStringLiteral("aa"), opencruise::BootManager::Running,
                    QStringLiteral("初期化 %1。接続待ちの開始を待っています").arg(msText(aaInitMs)));
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
    engine.rootContext()->setContextProperty(QStringLiteral("bootSkipped"), parser.isSet(skipBoot));   // 起動後の注意事項も出さない
    // 起動画面: Plymouth から引き継いだ(変わらない部分はフェードせずに最初から出す)/ Plymouth 用に書き出す
    engine.rootContext()->setContextProperty(QStringLiteral("splashHandoff"), splashHandoff);
    engine.rootContext()->setContextProperty(QStringLiteral("splashExport"), exportingSplash);

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
        boot.report(QStringLiteral("ui"), opencruise::BootManager::Ready, msText(qmlLoadTimer.elapsedMs()));
        // 描画が終わるたびに、外部モニターへのミラーを更新する(eglfs のときだけ動く)
        drmDisplay.attach(qobject_cast<QQuickWindow *>(engine.rootObjects().first()));
        // 最初の 1 枚を描いたら、systemd へ知らせる(自動起動のサービスは、これを受けて Plymouth を終わらせる)
        if (auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
            QObject::connect(
                window, &QQuickWindow::frameSwapped, &app,
                [splashHandoff]() {
                    notifySystemdReady();
                    if (splashHandoff) {
                        opencruise::log::info("APP", QStringLiteral("最初の画面を描きました(Linux の起動画面を終わらせます)"));
                    }
                },
                Qt::SingleShotConnection);
        }
    }

    // シャットダウン・再起動などの終了の合図(SIGTERM)では、終了画面を出してから終わる(書き出しのときは不要)
    if (!exportingSplash && !engine.rootObjects().isEmpty()) {
        installTermHandler(app, engine);
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
        if (exportingSplash) {
            return; // 書き出すだけ(起動待ち・接続は始めない)
        }
        if (parser.isSet(skipBoot)) {
            boot.bypass();
        } else {
            boot.start();
        }
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

    if (exportingSplash) {
        // フォント(太字など)の読み込みが終わってから書き出す(最大 8 秒待つ)
        auto *poll = new QTimer(&app);
        auto waited = std::make_shared<int>(0);
        poll->setInterval(200);
        QObject::connect(poll, &QTimer::timeout, &app, [&, poll, waited]() {
            *waited += poll->interval();
            if (*waited < 1500 || (appSettings.isFontLoading(appSettings.fontFamily()) && *waited < 8000)) {
                return;
            }
            poll->stop();
            const auto windows = app.allWindows();
            auto *quickWindow = windows.isEmpty() ? nullptr : qobject_cast<QQuickWindow *>(windows.first());
            const bool ok = exportBootSplash(quickWindow, parser.value(exportSplash));
            QCoreApplication::exit(ok ? 0 : 1);
        });
        poll->start();
    }

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
    // 終了の合図(aboutToQuit)で片付けた画面の部品を、画面全体を壊す前に消しておく(後回しにした削除を実行する)
    QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);

    opencruise::log::info("APP", QStringLiteral("イベントループを終了しました (コード %1)").arg(exitCode));
    opencruise::log::shutdown();
    return exitCode;
}
