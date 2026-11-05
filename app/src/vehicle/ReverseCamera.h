/**
 * @file ReverseCamera.h
 * @brief バックカメラ。バック信号を受けて画面をカメラ映像へ切り替え、UVC カメラ(キャプチャーボード)の映像を出す。
 *
 * QML へは context property `reverseCamera` として公開する。映像は QML の VideoOutput(ReverseCameraVideo.qml)を
 * setVideoOutput() で渡してもらい、ここが持つ QMediaCaptureSession から流す。
 *
 * バック信号:
 *  - 今はダミー(モック)だけ。キーボードの Ctrl+Shift+R(Main.qml)か、設定画面のスイッチで入/切する
 *  - 将来は外部マイコン(バックランプの線を読む)から受ける。受け口は setExternalReverse()。
 *    signalSource が External のときは、そちらの値を使う(外部マイコンの通信は未実装)
 *
 * 画面の切り替え(shown):
 *  - 自動切り替え(autoSwitch)がオンなら、バック信号が入ったらすぐ出し、切れたら returnDelay 秒後に戻す
 *    (その間にまたバックに入れたら出したまま)
 *  - 映像の右上の「閉じる」で、そのバックの間だけ閉じられる(dismiss。次にバックへ入れたらまた出る)
 *  - 設定画面の「映像を確認」で、バック信号に関係なく出せる(preview)
 *
 * カメラ:
 *  - Qt Multimedia の映像入力(Linux では V4L2。UVC のキャプチャーボード・USB カメラ)から選ぶ。
 *    設定は機器の id で保存し、抜き差しで番号が変わっても同じ機器を選ぶ。「自動」は最初に見つかった機器
 *  - 映すときだけカメラを動かす。「すぐに映す」(keepWarm)がオンなら常に動かしておき、切り替えを速くする
 *  - 解像度・フレームレートは、1280x720 以下でいちばん大きく、その中でフレームレートが高いものを選ぶ
 *  - 映像が実際に届き始めたら receiving を true にする(QML はそれまで画面を黒くしておく)
 * 設定は他の設定と同じ QSettings(IniFormat, UserScope, "OpenCruise"/"OpenCruise")の camera/ に保存する。
 * ログは [CAMERA] に英語で出す(画面の文言は QML 側で日本語にする)。
 */
#pragma once

#include <QCamera>
#include <QCameraDevice>
#include <QList>
#include <QMediaCaptureSession>
#include <QMediaDevices>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QTimer>

namespace opencruise {

class ReverseCamera : public QObject {
    Q_OBJECT
    /** バック信号(今の値。signalSource に応じてダミーか外部マイコンの値) */
    Q_PROPERTY(bool reverse READ reverse NOTIFY reverseChanged)
    /** バック信号の入力元。0 = ダミー(キーボード・設定画面)/ 1 = 外部マイコン(未実装) */
    Q_PROPERTY(int signalSource READ signalSource WRITE setSignalSource NOTIFY settingsChanged)
    /** ダミーのバック信号(保存しない。起動時は切) */
    Q_PROPERTY(bool mockReverse READ mockReverse WRITE setMockReverse NOTIFY reverseChanged)
    /** バック信号で自動で切り替えるか */
    Q_PROPERTY(bool autoSwitch READ autoSwitch WRITE setAutoSwitch NOTIFY settingsChanged)
    /** バック信号が切れてから元の画面へ戻るまでの秒数(0〜10) */
    Q_PROPERTY(int returnDelay READ returnDelay WRITE setReturnDelay NOTIFY settingsChanged)
    /** カメラ映像を出しているか(QML はこれで表示する) */
    Q_PROPERTY(bool shown READ shown NOTIFY shownChanged)
    /** 設定画面の「映像を確認」で出しているか */
    Q_PROPERTY(bool previewing READ previewing NOTIFY shownChanged)
    /** 選べるカメラの表示名。先頭は常に「自動」。抜き差しに追従する */
    Q_PROPERTY(QStringList deviceNames READ deviceNames NOTIFY devicesChanged)
    /** 選んでいるカメラ(deviceNames の番号。0 = 自動) */
    Q_PROPERTY(int deviceIndex READ deviceIndex WRITE setDeviceIndex NOTIFY devicesChanged)
    /** 保存してある機器が今は見つからない(抜けている)とき、その名前(見つかっていれば空) */
    Q_PROPERTY(QString missingDevice READ missingDevice NOTIFY devicesChanged)
    /** 左右反転して映す */
    Q_PROPERTY(bool mirror READ mirror WRITE setMirror NOTIFY settingsChanged)
    /** ガイド線(距離の目安)を出す */
    Q_PROPERTY(bool guides READ guides WRITE setGuides NOTIFY settingsChanged)
    /** 画面を埋める(はみ出しは切る)。false なら全体を表示(余りは黒) */
    Q_PROPERTY(bool fill READ fill WRITE setFill NOTIFY settingsChanged)
    /** 常にカメラを動かしておき、すぐに映す */
    Q_PROPERTY(bool keepWarm READ keepWarm WRITE setKeepWarm NOTIFY settingsChanged)
    /** カメラの状態。"none"(機器が無い)/ "off" / "starting" / "active" / "error" */
    Q_PROPERTY(QString cameraState READ cameraState NOTIFY cameraStateChanged)
    /** エラーの内容(英語。ログと同じ) */
    Q_PROPERTY(QString cameraError READ cameraError NOTIFY cameraStateChanged)
    /** カメラの映像(フレーム)が届いているか。カメラを動かし始めてから、最初のフレームが来たら true */
    Q_PROPERTY(bool receiving READ receiving NOTIFY receivingChanged)
    /** 使っているカメラの名前と形式(例 "USB Video: 1280x720 30fps") */
    Q_PROPERTY(QString activeDescription READ activeDescription NOTIFY cameraStateChanged)

public:
    explicit ReverseCamera(QObject *parent = nullptr);
    ~ReverseCamera() override;

    bool reverse() const { return reverse_; }
    int signalSource() const { return signalSource_; }
    void setSignalSource(int source);
    bool mockReverse() const { return mockReverse_; }
    void setMockReverse(bool on);
    bool autoSwitch() const { return autoSwitch_; }
    void setAutoSwitch(bool on);
    int returnDelay() const { return returnDelay_; }
    void setReturnDelay(int seconds);
    bool shown() const { return shown_; }
    bool previewing() const { return previewing_; }
    QStringList deviceNames() const;
    int deviceIndex() const;
    void setDeviceIndex(int index);
    QString missingDevice() const;
    bool mirror() const { return mirror_; }
    void setMirror(bool on);
    bool guides() const { return guides_; }
    void setGuides(bool on);
    bool fill() const { return fill_; }
    void setFill(bool on);
    bool keepWarm() const { return keepWarm_; }
    void setKeepWarm(bool on);
    QString cameraState() const { return cameraState_; }
    QString cameraError() const { return cameraError_; }
    QString activeDescription() const { return activeDescription_; }
    bool receiving() const { return receiving_; }

    /** @brief 映像の出し先(QML の VideoOutput)を登録する。 */
    Q_INVOKABLE void setVideoOutput(QObject *output);
    /** @brief ダミーのバック信号を入/切する(キーボードのショートカット用)。 */
    Q_INVOKABLE void toggleMockReverse() { setMockReverse(!mockReverse_); }
    /** @brief 設定画面の「映像を確認」。バック信号に関係なく出す / やめる。 */
    Q_INVOKABLE void setPreview(bool on);
    /** @brief 今のバックの間だけ映像を閉じる(次にバックへ入れたらまた出す)。確認中ならやめる。 */
    Q_INVOKABLE void dismiss();
    /** @brief カメラの一覧を読み直す。 */
    Q_INVOKABLE void refreshDevices();

public slots:
    /** @brief 外部マイコンからのバック信号(将来の受け口。signalSource が 1 のときに使う)。 */
    void setExternalReverse(bool on);

signals:
    void reverseChanged();
    void settingsChanged();
    void shownChanged();
    void devicesChanged();
    void cameraStateChanged();
    void receivingChanged();

private:
    void save(const QString &key, const QVariant &value);
    void updateReverse();
    void updateShown();
    void updateCamera();
    void startCamera(const QCameraDevice &device);
    void stopCamera();
    void setCameraState(const QString &state, const QString &error = QString());
    void setReceiving(bool on);
    QCameraDevice selectedDevice() const;

    bool reverse_ = false;
    int signalSource_ = 0;
    bool mockReverse_ = false;
    bool externalReverse_ = false;
    bool autoSwitch_ = true;
    int returnDelay_ = 2;
    bool shown_ = false;
    bool previewing_ = false;
    bool dismissed_ = false;
    bool holding_ = false;          // バック信号が切れた後、戻るまで待っている間
    QTimer holdTimer_;
    QString deviceId_;              // 保存してある機器の id(空なら自動)
    QString deviceName_;            // 保存してある機器の名前(見つからないときの表示用)
    bool mirror_ = false;
    bool guides_ = true;
    bool fill_ = false;
    bool keepWarm_ = false;

    QMediaDevices mediaDevices_;
    QList<QCameraDevice> devices_;
    QMediaCaptureSession session_;
    QCamera *camera_ = nullptr;
    QByteArray cameraId_;           // 動かしているカメラの id
    QPointer<QObject> output_;
    QString cameraState_ = QStringLiteral("off");
    QString cameraError_;
    QString activeDescription_;
    bool receiving_ = false;
    QMetaObject::Connection frameConnection_;
};

} // namespace opencruise
