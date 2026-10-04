// SPDX-License-Identifier: GPL-3.0-or-later
#include "../src/policy.h"
#include <cstdio>
#include <cstdlib>
using namespace whitelist;
static int checks;
static void Check(bool condition) { ++checks; if (!condition) std::abort(); }
int main() {
    for (int primary = 0; primary < 8; ++primary)
        for (int secondary = 0; secondary < 8; ++secondary)
            for (int melee = 0; melee < 8; ++melee)
                Check(ForbiddenCombination(primary, secondary, melee)
                    == ((primary & Wearable) != 0 && (secondary & Shield) != 0 && (melee & Sword) != 0));
    for (int quality = 0; quality < 16; ++quality) {
        Check(!Denied(false, quality, false));
        Check(!Denied(true, quality, true));
        Check(Denied(true, quality, false) == (quality != 0));
    }
    Check(!ForbiddenCombination(Wearable, 0, Sword));
    Check(!ForbiddenCombination(0, Shield, Sword));
    Check(!ForbiddenCombination(Wearable, Shield, 0));
    Check(Decide(true, true, 0, true) == DemoCombination);
    Check(Decide(true, true, 6, false) == DemoCombination);
    Check(Decide(false, true, 0, false) == Allowed);
    Check(Decide(false, true, 6, false) == ItemDenied);
    Check(Decide(false, true, 6, true) == Allowed);
    Check(Decide(false, false, 6, false) == Allowed);
    Transaction transaction;
    Check(transaction.depth == 0 && !transaction.known);
    transaction.Begin();
    transaction.known = true; transaction.forbidden = true;
    transaction.Begin();
    Check(transaction.depth == 2 && transaction.known);
    transaction.End();
    Check(transaction.depth == 1 && transaction.known);
    transaction.End();
    Check(transaction.depth == 0 && !transaction.known);
    transaction.Begin();
    Check(!transaction.known);
    transaction.Reset();
    Check(transaction.depth == 0 && !transaction.known && !transaction.forbidden);
    transaction.End();
    Check(transaction.depth == 0);
    std::printf("Whitelist policy: %d checks passed\n", checks);
}
