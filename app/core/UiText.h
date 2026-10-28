/**
 * @file UiText.h
 * @brief 画面に出す文の日本語化。ログは英語、画面は日本語にするため、接続層などの英語のメッセージを画面用に置き換える。
 *
 * 接続層(aasdk)・映像デコーダ・マイク・外部モニターなどのメッセージ(状態の詳細・切断理由・エラー)は英語で作り、
 * そのままログに出す。画面に出すときだけ toJapanese() を通す。
 * 先頭が表の英語と一致すれば日本語へ置き換え、残り(続きのメッセージ)も同じように置き換える
 * (例: "Disconnected: No response from the phone (ping timeout)" → 「切断: スマートフォンから応答がありません(Ping タイムアウト)」)。
 * 表に無い部分(ライブラリのエラー名など)は英語のまま残す。
 */
#pragma once

#include <QString>

#include <algorithm>
#include <utility>
#include <vector>

namespace opencruise::uitext {

/// 英語のメッセージの先頭 → 日本語(長いものから順に照合する)
inline const std::vector<std::pair<QString, QString>> &table() {
    static const std::vector<std::pair<QString, QString>> kTable = [] {
        std::vector<std::pair<QString, QString>> t = {
            // ---- Android Auto の接続層: 状態の詳細 ----
            {QStringLiteral("Waiting for the phone to connect"), QStringLiteral("スマートフォンの接続を待っています")},
            {QStringLiteral("Phone detected. Connecting"), QStringLiteral("スマートフォンを検出しました。接続処理中です")},
            {QStringLiteral("Connected (waiting for video to start)"), QStringLiteral("接続済み（映像の開始を待っています）")},
            {QStringLiteral("Receiving video"), QStringLiteral("映像を受信中")},
            {QStringLiteral("Video stream stopped"), QStringLiteral("映像ストリームが停止しました")},
            {QStringLiteral("Disconnected: "), QStringLiteral("切断: ")},
            {QStringLiteral("Retrying after a USB detection error: "), QStringLiteral("USB 検出エラーのため再試行します: ")},
            {QStringLiteral("Connection not started"), QStringLiteral("接続処理は開始されていません")},
            {QStringLiteral("Disconnecting to apply new video settings. Waiting to reconnect"),
             QStringLiteral("映像設定の変更のため切断しています。再接続を待機します")},
            {QStringLiteral("Playing test video (not via aasdk)"), QStringLiteral("テスト映像を再生中（aasdk 経由ではありません）")},
            // ---- 接続層: 切断理由・エラー ----
            {QStringLiteral("Disconnect requested by the phone (failed to send the response)"),
             QStringLiteral("スマートフォンからの切断要求（応答送信は失敗）")},
            {QStringLiteral("Disconnect requested by the phone"), QStringLiteral("スマートフォンからの切断要求")},
            {QStringLiteral("Received disconnect response"), QStringLiteral("切断応答を受信")},
            {QStringLiteral("Connection setup timed out (the phone is not responding)"),
             QStringLiteral("接続確立がタイムアウトしました（スマートフォンが応答しません）")},
            {QStringLiteral("Stop requested by the app (timed out waiting for the disconnect response)"),
             QStringLiteral("アプリが停止要求を出しました（切断応答の待機がタイムアウト）")},
            {QStringLiteral("Stop requested by the app (ByeBye send failed: "),
             QStringLiteral("アプリが停止要求を出しました（ByeBye 送信失敗: ")},
            {QStringLiteral("No response from the phone (ping timeout)"),
             QStringLiteral("スマートフォンから応答がありません（Ping タイムアウト）")},
            {QStringLiteral("Protocol version mismatch (status="), QStringLiteral("プロトコルバージョンが一致しません (status=")},
            {QStringLiteral("libusb initialization failed: "), QStringLiteral("libusb の初期化に失敗: ")},
            {QStringLiteral("libusb on this system does not support hotplug detection"),
             QStringLiteral("この環境の libusb はホットプラグ検出に対応していません")},
            {QStringLiteral("Built without aasdk (OPENCRUISE_ENABLE_AASDK=OFF)"),
             QStringLiteral("aasdk なしでビルドされています (OPENCRUISE_ENABLE_AASDK=OFF)")},
            {QStringLiteral("USB device initialization failed: "), QStringLiteral("USB デバイスの初期化に失敗: ")},
            {QStringLiteral("Session creation failed: "), QStringLiteral("セッション生成に失敗: ")},
            {QStringLiteral("SSL initialization failed: "), QStringLiteral("SSL 初期化に失敗: ")},
            {QStringLiteral("Failed to start the SSL handshake: "), QStringLiteral("SSL ハンドシェイク開始に失敗: ")},
            {QStringLiteral("SSL handshake failed: "), QStringLiteral("SSL ハンドシェイクに失敗: ")},
            {QStringLiteral("Failed to send the service discovery response: "), QStringLiteral("サービス探索応答の送信に失敗: ")},
            {QStringLiteral("PingRequest send failed: "), QStringLiteral("PingRequest 送信失敗: ")},
            {QStringLiteral("Control channel error: "), QStringLiteral("制御チャネルエラー: ")},
            {QStringLiteral("Control channel send failed "), QStringLiteral("制御チャネル送信失敗")},
            {QStringLiteral("Input channel error: "), QStringLiteral("入力チャネルエラー: ")},
            {QStringLiteral("Input channel send failed "), QStringLiteral("入力チャネル送信失敗")},
            {QStringLiteral("Microphone channel error: "), QStringLiteral("マイクチャネルエラー: ")},
            {QStringLiteral("Microphone channel send failed "), QStringLiteral("マイクチャネル送信失敗")},
            {QStringLiteral("Sensor channel error: "), QStringLiteral("センサーチャネルエラー: ")},
            {QStringLiteral("Sensor channel send failed"), QStringLiteral("センサーチャネル送信失敗")},
            {QStringLiteral("Audio channel error: "), QStringLiteral("音声チャネルエラー: ")},
            {QStringLiteral("Audio channel send failed "), QStringLiteral("音声チャネル送信失敗")},
            {QStringLiteral("Video channel error: "), QStringLiteral("映像チャネルエラー: ")},
            {QStringLiteral("Video channel send failed "), QStringLiteral("映像チャネル送信失敗")},
            // ---- 映像デコーダ・テスト映像 ----
            {QStringLiteral("Video decoder: "), QStringLiteral("映像デコーダ: ")},
            {QStringLiteral("FFmpeg has no H.264 decoder"), QStringLiteral("FFmpeg に H.264 デコーダがありません")},
            {QStringLiteral("FFmpeg memory allocation failed"), QStringLiteral("FFmpeg のメモリ確保に失敗しました")},
            {QStringLiteral("Could not open the H.264 decoder"), QStringLiteral("H.264 デコーダを開けませんでした")},
            {QStringLiteral("Cannot open the test video: "), QStringLiteral("テスト映像を開けません: ")},
            {QStringLiteral("No AUD found. Use an H.264 file encoded by x264 with aud=1"),
             QStringLiteral("AUD が見つかりません。x264 の aud=1 付きで作成した H.264 を指定してください")},
            // ---- 外部モニター(DRM) ----
            {QStringLiteral("QT_QPA_EGLFS_KMS_CONFIG is already set; following it for the screen setup (no mirroring)"),
             QStringLiteral("QT_QPA_EGLFS_KMS_CONFIG が設定済みのため、画面の設定はそちらに従います(ミラーは使いません)")},
            {QStringLiteral("No connected screen found (/sys/class/drm)"), QStringLiteral("つながっている画面が見つかりません(/sys/class/drm)")},
            {QStringLiteral("Cannot create the KMS config file: "), QStringLiteral("KMS 設定ファイルを作れません: ")},
            {QStringLiteral("Cannot read the image of the control screen"), QStringLiteral("操作する画面の画を読めません")},
            {QStringLiteral("Cannot read the screen information"), QStringLiteral("画面の情報を読めません")},
            {QStringLiteral("No free output circuit (CRTC)"), QStringLiteral("空いている出力回路(CRTC)がありません")},
            {QStringLiteral("Cannot start displaying ("), QStringLiteral("表示を始められません(")},
            {QStringLiteral("This GPU cannot scale the image ("), QStringLiteral("この GPU では拡大縮小して表示できません(")},
            {QStringLiteral(" (scaled from "), QStringLiteral("(拡大縮小: ")},
            // ---- マイク ----
            {QStringLiteral("No input device found"), QStringLiteral("入力デバイスが見つかりません")},
            {QStringLiteral("The input device does not support 16 kHz / 16-bit / mono: "),
             QStringLiteral("入力デバイスが 16kHz/16bit/モノラルに対応していません: ")},
            {QStringLiteral("Recording error (code "), QStringLiteral("録音中にエラーが発生しました (コード ")},
            {QStringLiteral("Could not start recording: "), QStringLiteral("録音を開始できませんでした: ")},
        };
        std::sort(t.begin(), t.end(), [](const auto &a, const auto &b) { return a.first.size() > b.first.size(); });
        return t;
    }();
    return kTable;
}

/**
 * @brief 英語のメッセージを画面用の日本語にする(表にある先頭を置き換え、続きも同じように置き換える)。
 */
inline QString toJapanese(const QString &text) {
    if (text.isEmpty()) return text;
    for (const auto &[en, ja] : table()) {
        if (text.startsWith(en)) {
            return ja + toJapanese(text.mid(en.size()));
        }
    }
    // 先頭が表に無い: 1 文字ずつ送って、途中から表の文が始まっていないか探す(例: "(Config): " の後のメッセージ)
    for (int i = 1; i < text.size(); ++i) {
        const QString rest = text.mid(i);
        for (const auto &[en, ja] : table()) {
            if (rest.startsWith(en)) return text.left(i) + ja + toJapanese(rest.mid(en.size()));
        }
    }
    return text;
}

} // namespace opencruise::uitext
