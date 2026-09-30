// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <array>
#include <atomic>
#include <bitset>
#include <chrono>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace oblivion_browser {
constexpr size_t MaxPlayers = 101; // SourceMod's TF2 player-slot limit.
constexpr size_t MaxNameBytes = 127;

struct Player {
    bool present = false;
    bool bot = false;
    uint32_t viewerIp = 0; // Only set for an authenticated live connection.
    std::string name;
    int32_t score = 0;
    float seconds = 0;
};
using Mask = std::bitset<MaxPlayers + 1>;
struct Snapshot {
    bool enabled = false;
    uint16_t queryPort = 27015;
    std::array<Player, MaxPlayers + 1> players;
    std::array<Mask, MaxPlayers + 1> hidden;
    // Rules for authenticated identities whose viewer may be disconnected.
    // The publisher resolves SteamIDs to current subject slots every snapshot.
    std::unordered_map<uint32_t, Mask> addressRules;
    std::unordered_map<uint32_t, Mask> byIp;
    void Index();
    Mask Hidden(uint32_t ip) const;
};
struct Packet {
    uint32_t ip;
    uint16_t port;
    std::vector<uint8_t> bytes;
    std::chrono::steady_clock::time_point created;
};
struct Stats {
    std::atomic<uint32_t> requests{0}, challenges{0}, lists{0}, filtered{0}, rows{0}, infos{0}, limited{0};
};

bool ParseIpv4(const char *text, uint32_t &ip);
std::vector<uint8_t> PlayerReply(const Snapshot &, uint32_t ip, uint32_t &omitted);
bool AdjustInfo(uint8_t *data, size_t size, const Snapshot &, uint32_t ip);

class Service {
public:
    bool Initialize();
    void Publish(std::shared_ptr<Snapshot>);
    void Clear();
    // true means this A2S_PLAYER packet was handled (including a bounded drop).
    bool Incoming(const void *data, int size, uint32_t ip, uint16_t port);
    int Outgoing(void *data, int maxSize, uint32_t *ip, uint16_t *port);
    bool FilterInfo(void *data, int size, uint32_t ip);
    size_t AddressCount() const;
    uint16_t QueryPort() const;
    Stats stats;
private:
    struct Bucket { double tokens = 16; double time = 0; };
    std::shared_ptr<const Snapshot> current_;
    std::array<uint8_t, 16> key_{};
    mutable std::mutex mutex_;
    std::deque<Packet> outgoing_;
    std::unordered_map<uint32_t, Bucket> limits_;
    Bucket global_{1024, 0};
    uint32_t Cookie(uint32_t ip, uint16_t port, uint64_t minute) const;
    bool Allow(uint32_t ip, double now);
};
} // namespace oblivion_browser
