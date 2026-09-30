// SPDX-License-Identifier: GPL-3.0-or-later
#include "browser_protocol.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
extern "C" {
#include "third_party/siphash/siphash.h"
}
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#else
#include <cerrno>
#include <sys/random.h>
#endif

namespace oblivion_browser {
namespace {
void U32(std::vector<uint8_t> &out, uint32_t value) { for (int i = 0; i < 4; ++i) out.push_back((value >> (i * 8)) & 255); }
uint32_t Read32(const uint8_t *data) {
    return uint32_t(data[0]) | (uint32_t(data[1]) << 8) | (uint32_t(data[2]) << 16) | (uint32_t(data[3]) << 24);
}
double Now() { return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count(); }
bool Spend(double &tokens, double &last, double now, double rate, double burst) {
    tokens = std::min(burst, tokens + std::max(0.0, now - last) * rate); last = now;
    if (tokens < 1) return false;
    tokens -= 1; return true;
}
}

bool ParseIpv4(const char *text, uint32_t &ip) {
    ip = 0;
    if (!text || !*text) return false;
    const char *p = text;
    for (int part = 0; part < 4; ++part) {
        unsigned value = 0, digits = 0;
        while (*p >= '0' && *p <= '9') {
            value = value * 10 + unsigned(*p++ - '0');
            if (++digits > 3 || value > 255) return false;
        }
        if (!digits || (part < 3 ? *p != '.' : *p != '\0')) return false;
        ip = (ip << 8) | value;
        if (part < 3) ++p;
    }
    return ip != 0;
}

void Snapshot::Index() {
    byIp.clear();
    Mask present;
    for (size_t i = 1; i <= MaxPlayers; ++i) if (players[i].present) present.set(i);
    for (const auto &entry : addressRules) {
        const Mask mask = entry.second & present;
        if (entry.first && mask.any()) byIp[entry.first] |= mask;
    }
    for (size_t i = 1; i <= MaxPlayers; ++i) {
        if (!players[i].present || !players[i].viewerIp) continue;
        const Mask mask = hidden[i] & present;
        if (mask.any()) byIp[players[i].viewerIp] |= mask;
    }
}
Mask Snapshot::Hidden(uint32_t ip) const {
    auto found = byIp.find(ip); return found == byIp.end() ? Mask{} : found->second;
}

std::vector<uint8_t> PlayerReply(const Snapshot &snapshot, uint32_t ip, uint32_t &omitted) {
    const Mask hidden = snapshot.Hidden(ip);
    std::vector<uint8_t> result{255,255,255,255,0x44,0};
    uint8_t index = 0; omitted = 0;
    for (size_t slot = 1; slot <= MaxPlayers; ++slot) {
        const auto &player = snapshot.players[slot];
        if (!player.present) continue;
        if (hidden.test(slot)) { ++omitted; continue; }
        result.push_back(index++);
        result.insert(result.end(), player.name.begin(), player.name.end()); result.push_back(0);
        U32(result, static_cast<uint32_t>(player.score));
        float seconds = std::isfinite(player.seconds) ? std::max(0.0f, player.seconds) : 0;
        uint32_t bits; std::memcpy(&bits, &seconds, 4); U32(result, bits);
    }
    result[5] = index;
    return result;
}

bool AdjustInfo(uint8_t *data, size_t size, const Snapshot &snapshot, uint32_t ip) {
    if (size < 6 || Read32(data) != 0xffffffff || data[4] != 0x49) return false;
    const Mask hidden = snapshot.Hidden(ip);
    if (!hidden.any()) return false;
    size_t pos = 6; // Protocol byte, then name/map/folder/game strings.
    for (int i = 0; i < 4; ++i) {
        while (pos < size && data[pos]) ++pos;
        if (pos == size) return false;
        ++pos;
    }
    if (size - pos < 5) return false;
    pos += 2; // AppID; counts are Players, MaxPlayers, Bots.
    unsigned players = 0, bots = 0;
    for (size_t i = 1; i <= MaxPlayers; ++i) if (hidden.test(i) && snapshot.players[i].present) {
        ++players; if (snapshot.players[i].bot) ++bots;
    }
    data[pos] = static_cast<uint8_t>(players >= data[pos] ? 0 : data[pos] - players);
    data[pos + 2] = static_cast<uint8_t>(bots >= data[pos + 2] ? 0 : data[pos + 2] - bots);
    return players != 0;
}

bool Service::Initialize() {
#ifdef _WIN32
    auto module = GetModuleHandleA("advapi32.dll");
    const bool ownedModule = !module;
    if (!module) module = LoadLibraryExW(L"advapi32.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    auto random = module ? reinterpret_cast<BOOLEAN (WINAPI *)(PVOID, ULONG)>(GetProcAddress(module, "SystemFunction036")) : nullptr;
    const bool initialized = random && random(key_.data(), static_cast<ULONG>(key_.size()));
    if (ownedModule && module) FreeLibrary(module);
    if (!initialized) return false;
#else
    size_t offset = 0;
    while (offset < key_.size()) {
        ssize_t count = getrandom(key_.data() + offset, key_.size() - offset, 0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return false;
        offset += static_cast<size_t>(count);
    }
#endif
    return true;
}

void Service::Publish(std::shared_ptr<Snapshot> snapshot) {
    snapshot->Index();
    const bool enabled = snapshot->enabled;
    std::shared_ptr<const Snapshot> immutable = std::move(snapshot);
    std::atomic_store(&current_, std::move(immutable));
    if (!enabled) { std::lock_guard<std::mutex> lock(mutex_); outgoing_.clear(); }
}
void Service::Clear() { Publish(std::make_shared<Snapshot>()); }
size_t Service::AddressCount() const {
    auto snapshot = std::atomic_load(&current_); return snapshot && snapshot->enabled ? snapshot->byIp.size() : 0;
}
uint16_t Service::QueryPort() const {
    auto snapshot = std::atomic_load(&current_); return snapshot ? snapshot->queryPort : 0;
}

uint32_t Service::Cookie(uint32_t ip, uint16_t port, uint64_t minute) const {
    uint8_t input[15], result[8];
    for (int i = 0; i < 4; ++i) input[i] = (ip >> (i * 8)) & 255;
    input[4] = port & 255; input[5] = port >> 8;
    for (int i = 0; i < 8; ++i) input[6 + i] = (minute >> (i * 8)) & 255;
    input[14] = 0x55;
    siphash(input, sizeof(input), key_.data(), result, sizeof(result));
    uint32_t token = Read32(result);
    return token == 0 || token == 0xffffffff ? token ^ 0x6f626c76 : token;
}

bool Service::Allow(uint32_t ip, double now) {
    if (!Spend(global_.tokens, global_.time, now, 512, 1024)) return false;
    if (limits_.size() >= 4096) {
        for (auto it = limits_.begin(); it != limits_.end();) {
            if (now - it->second.time > 60) it = limits_.erase(it); else ++it;
        }
        if (limits_.size() >= 4096 && !limits_.count(ip)) return false;
    }
    auto &bucket = limits_[ip];
    return Spend(bucket.tokens, bucket.time, now, 16, 32);
}

bool Service::Incoming(const void *raw, int size, uint32_t ip, uint16_t port) {
    if (!raw || size < 5) return false;
    const auto *data = static_cast<const uint8_t *>(raw);
    if (Read32(data) != 0xffffffff || data[4] != 0x55) return false;
    auto snapshot = std::atomic_load(&current_);
    if (!snapshot || !snapshot->enabled) return false;
    ++stats.requests;
    if ((size != 5 && size != 9) || !ip || !port) return true;
    const double now = Now();
    std::lock_guard<std::mutex> lock(mutex_);
    if (!Allow(ip, now) || outgoing_.size() > 992) { ++stats.limited; return true; }
    const uint64_t minute = static_cast<uint64_t>(now / 60);
    const uint32_t token = size == 9 ? Read32(data + 5) : 0;
    if (token != Cookie(ip, port, minute) && (!minute || token != Cookie(ip, port, minute - 1))) {
        std::vector<uint8_t> challenge{255,255,255,255,0x41}; U32(challenge, Cookie(ip, port, minute));
        outgoing_.push_back({ip, port, std::move(challenge), std::chrono::steady_clock::now()});
        ++stats.challenges; return true;
    }
    uint32_t removed;
    // Queue one Steam query datagram. The hook sends it through the existing
    // game socket, avoiding NET_SendPacket's incompatible Source split framing.
    // 101 slots * (127 name bytes + 10 record bytes) + 6 header bytes = 13,843,
    // safely below the API's documented 16 KiB outgoing buffer size.
    auto reply = PlayerReply(*snapshot, ip, removed);
    outgoing_.push_back({ip, port, std::move(reply), std::chrono::steady_clock::now()});
    ++stats.lists;
    if (removed) { ++stats.filtered; stats.rows += removed; }
    return true;
}

int Service::Outgoing(void *data, int maxSize, uint32_t *ip, uint16_t *port) {
    if (!data || maxSize < 1 || !ip || !port) return 0;
    std::lock_guard<std::mutex> lock(mutex_);
    while (!outgoing_.empty()) {
        Packet packet = std::move(outgoing_.front()); outgoing_.pop_front();
        if (std::chrono::steady_clock::now() - packet.created > std::chrono::seconds(3)
            || packet.bytes.size() > static_cast<size_t>(maxSize)) continue;
        std::memcpy(data, packet.bytes.data(), packet.bytes.size());
        *ip = packet.ip; *port = packet.port;
        return static_cast<int>(packet.bytes.size());
    }
    return 0;
}
bool Service::FilterInfo(void *data, int size, uint32_t ip) {
    auto snapshot = std::atomic_load(&current_);
    if (size <= 0 || !snapshot || !snapshot->enabled) return false;
    if (!AdjustInfo(static_cast<uint8_t *>(data), size, *snapshot, ip)) return false;
    ++stats.infos; return true;
}
} // namespace oblivion_browser
