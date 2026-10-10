// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <array>
#include <cstdint>

namespace weapons_loadout {
constexpr int kClasses = 10;
constexpr int kSlots = 7;
constexpr int kNoEntity = -1;
inline bool ValidSlot(int playerClass, int slot) {
    return playerClass > 0 && playerClass < kClasses && slot >= 0 && slot < kSlots;
}
struct Slot {
    bool selected = false;
    bool resolving = false;
    bool placeholder = false;
    uint64_t epoch = 0;
    int reference = kNoEntity;
};
struct Cache {
    uint64_t epoch = 1;
    std::array<std::array<Slot, kSlots>, kClasses> slots{};
    void Invalidate() { ++epoch; }
    void Reset() { Invalidate(); slots = {}; }
    bool Reusable(const Slot &slot, bool inInventory) const {
        return inInventory && slot.epoch == epoch;
    }
    // A resolver can re-enter Weapons and invalidate its own selection. Never
    // publish its old result into the new revision/session/transaction.
    void Store(Slot &slot, uint64_t started, int reference, bool inInventory) {
        if (inInventory && started == epoch) {
            slot.reference = reference;
            slot.epoch = epoch;
        }
    }
};
}
