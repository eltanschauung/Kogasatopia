// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <array>
#include <cstddef>
#include <cstdint>

namespace weapons_ext {
// Exact CTFPlayerShared pointer lookup; no hot-path allocation or client scan.
// Entries are published on put-in-server and retired before disconnect.
template <size_t MaxClients> class SharedClientCache {
    static constexpr size_t Capacity = 512;
    static_assert(MaxClients < Capacity / 2, "Keep the lookup table sparsely populated");
    struct Entry { uintptr_t key = 0; int client = 0; };
    std::array<Entry, Capacity> entries_{};
    static size_t Hash(uintptr_t key) { return (key >> 4 ^ key >> 13) & (Capacity - 1); }
public:
    void Remove(int client) {
        if (client < 1 || client > int(MaxClients)) return;
        for (auto &entry : entries_) if (entry.client == client) entry = {1, 0};
    }
    bool Put(const void *shared, int client) {
        auto key = reinterpret_cast<uintptr_t>(shared);
        if (key <= 1 || client < 1 || client > int(MaxClients)) return false;
        Remove(client);
        size_t vacant = Capacity;
        for (size_t n = 0, at = Hash(key); n < Capacity; ++n, at = (at + 1) & (Capacity - 1)) {
            auto &entry = entries_[at];
            if (entry.key == key) {
                entry = {key, client};
                return true;
            }
            if (entry.key <= 1 && vacant == Capacity) vacant = at;
            if (!entry.key) break;
        }
        if (vacant != Capacity) { entries_[vacant] = {key, client}; return true; }
        return false;
    }
    int Find(const void *shared) const {
        auto key = reinterpret_cast<uintptr_t>(shared);
        if (key <= 1) return 0;
        for (size_t n = 0, at = Hash(key); n < Capacity; ++n, at = (at + 1) & (Capacity - 1)) {
            const auto &entry = entries_[at];
            if (entry.key == key) return entry.client;
            if (!entry.key) return 0;
        }
        return 0;
    }
};
}
