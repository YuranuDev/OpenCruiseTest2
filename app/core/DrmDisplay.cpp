/**
 * @file DrmDisplay.cpp
 * @brief DrmDisplay の実装。
 */
#include "DrmDisplay.h"

#include "Log.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQuickWindow>
#include <QSettings>
#include <QVariantMap>

#include <algorithm>
#include <cstdlib>
#include <cstring>

#ifdef OPENCRUISE_WITH_DRM
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <cerrno>
#endif

namespace opencruise {

namespace {
const QString kMainKey = QStringLiteral("display/drm/main");
const QString kMirrorKey = QStringLiteral("display/drm/mirror");
const QString kScaleKey = QStringLiteral("display/drm/scaleMode");

QSettings openStore() {
    return QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"),
                     QStringLiteral("OpenCruise"));
}

/// 内蔵パネルらしい接続名か(eDP / LVDS / DSI / DPI)
bool isInternal(const QString &name) {
    for (const char *prefix : {"eDP", "LVDS", "DSI", "DPI"}) {
        if (name.startsWith(QLatin1String(prefix), Qt::CaseInsensitive)) return true;
    }
    return false;
}

/// カーネルの接続名(例: HDMI-A-1)を、Qt の eglfs が使う出力名(例: HDMI1)にする
QString qtName(const QString &kernelName) {
    const int dash = kernelName.lastIndexOf(QLatin1Char('-'));
    if (dash <= 0) return kernelName;
    QString type = kernelName.left(dash);
    const QString index = kernelName.mid(dash + 1);
    if (type.startsWith(QLatin1String("HDMI"))) type = QStringLiteral("HDMI");
    else if (type.startsWith(QLatin1String("DVI"))) type = QStringLiteral("DVI");
    return type + index;
}

bool wantsEglfs(int argc, char *argv[]) {
    for (int i = 1; i + 1 < argc; ++i) {
        if (std::strcmp(argv[i], "-platform") == 0 || std::strcmp(argv[i], "--platform") == 0) {
            return QString::fromLocal8Bit(argv[i + 1]).startsWith(QLatin1String("eglfs"));
        }
    }
    return qEnvironmentVariable("QT_QPA_PLATFORM").startsWith(QLatin1String("eglfs"));
}

/// /sys/class/drm のコネクタ
struct SysConnector {
    QString card;        ///< "card0"
    QString name;        ///< "DP-1"(カーネルの接続名)
    bool connected = false;
};

QList<SysConnector> scanSysfs() {
    QList<SysConnector> list;
    const QDir drm(QStringLiteral("/sys/class/drm"));
    for (const QString &entry : drm.entryList({QStringLiteral("card*-*")}, QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
        QFile status(drm.filePath(entry + QStringLiteral("/status")));
        if (!status.open(QIODevice::ReadOnly)) continue;
        SysConnector c;
        c.card = entry.section(QLatin1Char('-'), 0, 0);
        c.name = entry.section(QLatin1Char('-'), 1);
        c.connected = status.readAll().trimmed() == "connected";
        list << c;
    }
    return list;
}

/// 「自動」のときの操作する画面: 内蔵パネル → 先頭(つながっている画面の中から)
QString autoMain(const QList<SysConnector> &all) {
    for (const SysConnector &c : all) {
        if (c.connected && isInternal(c.name)) return c.name;
    }
    for (const SysConnector &c : all) {
        if (c.connected) return c.name;
    }
    return {};
}

// ---- 起動前に決めた内容(prepare) ----
bool g_prepared = false;     ///< KMS 設定ファイルを作って Qt に渡した
QString g_card;              ///< 使う GPU("card0")
QString g_main;              ///< 操作する画面(カーネルの接続名)
QString g_note;              ///< ログへ出す説明
} // namespace

// ============================================================================ 起動前
void DrmDisplay::prepare(int argc, char *argv[]) {
    if (!wantsEglfs(argc, argv)) return;
    if (qEnvironmentVariableIsSet("QT_QPA_EGLFS_KMS_CONFIG")) {
        g_note = QStringLiteral("QT_QPA_EGLFS_KMS_CONFIG が設定済みのため、画面の設定はそちらに従います(ミラーは使いません)");
        return;
    }
    const QList<SysConnector> all = scanSysfs();
    QList<SysConnector> connected;
    for (const SysConnector &c : all) {
        if (c.connected) connected << c;
    }
    if (connected.isEmpty()) {
        g_note = QStringLiteral("つながっている画面が見つかりません(/sys/class/drm)");
        return;
    }
    // 操作する画面: 保存した画面 → 内蔵パネル(タッチパネルが付いているのは普通こちら) → 先頭
    const QString saved = openStore().value(kMainKey).toString();
    const SysConnector *main = nullptr;
    for (const SysConnector &c : connected) {
        if (!main && c.name == saved) main = &c;
    }
    const QString automatic = autoMain(all);
    for (const SysConnector &c : connected) {
        if (!main && c.name == automatic) main = &c;
    }
    if (!main) main = &connected.first();
    g_card = main->card;
    g_main = main->name;

    // 操作する画面だけを Qt に使わせる。同じ GPU のほかの画面は "off"(DrmDisplay がミラーに使う)
    QJsonArray outputs;
    QJsonObject mainEntry{{QStringLiteral("name"), qtName(g_main)}, {QStringLiteral("primary"), true}};
    for (const QString &part : qEnvironmentVariable("QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS").split(QLatin1Char(':'))) {
        if (part.startsWith(QLatin1String("/dev/input/"))) {
            mainEntry.insert(QStringLiteral("touchDevice"), part);   // タッチパネルを操作する画面に結び付ける
            break;
        }
    }
    outputs.append(mainEntry);
    for (const SysConnector &c : all) {
        if (c.card == g_card && c.name != g_main) {
            outputs.append(QJsonObject{{QStringLiteral("name"), qtName(c.name)}, {QStringLiteral("mode"), QStringLiteral("off")}});
        }
    }
    const QJsonObject config{{QStringLiteral("device"), QStringLiteral("/dev/dri/") + g_card},
                             {QStringLiteral("hwcursor"), false},
                             {QStringLiteral("outputs"), outputs}};
    const QString path = QDir::tempPath() + QStringLiteral("/opencruise-eglfs-kms.json");
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        g_note = QStringLiteral("KMS 設定ファイルを作れません: ") + path;
        return;
    }
    const QByteArray json = QJsonDocument(config).toJson(QJsonDocument::Compact);
    file.write(json);
    file.close();
    qputenv("QT_QPA_EGLFS_KMS_CONFIG", path.toLocal8Bit());
    g_prepared = true;
    g_note = QStringLiteral("操作する画面: %1(%2)/ 設定 %3: %4")
                 .arg(g_main, g_card, path, QString::fromUtf8(json));
}

// ============================================================================ DRM の処理
#ifdef OPENCRUISE_WITH_DRM
namespace {
/// コネクタの名前(カーネルの接続名。例: DP-1)
QString connectorName(const drmModeConnector *c) {
    const char *type = drmModeGetConnectorTypeName(c->connector_type);
    return QStringLiteral("%1-%2").arg(QString::fromLatin1(type ? type : "Unknown")).arg(c->connector_type_id);
}

/// プレーンの種類(DRM_PLANE_TYPE_*)。取れなければ -1
int planeType(int fd, uint32_t planeId) {
    int type = -1;
    drmModeObjectProperties *props = drmModeObjectGetProperties(fd, planeId, DRM_MODE_OBJECT_PLANE);
    if (!props) return type;
    for (uint32_t i = 0; i < props->count_props; ++i) {
        drmModePropertyRes *p = drmModeGetProperty(fd, props->props[i]);
        if (p && std::strcmp(p->name, "type") == 0) type = static_cast<int>(props->prop_values[i]);
        drmModeFreeProperty(p);
    }
    drmModeFreeObjectProperties(props);
    return type;
}
} // namespace
#endif

/// ミラー先の 1 画面
struct MirrorOutput {
    QString name;               ///< カーネルの接続名
    bool connected = false;
    bool running = false;       ///< 表示中
    bool failed = false;        ///< 表示できなかった(つなぎ直すか設定を変えるまで再挑戦しない)
    QString detail;             ///< 設定画面に出す説明(解像度・エラー)
#ifdef OPENCRUISE_WITH_DRM
    uint32_t connectorId = 0;
    uint32_t crtcId = 0;
    uint32_t planeId = 0;       ///< 拡大縮小するときに使うプレーン
    drmModeModeInfo mode{};
    bool scaled = false;
    uint32_t dumbHandle = 0;    ///< 拡大縮小するときの下地(黒)
    uint32_t dumbFb = 0;
    uint32_t lastFb = 0;        ///< 最後に表示したフレームバッファ
#endif
};

struct DrmDisplay::Private {
    int fd = -1;
    uint32_t mainConnector = 0;
    uint32_t mainCrtc = 0;
    QList<SysConnector> sys;
    QList<MirrorOutput> mirrors;   ///< 操作する画面以外の、同じ GPU の画面

#ifdef OPENCRUISE_WITH_DRM
    /// このプロセスが開いている /dev/dri/cardN のうち、DRM マスターのもの(= Qt の fd)を探す
    static int findMasterFd(const QString &card) {
        const QDir fdDir(QStringLiteral("/proc/self/fd"));
        for (const QString &entry : fdDir.entryList(QDir::AllEntries | QDir::System | QDir::NoDotAndDotDot)) {
            const QString target = QFileInfo(fdDir.filePath(entry)).symLinkTarget();
            if (target != QStringLiteral("/dev/dri/") + card) continue;
            bool ok = false;
            const int fd = entry.toInt(&ok);
            if (ok && drmIsMaster(fd)) return fd;
        }
        return -1;
    }

    /// 名前のコネクタを探す(呼び出し側が drmModeFreeConnector する)
    drmModeConnector *findConnector(const QString &name) const {
        drmModeRes *res = drmModeGetResources(fd);
        if (!res) return nullptr;
        drmModeConnector *found = nullptr;
        for (int i = 0; i < res->count_connectors && !found; ++i) {
            drmModeConnector *c = drmModeGetConnector(fd, res->connectors[i]);
            if (c && connectorName(c) == name) found = c;
            else drmModeFreeConnector(c);
        }
        drmModeFreeResources(res);
        return found;
    }

    /// 操作する画面が使っている CRTC を調べる(Qt が画面を出すまでは 0)
    void resolveMain(const QString &name) {
        if (mainCrtc) return;
        drmModeConnector *c = findConnector(name);
        if (!c) return;
        mainConnector = c->connector_id;
        if (c->encoder_id) {
            drmModeEncoder *e = drmModeGetEncoder(fd, c->encoder_id);
            if (e) {
                mainCrtc = e->crtc_id;
                drmModeFreeEncoder(e);
            }
        }
        drmModeFreeConnector(c);
    }

    /// ミラー先に使える CRTC(操作する画面・ほかのミラー先が使っていないもの)と、その番号
    uint32_t pickCrtc(const drmModeConnector *c, int *crtcIndex) const {
        drmModeRes *res = drmModeGetResources(fd);
        if (!res) return 0;
        uint32_t picked = 0;
        for (int e = 0; e < c->count_encoders && !picked; ++e) {
            drmModeEncoder *enc = drmModeGetEncoder(fd, c->encoders[e]);
            if (!enc) continue;
            for (int i = 0; i < res->count_crtcs && !picked; ++i) {
                const uint32_t id = res->crtcs[i];
                if (!(enc->possible_crtcs & (1u << i)) || id == mainCrtc) continue;
                bool used = false;
                for (const MirrorOutput &m : mirrors) used = used || (m.running && m.crtcId == id);
                if (!used) {
                    picked = id;
                    *crtcIndex = i;
                }
            }
            drmModeFreeEncoder(enc);
        }
        drmModeFreeResources(res);
        return picked;
    }

    /// CRTC の主プレーン(拡大縮小に使う)
    uint32_t primaryPlane(int crtcIndex) const {
        drmModePlaneRes *planes = drmModeGetPlaneResources(fd);
        if (!planes) return 0;
        uint32_t found = 0;
        for (uint32_t i = 0; i < planes->count_planes && !found; ++i) {
            drmModePlane *p = drmModeGetPlane(fd, planes->planes[i]);
            if (p && (p->possible_crtcs & (1u << crtcIndex)) && planeType(fd, p->plane_id) == DRM_PLANE_TYPE_PRIMARY) {
                found = p->plane_id;
            }
            drmModeFreePlane(p);
        }
        drmModeFreePlaneResources(planes);
        return found;
    }

    /// 縦横比を保って画面いっぱいに収める表示位置
    static void fitRect(int srcW, int srcH, int dstW, int dstH, int *x, int *y, int *w, int *h) {
        const double scale = std::min(static_cast<double>(dstW) / srcW, static_cast<double>(dstH) / srcH);
        *w = static_cast<int>(srcW * scale);
        *h = static_cast<int>(srcH * scale);
        *x = (dstW - *w) / 2;
        *y = (dstH - *h) / 2;
    }

    bool setPlane(MirrorOutput &m, uint32_t fb, int fbW, int fbH) const {
        int x = 0, y = 0, w = 0, h = 0;
        fitRect(fbW, fbH, m.mode.hdisplay, m.mode.vdisplay, &x, &y, &w, &h);
        return drmModeSetPlane(fd, m.planeId, m.crtcId, fb, 0, x, y, static_cast<uint32_t>(w), static_cast<uint32_t>(h), 0, 0,
                               static_cast<uint32_t>(fbW) << 16, static_cast<uint32_t>(fbH) << 16) == 0;
    }

    /// ミラー先を表示し始める。失敗したら m.detail に理由を入れて false
    bool start(MirrorOutput &m, uint32_t fb, int scaleMode) {
        drmModeFB *info = drmModeGetFB(fd, fb);
        if (!info) {
            m.detail = QStringLiteral("操作する画面の画を読めません");
            return false;
        }
        const int fbW = static_cast<int>(info->width), fbH = static_cast<int>(info->height);
        drmModeFreeFB(info);

        drmModeConnector *c = findConnector(m.name);
        if (!c || c->connection != DRM_MODE_CONNECTED || c->count_modes == 0) {
            drmModeFreeConnector(c);
            m.detail = QStringLiteral("画面の情報を読めません");
            return false;
        }
        // 解像度: 同じ解像度(推奨・60Hz に近いもの)→ 無ければ推奨解像度で拡大縮小
        int pick = -1, preferred = 0;
        for (int i = 0; i < c->count_modes; ++i) {
            const drmModeModeInfo &mi = c->modes[i];
            if (mi.type & DRM_MODE_TYPE_PREFERRED) preferred = i;
            if (scaleMode == 0 && mi.hdisplay == fbW && mi.vdisplay == fbH && !(mi.flags & DRM_MODE_FLAG_INTERLACE)) {
                if (pick < 0 || std::abs(static_cast<int>(mi.vrefresh) - 60) < std::abs(static_cast<int>(c->modes[pick].vrefresh) - 60)) {
                    pick = i;
                }
            }
        }
        m.scaled = pick < 0 || c->modes[pick].hdisplay != fbW || c->modes[pick].vdisplay != fbH;
        if (pick < 0) pick = preferred;
        m.mode = c->modes[pick];
        m.connectorId = c->connector_id;
        int crtcIndex = -1;
        m.crtcId = pickCrtc(c, &crtcIndex);
        drmModeFreeConnector(c);
        if (!m.crtcId) {
            m.detail = QStringLiteral("空いている出力回路(CRTC)がありません");
            return false;
        }

        if (!m.scaled) {
            if (drmModeSetCrtc(fd, m.crtcId, fb, 0, 0, &m.connectorId, 1, &m.mode) != 0) {
                m.detail = QStringLiteral("表示を始められません(%1)").arg(QString::fromLocal8Bit(std::strerror(errno)));
                return false;
            }
        } else {
            // 下地(黒)で画面を点け、主プレーンに操作する画面の画を拡大縮小して載せる
            uint32_t pitch = 0;
            uint64_t size = 0;
            if (drmModeCreateDumbBuffer(fd, m.mode.hdisplay, m.mode.vdisplay, 32, 0, &m.dumbHandle, &pitch, &size) != 0 ||
                drmModeAddFB(fd, m.mode.hdisplay, m.mode.vdisplay, 24, 32, pitch, m.dumbHandle, &m.dumbFb) != 0 ||
                drmModeSetCrtc(fd, m.crtcId, m.dumbFb, 0, 0, &m.connectorId, 1, &m.mode) != 0) {
                m.detail = QStringLiteral("表示を始められません(%1)").arg(QString::fromLocal8Bit(std::strerror(errno)));
                releaseDumb(m);
                return false;
            }
            m.planeId = primaryPlane(crtcIndex);
            if (!m.planeId || !setPlane(m, fb, fbW, fbH)) {
                m.detail = QStringLiteral("この GPU では拡大縮小して表示できません(%1×%2 → %3×%4)")
                               .arg(fbW).arg(fbH).arg(m.mode.hdisplay).arg(m.mode.vdisplay);
                stop(m);
                return false;
            }
        }
        m.lastFb = fb;
        m.running = true;
        m.detail = QStringLiteral("%1×%2 %3Hz%4")
                       .arg(m.mode.hdisplay).arg(m.mode.vdisplay).arg(m.mode.vrefresh)
                       .arg(m.scaled ? QStringLiteral("(%1×%2 を拡大縮小)").arg(fbW).arg(fbH) : QString());
        return true;
    }

    /// 新しい画に切り替える(前の切り替えが終わっていなければ、次の描画で再試行)
    void update(MirrorOutput &m, uint32_t fb) {
        if (fb == m.lastFb) return;
        if (m.scaled) {
            drmModeFB *info = drmModeGetFB(fd, fb);
            if (!info) return;
            const bool ok = setPlane(m, fb, static_cast<int>(info->width), static_cast<int>(info->height));
            drmModeFreeFB(info);
            if (ok) m.lastFb = fb;
        } else if (drmModePageFlip(fd, m.crtcId, fb, 0, nullptr) == 0) {
            m.lastFb = fb;
        }
    }

    /// CRTC が消されていないか(Qt が画を作り直すと、表示していたフレームバッファが消えて画面が消える)
    bool alive(const MirrorOutput &m) const {
        drmModeCrtc *crtc = drmModeGetCrtc(fd, m.crtcId);
        const bool ok = crtc && crtc->mode_valid && crtc->buffer_id != 0;
        drmModeFreeCrtc(crtc);
        return ok;
    }

    void releaseDumb(MirrorOutput &m) const {
        if (m.dumbFb) drmModeRmFB(fd, m.dumbFb);
        if (m.dumbHandle) drmModeDestroyDumbBuffer(fd, m.dumbHandle);
        m.dumbFb = 0;
        m.dumbHandle = 0;
    }

    void stop(MirrorOutput &m) const {
        if (m.crtcId && fd >= 0) {
            drmModeSetCrtc(fd, m.crtcId, 0, 0, 0, nullptr, 0, nullptr);
        }
        releaseDumb(m);
        m.running = false;
        m.crtcId = 0;
        m.planeId = 0;
        m.lastFb = 0;
    }
#endif
};

// ============================================================================ 起動後
DrmDisplay::DrmDisplay(QObject *parent) : QObject(parent), d_(std::make_unique<Private>()) {
    const QSettings store = openStore();
    savedMain_ = store.value(kMainKey).toString();
    mirrorEnabled_ = store.value(kMirrorKey, true).toBool();
    scaleMode_ = store.value(kScaleKey, 0).toInt() == 1 ? 1 : 0;
    if (!g_note.isEmpty()) {
        log::info("DISPLAY", QStringLiteral("DRM: ") + g_note);
    }

    if (!QGuiApplication::platformName().startsWith(QLatin1String("eglfs"))) {
        status_ = QStringLiteral("eglfs 以外では使いません(外部モニターの設定は OS のディスプレイ設定で行ってください)");
        return;
    }
#ifdef OPENCRUISE_WITH_DRM
    if (!g_prepared) {
        status_ = g_note.isEmpty() ? QStringLiteral("画面の設定を用意できませんでした") : g_note;
        return;
    }
    d_->fd = Private::findMasterFd(g_card);
    if (d_->fd < 0) {
        status_ = QStringLiteral("Qt の DRM(/dev/dri/%1)を見つけられません").arg(g_card);
        log::warn("DISPLAY", QStringLiteral("DRM: ") + status_);
        return;
    }
    active_ = true;
    status_ = QStringLiteral("操作する画面: %1").arg(g_main);
    connect(&pollTimer_, &QTimer::timeout, this, &DrmDisplay::poll);
    pollTimer_.start(1500);
    poll();
#else
    status_ = QStringLiteral("このビルドは DRM に対応していません(libdrm-dev を入れてビルドし直してください)");
#endif
}

DrmDisplay::~DrmDisplay() { stop(); }

bool DrmDisplay::supported() const {
#ifdef OPENCRUISE_WITH_DRM
    return true;
#else
    return false;
#endif
}

void DrmDisplay::attach(QQuickWindow *window) {
    window_ = window;
    if (!window || !active_) return;
    // 描画スレッドから届くので、UI スレッドで処理する(DRM の操作は UI スレッドだけで行う)
    connect(window, &QQuickWindow::frameSwapped, this, &DrmDisplay::onFrame, Qt::QueuedConnection);
}

void DrmDisplay::setStatus(const QString &text) {
    status_ = text;
    emit changed();
}

void DrmDisplay::poll() {
#ifdef OPENCRUISE_WITH_DRM
    if (!active_) return;
    d_->sys = scanSysfs();
    // ミラー先の一覧を、今のコネクタに合わせる(同じ GPU で操作する画面以外)
    QList<MirrorOutput> next;
    for (const SysConnector &c : d_->sys) {
        if (c.card != g_card || c.name == g_main) continue;
        MirrorOutput m;
        for (const MirrorOutput &old : d_->mirrors) {
            if (old.name == c.name) m = old;
        }
        m.name = c.name;
        const bool wasConnected = m.connected;
        m.connected = c.connected;
        if (m.running && (!m.connected || !mirrorEnabled_)) {
            d_->stop(m);
            if (!m.connected) log::info("DISPLAY", QStringLiteral("DRM: %1 が外れたのでミラーをやめました").arg(m.name));
        } else if (m.running && !d_->alive(m)) {
            d_->stop(m);   // 画面が消されていた: 次の描画でやり直す
        }
        if (!m.connected || (m.connected && !wasConnected)) {
            m.detail.clear();   // つながり直したら前の失敗を忘れて再挑戦する
            m.failed = false;
        }
        next << m;
    }
    d_->mirrors = next;
    emit changed();
#endif
}

void DrmDisplay::onFrame() {
#ifdef OPENCRUISE_WITH_DRM
    if (!active_ || !mirrorEnabled_) return;
    d_->resolveMain(g_main);
    if (!d_->mainCrtc) return;
    drmModeCrtc *crtc = drmModeGetCrtc(d_->fd, d_->mainCrtc);
    const uint32_t fb = crtc ? crtc->buffer_id : 0;
    drmModeFreeCrtc(crtc);
    if (!fb) return;
    bool changedAny = false;
    for (MirrorOutput &m : d_->mirrors) {
        if (!m.connected) continue;
        if (m.running) {
            d_->update(m, fb);
        } else if (!m.failed) {   // 失敗した画面は、つなぎ直すか設定を変えるまで再挑戦しない
            if (d_->start(m, fb, scaleMode_)) {
                log::info("DISPLAY", QStringLiteral("DRM: %1 へミラーを始めました(%2)").arg(m.name, m.detail));
            } else {
                m.failed = true;
                log::warn("DISPLAY", QStringLiteral("DRM: %1 へミラーできません: %2").arg(m.name, m.detail));
            }
            changedAny = true;
        }
    }
    if (changedAny) emit changed();
#endif
}

void DrmDisplay::stop() {
#ifdef OPENCRUISE_WITH_DRM
    for (MirrorOutput &m : d_->mirrors) {
        if (m.running) d_->stop(m);
    }
#endif
}

QVariantList DrmDisplay::outputs() const {
    QVariantList list;
    for (const SysConnector &c : d_->sys) {
        QString role;
        QString detail;
        if (c.name == g_main && c.card == g_card) {
            role = QStringLiteral("操作する画面");
        } else if (!c.connected) {
            role = QStringLiteral("未接続");
        } else if (c.card != g_card) {
            role = QStringLiteral("使わない(別の GPU)");
        } else {
            role = mirrorEnabled_ ? QStringLiteral("ミラー待ち") : QStringLiteral("使わない");
            for (const MirrorOutput &m : d_->mirrors) {
                if (m.name != c.name) continue;
                detail = m.detail;
                if (m.running) role = QStringLiteral("ミラー中");
                else if (m.failed && mirrorEnabled_) role = QStringLiteral("ミラーできません");
            }
        }
        list.append(QVariantMap{{QStringLiteral("name"), c.name}, {QStringLiteral("connected"), c.connected},
                                {QStringLiteral("role"), role}, {QStringLiteral("detail"), detail}});
    }
    return list;
}

QStringList DrmDisplay::mainChoices() const {
    QStringList list{QStringLiteral("自動(内蔵パネル)")};
    bool savedListed = savedMain_.isEmpty();
    for (const SysConnector &c : d_->sys) {
        if (!c.connected) continue;
        list << c.name;
        savedListed = savedListed || c.name == savedMain_;
    }
    if (!savedListed) list << savedMain_ + QStringLiteral("(未接続)");
    return list;
}

int DrmDisplay::mainChoiceIndex() const {
    if (savedMain_.isEmpty()) return 0;
    const QStringList list = mainChoices();
    for (int i = 1; i < list.size(); ++i) {
        if (list[i] == savedMain_ || list[i] == savedMain_ + QStringLiteral("(未接続)")) return i;
    }
    return 0;
}

void DrmDisplay::setMainChoiceIndex(int index) {
    const QStringList list = mainChoices();
    if (index < 0 || index >= list.size()) return;
    QString name = index == 0 ? QString() : list[index];
    name.remove(QStringLiteral("(未接続)"));
    if (name == savedMain_) return;
    savedMain_ = name;
    openStore().setValue(kMainKey, savedMain_);
    emit changed();
}

QString DrmDisplay::mainOutput() const { return g_main; }

void DrmDisplay::setMirrorEnabled(bool on) {
    if (on == mirrorEnabled_) return;
    mirrorEnabled_ = on;
    openStore().setValue(kMirrorKey, mirrorEnabled_);
#ifdef OPENCRUISE_WITH_DRM
    for (MirrorOutput &m : d_->mirrors) {
        if (!on && m.running) d_->stop(m);
        m.detail.clear();   // オンに戻したら、失敗していた画面も再挑戦する
        m.failed = false;
    }
#endif
    emit changed();
}

void DrmDisplay::setScaleMode(int mode) {
    mode = mode == 1 ? 1 : 0;
    if (mode == scaleMode_) return;
    scaleMode_ = mode;
    openStore().setValue(kScaleKey, scaleMode_);
#ifdef OPENCRUISE_WITH_DRM
    for (MirrorOutput &m : d_->mirrors) {   // 新しい方式で表示し直す
        if (m.running) d_->stop(m);
        m.detail.clear();
        m.failed = false;
    }
#endif
    emit changed();
}

bool DrmDisplay::restartRequired() const {
    if (!active_) return false;
    // 次に起動したときに選ばれる画面(prepare と同じ規則)が、今の画面と違えば再起動が要る
    bool savedConnected = false;
    for (const SysConnector &c : d_->sys) savedConnected = savedConnected || (c.connected && c.name == savedMain_);
    const QString next = (!savedMain_.isEmpty() && savedConnected) ? savedMain_ : autoMain(d_->sys);
    return !next.isEmpty() && next != g_main;
}

} // namespace opencruise
