/**
 * @file PulseAudioControl.cpp
 * @brief PulseAudio の端子・プロファイル単位の出力先 / 入力元の一覧と切り替え(pactl を使う)。
 */
#include "PulseAudioControl.h"

#include "Log.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QSet>

namespace opencruise {

namespace {

QProcessEnvironment pactlEnvironment() {
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));   // 文字の出力の見出しを英語にそろえる(読めるように)
    return env;
}

// シンク/ソースとカードを結びつけるための、プロパティの値(どれか 1 つでも同じなら同じ機器)
const QStringList kCardKeys = {QStringLiteral("alsa.card"), QStringLiteral("api.alsa.card"),
                               QStringLiteral("device.bus_path"), QStringLiteral("api.bluez5.address"),
                               QStringLiteral("device.string")};

QString propOf(const QVariantMap &item, const QString &key) {
    return item.value(QStringLiteral("properties")).toMap().value(key).toString();
}

bool truthy(const QVariant &v) {
    if (v.typeId() == QMetaType::Bool) return v.toBool();
    const QString s = v.toString().toLower();
    return s == QStringLiteral("yes") || s == QStringLiteral("true") || s == QStringLiteral("1");
}

// プロファイル名の出力の部分("output:hdmi-stereo+input:analog-stereo" → "hdmi-stereo")と入力の部分
QString outputPart(const QString &profile) {
    for (const QString &part : profile.split(QLatin1Char('+'))) {
        if (part.startsWith(QStringLiteral("output:"))) return part.mid(7);
    }
    return QString();
}
QString inputPart(const QString &profile) {
    for (const QString &part : profile.split(QLatin1Char('+'))) {
        if (part.startsWith(QStringLiteral("input:"))) return part.mid(6);
    }
    return QString();
}
// プロファイルの説明の出力の部分("Digital Stereo (HDMI) Output + Analog Stereo Input" → 前半)
QString outputDescription(const QString &description) {
    const QStringList parts = description.split(QStringLiteral(" + "));
    for (const QString &p : parts) {
        if (!p.contains(QStringLiteral("Input"), Qt::CaseInsensitive)) return p;
    }
    return parts.value(0);
}

} // namespace

PulseAudioControl::PulseAudioControl(QObject *parent) : QObject(parent) {
    debounce_.setSingleShot(true);
    debounce_.setInterval(300);
    connect(&debounce_, &QTimer::timeout, this, [this]() { refresh(); });
    restartSubscribe_.setSingleShot(true);
    restartSubscribe_.setInterval(5000);
    connect(&restartSubscribe_, &QTimer::timeout, this, [this]() { startSubscribe(); });
    // pactl subscribe の出力: 機器・端子・プロファイルが変わったら、少し待って読み直す
    connect(&subscribe_, &QProcess::readyReadStandardOutput, this, [this]() {
        while (subscribe_.canReadLine()) {
            const QString line = QString::fromUtf8(subscribe_.readLine());
            // 自分の再生・録音(sink-input / source-output)の出入りでは読み直さない
            if (line.contains(QStringLiteral("sink-input")) || line.contains(QStringLiteral("source-output"))) continue;
            if (line.contains(QStringLiteral(" card ")) || line.contains(QStringLiteral(" sink ")) || line.contains(QStringLiteral(" source "))
                || line.contains(QStringLiteral(" server"))) {
                debounce_.start();
            }
        }
    });
    connect(&subscribe_, &QProcess::finished, this, [this]() {
        if (!quitting_) restartSubscribe_.start();   // PulseAudio が再起動したときなど
    });

    refresh();
    if (available_) startSubscribe();
}

PulseAudioControl::~PulseAudioControl() {
    quitting_ = true;
    if (subscribe_.state() != QProcess::NotRunning) {
        subscribe_.kill();
        subscribe_.waitForFinished(500);
    }
}

bool PulseAudioControl::runPactl(const QStringList &args, QByteArray *out, int timeoutMs) const {
    QProcess p;
    p.setProcessEnvironment(pactlEnvironment());
    p.start(QStringLiteral("pactl"), args);
    if (!p.waitForStarted(timeoutMs)) return false;
    if (!p.waitForFinished(timeoutMs)) {
        p.kill();
        p.waitForFinished(200);
        return false;
    }
    if (p.exitStatus() != QProcess::NormalExit || p.exitCode() != 0) return false;
    if (out) *out = p.readAllStandardOutput();
    return true;
}

bool PulseAudioControl::readJson(const QString &what, QVariantList *list) const {
    QByteArray out;
    if (!runPactl({QStringLiteral("-f"), QStringLiteral("json"), QStringLiteral("list"), what}, &out)) return false;
    QJsonParseError error{};
    const QJsonDocument doc = QJsonDocument::fromJson(out, &error);
    if (error.error != QJsonParseError::NoError || !doc.isArray()) return false;
    *list = doc.array().toVariantList();
    return true;
}

// pactl の文字の出力(LC_ALL=C)を、JSON と同じ形に読み替える
bool PulseAudioControl::readText(const QString &what, QVariantList *list) const {
    QByteArray out;
    if (!runPactl({QStringLiteral("list"), what}, &out)) return false;
    const QStringList lines = QString::fromUtf8(out).split(QLatin1Char('\n'));
    static const QRegularExpression header(QStringLiteral("^(Sink|Source|Card) #\\d+"));
    static const QRegularExpression keyValue(QStringLiteral("^\\t([A-Za-z ]+): ?(.*)$"));
    static const QRegularExpression propLine(QStringLiteral("^\\t\\t([^ =]+) = \"(.*)\"$"));
    static const QRegularExpression portLine(QStringLiteral("^\\t\\t(\\S+): (.*) \\((.*)\\)$"));
    QVariantMap cur;
    QVariantMap props;
    QVariantList ports;
    QVariantMap profiles;
    QString section;
    auto flush = [&]() {
        if (cur.isEmpty()) return;
        cur.insert(QStringLiteral("properties"), props);
        cur.insert(QStringLiteral("ports"), ports);
        cur.insert(QStringLiteral("profiles"), profiles);
        list->append(cur);
        cur.clear();
        props.clear();
        ports.clear();
        profiles.clear();
    };
    for (const QString &line : lines) {
        if (header.match(line).hasMatch()) {
            flush();
            cur.insert(QStringLiteral("_"), line);
            section.clear();
            continue;
        }
        if (cur.isEmpty()) continue;
        const auto kv = keyValue.match(line);
        if (kv.hasMatch()) {
            const QString key = kv.captured(1).trimmed();
            const QString value = kv.captured(2).trimmed();
            section = key;
            if (key == QStringLiteral("Name")) cur.insert(QStringLiteral("name"), value);
            else if (key == QStringLiteral("Description")) cur.insert(QStringLiteral("description"), value);
            else if (key == QStringLiteral("Active Port")) cur.insert(QStringLiteral("active_port"), value);
            else if (key == QStringLiteral("Active Profile")) cur.insert(QStringLiteral("active_profile"), value);
            continue;
        }
        if (section == QStringLiteral("Properties")) {
            const auto m = propLine.match(line);
            if (m.hasMatch()) props.insert(m.captured(1), m.captured(2));
        } else if (section == QStringLiteral("Ports") || section == QStringLiteral("Profiles")) {
            const auto m = portLine.match(line);
            if (!m.hasMatch()) continue;
            const QString detail = m.captured(3);
            if (section == QStringLiteral("Ports")) {
                QVariantMap port;
                port.insert(QStringLiteral("name"), m.captured(1).trimmed());
                port.insert(QStringLiteral("description"), m.captured(2).trimmed());
                port.insert(QStringLiteral("availability"), detail.contains(QStringLiteral("not available"))
                                                               ? QStringLiteral("not available")
                                                               : (detail.contains(QStringLiteral("available")) ? QStringLiteral("available")
                                                                                                                 : QStringLiteral("availability unknown")));
                ports.append(port);
            } else {
                QVariantMap profile;
                profile.insert(QStringLiteral("description"), m.captured(2).trimmed());
                static const QRegularExpression sinks(QStringLiteral("sinks: (\\d+)"));
                static const QRegularExpression avail(QStringLiteral("available: (\\w+)"));
                const auto sm = sinks.match(detail);
                const auto am = avail.match(detail);
                profile.insert(QStringLiteral("sinks"), sm.hasMatch() ? sm.captured(1).toInt() : 0);
                profile.insert(QStringLiteral("available"), am.hasMatch() ? am.captured(1) : QStringLiteral("yes"));
                profiles.insert(m.captured(1).trimmed(), profile);
            }
        }
    }
    flush();
    return true;
}

void PulseAudioControl::refresh() {
    QVariantList sinks, sources, cards;
    bool ok = false;
    if (json_) {
        ok = readJson(QStringLiteral("sinks"), &sinks) && readJson(QStringLiteral("sources"), &sources)
             && readJson(QStringLiteral("cards"), &cards);
        if (!ok) {
            sinks.clear(); sources.clear(); cards.clear();
            json_ = false;   // 古い pactl(JSON に対応していない)なら、文字の出力を読む
        }
    }
    if (!ok) {
        ok = readText(QStringLiteral("sinks"), &sinks) && readText(QStringLiteral("sources"), &sources)
             && readText(QStringLiteral("cards"), &cards);
    }
    const bool wasAvailable = available_;
    available_ = ok;
    if (!ok) {
        if (wasAvailable || signature_.isEmpty()) {
            log::info("AUDIO", QStringLiteral("PulseAudio control (pactl) is not available; using the Qt device list"));
            signature_ = QStringLiteral("-");
        }
        outputs_.clear();
        inputs_.clear();
        if (wasAvailable) emit changed();
        return;
    }

    // カード: 名前・説明・今のプロファイル・結びつけ用のプロパティ
    struct Card { QString name, description, active; QVariantMap profiles; QStringList keys; };
    QList<Card> cardList;
    for (const QVariant &v : std::as_const(cards)) {
        const QVariantMap m = v.toMap();
        Card c;
        c.name = m.value(QStringLiteral("name")).toString();
        c.description = propOf(m, QStringLiteral("device.description"));
        if (c.description.isEmpty()) c.description = c.name;
        c.active = m.value(QStringLiteral("active_profile")).toString();
        c.profiles = m.value(QStringLiteral("profiles")).toMap();
        for (const QString &k : kCardKeys) {
            const QString val = propOf(m, k);
            c.keys << (val.isEmpty() ? QString() : k + QLatin1Char('=') + val);
        }
        cardList << c;
    }
    auto cardFor = [&](const QVariantMap &node) -> QString {
        for (const Card &c : std::as_const(cardList)) {
            for (int i = 0; i < kCardKeys.size(); ++i) {
                const QString val = propOf(node, kCardKeys[i]);
                if (!val.isEmpty() && c.keys.value(i) == kCardKeys[i] + QLatin1Char('=') + val) return c.name;
            }
        }
        return QString();
    };

    activePorts_.clear();
    activeProfiles_.clear();
    cardOfNode_.clear();
    for (const Card &c : std::as_const(cardList)) activeProfiles_.insert(c.name, c.active);

    // シンク/ソースの端子ごとに 1 項目(つながっていない端子は、今使っているもの以外は出さない)
    auto nodeEntries = [&](const QVariantList &nodes, bool output) {
        QList<Entry> list;
        for (const QVariant &v : nodes) {
            const QVariantMap m = v.toMap();
            const QString name = m.value(QStringLiteral("name")).toString();
            if (name.isEmpty()) continue;
            // 入力では、出力の音を録る「モニター」は出さない
            if (!output && (name.endsWith(QStringLiteral(".monitor"))
                            || propOf(m, QStringLiteral("device.class")) == QStringLiteral("monitor")))
                continue;
            const QString description = m.value(QStringLiteral("description")).toString().isEmpty()
                                            ? name : m.value(QStringLiteral("description")).toString();
            const QString active = m.value(QStringLiteral("active_port")).toString();
            const QString card = cardFor(m);
            activePorts_.insert(name, active);
            if (!card.isEmpty()) cardOfNode_.insert(name, card);
            QList<Entry> portsOf;
            for (const QVariant &pv : m.value(QStringLiteral("ports")).toList()) {
                const QVariantMap p = pv.toMap();
                const QString port = p.value(QStringLiteral("name")).toString();
                if (port.isEmpty()) continue;
                if (p.value(QStringLiteral("availability")).toString() == QStringLiteral("not available") && port != active) continue;
                Entry e;
                e.node = name;
                e.port = port;
                e.card = card;
                e.key = QStringLiteral("port:%1|%2").arg(name, port);
                e.name = description + QStringLiteral(" ・ ") + p.value(QStringLiteral("description")).toString();
                portsOf << e;
            }
            if (portsOf.size() <= 1) {   // 端子が 1 つ(か無い)なら、機器の名前だけ
                Entry e;
                e.node = name;
                e.port = portsOf.isEmpty() ? QString() : portsOf.first().port;
                e.card = card;
                e.key = QStringLiteral("port:%1|%2").arg(name, e.port);
                e.name = description;
                portsOf = {e};
            }
            list << portsOf;
        }
        return list;
    };
    QList<Entry> outs = nodeEntries(sinks, true);
    QList<Entry> ins = nodeEntries(sources, false);

    // カードの、今は使っていない出力のプロファイル(HDMI など)。サラウンドなどの細かい違いは出さない(ステレオだけ)
    for (const Card &c : std::as_const(cardList)) {
        const QString activeOut = outputPart(c.active);
        const QString activeIn = inputPart(c.active);
        QSet<QString> seen;
        QList<Entry> extra;
        for (auto it = c.profiles.constBegin(); it != c.profiles.constEnd(); ++it) {
            const QString profile = it.key();
            const QVariantMap info = it.value().toMap();
            const QString out = outputPart(profile);
            if (out.isEmpty() || out == activeOut || !out.contains(QStringLiteral("stereo")) || seen.contains(out)) continue;
            if (info.value(QStringLiteral("sinks")).toInt() <= 0 || !truthy(info.value(QStringLiteral("available"), true))) continue;
            // 入力の部分は今のまま(マイクが止まらないように)にできるプロファイルを選ぶ
            QString chosen = profile;
            const QString keepIn = QStringLiteral("output:%1+input:%2").arg(out, activeIn);
            if (!activeIn.isEmpty() && c.profiles.contains(keepIn)) chosen = keepIn;
            else if (c.profiles.contains(QStringLiteral("output:") + out)) chosen = QStringLiteral("output:") + out;
            seen.insert(out);
            Entry e;
            e.card = c.name;
            e.profile = chosen;
            e.key = QStringLiteral("profile:%1|%2").arg(c.name, chosen);
            e.name = c.description + QStringLiteral(" ・ ")
                     + outputDescription(c.profiles.value(chosen).toMap().value(QStringLiteral("description")).toString());
            extra << e;
        }
        outs << extra;
    }

    QStringList sig;
    for (const Entry &e : std::as_const(outs)) sig << e.key + QLatin1Char('=') + e.name;
    sig << QStringLiteral("#");
    for (const Entry &e : std::as_const(ins)) sig << e.key + QLatin1Char('=') + e.name;
    for (auto it = activePorts_.constBegin(); it != activePorts_.constEnd(); ++it) sig << it.key() + QLatin1Char('>') + it.value();
    for (auto it = activeProfiles_.constBegin(); it != activeProfiles_.constEnd(); ++it) sig << it.key() + QLatin1Char('>') + it.value();
    sig.sort();
    const QString signature = sig.join(QLatin1Char('\n'));
    outputs_ = outs;
    inputs_ = ins;
    if (signature == signature_) return;
    signature_ = signature;
    QStringList names;
    for (const Entry &e : std::as_const(outputs_)) names << e.name;
    log::info("AUDIO", QStringLiteral("PulseAudio outputs (%1): %2 / inputs: %3")
                           .arg(json_ ? QStringLiteral("json") : QStringLiteral("text"),
                                names.isEmpty() ? QStringLiteral("none") : names.join(QStringLiteral(", ")))
                           .arg(ins.size()));
    emit changed();
}

void PulseAudioControl::activate(const Entry &entry) {
    QStringList args;
    if (!entry.profile.isEmpty()) {
        args = {QStringLiteral("set-card-profile"), entry.card, entry.profile};
    } else if (!entry.port.isEmpty() && entry.port != activePort(entry.node)) {
        const bool isSource = std::any_of(inputs_.begin(), inputs_.end(), [&](const Entry &e) { return e.node == entry.node; });
        args = {isSource ? QStringLiteral("set-source-port") : QStringLiteral("set-sink-port"), entry.node, entry.port};
    } else {
        return;   // もうその端子になっている
    }
    log::info("AUDIO", QStringLiteral("pactl %1").arg(args.join(QLatin1Char(' '))));
    auto *p = new QProcess(this);
    p->setProcessEnvironment(pactlEnvironment());
    connect(p, &QProcess::finished, this, [this, p, args](int code, QProcess::ExitStatus status) {
        if (status != QProcess::NormalExit || code != 0) {
            log::warn("AUDIO", QStringLiteral("pactl %1 failed: %2")
                                   .arg(args.join(QLatin1Char(' ')), QString::fromUtf8(p->readAllStandardError()).trimmed()));
        }
        p->deleteLater();
        debounce_.start();   // 切り替わった後の一覧を読む(subscribe でも来るが、念のため)
    });
    p->start(QStringLiteral("pactl"), args);
}

void PulseAudioControl::startSubscribe() {
    if (quitting_ || subscribe_.state() != QProcess::NotRunning) return;
    subscribe_.setProcessEnvironment(pactlEnvironment());
    subscribe_.start(QStringLiteral("pactl"), {QStringLiteral("subscribe")});
}

} // namespace opencruise
