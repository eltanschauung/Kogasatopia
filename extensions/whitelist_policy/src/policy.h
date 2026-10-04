// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <array>
#include <cstdint>

namespace whitelist {
constexpr int kDefinitions = 65536;
enum Classification : uint8_t { Wearable = 1, Shield = 2, Sword = 4 };
enum Reason : int { Allowed, ItemDenied, DemoCombination };
struct Definition { uint8_t classification = 0; bool allowed = true; };

inline bool ForbiddenCombination(uint8_t primary, uint8_t secondary, uint8_t melee) {
    return (primary & Wearable) && (secondary & Shield) && (melee & Sword);
}
inline bool Denied(bool initialized, int quality, bool allowed) {
    // Valve exempts AE_NORMAL (0), based on the instance, not schema quality.
    return initialized && quality != 0 && !allowed;
}
inline Reason Decide(bool forbiddenCombination, bool initialized, int quality, bool allowed) {
    if (forbiddenCombination) return DemoCombination;
    return Denied(initialized, quality, allowed) ? ItemDenied : Allowed;
}
struct Transaction {
    unsigned depth = 0;
    bool known = false;
    bool forbidden = false;
    void Begin() { if (depth++ == 0) known = false; }
    void End() { if (depth && --depth == 0) known = false; }
    void Reset() { depth = 0; known = false; forbidden = false; }
};
}
