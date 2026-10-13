// SPDX-License-Identifier: GPL-3.0-or-later
#include "pending_pairs.h"
#include "shared_client_cache.h"
#include <cassert>
#include <cstdio>
#include <set>

int main() {
    weapons_ext::PendingPairs<64> pairs;
    assert(!pairs.Add(0, 1));
    assert(!pairs.Add(65, 1));
    assert(pairs.Count() == 0);
    for (int attacker = 1; attacker <= 64; ++attacker)
        for (int victim = 1; victim <= 64; ++victim) {
            assert(pairs.Add(attacker, victim));
            assert(!pairs.Add(attacker, victim));
        }
    assert(pairs.Count() == 4096);
    std::set<int> seen;
    int attacker, victim;
    while (pairs.Pop(attacker, victim)) seen.insert(attacker * 65 + victim);
    assert(seen.size() == 4096 && !pairs.Pop(attacker, victim));
    for (int round = 0; round < 100; ++round) {
        assert(pairs.Add(1, 2));
        assert(pairs.Add(2, 1));
        size_t batch = pairs.Count();
        for (size_t i = 0; i < batch; ++i) {
            assert(pairs.Pop(attacker, victim));
            if (i == 0) assert(pairs.Add(attacker, victim)); // Reentrant same pair.
        }
        assert(pairs.Count() == 1);
        assert(pairs.Pop(attacker, victim));
    }
    pairs.Add(3, 4); pairs.Reset(); assert(!pairs.Count());

    weapons_ext::SharedClientCache<64> clients;
    auto pointer = [](int index) { return reinterpret_cast<void *>(uintptr_t(0x100000 + index * 8192)); };
    assert(!clients.Put(nullptr, 1) && !clients.Put(pointer(1), 0));
    for (int i = 1; i <= 64; ++i) assert(clients.Put(pointer(i), i));
    for (int i = 1; i <= 64; ++i) assert(clients.Find(pointer(i)) == i);
    assert(!clients.Find(pointer(70)) && !clients.Find(nullptr));
    for (int i = 1; i <= 64; i += 2) clients.Remove(i);
    for (int i = 1; i <= 64; ++i) assert(clients.Find(pointer(i)) == (i % 2 ? 0 : i));
    for (int i = 1; i <= 64; i += 2) assert(clients.Put(pointer(i + 100), i));
    for (int i = 1; i <= 64; ++i) assert(clients.Find(pointer(i % 2 ? i + 100 : i)) == i);
    for (int i = 1; i <= 64; ++i) clients.Remove(i);
    for (int i = 1; i <= 64; ++i) assert(!clients.Find(pointer(i)));
    std::puts("hot-path queue/cache tests passed (exhaustive pairs, dedup, wraparound, reentrancy, disconnect and reuse)");
}
