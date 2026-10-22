/**
 * @file AudioSettings.h
 * @brief 音量(マップ音声・音楽音声・システム)と、グループごとの出力先デバイスの設定。
 *
 * QML へは context property `audioSettings` として公開する。設定は他の設定と同じ
 * QSettings(IniFormat, UserScope, "OpenCruise"/"OpenCruise")に保存する。
 *
 * 音声は 3 つのグループに分ける:
 *  - マップ音声  : Android Auto のガイダンス音声(AudioPlayer の kind 2)
 *  - 音楽音声    : Android Auto のメディア音声(kind 1)
 *  - システム    : アプリの操作音・起動音(SystemSound)と、Android Auto のシステム音(kind 0)
 *
 * これとは別に、Android Auto の音声入力に使うマイクの設定(使用する/しない、入力元デバイス)も持つ。
 */
#pragma once

#include <QAudioDevice>
#include <QByteArray>
#include <QList>
#include <QMediaDevices>
#include <QObject>
#include <QString>
#include <QStringList>

namespace opencruise {

/**
 * @brief 音量と出力先の設定モデル。UI スレッド専用。
 */
class AudioSettings : public QObject {
    Q_OBJECT
    /** マップ音声の音量(0..100) */
    Q_PROPERTY(int mapVolume READ mapVolume WRITE setMapVolume NOTIFY volumesChanged)
    /** 音楽音声の音量(0..100) */
    Q_PROPERTY(int musicVolume READ musicVolume WRITE setMusicVolume NOTIFY volumesChanged)
    /** システム音量(0..100) */
    Q_PROPERTY(int systemVolume READ systemVolume WRITE setSystemVolume NOTIFY volumesChanged)
    /** マップ音声の出力先(outputNames の番号。0 = システム既定) */
    Q_PROPERTY(int mapDeviceIndex READ mapDeviceIndex WRITE setMapDeviceIndex NOTIFY devicesChanged)
    /** 音楽音声の出力先(outputNames の番号。0 = システム既定) */
    Q_PROPERTY(int musicDeviceIndex READ musicDeviceIndex WRITE setMusicDeviceIndex NOTIFY devicesChanged)
    /** システム音の出力先(outputNames の番号。0 = システム既定) */
    Q_PROPERTY(int systemDeviceIndex READ systemDeviceIndex WRITE setSystemDeviceIndex NOTIFY devicesChanged)
    /** 選択できる出力先の表示名。先頭は常に「システム既定」。接続の増減に追従する */
    Q_PROPERTY(QStringList outputNames READ outputNames NOTIFY outputsChanged)
    /** マイクを使うか。オフの間は、Android Auto から要求されても録音も送信もしない */
    Q_PROPERTY(bool micEnabled READ micEnabled WRITE setMicEnabled NOTIFY micChanged)
    /** マイクの入力元(inputNames の番号。0 = システム既定) */
    Q_PROPERTY(int micDeviceIndex READ micDeviceIndex WRITE setMicDeviceIndex NOTIFY micChanged)
    /** 選択できる入力元の表示名。先頭は常に「システム既定」。接続の増減に追従する */
    Q_PROPERTY(QStringList inputNames READ inputNames NOTIFY inputsChanged)

public:
    enum Group { Map = 0, Music = 1, System = 2, GroupCount = 3 };
    Q_ENUM(Group)

    explicit AudioSettings(QObject *parent = nullptr);

    /** @brief AudioPlayer のチャネル番号(0=System / 1=Media / 2=Guidance)が属するグループ。 */
    static Group groupForKind(int kind);

    int volume(Group group) const { return volumes_[group]; }
    /** @brief 再生器へ渡す音量(0.0..1.0)。スライダーの値を 2 乗して、聞こえ方に近い変化にする。 */
    double gain(Group group) const;
    /** @brief 音量を 0..100 に丸めて変更して保存する。 */
    void setVolume(Group group, int volume);

    int mapVolume() const { return volume(Map); }
    int musicVolume() const { return volume(Music); }
    int systemVolume() const { return volume(System); }
    void setMapVolume(int v) { setVolume(Map, v); }
    void setMusicVolume(int v) { setVolume(Music, v); }
    void setSystemVolume(int v) { setVolume(System, v); }

    /** @brief 出力先の番号(0 = システム既定)。保存された機器が接続されていない間は 0 を返す。 */
    int deviceIndex(Group group) const;
    /** @brief 出力先を番号で選んで保存する。範囲外は無視する。 */
    void setDeviceIndex(Group group, int index);
    /** @brief 実際に使う出力デバイス。未選択・未接続ならシステム既定のデバイス。 */
    QAudioDevice device(Group group) const;

    int mapDeviceIndex() const { return deviceIndex(Map); }
    int musicDeviceIndex() const { return deviceIndex(Music); }
    int systemDeviceIndex() const { return deviceIndex(System); }
    void setMapDeviceIndex(int i) { setDeviceIndex(Map, i); }
    void setMusicDeviceIndex(int i) { setDeviceIndex(Music, i); }
    void setSystemDeviceIndex(int i) { setDeviceIndex(System, i); }

    QStringList outputNames() const { return outputNames_; }

    bool micEnabled() const { return micEnabled_; }
    /** @brief マイクの使用可否を変更して保存する。 */
    void setMicEnabled(bool enabled);
    /** @brief マイクの入力元の番号(0 = システム既定)。保存された機器が接続されていない間は 0 を返す。 */
    int micDeviceIndex() const;
    /** @brief マイクの入力元を番号で選んで保存する。範囲外は無視する。 */
    void setMicDeviceIndex(int index);
    /** @brief 実際に使う入力デバイス。未選択・未接続ならシステム既定のデバイス。 */
    QAudioDevice micDevice() const;
    QStringList inputNames() const { return inputNames_; }

signals:
    void volumesChanged();
    void devicesChanged();
    void outputsChanged();
    /** @brief あるグループの音量が変わった(再生中の出力へ反映するため)。 */
    void volumeChangedFor(int group);
    /** @brief あるグループの実際の出力デバイスが変わった(再生中の出力を作り直すため)。 */
    void deviceChangedFor(int group);
    /** @brief マイクの使用可否・入力元の選択、または選択が指す実際のデバイスが変わった。 */
    void micChanged();
    /** @brief 入力デバイスの一覧が変わった。 */
    void inputsChanged();

private:
    /** @brief 出力デバイスの一覧を取り直す。変化があれば通知する。 */
    void refreshOutputs();
    /** @brief 入力デバイスの一覧を取り直し、変化を通知する。 */
    void refreshInputs();
    /** @brief グループの設定が指している機器の id(未選択・未接続ならシステム既定の id)。 */
    QByteArray resolvedId(Group group) const;

    int volumes_[GroupCount] = {100, 100, 100};
    QByteArray selectedIds_[GroupCount]; ///< 選択した機器の id。空ならシステム既定
    QList<QAudioDevice> outputs_;
    QStringList outputNames_;
    bool micEnabled_ = true;
    QByteArray selectedMicId_; ///< 選択したマイクの id。空ならシステム既定
    QList<QAudioDevice> inputs_;
    QStringList inputNames_;
    QMediaDevices mediaDevices_;
};

} // namespace opencruise
