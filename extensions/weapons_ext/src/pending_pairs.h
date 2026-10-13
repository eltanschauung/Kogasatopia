// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <array>
#include <cstddef>
#include <cstdint>

namespace weapons_ext {
// Fixed-capacity deduplicated FIFO: zero allocations, O(pending pairs) work.
// A frame processes only its initial Count(), leaving reentrant work queued.
template <size_t MaxClients> class PendingPairs {
    static constexpr size_t Width = MaxClients + 1;
    static constexpr size_t Capacity = Width * Width;
    std::array<uint32_t, Capacity> queue_{};
    std::array<bool, Capacity> queued_{};
    size_t head_ = 0, tail_ = 0, count_ = 0;
public:
    bool Add(int attacker, int victim) {
        if (attacker < 1 || victim < 1 || attacker > int(MaxClients) || victim > int(MaxClients)) return false;
        size_t key = size_t(attacker) * Width + size_t(victim);
        if (queued_[key]) return false;
        queued_[key] = true;
        queue_[tail_] = uint32_t(key);
        tail_ = (tail_ + 1) % Capacity;
        ++count_;
        return true;
    }
    bool Pop(int &attacker, int &victim) {
        if (!count_) return false;
        const size_t key = queue_[head_];
        head_ = (head_ + 1) % Capacity;
        --count_;
        queued_[key] = false;
        attacker = int(key / Width);
        victim = int(key % Width);
        return true;
    }
    size_t Count() const { return count_; }
    void Reset() { head_ = tail_ = count_ = 0; queued_.fill(false); }
};
}
