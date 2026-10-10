// SPDX-License-Identifier: GPL-3.0-or-later
#include "../src/loadout_cache.h"
#include "../src/policy.h"
#include <cstdio>
#include <cstdlib>
using namespace weapons_loadout;
static int checks;
static void Check(bool condition) { ++checks; if (!condition) std::abort(); }
int main() {
    Cache cache;
    auto &slot = cache.slots[1][0];
    Check(!slot.selected && !slot.resolving && slot.reference == kNoEntity);
    Check(!cache.Reusable(slot, true));
    slot.selected = true;
    cache.Store(slot, cache.epoch, 12345, true);
    Check(cache.Reusable(slot, true) && slot.reference == 12345);
    Check(!cache.Reusable(slot, false)); // Never cache a UI lookup's permissions.
    const auto oldEpoch = cache.epoch;
    cache.Invalidate();
    Check(!cache.Reusable(slot, true) && slot.selected);
    cache.Store(slot, oldEpoch, 54321, true);
    Check(!cache.Reusable(slot, true)); // Mutation inside the resolver.
    cache.Store(slot, cache.epoch, kNoEntity, true);
    Check(cache.Reusable(slot, true) && slot.reference == kNoEntity);
    cache.Invalidate(); // Next outer transaction: permissions must be rechecked.
    Check(!cache.Reusable(slot, true));
    const auto epoch = cache.epoch;
    whitelist::Transaction inventory;
    inventory.Begin(); inventory.Begin(); inventory.End();
    Check(inventory.depth == 1 && cache.epoch == epoch);
    const auto beforeReset = cache.epoch;
    cache.Reset(); // Disconnect/recycled client or plugin owner change.
    Check(!cache.slots[1][0].selected && !cache.Reusable(cache.slots[1][0], true));
    Check(cache.epoch != beforeReset);
    for (int playerClass = -1; playerClass <= 11; ++playerClass)
        for (int s = -1; s <= 19; ++s)
            Check(ValidSlot(playerClass, s) == (playerClass >= 1 && playerClass <= 9 && s >= 0 && s < 7));
    std::printf("Weapons native loadout cache: %d checks passed\n", checks);
}
