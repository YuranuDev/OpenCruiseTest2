/**
 * @file Log.h
 * @brief アプリ共通のログ基盤（コンソール出力 + ローテーション付きファイル出力）。
 *
 * 使い方:
 *  - main() の早い段階で opencruise::log::initialize() を呼ぶ。以降は Qt の qDebug/qInfo/qWarning/
 *    qCritical も同じ形式でファイルに残る（Qt のメッセージハンドラを差し替えるため）。
 *  - コンポーネント名を明示したい場合は log::info("USB", ...) のように呼ぶ。
 *
 * 出力形式:
 *  2026-10-20 15:30:12.123 [INFO] [USB] Device detected
 *  - DEBUG の行は末尾にスレッドID、Qt 由来の行は末尾に発生箇所(ファイル:行)が付く。
 *
 * 既存メッセージの `[aa] [session] ...` のような先頭タグは、最後のタグをコンポーネント名として採用し
 * 本文からは取り除く（例: コンポーネント SESSION、本文 "..."）。
 */
#pragma once

#include <cstdint>

#include <QString>
#include <QtGlobal>

namespace opencruise::log {

/**
 * @brief ログレベル。値の大小で重要度を比較できる。
 */
enum class Level : int {
    Debug = 0,
    Info = 1,
    Warn = 2,
    Error = 3,
    Fatal = 4
};

/**
 * @brief ログ基盤の設定。既定値は defaultOptions() で生成する。
 */
struct Options {
    QString directory;                 ///< 保存先ディレクトリ（空なら defaultDirectory()）
    Level minLevel = Level::Info;      ///< 記録する最小レベル
    qint64 maxFileBytes = 8 * 1024 * 1024; ///< 1ファイルの上限サイズ(バイト)。0 以下で無制限
    int maxFilesPerRun = 4;            ///< 1回の起動で作るファイル数の上限(分割数)
    int maxRuns = 10;                  ///< ディレクトリに残すログファイル数の上限
    bool mirrorToConsole = true;       ///< コンソール(標準エラー)にも同時に出力するか
};

/** @brief 既定の保存先（OS のアプリデータ領域 + /logs）。 */
QString defaultDirectory();

/** @brief 環境変数を反映した既定設定。
 *  OPENCRUISE_LOG_DIR / OPENCRUISE_LOG_LEVEL / OPENCRUISE_LOG_MAX_BYTES を参照する。 */
Options defaultOptions();

/**
 * @brief 文字列をレベルへ変換する。
 * @param text "debug" / "info" / "warn" / "error" / "fatal"（大文字小文字は問わない）
 * @param[out] ok 解釈できたら true
 */
Level parseLevel(const QString &text, bool *ok = nullptr);

/** @brief レベルの表記（"DEBUG" など）。 */
const char *levelToString(Level level);

/**
 * @brief ログ基盤を開始する。Qt のメッセージハンドラを差し替える。
 *
 * ファイルを開けなかった場合もコンソール出力は有効なまま false を返す（致命的ではない）。
 * @param options 設定
 * @param[out] errorMessage ファイル出力を開始できなかった理由
 * @return ファイル出力を開始できたら true
 */
bool initialize(const Options &options, QString *errorMessage = nullptr);

/** @brief ログをフラッシュして閉じる。以降の qDebug 等は既定の出力に戻る。 */
void shutdown();

/** @brief ファイル出力が有効か。 */
bool isFileLoggingActive();

/** @brief 現在書き込んでいるファイルのパス（未開始なら空）。 */
QString currentFilePath();

/** @brief ログの保存先ディレクトリ（未開始なら空）。 */
QString directoryPath();

/** @brief 任意のレベル・コンポーネントで 1 行記録する。 */
void write(Level level, const char *component, const QString &message);

void debug(const char *component, const QString &message);
void info(const char *component, const QString &message);
void warn(const char *component, const QString &message);
void error(const char *component, const QString &message);
void fatal(const char *component, const QString &message);

/** @brief 実行環境（OS / Qt / ビルド種別）の説明文。起動時に 1 行記録する用途。 */
QString describeEnvironment();

/**
 * @brief 処理時間の計測。開始時に生成し、完了時に elapsedMs() をログへ出す。
 */
class Stopwatch {
public:
    Stopwatch();

    /** @brief 生成からの経過時間(ミリ秒)。 */
    qint64 elapsedMs() const;

private:
    std::int64_t startedMs_ = 0;
};

} // namespace opencruise::log
