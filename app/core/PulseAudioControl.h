/**
 * @file PulseAudioControl.h
 * @brief PulseAudio(PipeWire の pipewire-pulse も同じ)の出力先・入力元を、機器の「端子」の単位で一覧にして切り替える。
 *
 * Qt の機器一覧は PulseAudio のシンク単位なので、内蔵のサウンド機器は「Built-in Audio Analog Stereo」の 1 つにまとまり、
 * スピーカー / ヘッドホン / HDMI などを選べない。ALSA の機器(hw:…)を直接開けば選べるが、それは機器を占有して
 * ほかのアプリの音が鳴らなくなる。そこで、音はこれまでどおり PulseAudio を通して(占有しない)、その中で
 *  - シンクの端子(ポート)を切り替える(例: スピーカー ⇄ ヘッドホン)… pactl set-sink-port
 *  - カードのプロファイルを切り替える(例: アナログ ⇄ HDMI)… pactl set-card-profile
 * ことで、出力先を選べるようにする。入力(マイク)はソースの端子(内蔵マイク / ヘッドセットのマイクなど)を選ぶ。
 *
 * 一覧は pactl(pulseaudio-utils)で読む(JSON で読めなければ文字の出力を読む)。pactl subscribe で、
 * 機器の抜き差し・端子の接続(ヘッドホンを挿したなど)を見て、一覧を読み直す(changed)。
 * pactl が無い・PulseAudio が動いていないときは available() が false になり、AudioSettings は Qt の一覧を使う。
 *
 * 注意: 端子・プロファイルは機器(シンク)ごとに 1 つなので、同じ機器を使う音(マップ・音楽・システム)は同じ端子から出る。
 * また、システム全体の設定なので、ほかのアプリの音の出先も変わる(車載 PC 専用なので問題にしない)。
 */
#pragma once

#include <QHash>
#include <QList>
#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariantMap>

namespace opencruise {

class PulseAudioControl : public QObject {
    Q_OBJECT
public:
    /** 一覧の 1 項目(出力先 / 入力元) */
    struct Entry {
        QString key;         ///< 保存用の識別子("port:<シンク/ソース名>|<端子名>" / "profile:<カード名>|<プロファイル名>")
        QString name;        ///< 表示名(例 "Built-in Audio ・ ヘッドホン")
        QString node;        ///< シンク/ソースの名前(Qt の QAudioDevice の id と同じ)。プロファイルの項目は空
        QString port;        ///< 端子の名前(端子が 1 つも無い機器は空)
        QString card;        ///< カードの名前(分からないときは空)
        QString profile;     ///< 切り替えるプロファイル(プロファイルの項目だけ)
    };

    explicit PulseAudioControl(QObject *parent = nullptr);
    ~PulseAudioControl() override;

    /** @brief PulseAudio を pactl で操作できるか。 */
    bool available() const { return available_; }
    QList<Entry> outputs() const { return outputs_; }
    QList<Entry> inputs() const { return inputs_; }
    /** @brief シンク/ソースの今の端子(無ければ空)。 */
    QString activePort(const QString &node) const { return activePorts_.value(node); }
    /** @brief カードの今のプロファイル(無ければ空)。 */
    QString activeProfile(const QString &card) const { return activeProfiles_.value(card); }
    /** @brief シンク/ソースが属するカード(分からなければ空)。 */
    QString cardOf(const QString &node) const { return cardOfNode_.value(node); }

    /** @brief 項目を選ぶ(端子・プロファイルを切り替える)。切り替えは非同期。 */
    void activate(const Entry &entry);
    /** @brief 一覧を読み直す(変わっていれば changed を出す)。 */
    void refresh();

signals:
    void changed();

private:
    bool runPactl(const QStringList &args, QByteArray *out, int timeoutMs = 2000) const;
    bool readJson(const QString &what, QVariantList *list) const;
    bool readText(const QString &what, QVariantList *list) const;
    void startSubscribe();

    bool available_ = false;
    bool json_ = true;          // pactl -f json が使えるか(使えなければ文字の出力を読む)
    QList<Entry> outputs_;
    QList<Entry> inputs_;
    QHash<QString, QString> activePorts_;
    QHash<QString, QString> activeProfiles_;
    QHash<QString, QString> cardOfNode_;
    QString signature_;         // 一覧の中身(変わったかどうかの比較用)
    QProcess subscribe_;
    QTimer debounce_;
    QTimer restartSubscribe_;
    bool quitting_ = false;
};

} // namespace opencruise
