/**
 * @file PhoneInfo.h
 * @brief スマートフォンから届く情報の、Qt に依存しない受け渡し用の値(接続層 → UI)。
 */
#pragma once

#include <string>
#include <vector>

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
    std::string albumArt; ///< ジャケット画像のデータ(JPEG / PNG など。届かなければ空)
};

/// 再生状態。state は 1=停止 2=再生中 3=一時停止。positionSec が不明なら 0
struct MediaPlaybackInfo {
    int state = 1;
    std::string source; ///< 再生元アプリ名
    int positionSec = 0;
};

/// 車線 1 本の中の 1 方向。shape は NavigationLane.LaneDirection.Shape の値
/// (0=不明 1=直進 2=やや左 3=やや右 4=左 5=右 6=急左 7=急右 8=左Uターン 9=右Uターン)
struct NavigationLaneDirectionInfo {
    int shape = 0;
    bool highlighted = false; ///< 進むべき方向として強調する
};

/// 車線 1 本(複数の方向を持つことがある)
struct NavigationLaneInfo {
    std::vector<NavigationLaneDirectionInfo> directions;
};

/// 目的地 1 か所。住所は NavigationState、距離・時刻は NavigationCurrentPosition から届く(並び順で対応づける)
struct NavigationDestinationInfo {
    std::string address;
    int distanceMeters = -1;   ///< 残り距離。不明なら -1
    std::string distanceLabel; ///< 表示用の距離(単位を含まない数値の文字列)
    int distanceUnit = 0;      ///< NavigationDistance.DistanceUnits の値(0=不明 1=m 2=km 3=km(小数1桁) 4=mile 5=mile(小数1桁) 6=ft 7=yd)
    std::string eta;           ///< 到着予定時刻(表示用の文字列)
    long long secondsToArrival = -1; ///< 到着までの秒数。不明なら -1
};

/// Android Auto ナビゲーションの現在の案内と距離
struct NavigationInfo {
    int status = 0; // 0=unavailable, 1=active, 2=inactive, 3=rerouting
    int maneuver = 0;
    int side = 0;
    int distanceMeters = -1;
    std::string distanceLabel;
    int distanceUnit = 0;             ///< 次の操作までの距離の単位(NavigationDistance.DistanceUnits の値)
    long long timeToStepSeconds = -1; ///< 次の操作までの秒数。不明なら -1
    std::string road;
    std::string currentRoad;          ///< 今走っている道路名(NavigationCurrentPosition.current_road)
    int roundaboutExitNumber = 0;     ///< 次の操作がロータリーのときの出口番号(無ければ 0)
    int roundaboutExitAngle = 0;      ///< 同じく出口の角度(無ければ 0)
    std::string cue;                  ///< 次の操作の読み上げ用テキスト(cue.alternate_text の先頭。無ければ空)
    std::vector<NavigationLaneInfo> lanes; ///< 次の操作の車線案内(無ければ空)
    int nextManeuver = 0;
    int nextSide = 0;
    std::string nextRoad;
    std::vector<NavigationDestinationInfo> destinations; ///< 目的地(経由地を含む)。無ければ空
};

} // namespace opencruise::aa
