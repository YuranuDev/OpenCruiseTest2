/**
 * @file PhoneInfo.h
 * @brief スマートフォンから届く情報の、Qt に依存しない受け渡し用の値(接続層 → UI)。
 */
#pragma once

#include <string>

namespace opencruise::aa {

/// 通話 1 件。state は PhoneStatus.State の値(0=不明 1=通話中 2=保留 3=待機 4=着信 5=会議 6=ミュート)
struct PhoneCallInfo {
    int state = 0;
    int durationSec = 0;
    std::string name;   ///< 発信者名(caller_id)。無ければ空
    std::string number; ///< 電話番号(caller_number)。無ければ空
};

/// スマホの汎用通知 1 件。プロトコル上、送信元アプリ名・本文は無い
struct PhoneNoticeInfo {
    std::string id;
    std::string text;
};

/// 再生中の曲(メタデータ)。長さが不明なら durationSec は 0
struct MediaTrackInfo {
    std::string song;
    std::string artist;
    std::string album;
    int durationSec = 0;
};

/// 再生状態。state は 1=停止 2=再生中 3=一時停止。positionSec が不明なら 0
struct MediaPlaybackInfo {
    int state = 1;
    std::string source; ///< 再生元アプリ名
    int positionSec = 0;
};

} // namespace opencruise::aa
