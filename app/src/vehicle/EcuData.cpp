/**
 * @file EcuData.cpp
 * @brief エンジン ECU(K-Line / KWP2000)の診断データの実装。項目の定義は docs/reference/kei_kline_params.csv。
 */
#include "EcuData.h"

#include "VehicleDataManager.h"
#include "core/Log.h"

#include <QDateTime>
#include <QFile>
#include <QSettings>
#include <QStringList>

#include <algorithm>
#include <cmath>
#include <limits>

namespace opencruise {

namespace {

/// 同じ項目のデータ元の選び方: auto(VIN/SEN 優先) / ecuFirst(ECU 優先) / node(VIN/SEN だけ) / ecu(ECU だけ)
bool isSourceMode(const QString &mode) {
    return mode == QLatin1String("auto") || mode == QLatin1String("ecuFirst") || mode == QLatin1String("node") || mode == QLatin1String("ecu");
}

QSettings openStore() {
    return QSettings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("OpenCruise"), QStringLiteral("OpenCruise"));
}

enum class Kind { Number, Bit, Enum };

/// 項目の定義(kei_kline_params.csv を写したもの)。位置は「61 xx の直後」を 0 とする
struct Param {
    const char *id;
    int block;          ///< 0x00 = `21 00` / 0x02 = `21 02`
    int pos;
    int len;            ///< 1 / 2(16bit は上位が先)
    int bit;            ///< ビットの項目のビット番号(それ以外は -1)
    Kind kind;
    double scale;
    double offset;
    const char *unit;
    const char *title;  ///< 日本語の名前
    const char *group;
    int dec;            ///< 表示の小数の桁
    double min, max;    ///< メーター・グラフの既定の範囲
    double limitMin, limitMax;  ///< 設定できる範囲(生の値の範囲)
    double step;        ///< 設定の刻み
    const char *icon;
    bool gauge;         ///< メーター・グラフの種類にするか(既存の計測値と同じものは作らない)
    const char *note;
};

constexpr double kNoRange = 0;

// clang-format off
const Param kParams[] = {
    // ---- エンジン ----
    {"load",        0x00, 13, 1, -1, Kind::Number, 0.392157, 0,    "%",     "エンジン負荷",           "engine", 1, 0, 100, 0, 100, 5,   "mdi:engine", true, ""},
    {"ecuRpm",      0x00, 20, 2, -1, Kind::Number, 0.25,     0,    "rpm",   "エンジン回転数",         "engine", 0, 0, 8000, 0, 16383, 500, "mdi:gauge", false, "回転数のメーターと同じ値"},
    {"ecuSpeed",    0x00, 22, 1, -1, Kind::Number, 1,        0,    "km/h",  "車速",                   "drive",  0, 0, 180, 0, 255, 10,  "mdi:speedometer", false, "スピードメーターと同じ値"},
    {"ecuCoolant",  0x00, 14, 1, -1, Kind::Number, 1,      -40,    "℃",     "水温",                   "engine", 0, 40, 130, -40, 215, 5, "mdi:coolant-temperature", false, "水温計と同じ値"},
    {"ignition",    0x00, 23, 1, -1, Kind::Number, 0.5,    -64,    "°",     "点火時期(1番)",          "engine", 1, -10, 50, -64, 63.5, 2, "flash_on", true, ""},
    {"idleTarget",  0x00, 35, 1, -1, Kind::Number, 7.84314,  0,    "rpm",   "目標アイドル回転数",     "engine", 0, 0, 1500, 0, 2000, 50, "mdi:engine-outline", true, ""},
    {"vvtDiff",     0x02, 19, 1, -1, Kind::Number, 0.352941, -45,  "°",     "VVT 目標−実際の差",      "engine", 1, -20, 20, -45, 45, 2, "mdi:valve", true, ""},
    // ---- 燃料 ----
    {"fuelStatusB1",0x00, 11, 1, -1, Kind::Enum,   1,        0,    "",      "燃料系の状態 B1",        "fuel",   0, 0, 0, 0, 0, 0, "mdi:fuel", false, ""},
    {"fuelStatusB2",0x00, 12, 1, -1, Kind::Enum,   1,        0,    "",      "燃料系の状態 B2",        "fuel",   0, 0, 0, 0, 0, 0, "mdi:fuel", false, ""},
    {"stftB1",      0x00, 15, 1, -1, Kind::Number, 0.78125, -100,  "%",     "短期燃料補正 B1",        "fuel",   1, -25, 25, -100, 99.2, 1, "mdi:chart-bell-curve", true, ""},
    {"ltftB1",      0x00, 16, 1, -1, Kind::Number, 0.78125, -100,  "%",     "長期燃料補正 B1",        "fuel",   1, -25, 25, -100, 99.2, 1, "mdi:chart-bell-curve", true, ""},
    {"totalTrimB1", 0x00, 47, 1, -1, Kind::Number, 0.78125, -100,  "%",     "合計燃料補正 B1",        "fuel",   1, -30, 30, -100, 99.2, 1, "mdi:chart-bell-curve", true, ""},
    {"stftB2",      0x00, 17, 1, -1, Kind::Number, 0.78125, -100,  "%",     "短期燃料補正 B2",        "fuel",   1, -25, 25, -100, 99.2, 1, "mdi:chart-bell-curve", true, "バンク 2 の無い 3 気筒では出ない見込み"},
    {"ltftB2",      0x00, 18, 1, -1, Kind::Number, 0.78125, -100,  "%",     "長期燃料補正 B2",        "fuel",   1, -25, 25, -100, 99.2, 1, "mdi:chart-bell-curve", true, "バンク 2 の無い 3 気筒では出ない見込み"},
    {"totalTrimB2", 0x00, 48, 1, -1, Kind::Number, 0.78125, -100,  "%",     "合計燃料補正 B2",        "fuel",   1, -30, 30, -100, 99.2, 1, "mdi:chart-bell-curve", true, "バンク 2 の無い 3 気筒では出ない見込み"},
    {"injB1",       0x00, 37, 2, -1, Kind::Number, 0.001,    0,    "ms",    "噴射時間(1番 B1)",       "fuel",   2, 0, 20, 0, 65.5, 0.5, "mdi:fuel", true, ""},
    {"injB2",       0x00, 39, 2, -1, Kind::Number, 0.001,    0,    "ms",    "噴射時間(1番 B2)",       "fuel",   2, 0, 20, 0, 65.5, 0.5, "mdi:fuel", true, "バンク 2 の無い 3 気筒では出ない見込み"},
    {"fuelLevelEcu",0x00, 52, 1, -1, Kind::Number, 0.392157, 0,    "%",     "燃料残量(ECU)",          "fuel",   0, 0, 100, 0, 100, 5, "mdi:gas-station", true, "K6A では出ない見込み"},
    {"tankPressure",0x00, 53, 1, -1, Kind::Number, 0.078125, -10,  "kPa",   "燃料タンク差圧",         "fuel",   2, -5, 5, -10, 9.9, 0.5, "mdi:gas-station", true, ""},
    // ---- 吸気 ----
    {"map",         0x00, 19, 1, -1, Kind::Number, 1,        0,    "kPa",   "吸気管圧力(絶対圧)",     "air",    0, 0, 200, 0, 255, 10, "mdi:car-turbocharger", true, "大気圧を引くとブースト圧"},
    {"baro",        0x00, 41, 1, -1, Kind::Number, 0.5,      0,    "kPa",   "大気圧",                 "air",    1, 60, 110, 0, 127.5, 5, "mdi:weather-cloudy", true, ""},
    {"iat",         0x00, 24, 1, -1, Kind::Number, 1,      -40,    "℃",     "吸気温",                 "air",    0, -20, 80, -40, 215, 5, "mdi:thermometer", true, ""},
    {"maf",         0x00, 25, 2, -1, Kind::Number, 0.01,     0,    "g/s",   "吸入空気量(MAF)",        "air",    2, 0, 50, 0, 655, 5, "mdi:air-filter", true, "K6A は MAP 方式なので出ない見込み"},
    // ---- スロットル・アイドル ----
    {"throttlePos", 0x00, 27, 1, -1, Kind::Number, 0.392157, 0,    "%",     "スロットル開度",         "throttle", 1, 0, 100, 0, 100, 5, "mdi:car-cruise-control", true, ""},
    {"tpsVolt",     0x00, 36, 1, -1, Kind::Number, 0.0196078, 0,   "V",     "スロットルセンサー電圧", "throttle", 2, 0, 5, 0, 5, 0.25, "mdi:sine-wave", true, ""},
    {"iacPos",      0x00, 42, 1, -1, Kind::Number, 0.392157, 0,    "%",     "ISC(アイドル制御)開度",  "throttle", 1, 0, 100, 0, 100, 5, "mdi:valve", true, ""},
    {"iacFlow",     0x00, 43, 2, -1, Kind::Number, 1,        0,    "L/min", "ISC 流量(計算値)",       "throttle", 0, 0, 400, 0, 65535, 20, "mdi:air-filter", true, ""},
    {"mainTps",     0x02, 8,  1, -1, Kind::Number, 0.0196078, 0,   "V",     "スロットルセンサー(メイン)", "throttle", 2, 0, 5, 0, 5, 0.25, "mdi:sine-wave", true, "電子スロットル車のみ"},
    {"assistTps",   0x02, 9,  1, -1, Kind::Number, 0.0196078, 0,   "V",     "スロットルセンサー(サブ)",   "throttle", 2, 0, 5, 0, 5, 0.25, "mdi:sine-wave", true, "電子スロットル車のみ"},
    {"mainAps",     0x02, 10, 1, -1, Kind::Number, 0.0196078, 0,   "V",     "アクセルセンサー(メイン)",   "throttle", 2, 0, 5, 0, 5, 0.25, "mdi:sine-wave", true, "電子スロットル車のみ"},
    {"assistAps",   0x02, 11, 1, -1, Kind::Number, 0.0196078, 0,   "V",     "アクセルセンサー(サブ)",     "throttle", 2, 0, 5, 0, 5, 0.25, "mdi:sine-wave", true, "電子スロットル車のみ"},
    {"accelPos",    0x02, 12, 1, -1, Kind::Number, 0.392157, 0,    "%",     "アクセル開度(ECU)",      "throttle", 1, 0, 100, 0, 100, 5, "mdi:car-clutch", false, "アクセルと同じ値。電子スロットル車のみ"},
    {"throttleTarget",0x02, 13, 1, -1, Kind::Number, 0.392157, 0,  "%",     "目標スロットル開度",     "throttle", 1, 0, 100, 0, 100, 5, "mdi:car-cruise-control", true, "電子スロットル車のみ"},
    {"throttleMotorV",0x02, 32, 1, -1, Kind::Number, 0.0784314, 0, "V",     "スロットルモーター電源電圧", "throttle", 1, 8, 16, 0, 20, 0.5, "mdi:car-battery", true, "電子スロットル車のみ"},
    // ---- 排気・O2 ----
    {"o2B1S1",      0x00, 29, 1, -1, Kind::Number, 0.005,    0,    "V",     "O2 センサー B1S1",       "exhaust", 3, 0, 1.2, 0, 1.275, 0.05, "mdi:molecule-co2", true, ""},
    {"o2B1S2",      0x00, 30, 1, -1, Kind::Number, 0.005,    0,    "V",     "O2 センサー B1S2",       "exhaust", 3, 0, 1.2, 0, 1.275, 0.05, "mdi:molecule-co2", true, ""},
    {"o2B2S1",      0x00, 31, 1, -1, Kind::Number, 0.005,    0,    "V",     "O2 センサー B2S1",       "exhaust", 3, 0, 1.2, 0, 1.275, 0.05, "mdi:molecule-co2", true, "バンク 2 の無い 3 気筒では出ない見込み"},
    {"o2B2S2",      0x00, 32, 1, -1, Kind::Number, 0.005,    0,    "V",     "O2 センサー B2S2",       "exhaust", 3, 0, 1.2, 0, 1.275, 0.05, "mdi:molecule-co2", true, "バンク 2 の無い 3 気筒では出ない見込み"},
    {"afB1S1",      0x02, 29, 2, -1, Kind::Number, 0.00390625, -128, "mA",  "A/F センサー B1S1",      "exhaust", 2, -2, 2, -128, 128, 0.1, "mdi:molecule-co2", true, "ワイドバンド A/F センサー車のみ"},
    {"afB2S1",      0x02, 33, 2, -1, Kind::Number, 0.00390625, -128, "mA",  "A/F センサー B2S1",      "exhaust", 2, -2, 2, -128, 128, 0.1, "mdi:molecule-co2", true, "ワイドバンド A/F センサー車のみ"},
    // ---- EVAP・EGR ----
    {"evapPurge",   0x00, 50, 1, -1, Kind::Number, 0.392157, 0,    "%",     "パージ(EVAP)デューティ", "evap",   1, 0, 100, 0, 100, 5, "mdi:valve", true, ""},
    {"egrDuty",     0x00, 54, 1, -1, Kind::Number, 0.392157, 0,    "%",     "EGR デューティ",         "evap",   1, 0, 100, 0, 100, 5, "mdi:valve", true, ""},
    {"evapTemp",    0x00, 56, 1, -1, Kind::Number, 1,      -40,    "℃",     "燃料蒸気温度",           "evap",   0, 0, 80, -40, 215, 5, "mdi:thermometer", true, ""},
    // ---- 電装・エアコン ----
    {"ecuBattery",  0x00, 49, 1, -1, Kind::Number, 0.0784314, 0,   "V",     "バッテリー電圧(ECU)",    "electric", 1, 8, 18, 0, 20, 0.5, "mdi:car-battery", false, "電圧計と同じ値"},
    {"current",     0x02, 25, 1, -1, Kind::Number, 0.5,      0,    "A",     "消費電流",               "electric", 1, 0, 80, 0, 127.5, 5, "mdi:lightning-bolt", true, ""},
    {"genDuty",     0x02, 26, 1, -1, Kind::Number, 0.392157, 0,    "%",     "発電機制御デューティ",   "electric", 1, 0, 100, 0, 100, 5, "mdi:lightning-bolt", true, ""},
    {"genField",    0x02, 27, 1, -1, Kind::Number, 0.392157, 0,    "%",     "発電機フィールドデューティ", "electric", 1, 0, 100, 0, 100, 5, "mdi:lightning-bolt", true, ""},
    {"refrigerant", 0x02, 22, 1, -1, Kind::Number, 40,   -2000,    "kPa",   "エアコン冷媒圧",         "electric", 0, 0, 3000, -2000, 8200, 100, "mdi:air-conditioner", true, ""},
    // ---- スイッチ・作動状態(ビット) ----
    {"radiatorFan", 0x00, 65, 1, 0, Kind::Bit, 1, 0, "", "ラジエーターファン",       "switch", 0, 0, 0, 0, 0, 0, "mdi:fan", false, ""},
    {"fuelPump",    0x00, 65, 1, 1, Kind::Bit, 1, 0, "", "燃料ポンプ",               "switch", 0, 0, 0, 0, 0, 0, "mdi:fuel", false, ""},
    {"canister",    0x00, 65, 1, 4, Kind::Bit, 1, 0, "", "キャニスター",             "switch", 0, 0, 0, 0, 0, 0, "mdi:valve", false, ""},
    {"tankPressCtl",0x00, 65, 1, 5, Kind::Bit, 1, 0, "", "タンク圧制御",             "switch", 0, 0, 0, 0, 0, 0, "mdi:gas-station", false, ""},
    {"fuelCut",     0x00, 65, 1, 6, Kind::Bit, 1, 0, "", "燃料カット",               "switch", 0, 0, 0, 0, 0, 0, "mdi:fuel", false, ""},
    {"psSwitch",    0x00, 66, 1, 1, Kind::Bit, 1, 0, "", "パワステスイッチ",         "switch", 0, 0, 0, 0, 0, 0, "mdi:steering", false, ""},
    {"acSwitch",    0x00, 66, 1, 2, Kind::Bit, 1, 0, "", "エアコン",                 "switch", 0, 0, 0, 0, 0, 0, "mdi:air-conditioner", false, ""},
    {"pnSwitch",    0x00, 66, 1, 3, Kind::Bit, 1, 0, "", "P/N ポジション",           "switch", 0, 0, 0, 0, 0, 0, "mdi:car-shift-pattern", false, ""},
    {"idleSwitch",  0x00, 66, 1, 4, Kind::Bit, 1, 0, "", "アイドルスイッチ",         "switch", 0, 0, 0, 0, 0, 0, "mdi:engine-outline", false, ""},
    {"starter",     0x00, 66, 1, 7, Kind::Bit, 1, 0, "", "スタータースイッチ",       "switch", 0, 0, 0, 0, 0, 0, "mdi:key", false, ""},
    {"blowerFan",   0x00, 67, 1, 1, Kind::Bit, 1, 0, "", "ブロワーファン",           "switch", 0, 0, 0, 0, 0, 0, "mdi:fan", false, ""},
    {"condenserFan",0x00, 67, 1, 2, Kind::Bit, 1, 0, "", "コンデンサーファン",       "switch", 0, 0, 0, 0, 0, 0, "mdi:fan", false, ""},
    {"acClutch",    0x00, 67, 1, 3, Kind::Bit, 1, 0, "", "A/C マグネットクラッチ",   "switch", 0, 0, 0, 0, 0, 0, "mdi:air-conditioner", false, ""},
    {"wastegate",   0x00, 67, 1, 4, Kind::Bit, 1, 0, "", "ウェイストゲート",         "switch", 0, 0, 0, 0, 0, 0, "mdi:car-turbocharger", false, ""},
    {"abv",         0x00, 67, 1, 5, Kind::Bit, 1, 0, "", "エアバイパスバルブ",       "switch", 0, 0, 0, 0, 0, 0, "mdi:valve", false, ""},
    {"varIntake",   0x00, 67, 1, 7, Kind::Bit, 1, 0, "", "可変吸気バルブ",           "switch", 0, 0, 0, 0, 0, 0, "mdi:valve", false, ""},
    {"o2ActB1S1",   0x00, 68, 1, 0, Kind::Bit, 1, 0, "", "O2 センサー活性 B1S1",     "switch", 0, 0, 0, 0, 0, 0, "mdi:molecule-co2", false, ""},
    {"o2ActB1S2",   0x00, 68, 1, 1, Kind::Bit, 1, 0, "", "O2 センサー活性 B1S2",     "switch", 0, 0, 0, 0, 0, 0, "mdi:molecule-co2", false, ""},
    {"o2ActB2S1",   0x00, 68, 1, 2, Kind::Bit, 1, 0, "", "O2 センサー活性 B2S1",     "switch", 0, 0, 0, 0, 0, 0, "mdi:molecule-co2", false, ""},
    {"o2ActB2S2",   0x00, 68, 1, 3, Kind::Bit, 1, 0, "", "O2 センサー活性 B2S2",     "switch", 0, 0, 0, 0, 0, 0, "mdi:molecule-co2", false, ""},
    {"elecLoad",    0x00, 68, 1, 6, Kind::Bit, 1, 0, "", "電気負荷",                 "switch", 0, 0, 0, 0, 0, 0, "mdi:lightning-bolt", false, ""},
    {"brakeSwitch", 0x00, 68, 1, 7, Kind::Bit, 1, 0, "", "ブレーキスイッチ",         "switch", 0, 0, 0, 0, 0, 0, "mdi:car-brake-alert", false, ""},
    {"afActB1S1",   0x00, 69, 1, 0, Kind::Bit, 1, 0, "", "A/F センサー活性 B1S1",    "switch", 0, 0, 0, 0, 0, 0, "mdi:molecule-co2", false, ""},
    {"afActB2S1",   0x00, 69, 1, 1, Kind::Bit, 1, 0, "", "A/F センサー活性 B2S1",    "switch", 0, 0, 0, 0, 0, 0, "mdi:molecule-co2", false, ""},
    {"throttleRelay",0x02, 35, 1, 3, Kind::Bit, 1, 0, "", "スロットルモーターリレー", "switch", 0, 0, 0, 0, 0, 0, "mdi:car-cruise-control", false, ""},
};
// clang-format on

struct Group { const char *id; const char *title; const char *icon; };
const Group kGroups[] = {
    {"drive",    "走行",                   "directions_car"},   // 車速など(VIN ノードの値が主。画面の分類をそろえるため)
    {"engine",   "エンジン",               "mdi:engine"},
    {"fuel",     "燃料",                   "mdi:fuel"},
    {"air",      "吸気",                   "mdi:air-filter"},
    {"throttle", "スロットル・アイドル",   "mdi:car-cruise-control"},
    {"exhaust",  "排気・O2",               "mdi:molecule-co2"},
    {"evap",     "EVAP・EGR",              "mdi:valve"},
    {"electric", "電装・エアコン",         "mdi:car-battery"},
    {"switch",   "スイッチ・作動状態",     "toggle_on"},
};

const Param *findParam(const QString &id) {
    for (const Param &p : kParams) {
        if (id == QLatin1String(p.id)) return &p;
    }
    return nullptr;
}

QString fuelStatusText(int v) {
    switch (v) {
    case 1: return QStringLiteral("オープンループ(暖機中など)");
    case 2: return QStringLiteral("クローズドループ(O2 センサーで補正中)");
    case 4: return QStringLiteral("オープンループ(加速・燃料カットなど)");
    case 8: return QStringLiteral("オープンループ(異常)");
    case 16: return QStringLiteral("クローズドループ(異常あり)");
    default: return QStringLiteral("状態 %1").arg(v);
    }
}

// ---- 故障コードの一覧(resources/data/suzuki_dtc_list.csv)。初めて使うときに読む ----
// 列: コード, 系統, 区分, 名称(日本語), 検出条件・詳細(日本語), 名称(英語), 検出条件・詳細(英語), 生データ
// 日本語が空なら英語を使う。英語の名称も残す(画面で原文として出す)
struct DtcInfo { QString name; QString system; QString category; QString detail; QString nameEn; };

QStringList parseCsvLine(const QString &line) {
    QStringList out;
    QString cur;
    bool quoted = false;
    for (int i = 0; i < line.size(); ++i) {
        const QChar c = line.at(i);
        if (quoted) {
            if (c == QLatin1Char('"')) {
                if (i + 1 < line.size() && line.at(i + 1) == QLatin1Char('"')) { cur += c; ++i; }
                else quoted = false;
            } else {
                cur += c;
            }
        } else if (c == QLatin1Char('"')) {
            quoted = true;
        } else if (c == QLatin1Char(',')) {
            out << cur;
            cur.clear();
        } else {
            cur += c;
        }
    }
    out << cur;
    return out;
}

const QHash<QString, DtcInfo> &dtcTable() {
    static QHash<QString, DtcInfo> table;
    static bool loaded = false;
    if (loaded) return table;
    loaded = true;
    QFile file(QStringLiteral(":/ecu/suzuki_dtc_list.csv"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        log::warn("ECU", QStringLiteral("could not open the DTC list (suzuki_dtc_list.csv)"));
        return table;
    }
    QString text = QString::fromUtf8(file.readAll());
    if (text.startsWith(QChar(0xFEFF))) text.remove(0, 1);
    // 改行を含む項目があっても読めるように、引用符の中の改行はつなぐ
    QStringList lines;
    QString pending;
    for (const QString &raw : text.split(QLatin1Char('\n'))) {
        pending = pending.isEmpty() ? raw : pending + QLatin1Char(' ') + raw;
        if (pending.count(QLatin1Char('"')) % 2 == 0) { lines << pending; pending.clear(); }
    }
    for (int i = 1; i < lines.size(); ++i) {   // 1 行目は見出し
        const QStringList f = parseCsvLine(lines.at(i).trimmed());
        if (f.size() < 4 || f.at(0).isEmpty()) continue;
        auto at = [&f](int i) { return i < f.size() ? f.at(i).trimmed() : QString(); };
        const QString nameJa = at(3), detailJa = at(4), nameEn = at(5), detailEn = at(6);
        table.insert(at(0).toUpper(), DtcInfo{nameJa.isEmpty() ? nameEn : nameJa, at(1), at(2),
                                              detailJa.isEmpty() ? detailEn : detailJa, nameEn});
    }
    log::info("ECU", QStringLiteral("DTC list loaded: %1 codes").arg(table.size()));
    return table;
}

/// 2 バイトの故障コードを文字にする(SAE J2012: 上位 2 ビットで P / C / B / U)
QString dtcCodeText(quint8 hi, quint8 lo) {
    static const char kSys[] = {'P', 'C', 'B', 'U'};
    return QStringLiteral("%1%2%3%4")
        .arg(QLatin1Char(kSys[(hi >> 6) & 3]))
        .arg((hi >> 4) & 3)
        .arg(hi & 0x0F, 1, 16, QLatin1Char('0'))
        .arg(lo, 2, 16, QLatin1Char('0'))
        .toUpper();
}

/// 状態バイトのビット 6〜5(ISO 14230-3 の記録状態)で分ける。推定(実車で要確認)
QString dtcState(quint8 status) {
    switch ((status >> 5) & 3) {
    case 3: return QStringLiteral("current");
    case 2: return QStringLiteral("pending");
    case 1: return QStringLiteral("past");
    default: return QString();
    }
}

QString makerName(const QString &raw) {
    const QString code = raw.trimmed().left(3).toUpper();
    if (code == QLatin1String("DEN")) return QStringLiteral("デンソー (DEN)");
    if (code == QLatin1String("HIT")) return QStringLiteral("日立 (HIT)");
    if (code == QLatin1String("AAW")) return QStringLiteral("アイシン AW (AAW)");
    return raw.trimmed();
}

} // namespace

// ============================================================================ 本体

EcuData::EcuData(VehicleDataManager *vehicle, QObject *parent) : QObject(parent), vehicle_(vehicle) {
    mockDtcMode_ = std::clamp(openStore().value(QStringLiteral("mock/dtcMode"), 0).toInt(), 0, 2);
    {
        QSettings store = openStore();
        store.beginGroup(QStringLiteral("vehicle/sourcePrefs"));
        for (const QString &key : store.childKeys()) {
            const QString mode = store.value(key).toString();
            if (isSourceMode(mode)) sourcePrefs_.insert(key, mode);
        }
        store.endGroup();
        const QString ov = store.value(QStringLiteral("vehicle/sourceOverride")).toString();
        if (isSourceMode(ov)) sourceOverride_ = ov;
    }
    mockTimer_.setInterval(180);   // 実車の見込み(1 周 150〜180ms、約 5〜7Hz)に合わせる
    connect(&mockTimer_, &QTimer::timeout, this, &EcuData::mockTick);
    if (vehicle_) {
        connect(vehicle_, &VehicleDataManager::dataAvailableChanged, this, &EcuData::updateMockLink);
    }
    rateClock_.start();
    updateMockLink();
}

// ---- 定義 ----
QVariantList EcuData::params() const {
    QVariantList list;
    for (const Param &p : kParams) {
        const QString kind = p.kind == Kind::Bit ? QStringLiteral("bit") : p.kind == Kind::Enum ? QStringLiteral("enum")
                                                                                                : QStringLiteral("number");
        list.append(QVariantMap{
            {QStringLiteral("id"), QString::fromLatin1(p.id)},
            {QStringLiteral("title"), QString::fromUtf8(p.title)},
            {QStringLiteral("group"), QString::fromLatin1(p.group)},
            {QStringLiteral("unit"), QString::fromUtf8(p.unit)},
            {QStringLiteral("kind"), kind},
            {QStringLiteral("dec"), p.dec},
            {QStringLiteral("min"), p.min},
            {QStringLiteral("max"), p.max},
            {QStringLiteral("limitMin"), p.limitMin},
            {QStringLiteral("limitMax"), p.limitMax},
            {QStringLiteral("step"), p.step},
            {QStringLiteral("icon"), QString::fromLatin1(p.icon)},
            {QStringLiteral("gauge"), p.gauge},
            {QStringLiteral("block"), QStringLiteral("21 %1").arg(p.block, 2, 16, QLatin1Char('0'))},
            {QStringLiteral("pos"), p.pos},
            {QStringLiteral("note"), QString::fromUtf8(p.note)},
        });
    }
    return list;
}

QVariantList EcuData::groups() const {
    QVariantList list;
    for (const Group &g : kGroups) {
        list.append(QVariantMap{{QStringLiteral("id"), QString::fromLatin1(g.id)},
                                {QStringLiteral("title"), QString::fromUtf8(g.title)},
                                {QStringLiteral("icon"), QString::fromLatin1(g.icon)}});
    }
    return list;
}

// ---- 値 ----
double EcuData::value(const QString &id) const {
    const auto it = values_.constFind(id);
    return it == values_.constEnd() ? std::numeric_limits<double>::quiet_NaN() : it.value();
}

bool EcuData::has(const QString &id) const {
    return available() && values_.contains(id);
}

QString EcuData::text(const QString &id) const {
    const Param *p = findParam(id);
    if (!p || !has(id)) return QStringLiteral("--");
    const double v = value(id);
    switch (p->kind) {
    case Kind::Bit: return v != 0 ? QStringLiteral("ON") : QStringLiteral("OFF");
    case Kind::Enum: return fuelStatusText(int(v));
    case Kind::Number: break;
    }
    const QString unit = QString::fromUtf8(p->unit);
    return QString::number(v, 'f', p->dec) + (unit.isEmpty() ? QString() : QStringLiteral(" ") + unit);
}

QVariantMap EcuData::numericValues() const {
    QVariantMap map;
    if (!available()) return map;
    for (const Param &p : kParams) {
        if (p.kind != Kind::Number) continue;
        const auto it = values_.constFind(QString::fromLatin1(p.id));
        if (it != values_.constEnd()) map.insert(QString::fromLatin1(p.id), it.value());
    }
    return map;
}

// ---- 故障コード ----
int EcuData::currentDtcCount() const {
    int n = 0;
    for (const QVariant &v : dtcs_) {
        const QString s = v.toMap().value(QStringLiteral("state")).toString();
        if (s == QLatin1String("current") || s == QLatin1String("pending")) ++n;
    }
    return n;
}

int EcuData::pastDtcCount() const {
    int n = 0;
    for (const QVariant &v : dtcs_) {
        if (v.toMap().value(QStringLiteral("state")).toString() == QLatin1String("past")) ++n;
    }
    return n;
}

QString EcuData::dtcSummary(const QString &state) const {
    QStringList items;
    for (const QVariant &v : dtcs_) {
        const QVariantMap m = v.toMap();
        const QString s = m.value(QStringLiteral("state")).toString();
        const bool want = state == QLatin1String("past") ? s == QLatin1String("past")
                                                         : (s == QLatin1String("current") || s == QLatin1String("pending"));
        if (!want) continue;
        const QString desc = m.value(QStringLiteral("description")).toString();
        items << (desc.isEmpty() ? m.value(QStringLiteral("code")).toString()
                                 : m.value(QStringLiteral("code")).toString() + QStringLiteral(" ") + desc);
    }
    if (items.isEmpty()) return QString();
    QString text = items.first();
    if (items.size() > 1) text += QStringLiteral(" ・ ほか %1 件").arg(items.size() - 1);
    return text;
}

QString EcuData::dtcDescription(const QString &code) {
    return dtcTable().value(code.trimmed().toUpper()).name;
}

QVariantList EcuData::ecuInfo() const {
    static const struct { int id; const char *label; } kLabels[] = {
        {0x8A, "部品番号"}, {0x92, "メーカー"}, {0x8D, "ソフトウェアバージョン"}, {0x99, "更新日"},
        {0x8B, "OEM 番号"}, {0x8C, "OEM 番号(2)"}, {0x9A, "キャリブレーション ID"}, {0x9E, "キャリブレーション ID(2)"},
        {0x9F, "キャリブレーション ID(3)"}, {0x98, "テスターのシリアル番号"}};
    QVariantList list;
    for (const auto &l : kLabels) {
        QString value = QStringLiteral("--");
        const auto it = ecuInfo_.constFind(l.id);
        if (it != ecuInfo_.constEnd()) {
            // ASCII として読めればその文字、読めなければ 16 進
            const QByteArray &raw = it.value();
            bool ascii = !raw.isEmpty();
            for (const char c : raw) {
                if (c != 0 && (c < 0x20 || c > 0x7E)) { ascii = false; break; }
            }
            value = ascii ? QString::fromLatin1(raw).remove(QChar(0)).trimmed() : QString::fromLatin1(raw.toHex(' ')).toUpper();
            if (l.id == 0x92) value = makerName(value);
        }
        list.append(QVariantMap{{QStringLiteral("label"), QString::fromUtf8(l.label)}, {QStringLiteral("value"), value}});
    }
    return list;
}

// ---- 通信の状態 ----
QString EcuData::sourceText() const {
    if (linkState_ == QLatin1String("mock")) return QStringLiteral("ダミーデータ(K-Line の通信は未実装)");
    if (linkState_ == QLatin1String("none")) return QStringLiteral("なし(ダミーデータも切っています)");
    return source_;
}

QString EcuData::lastUpdateText() const {
    if (lastUpdateMs_ == 0) return QStringLiteral("--");
    return QDateTime::fromMSecsSinceEpoch(lastUpdateMs_).toString(QStringLiteral("HH:mm:ss.zzz"));
}

void EcuData::setLink(const QString &state, const QString &source, int responseMs) {
    // 実際のデータ元がつながったら、ダミーはやめる(以後はダミーに戻さない)
    if (state != QLatin1String("mock") && mockTimer_.isActive()) {
        mockTimer_.stop();
        log::info("ECU", QStringLiteral("a real data source is connected; mock data stopped"));
    }
    const bool changed = state != linkState_ || source != source_;
    linkState_ = state;
    source_ = source;
    if (responseMs >= 0) responseMs_ = responseMs;
    if (changed) {
        log::info("ECU", QStringLiteral("link: %1").arg(state));
        if (!available()) {
            values_.clear();
            missing_.clear();
            ++revision_;
            emit valuesChanged();
        }
    }
    emit linkChanged();
}

void EcuData::reportError(const QString &what) {
    ++errorCount_;
    log::warn("ECU", QStringLiteral("communication error: %1").arg(what));
    emit linkChanged();
}

// ---- 受け口 ----
void EcuData::ingestBlock(int localId, const QByteArray &data) {
    for (const Param &p : kParams) {
        if (p.block != localId) continue;
        const QString id = QString::fromLatin1(p.id);
        if (p.pos + p.len > data.size()) { values_.remove(id); continue; }
        const quint8 b0 = quint8(data.at(p.pos));
        double v = 0;
        if (p.kind == Kind::Bit) {
            if (b0 == 0xFF) { values_.remove(id); missing_.insert(id, true); continue; }
            v = (b0 >> p.bit) & 1;
        } else {
            quint32 raw = b0;
            bool allFF = b0 == 0xFF;
            if (p.len == 2) {
                const quint8 b1 = quint8(data.at(p.pos + 1));
                raw = (quint32(b0) << 8) | b1;
                allFF = b0 == 0xFF && b1 == 0xFF;
            }
            if (allFF) { values_.remove(id); missing_.insert(id, true); continue; }
            v = p.kind == Kind::Enum ? double(raw) : raw * p.scale + p.offset;
        }
        values_.insert(id, v);
        missing_.remove(id);
    }
    if (localId == 0x00) decodeDtcsFromBlock00(data);

    ++frameCount_;
    if (localId == 0x00) ++rateFrames_;   // 更新の速さは、メインブロック(`21 00`)の回数で数える
    lastUpdateMs_ = QDateTime::currentMSecsSinceEpoch();
    if (rateClock_.elapsed() >= 1000) {
        rateHz_ = rateFrames_ * 1000.0 / rateClock_.restart();
        rateFrames_ = 0;
    }
    ++revision_;
    emit valuesChanged();
    emit linkChanged();
}

// `21 00` の位置 0(件数)・1〜6(コード 2 件と状態)・7(MIL)。`18` の一覧を受け取っていれば、コードはそちらを使う
void EcuData::decodeDtcsFromBlock00(const QByteArray &data) {
    if (data.size() < 8) return;
    const bool mil = (quint8(data.at(7)) & 0x80) != 0 && quint8(data.at(7)) != 0xFF;
    if (mil != milOn_) {
        milOn_ = mil;
        log::info("ECU", QStringLiteral("MIL %1").arg(mil ? QStringLiteral("on") : QStringLiteral("off")));
        emit dtcsChanged();
    }
    if (dtcListSeen_) return;
    const quint8 count = quint8(data.at(0));
    int n = 0;
    QByteArray items;
    for (int k = 0; k < 2; ++k) {
        const quint8 hi = quint8(data.at(1 + 3 * k)), lo = quint8(data.at(2 + 3 * k)), st = quint8(data.at(3 + 3 * k));
        if ((hi == 0xFF && lo == 0xFF) || (hi == 0 && lo == 0)) continue;
        items.append(char(hi)).append(char(lo)).append(char(st));
        ++n;
    }
    if (count == 0xFF && n == 0) return;   // この ECU では出ない
    applyDtcs(QByteArray(1, char(n)) + items);
}

void EcuData::ingestDtcList(const QByteArray &data) {
    dtcListSeen_ = true;
    applyDtcs(data);
}

void EcuData::applyDtcs(const QByteArray &data) {
    QVariantList list;
    if (!data.isEmpty()) {
        const int count = quint8(data.at(0));
        for (int i = 0; i < count && 1 + 3 * i + 2 < data.size(); ++i) {
            const quint8 hi = quint8(data.at(1 + 3 * i)), lo = quint8(data.at(2 + 3 * i)), st = quint8(data.at(3 + 3 * i));
            const QString state = dtcState(st);
            if (state.isEmpty()) continue;
            const QString code = dtcCodeText(hi, lo);
            const DtcInfo info = dtcTable().value(code);
            list.append(QVariantMap{
                {QStringLiteral("code"), code},
                {QStringLiteral("description"), info.name},
                {QStringLiteral("detail"), info.detail},
                {QStringLiteral("descriptionEn"), info.nameEn},
                {QStringLiteral("system"), info.system},
                {QStringLiteral("category"), info.category},
                {QStringLiteral("state"), state},
                {QStringLiteral("status"), QStringLiteral("%1").arg(st, 2, 16, QLatin1Char('0')).toUpper()},
                {QStringLiteral("statusText"), state == QLatin1String("current") ? QStringLiteral("現在起きている")
                                               : state == QLatin1String("pending") ? QStringLiteral("起きかけている(確定前)")
                                                                                   : QStringLiteral("過去の記録")},
                {QStringLiteral("lampRequest"), (st & 0x80) != 0},
            });
        }
    }
    // 変わったときだけ知らせる
    if (list != dtcs_) {
        dtcs_ = list;
        QStringList codes;
        for (const QVariant &v : dtcs_) codes << v.toMap().value(QStringLiteral("code")).toString() + QLatin1Char('/')
                                                   + v.toMap().value(QStringLiteral("state")).toString();
        log::info("ECU", QStringLiteral("DTCs: %1").arg(codes.isEmpty() ? QStringLiteral("none") : codes.join(QStringLiteral(", "))));
        emit dtcsChanged();
    }
}

void EcuData::ingestEcuInfo(int id, const QByteArray &data) {
    if (ecuInfo_.value(id) == data) return;
    ecuInfo_.insert(id, data);
    emit ecuInfoChanged();
}

// ============================================================================ ダミー
void EcuData::setSourcePref(const QString &metric, const QString &mode) {
    if (metric.isEmpty() || !isSourceMode(mode)) return;
    if (sourcePrefs_.value(metric, QStringLiteral("auto")).toString() == mode) return;
    if (mode == QStringLiteral("auto")) sourcePrefs_.remove(metric);
    else sourcePrefs_.insert(metric, mode);
    QSettings store = openStore();
    if (mode == QStringLiteral("auto")) store.remove(QStringLiteral("vehicle/sourcePrefs/") + metric);
    else store.setValue(QStringLiteral("vehicle/sourcePrefs/") + metric, mode);
    log::info("ECU", QStringLiteral("source preference: %1 = %2").arg(metric, mode));
    emit settingsChanged();
}

void EcuData::setSourceOverride(const QString &mode) {
    const QString m = isSourceMode(mode) ? mode : QString();
    if (m == sourceOverride_) return;
    sourceOverride_ = m;
    QSettings store = openStore();
    if (m.isEmpty()) store.remove(QStringLiteral("vehicle/sourceOverride"));
    else store.setValue(QStringLiteral("vehicle/sourceOverride"), m);
    log::info("ECU", QStringLiteral("source override: %1").arg(m.isEmpty() ? QStringLiteral("none") : m));
    emit settingsChanged();
}

void EcuData::setMockDtcMode(int mode) {
    mode = std::clamp(mode, 0, 2);
    if (mode == mockDtcMode_) return;
    mockDtcMode_ = mode;
    openStore().setValue(QStringLiteral("mock/dtcMode"), mode);
    log::info("ECU", QStringLiteral("mock DTC mode: %1").arg(mode));
    emit settingsChanged();
}

void EcuData::updateMockLink() {
    if (linkState_ != QLatin1String("none") && linkState_ != QLatin1String("mock")) return;   // 実際のデータ元を使っている
    const bool on = vehicle_ && vehicle_->dataAvailable();
    if (on && !mockTimer_.isActive()) {
        // ダミーの ECU 情報(部品番号は HN22S 用 ECU の番号の形。中身はダミー)
        ingestEcuInfo(0x8A, QByteArrayLiteral("33920-84F6*"));
        ingestEcuInfo(0x92, QByteArrayLiteral("DEN"));
        ingestEcuInfo(0x8D, QByteArrayLiteral("MOCK-0001"));
        ingestEcuInfo(0x99, QByteArrayLiteral("2026-11-18"));
        ingestEcuInfo(0x9A, QByteArrayLiteral("DUMMY-CAL"));
        responseMs_ = 62;
        mockTimer_.start();
        setLink(QStringLiteral("mock"), QString());
    } else if (!on) {
        mockTimer_.stop();
        if (linkState_ != QLatin1String("none")) setLink(QStringLiteral("none"), QString());
    }
}

namespace {
void put(QByteArray &b, int pos, double value, double scale, double offset, int len = 1) {
    const double raw = std::round((value - offset) / scale);
    const quint32 max = len == 2 ? 0xFFFE : 0xFE;   // FF(FF FF)は「項目なし」なので使わない
    const quint32 r = quint32(std::clamp(raw, 0.0, double(max)));
    if (len == 2) {
        b[pos] = char((r >> 8) & 0xFF);
        b[pos + 1] = char(r & 0xFF);
    } else {
        b[pos] = char(r);
    }
}
} // namespace

void EcuData::mockTick() {
    ingestBlock(0x00, makeMockBlock00());
    ingestBlock(0x02, makeMockBlock02());
    ingestDtcList(makeMockDtcs());
}

QByteArray EcuData::makeMockBlock00() {
    QByteArray b(70, char(0xFF));   // FF = 項目なし(K6A で出ない見込みの項目はそのまま)
    const VehicleDataManager &v = *vehicle_;
    const double rpm = v.rpm(), speed = v.speedKmh(), coolant = v.coolantTempC(), thr = v.throttlePercent();
    const double boostKpa = v.boostBar() * 100.0;
    const bool warm = coolant > 60;
    const bool fuelCut = thr < 1 && rpm > 1500 && speed > 10;
    const double load = fuelCut ? 0 : std::clamp(18 + thr * 0.75 + boostKpa * 0.25, 0.0, 100.0);
    std::normal_distribution<double> noise(0.0, 1.0);
    // 燃料補正: 短期は O2 に合わせて揺れ、長期はゆっくり
    mockTrimShort_ = std::clamp(mockTrimShort_ * 0.85 + noise(rng_) * 1.2, -12.0, 12.0);
    mockTrimLong_ = std::clamp(mockTrimLong_ + noise(rng_) * 0.02, 0.0, 8.0);
    mockO2Phase_ += 0.18 * 2 * M_PI * (rpm > 0 ? 1.2 : 0);

    // DTC(位置 0〜7)は makeMockDtcs と同じ内容を入れる
    const QByteArray dtcs = makeMockDtcs();
    const int count = quint8(dtcs.at(0));
    b[0] = char(count);
    for (int k = 0; k < 2; ++k) {
        if (k < count) {
            b[1 + 3 * k] = dtcs.at(1 + 3 * k);
            b[2 + 3 * k] = dtcs.at(2 + 3 * k);
            b[3 + 3 * k] = dtcs.at(3 + 3 * k);
        } else {
            b[1 + 3 * k] = 0; b[2 + 3 * k] = 0; b[3 + 3 * k] = 0;
        }
    }
    b[7] = char((mockDtcMode_ == 2 ? 0x80 : 0x00) | (count & 0x7F));   // MIL + 件数(OBD 形式)
    b[11] = char(fuelCut ? 4 : (warm ? 2 : 1));                        // 燃料系の状態 B1
    put(b, 13, load, 0.392157, 0);
    put(b, 14, coolant, 1, -40);
    if (warm && !fuelCut) put(b, 15, mockTrimShort_, 0.78125, -100); else put(b, 15, 0, 0.78125, -100);
    put(b, 16, mockTrimLong_, 0.78125, -100);
    put(b, 19, std::clamp(101.3 + boostKpa, 20.0, 254.0), 1, 0);
    put(b, 20, rpm, 0.25, 0, 2);
    put(b, 22, speed, 1, 0);
    put(b, 23, std::clamp(8 + rpm / 350.0 - boostKpa / 12.0, -10.0, 45.0), 0.5, -64);
    put(b, 24, 22 + std::max(0.0, boostKpa) * 0.12 + (speed < 5 ? 6 : 0), 1, -40);
    put(b, 27, thr * 0.92, 0.392157, 0);
    put(b, 29, warm ? 0.45 + 0.4 * std::sin(mockO2Phase_) : 0.45, 0.005, 0);
    put(b, 35, warm ? 850 : 1100, 7.84314, 0);
    put(b, 36, 0.62 + thr * 0.039, 0.0196078, 0);
    put(b, 37, fuelCut ? 0 : 2.2 + load * 0.075, 0.001, 0, 2);
    put(b, 41, 101.0, 0.5, 0);
    put(b, 42, thr < 1 ? (warm ? 26 : 40) : 12, 0.392157, 0);
    put(b, 43, thr < 1 ? (warm ? 165 : 230) : 60, 1, 0, 2);
    put(b, 47, (warm && !fuelCut ? mockTrimShort_ : 0) + mockTrimLong_, 0.78125, -100);
    put(b, 49, v.batteryVolts(), 0.0784314, 0);
    put(b, 50, warm && rpm > 1500 ? 18 : 0, 0.392157, 0);
    put(b, 54, 0, 0.392157, 0);
    // スイッチ類
    quint8 s65 = 0, s66 = 0, s67 = 0, s68 = 0;
    if (coolant > 96) s65 |= 1 << 0;                 // ラジエーターファン
    if (rpm > 300) s65 |= 1 << 1;                    // 燃料ポンプ
    if (warm) s65 |= 1 << 4;                         // キャニスター
    if (fuelCut) s65 |= 1 << 6;                      // 燃料カット
    if (speed < 1 && v.brakePercent() > 5) s66 |= 1 << 3;   // P/N(停車中はブレーキを踏んでいる)
    if (thr < 1) s66 |= 1 << 4;                      // アイドルスイッチ
    if (boostKpa > 80) s67 |= 1 << 4;                // ウェイストゲート
    if (warm) s68 |= 1 << 0;                         // O2 センサー活性 B1S1
    if (v.brakePercent() > 5) s68 |= 1 << 7;         // ブレーキスイッチ
    b[65] = char(s65);
    b[66] = char(s66);
    b[67] = char(s67);
    b[68] = char(s68);
    return b;
}

QByteArray EcuData::makeMockBlock02() {
    QByteArray b(40, char(0xFF));
    for (int i = 0; i < 7; ++i) b[i] = 0;   // 位置 0〜6: 21 00 と同じ形式(ここでは件数 0)
    put(b, 19, std::clamp(vehicle_->rpm() > 3000 ? 2.0 : 0.4, -45.0, 45.0), 0.352941, -45);
    return b;
}

QByteArray EcuData::makeMockDtcs() const {
    QByteArray b;
    switch (mockDtcMode_) {
    case 1:   // 過去の記録だけ: P0420(触媒の効率低下)
        b.append(char(1)).append(char(0x04)).append(char(0x20)).append(char(0x20));
        break;
    case 2:   // 現在: P0115(水温センサー回路)+ 過去: P0420
        b.append(char(2)).append(char(0x01)).append(char(0x15)).append(char(0xE0))
         .append(char(0x04)).append(char(0x20)).append(char(0x20));
        break;
    default:
        b.append(char(0));
        break;
    }
    return b;
}

} // namespace opencruise
