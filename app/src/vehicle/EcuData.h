/**
 * @file EcuData.h
 * @brief エンジン ECU(Kei HN22S。K-Line / KWP2000)の診断データ。
 *
 * QML へは context property `ecu` として公開する。
 *
 * 項目の定義は docs/reference/kei_kline_params.csv(SZ Viewer の解析結果)を写したもの(EcuData.cpp の kParams)。
 *  - `21 00`(メインブロック。`61 00` の直後を位置 0)/ `21 02`(サブブロック)の決まった位置のバイトを、
 *    係数・オフセットで換算する。値が FF(16bit は FF FF)のときは「項目なし」(このECUでは出ない)として扱う
 *  - スイッチ類はビット、燃料系の状態は列挙
 *  - 故障コード(DTC): `18 00 GG GG` の応答(`58` の後: 件数 + [コード上位, 下位, 状態] × 件数)を読む。
 *    状態のビット 6〜5(ISO 14230-3 の DTC の記録状態)で分ける。SZ Viewer の解析・規格からの推定で、実車では未確認:
 *      11 = 現在(要求のときに起きている) / 10 = 確定前(起きかけている。現在として扱う) / 01 = 過去(記録だけ)
 *    `21 00` の位置 1〜6 にもコード 2 件と状態があるので、`18` を読めないときはそちらを使う
 *  - チェックランプ(MIL)は `21 00` の位置 7 のビット 7
 *  - ECU 情報: `1A xx` の応答(部品番号・メーカー・ソフトウェア版など。ASCII)
 *
 * データ元(受け口): 実際の通信(将来の DIAG ノード(OC-Link)か、KKL ケーブル)は、受け取った応答を
 * ingestBlock() / ingestDtcList() / ingestEcuInfo() に渡し、setLink() で通信の状態を知らせるだけでよい。
 * 今はダミーだけ: VehicleDataManager のダミーの車の動き(回転数・車速・水温・アクセル・電圧・ブースト)から
 * `21 00` / `21 02` のバイト列を作り(約 5Hz。実車の見込みと同じ)、同じ受け口へ渡す(換算の処理も実データと同じ道を通る)。
 * ダミーの故障コードは設定(mockDtcMode)で選ぶ。
 * ログは [ECU] に英語で出す。書き込み・消去・アクチュエーター操作のサービス(14 / 30 など)は使わない。
 */
#pragma once

#include <QByteArray>
#include <QElapsedTimer>
#include <QHash>
#include <QObject>
#include <QString>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

#include <random>

namespace opencruise {

class VehicleDataManager;

class EcuData : public QObject {
    Q_OBJECT
    /** 項目の定義(表示順)。{ id, title, group, unit, kind("number"/"bit"/"enum"), dec, min, max, limitMin, limitMax, step,
     *  icon, gauge(メーター・グラフの種類にするか), block, pos, note } */
    Q_PROPERTY(QVariantList params READ params CONSTANT)
    /** 分類(表示順)。{ id, title, icon } */
    Q_PROPERTY(QVariantList groups READ groups CONSTANT)
    /** 値が更新されるたびに増える(QML の束縛が value() などを読み直すため) */
    Q_PROPERTY(int revision READ revision NOTIFY valuesChanged)
    /** 値を受け取っているか(通信中、またはダミー) */
    Q_PROPERTY(bool available READ available NOTIFY linkChanged)
    /** 通信の状態: "none"(データ元なし) / "mock"(ダミー) / "connecting" / "connected" / "lost" */
    Q_PROPERTY(QString linkState READ linkState NOTIFY linkChanged)
    /** データ元の説明(画面表示用) */
    Q_PROPERTY(QString sourceText READ sourceText NOTIFY linkChanged)
    /** 更新の速さ(1 秒あたりのブロック数)・直近の応答時間(ms)・受け取った回数・異常の回数・最後に受け取った時刻 */
    Q_PROPERTY(double rateHz READ rateHz NOTIFY linkChanged)
    Q_PROPERTY(int responseMs READ responseMs NOTIFY linkChanged)
    Q_PROPERTY(int frameCount READ frameCount NOTIFY linkChanged)
    Q_PROPERTY(int errorCount READ errorCount NOTIFY linkChanged)
    Q_PROPERTY(QString lastUpdateText READ lastUpdateText NOTIFY linkChanged)
    /** チェックランプ(MIL)が点いているか */
    Q_PROPERTY(bool milOn READ milOn NOTIFY dtcsChanged)
    /** 故障コード。{ code("P0115"), description(日本語), descriptionEn(原文), detail, system, category, state("current"/"pending"/"past"), status(状態バイト), statusText } */
    Q_PROPERTY(QVariantList dtcs READ dtcs NOTIFY dtcsChanged)
    Q_PROPERTY(int currentDtcCount READ currentDtcCount NOTIFY dtcsChanged)
    Q_PROPERTY(int pastDtcCount READ pastDtcCount NOTIFY dtcsChanged)
    /** ECU 情報。{ label, value } */
    Q_PROPERTY(QVariantList ecuInfo READ ecuInfo NOTIFY ecuInfoChanged)
    /** ダミーの故障コード: 0 = なし / 1 = 過去の記録だけ / 2 = 現在と過去。保存する */
    Q_PROPERTY(int mockDtcMode READ mockDtcMode WRITE setMockDtcMode NOTIFY settingsChanged)
    /** 車両信号(VIN / SEN ノード)とこの ECU の両方から取れる項目(車速・回転数・水温・電圧・アクセル)の、データ元の選び方。
     *  { 計測値の id: "auto"(VIN/SEN 優先。既定)/ "ecuFirst"(ECU 優先)/ "node"(VIN/SEN だけ)/ "ecu"(ECU だけ) }。
     *  既定(auto)の項目は入れない。保存する。値を選ぶ処理は QML の VehicleSignals */
    Q_PROPERTY(QVariantMap sourcePrefs READ sourcePrefs NOTIFY settingsChanged)
    /** すべての項目の選び方をまとめて上書きする: ""(上書きしない。項目ごとの sourcePrefs を使う。既定)/ sourcePrefs と同じ値。保存する */
    Q_PROPERTY(QString sourceOverride READ sourceOverride WRITE setSourceOverride NOTIFY settingsChanged)

public:
    explicit EcuData(VehicleDataManager *vehicle, QObject *parent = nullptr);

    QVariantList params() const;
    QVariantList groups() const;
    int revision() const { return revision_; }
    bool available() const { return linkState_ == QStringLiteral("mock") || linkState_ == QStringLiteral("connected"); }
    QString linkState() const { return linkState_; }
    QString sourceText() const;
    double rateHz() const { return rateHz_; }
    int responseMs() const { return responseMs_; }
    int frameCount() const { return frameCount_; }
    int errorCount() const { return errorCount_; }
    QString lastUpdateText() const;
    bool milOn() const { return milOn_; }
    QVariantList dtcs() const { return dtcs_; }
    int currentDtcCount() const;
    int pastDtcCount() const;
    QVariantList ecuInfo() const;
    int mockDtcMode() const { return mockDtcMode_; }
    void setMockDtcMode(int mode);
    QVariantMap sourcePrefs() const { return sourcePrefs_; }
    /** @brief 同じ項目のデータ元の選び方を変える(mode は sourcePrefs の値)。 */
    Q_INVOKABLE void setSourcePref(const QString &metric, const QString &mode);
    QString sourceOverride() const { return sourceOverride_; }
    void setSourceOverride(const QString &mode);

    /** @brief 項目の値(数値・ビット(0/1)・列挙の番号)。無い・項目なしなら NaN。 */
    Q_INVOKABLE double value(const QString &id) const;
    /** @brief 項目の値があるか(受け取っていて、このECUで出る項目か)。 */
    Q_INVOKABLE bool has(const QString &id) const;
    /** @brief 画面に出す文字(数値は単位つき、ビットは ON / OFF、列挙は説明)。無ければ "--"。 */
    Q_INVOKABLE QString text(const QString &id) const;
    /** @brief 数値の項目の今の値をまとめて(グラフの履歴用)。{ id: 値 } */
    Q_INVOKABLE QVariantMap numericValues() const;
    /** @brief 故障コードの短いまとめ(通知の本文用)。state: "current"(現在と確定前) / "past" */
    Q_INVOKABLE QString dtcSummary(const QString &state) const;
    /** @brief 故障コードの説明(分からなければ空)。 */
    Q_INVOKABLE static QString dtcDescription(const QString &code);

public slots:
    // ---- 受け口(実際の通信から呼ぶ。どれも本体のスレッドで呼ぶこと) ----
    /** @brief `21 xx` の応答のデータ部(`61 xx` の後ろ)を受け取る。 */
    void ingestBlock(int localId, const QByteArray &data);
    /** @brief `18` の応答(`58` の後ろ: 件数 + [上位, 下位, 状態] × 件数)を受け取る。 */
    void ingestDtcList(const QByteArray &data);
    /** @brief `1A xx` の応答のデータ部(`5A xx` の後ろ)を受け取る。 */
    void ingestEcuInfo(int id, const QByteArray &data);
    /** @brief 通信の状態を知らせる(state は linkState の値。source はデータ元の説明。responseMs は応答時間)。 */
    void setLink(const QString &state, const QString &source, int responseMs = -1);
    /** @brief 通信の異常(タイムアウト・否定応答・チェックサム違い)を 1 回数える。 */
    void reportError(const QString &what);

signals:
    void valuesChanged();
    void linkChanged();
    void dtcsChanged();
    void ecuInfoChanged();
    void settingsChanged();

private:
    void mockTick();
    void updateMockLink();
    QByteArray makeMockBlock00();
    QByteArray makeMockBlock02();
    QByteArray makeMockDtcs() const;
    void decodeDtcsFromBlock00(const QByteArray &data);
    void applyDtcs(const QByteArray &data);   ///< 件数 + [上位, 下位, 状態] × 件数 を一覧にする(変わったときだけ知らせる)

    VehicleDataManager *vehicle_ = nullptr;
    QHash<QString, double> values_;
    QHash<QString, bool> missing_;          ///< 受け取ったが FF(このECUでは出ない)項目
    int revision_ = 0;
    QString linkState_ = QStringLiteral("none");
    QString source_;
    double rateHz_ = 0;
    int responseMs_ = -1;
    int frameCount_ = 0;
    int errorCount_ = 0;
    qint64 lastUpdateMs_ = 0;
    QElapsedTimer rateClock_;
    int rateFrames_ = 0;
    bool milOn_ = false;
    QVariantList dtcs_;
    bool dtcListSeen_ = false;              ///< `18` の応答を受け取ったことがある(`21 00` のコードより優先する)
    QHash<int, QByteArray> ecuInfo_;
    int mockDtcMode_ = 0;
    QVariantMap sourcePrefs_;
    QString sourceOverride_;
    QTimer mockTimer_;
    std::mt19937 rng_{12345};
    double mockTrimShort_ = 0;
    double mockTrimLong_ = 4;
    double mockO2Phase_ = 0;
};

} // namespace opencruise
