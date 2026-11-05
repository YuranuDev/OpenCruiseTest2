/**
 * @file ReverseCamera.cpp
 * @brief バックカメラ(バック信号での切り替えと、UVC カメラの映像)の実装。
 */
#include "ReverseCamera.h"

#include "core/Log.h"

#include <QCameraFormat>
#include <QSettings>
#include <QVariant>
#include <QVideoFrame>
#include <QVideoSink>

#include <algorithm>

namespace opencruise {

namespace {
QSettings openStore() {
    return QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"), QStringLiteral("OpenCruise"));
}

QString idOf(const QCameraDevice &device) { return QString::fromUtf8(device.id()); }

QString formatText(const QCameraFormat &f) {
    if (f.isNull()) return QStringLiteral("default format");
    return QStringLiteral("%1x%2 %3fps").arg(f.resolution().width()).arg(f.resolution().height()).arg(f.maxFrameRate(), 0, 'f', 0);
}

// 1280x720 以下でいちばん画素数の多い形式。同じならフレームレートの高いもの(30fps を超える分は区別しない)。
// 1280x720 以下が無ければ、いちばん小さいもの
QCameraFormat chooseFormat(const QCameraDevice &device) {
    const QList<QCameraFormat> formats = device.videoFormats();
    QCameraFormat best;
    auto score = [](const QCameraFormat &f) {
        const QSize s = f.resolution();
        return qint64(s.width()) * s.height() * 100 + qint64(std::min(30.f, f.maxFrameRate()));
    };
    for (const QCameraFormat &f : formats) {
        const QSize s = f.resolution();
        if (s.width() > 1280 || s.height() > 720) continue;
        if (best.isNull() || score(f) > score(best)) best = f;
    }
    if (best.isNull()) {
        for (const QCameraFormat &f : formats) {
            if (best.isNull() || qint64(f.resolution().width()) * f.resolution().height()
                                     < qint64(best.resolution().width()) * best.resolution().height())
                best = f;
        }
    }
    return best;
}
} // namespace

ReverseCamera::ReverseCamera(QObject *parent) : QObject(parent) {
    const QSettings store = openStore();
    signalSource_ = std::clamp(store.value(QStringLiteral("camera/signalSource"), 0).toInt(), 0, 1);
    autoSwitch_ = store.value(QStringLiteral("camera/autoSwitch"), true).toBool();
    returnDelay_ = std::clamp(store.value(QStringLiteral("camera/returnDelay"), 2).toInt(), 0, 10);
    deviceId_ = store.value(QStringLiteral("camera/deviceId")).toString();
    deviceName_ = store.value(QStringLiteral("camera/deviceName")).toString();
    mirror_ = store.value(QStringLiteral("camera/mirror"), false).toBool();
    guides_ = store.value(QStringLiteral("camera/guides"), true).toBool();
    fill_ = store.value(QStringLiteral("camera/fill"), false).toBool();
    keepWarm_ = store.value(QStringLiteral("camera/keepWarm"), false).toBool();

    holdTimer_.setSingleShot(true);
    connect(&holdTimer_, &QTimer::timeout, this, [this]() {
        holding_ = false;
        updateShown();
    });
    connect(&mediaDevices_, &QMediaDevices::videoInputsChanged, this, [this]() { refreshDevices(); });

    devices_ = QMediaDevices::videoInputs();
    QStringList names;
    for (const QCameraDevice &d : devices_) names << QStringLiteral("%1 (%2)").arg(d.description(), idOf(d));
    log::info("CAMERA", QStringLiteral("video inputs: %1 / selected: %2 / signal source: %3")
                            .arg(names.isEmpty() ? QStringLiteral("none") : names.join(QStringLiteral(", ")),
                                 deviceId_.isEmpty() ? QStringLiteral("auto") : deviceId_,
                                 signalSource_ == 0 ? QStringLiteral("mock (Ctrl+Shift+R)") : QStringLiteral("external")));
    updateCamera();   // keepWarm なら起動時から動かしておく
}

ReverseCamera::~ReverseCamera() { stopCamera(); }

void ReverseCamera::save(const QString &key, const QVariant &value) {
    openStore().setValue(key, value);
    emit settingsChanged();
}

// ---------------------------------------------------------------- バック信号
void ReverseCamera::setSignalSource(int source) {
    source = std::clamp(source, 0, 1);
    if (source == signalSource_) return;
    signalSource_ = source;
    log::info("CAMERA", QStringLiteral("signal source: %1").arg(source == 0 ? QStringLiteral("mock") : QStringLiteral("external")));
    save(QStringLiteral("camera/signalSource"), signalSource_);
    updateReverse();
}

void ReverseCamera::setMockReverse(bool on) {
    if (on == mockReverse_) return;
    mockReverse_ = on;
    emit reverseChanged();
    updateReverse();
}

void ReverseCamera::setExternalReverse(bool on) {
    if (on == externalReverse_) return;
    externalReverse_ = on;
    updateReverse();
}

void ReverseCamera::updateReverse() {
    const bool now = signalSource_ == 0 ? mockReverse_ : externalReverse_;
    if (now == reverse_) return;
    reverse_ = now;
    log::info("CAMERA", QStringLiteral("reverse signal: %1 (%2)")
                            .arg(now ? QStringLiteral("ON") : QStringLiteral("OFF"),
                                 signalSource_ == 0 ? QStringLiteral("mock") : QStringLiteral("external")));
    if (now) {
        dismissed_ = false;        // バックに入れ直したら、閉じたものもまた出す
        holding_ = false;
        holdTimer_.stop();
    } else if (shown_ && !previewing_) {
        // 切れても、少しの間はそのまま映す(切り返しで何度も切り替わらないように)
        holding_ = returnDelay_ > 0;
        if (holding_) holdTimer_.start(returnDelay_ * 1000);
    }
    emit reverseChanged();
    updateShown();
}

// ---------------------------------------------------------------- 表示の切り替え
void ReverseCamera::setAutoSwitch(bool on) {
    if (on == autoSwitch_) return;
    autoSwitch_ = on;
    save(QStringLiteral("camera/autoSwitch"), autoSwitch_);
    updateShown();
}

void ReverseCamera::setReturnDelay(int seconds) {
    seconds = std::clamp(seconds, 0, 10);
    if (seconds == returnDelay_) return;
    returnDelay_ = seconds;
    save(QStringLiteral("camera/returnDelay"), returnDelay_);
}

void ReverseCamera::setPreview(bool on) {
    if (on == previewing_) return;
    previewing_ = on;
    log::info("CAMERA", QStringLiteral("preview: %1").arg(on ? QStringLiteral("on") : QStringLiteral("off")));
    updateShown();
}

void ReverseCamera::dismiss() {
    if (previewing_) {
        setPreview(false);
        return;
    }
    if (!shown_) return;
    log::info("CAMERA", QStringLiteral("dismissed by the user"));
    dismissed_ = true;
    holding_ = false;
    holdTimer_.stop();
    updateShown();
}

void ReverseCamera::updateShown() {
    const bool want = previewing_ || (autoSwitch_ && !dismissed_ && (reverse_ || holding_));
    if (want != shown_) {
        shown_ = want;
        log::info("CAMERA", QStringLiteral("camera view %1").arg(want ? QStringLiteral("shown") : QStringLiteral("hidden")));
        emit shownChanged();
    } else {
        emit shownChanged();   // previewing の変化を知らせる(shown は同じでも)
    }
    updateCamera();
}

// ---------------------------------------------------------------- カメラの選択
void ReverseCamera::refreshDevices() {
    const QList<QCameraDevice> list = QMediaDevices::videoInputs();
    bool same = list.size() == devices_.size();
    for (int i = 0; same && i < list.size(); ++i) same = list[i].id() == devices_[i].id();
    if (same) return;
    devices_ = list;
    QStringList names;
    for (const QCameraDevice &d : devices_) names << d.description();
    log::info("CAMERA", QStringLiteral("video inputs changed: %1").arg(names.isEmpty() ? QStringLiteral("none") : names.join(QStringLiteral(", "))));
    emit devicesChanged();
    // 動かしているカメラが抜けたら止める。選んでいたカメラが戻ったら動かす
    if (camera_ != nullptr) {
        const bool stillThere = std::any_of(devices_.begin(), devices_.end(), [this](const QCameraDevice &d) { return d.id() == cameraId_; });
        if (!stillThere) {
            log::warn("CAMERA", QStringLiteral("the active camera was disconnected"));
            stopCamera();
        }
    }
    updateCamera();
}

QStringList ReverseCamera::deviceNames() const {
    QStringList names{QStringLiteral("自動")};
    for (const QCameraDevice &d : devices_) names << d.description();
    return names;
}

int ReverseCamera::deviceIndex() const {
    if (deviceId_.isEmpty()) return 0;
    for (int i = 0; i < devices_.size(); ++i) {
        if (idOf(devices_[i]) == deviceId_) return i + 1;
    }
    return 0;   // 見つからない(missingDevice に名前を出す)
}

void ReverseCamera::setDeviceIndex(int index) {
    QString id, name;
    if (index >= 1 && index <= devices_.size()) {
        id = idOf(devices_[index - 1]);
        name = devices_[index - 1].description();
    }
    if (id == deviceId_) return;
    deviceId_ = id;
    deviceName_ = name;
    log::info("CAMERA", QStringLiteral("camera selected: %1").arg(id.isEmpty() ? QStringLiteral("auto") : QStringLiteral("%1 (%2)").arg(name, id)));
    QSettings store = openStore();
    store.setValue(QStringLiteral("camera/deviceId"), deviceId_);
    store.setValue(QStringLiteral("camera/deviceName"), deviceName_);
    emit devicesChanged();
    stopCamera();      // 別の機器に替える
    updateCamera();
}

QString ReverseCamera::missingDevice() const {
    if (deviceId_.isEmpty() || deviceIndex() > 0) return QString();
    return deviceName_.isEmpty() ? deviceId_ : deviceName_;
}

QCameraDevice ReverseCamera::selectedDevice() const {
    if (!deviceId_.isEmpty()) {
        for (const QCameraDevice &d : devices_) {
            if (idOf(d) == deviceId_) return d;
        }
        return QCameraDevice();   // 選んだ機器が無いときは、ほかのカメラに替えない(別のカメラが映ると紛らわしい)
    }
    const QCameraDevice def = QMediaDevices::defaultVideoInput();
    if (!def.isNull()) return def;
    return devices_.isEmpty() ? QCameraDevice() : devices_.first();
}

// ---------------------------------------------------------------- 見た目の設定
void ReverseCamera::setMirror(bool on) {
    if (on == mirror_) return;
    mirror_ = on;
    save(QStringLiteral("camera/mirror"), mirror_);
}
void ReverseCamera::setGuides(bool on) {
    if (on == guides_) return;
    guides_ = on;
    save(QStringLiteral("camera/guides"), guides_);
}
void ReverseCamera::setFill(bool on) {
    if (on == fill_) return;
    fill_ = on;
    save(QStringLiteral("camera/fill"), fill_);
}
void ReverseCamera::setKeepWarm(bool on) {
    if (on == keepWarm_) return;
    keepWarm_ = on;
    save(QStringLiteral("camera/keepWarm"), keepWarm_);
    updateCamera();
}

// ---------------------------------------------------------------- カメラの動かし方
void ReverseCamera::setVideoOutput(QObject *output) {
    output_ = output;
    session_.setVideoOutput(output);
    // 最初のフレームが届いたことを知るため、出し先(VideoOutput)の videoSink を見る
    QObject::disconnect(frameConnection_);
    QVideoSink *sink = output ? output->property("videoSink").value<QVideoSink *>() : nullptr;
    if (sink == nullptr) sink = session_.videoSink();
    if (sink != nullptr) {
        frameConnection_ = connect(sink, &QVideoSink::videoFrameChanged, this, [this](const QVideoFrame &frame) {
            if (!receiving_ && camera_ != nullptr && frame.isValid()) setReceiving(true);
        });
    } else {
        log::warn("CAMERA", QStringLiteral("no video sink on the output; the view is shown when the camera becomes active"));
    }
}

void ReverseCamera::setReceiving(bool on) {
    if (on == receiving_) return;
    receiving_ = on;
    if (on) log::info("CAMERA", QStringLiteral("first video frame received"));
    emit receivingChanged();
}

void ReverseCamera::setCameraState(const QString &state, const QString &error) {
    if (state == cameraState_ && error == cameraError_) return;
    cameraState_ = state;
    cameraError_ = error;
    emit cameraStateChanged();
}

void ReverseCamera::updateCamera() {
    const bool want = shown_ || keepWarm_;
    if (!want) {
        stopCamera();
        return;
    }
    const QCameraDevice device = selectedDevice();
    if (device.isNull()) {
        stopCamera();
        setCameraState(QStringLiteral("none"));
        return;
    }
    if (camera_ != nullptr && cameraId_ == device.id()) return;   // もう動かしている
    stopCamera();
    startCamera(device);
}

void ReverseCamera::startCamera(const QCameraDevice &device) {
    camera_ = new QCamera(device, this);
    cameraId_ = device.id();
    const QCameraFormat format = chooseFormat(device);
    if (!format.isNull()) camera_->setCameraFormat(format);
    activeDescription_ = QStringLiteral("%1: %2").arg(device.description(), formatText(format));
    connect(camera_, &QCamera::activeChanged, this, [this](bool active) {
        if (active) {
            log::info("CAMERA", QStringLiteral("camera started: %1").arg(activeDescription_));
            setCameraState(QStringLiteral("active"));
            // フレームを見られない(出し先が未登録・videoSink が無い)ときは、動き始めた時点で映す
            if (!frameConnection_) setReceiving(true);
        } else if (cameraState_ != QStringLiteral("error")) {
            setCameraState(QStringLiteral("off"));
        }
    });
    connect(camera_, &QCamera::errorOccurred, this, [this](QCamera::Error error, const QString &text) {
        if (error == QCamera::NoError) return;
        log::warn("CAMERA", QStringLiteral("camera error: %1").arg(text));
        setCameraState(QStringLiteral("error"), text);
    });
    session_.setCamera(camera_);
    setReceiving(false);
    setCameraState(QStringLiteral("starting"));
    log::info("CAMERA", QStringLiteral("starting camera: %1 (%2)").arg(activeDescription_, idOf(device)));
    camera_->start();
}

void ReverseCamera::stopCamera() {
    if (camera_ == nullptr) {
        if (cameraState_ != QStringLiteral("none")) setCameraState(QStringLiteral("off"));
        return;
    }
    QCamera *cam = camera_;
    camera_ = nullptr;
    cameraId_.clear();
    cam->disconnect(this);
    cam->stop();
    session_.setCamera(nullptr);
    cam->deleteLater();
    setReceiving(false);
    log::info("CAMERA", QStringLiteral("camera stopped"));
    setCameraState(QStringLiteral("off"));
}

} // namespace opencruise
