/**
 * @file TouchTracker.h
 * @brief 触れている指を追跡し、Android Auto 向けの TouchEvent を組み立てる（Qt 非依存）。
 *
 * 入力デバイス(Qt のタッチ/マウス)ごとの指の識別子と、Android の MotionEvent 形式
 * (Down / PointerDown / Move / PointerUp / Up と、触れているすべての指の一覧)との橋渡しをする。
 * UI スレッドからのみ使うこと（スレッドセーフではない）。
 *
 * 使い方: 1 回の入力イベントの中では「move() を必要な指すべてに → press() / release()」の順に呼ぶ。
 * move() は状態を更新するだけで、まとめて 1 回の Move として送るのは flush()。
 * press() / release() は呼ばれた時点で未送信の Move を先に送る。
 */
#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <utility>
#include <vector>

#include "TouchEvent.h"

namespace opencruise {

class TouchTracker {
public:
    /// 同時に追跡できる指の最大数。超える指は無視する
    static constexpr std::size_t kMaxPointers = 10;

    using Sink = std::function<void(const aa::TouchEvent &)>;

    /**
     * @brief 送信先を設定する。nullptr でも構わない（その場合イベントは捨てる）。
     */
    void setSink(Sink sink) { sink_ = std::move(sink); }

    /**
     * @brief 指が触れた。
     * @param sourceId 入力デバイス側の指の識別子（触れている間は同じ値。マウスには別の値を使う）
     * @param x,y Android Auto のタッチ座標系での位置
     * @return 追跡を開始できたら true。すでに追跡中の識別子は位置の更新として扱い true。
     *         同時に追跡できる数を超えた場合は false
     */
    bool press(int sourceId, int x, int y) {
        flush();
        if (Pointer *existing = find(sourceId)) {
            existing->x = x;
            existing->y = y;
            dirty_ = true;
            return true;
        }
        if (pointers_.size() >= kMaxPointers) {
            return false;
        }
        Pointer pointer;
        pointer.sourceId = sourceId;
        pointer.slot = lowestFreeSlot();
        pointer.x = x;
        pointer.y = y;
        pointers_.push_back(pointer);
        dispatch(pointers_.size() == 1 ? aa::TouchAction::Down : aa::TouchAction::PointerDown,
             pointers_.size() - 1);
        return true;
    }

    /**
     * @brief 指が動いた。位置を更新するだけで、送信は flush() / press() / release() の時に行う。
     *        追跡していない識別子は無視する。
     */
    void move(int sourceId, int x, int y) {
        Pointer *pointer = find(sourceId);
        if (pointer == nullptr) {
            return;
        }
        if (pointer->x != x || pointer->y != y) {
            pointer->x = x;
            pointer->y = y;
            dirty_ = true;
        }
    }

    /**
     * @brief 位置が変わった指があれば、触れているすべての指をまとめて 1 回の Move として送る。
     */
    void flush() {
        if (!dirty_) {
            return;
        }
        dirty_ = false;
        if (!pointers_.empty()) {
            dispatch(aa::TouchAction::Move, 0);
        }
    }

    /**
     * @brief 指が離れた。離れる指も、最後の位置で一覧に含めて送る。
     *        追跡していない識別子は無視する。
     */
    void release(int sourceId, int x, int y) {
        flush();
        Pointer *pointer = find(sourceId);
        if (pointer == nullptr) {
            return;
        }
        pointer->x = x;
        pointer->y = y;
        const std::size_t index = static_cast<std::size_t>(pointer - pointers_.data());
        dispatch(pointers_.size() == 1 ? aa::TouchAction::Up : aa::TouchAction::PointerUp, index);
        pointers_.erase(pointers_.begin() + static_cast<std::ptrdiff_t>(index));
    }

    /**
     * @brief 指 1 本を、最後に分かっている位置で離したことにして送る（入力が途中で取り消された場合用）。
     *        追跡していない識別子は無視する。
     */
    void cancel(int sourceId) {
        if (const Pointer *pointer = find(sourceId)) {
            release(sourceId, pointer->x, pointer->y);
        }
    }

    /**
     * @brief 追跡中のすべての指を、最後の位置で離したことにして送る（スマートフォン側に
     *        「触れたまま」の状態を残さないため）。何も触れていなければ何もしない。
     */
    void releaseAll() {
        flush();
        while (!pointers_.empty()) {
            const Pointer last = pointers_.back();
            release(last.sourceId, last.x, last.y);
        }
    }

    /** @brief 追跡中の指か。 */
    bool isActive(int sourceId) const { return find(sourceId) != nullptr; }

    /** @brief 触れている指があるか。 */
    bool hasActive() const { return !pointers_.empty(); }

private:
    struct Pointer {
        int sourceId = 0;
        std::uint32_t slot = 0; ///< スマートフォンへ送る pointer_id。触れている間は変わらない
        int x = 0;
        int y = 0;
    };

    Pointer *find(int sourceId) {
        for (Pointer &pointer : pointers_) {
            if (pointer.sourceId == sourceId) {
                return &pointer;
            }
        }
        return nullptr;
    }
    const Pointer *find(int sourceId) const {
        for (const Pointer &pointer : pointers_) {
            if (pointer.sourceId == sourceId) {
                return &pointer;
            }
        }
        return nullptr;
    }

    /// 使われていない最小の番号。Qt のタッチ ID は大きくなりうるので、小さい番号に振り直して送る
    std::uint32_t lowestFreeSlot() const {
        for (std::uint32_t slot = 0;; ++slot) {
            const bool used = std::any_of(pointers_.begin(), pointers_.end(),
                                          [slot](const Pointer &p) { return p.slot == slot; });
            if (!used) {
                return slot;
            }
        }
    }

    void dispatch(aa::TouchAction action, std::size_t actionIndex) {
        if (!sink_) {
            return;
        }
        aa::TouchEvent event;
        event.action = action;
        event.actionIndex = static_cast<std::uint32_t>(actionIndex);
        event.points.reserve(pointers_.size());
        for (const Pointer &pointer : pointers_) {
            event.points.push_back({pointer.slot, pointer.x, pointer.y});
        }
        sink_(event);
    }

    std::vector<Pointer> pointers_; ///< 触れている指（触れた順）
    bool dirty_ = false;            ///< 未送信の位置変化がある
    Sink sink_;
};

} // namespace opencruise
