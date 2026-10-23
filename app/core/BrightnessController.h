/**
 * @file BrightnessController.h
 * @brief 画面の明るさ(輝度)の設定と、実際の画面への反映。
 *
 * QML へは context property `brightnessController` として公開する。設定は他の設定と同じ
 * QSettings(IniFormat, UserScope, "OpenCruise"/"OpenCruise")の display/brightness に保存する。
 *
 * 明るさは 10..100(%)。0 にしないのは、運転中に画面が真っ暗になって操作できなくなるのを防ぐため。
 *
 * 反映方法は、実行環境に応じて次の 2 通りから自動で選ぶ(同時には使わない。二重に暗くならない):
 *  - ハードウェア: Linux で /sys/class/backlight/<機器>/brightness に書き込める場合、バックライトを直接制御する。
 *  - ソフトウェア: 上記が使えない場合(Windows、書き込み権限が無い、バックライトが無い外部ディスプレイなど)、
 *                  画面全体に黒い半透明の幕を重ねて暗くする(QML の overlayOpacity をバインドして描く)。
 * ハードウェアへの書き込みに失敗したら、ソフトウェア方式へ切り替えて動作を続ける。
 *
 * ハードウェア方式は、保存された設定がある場合だけ起動時に値を反映する(初回起動でいきなりバックライトを
 * 最大にしないため。設定が無いときの初期値は、現在のバックライトの値から求める)。終了時に元の値へは戻さない
 * (車載機として、次回も同じ明るさで起動するため)。
 */
#pragma once

#include <QObject>
#include <QString>

namespace opencruise {

/**
 * @brief 明るさの状態と反映先を持つモデル。UI スレッド専用。
 */
class BrightnessController : public QObject {
    Q_OBJECT
    /** 明るさ(minimum..100 %) */
    Q_PROPERTY(int brightness READ brightness WRITE setBrightness NOTIFY brightnessChanged)
    /** 設定できる最小の明るさ(%) */
    Q_PROPERTY(int minimum READ minimum CONSTANT)
    /** バックライトを直接制御しているか(false のときは画面を暗幕で暗くしている) */
    Q_PROPERTY(bool hardwareControl READ hardwareControl NOTIFY backendChanged)
    /** 反映方法の表示用の説明 */
    Q_PROPERTY(QString methodText READ methodText NOTIFY backendChanged)
    /** 暗幕(黒)の不透明度 0..1。ハードウェア制御中は常に 0。QML の暗幕の opacity へバインドする */
    Q_PROPERTY(qreal overlayOpacity READ overlayOpacity NOTIFY overlayOpacityChanged)

public:
    static constexpr int kMinimum = 10;
    static constexpr int kMaximum = 100;

    explicit BrightnessController(QObject *parent = nullptr);

    int brightness() const { return brightness_; }
    int minimum() const { return kMinimum; }
    /** @brief 明るさを minimum..100 に丸めて変更し、保存して画面へ反映する。 */
    void setBrightness(int percent);
    /** @brief 明るさを delta(%)だけ増減する。ショートカット用。 */
    Q_INVOKABLE void adjustBrightness(int delta);

    bool hardwareControl() const { return !backlightPath_.isEmpty(); }
    QString methodText() const;
    qreal overlayOpacity() const;

signals:
    void brightnessChanged();
    void backendChanged();
    void overlayOpacityChanged();

private:
    /** @brief 書き込める Linux バックライトを探す。見つかれば backlightPath_ / backlightMax_ を設定する。 */
    void detectBacklight();
    /** @brief 現在の明るさをバックライトへ書く。失敗したらソフトウェア方式へ切り替える。 */
    void applyToBacklight();
    /** @brief バックライトの現在値を 0..100(%)で読む。読めなければ -1。 */
    int readBacklightPercent() const;
    /** @brief ハードウェア制御をやめ、暗幕へ切り替える。 */
    void fallBackToSoftware(const QString &reason);

    int brightness_ = kMaximum;
    QString backlightPath_; ///< 制御に使う brightness ファイルのパス。空ならソフトウェア方式
    QString backlightName_; ///< 表示用の機器名
    int backlightMax_ = 0;
};

} // namespace opencruise
