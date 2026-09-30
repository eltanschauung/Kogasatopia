// SPDX-License-Identifier: GPL-3.0-or-later
#include "udp_reply_sender.h"
#include <cstdlib>
#include <vector>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
using NativeSocket = SOCKET;
using AddressSize = int;
constexpr NativeSocket NoSocket = INVALID_SOCKET;
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <dirent.h>
using NativeSocket = int;
using AddressSize = socklen_t;
constexpr NativeSocket NoSocket = -1;
#endif

namespace {
bool Matches(NativeSocket socket, uint16_t port) {
    int type = 0; AddressSize size = sizeof(type);
    if (getsockopt(socket, SOL_SOCKET, SO_TYPE, reinterpret_cast<char *>(&type), &size) != 0 || type != SOCK_DGRAM) return false;
    sockaddr_storage address{}; size = sizeof(address);
    if (getsockname(socket, reinterpret_cast<sockaddr *>(&address), &size) != 0 || address.ss_family != AF_INET) return false;
    return ntohs(reinterpret_cast<sockaddr_in *>(&address)->sin_port) == port;
}
NativeSocket FindSocket(uint16_t port) {
#ifdef _WIN32
    // Enumerate handles of this SRCDS process only. Do not open or inspect any
    // other process. SOCKET handles are borrowed, never closed by this module.
    struct Entry { HANDLE handle; ULONG_PTR handles, pointers; ULONG access, type, attributes, reserved; };
    struct Snapshot { ULONG_PTR count, reserved; Entry entries[1]; };
    using Query = LONG (NTAPI *)(HANDLE, ULONG, PVOID, ULONG, PULONG);
    auto query = reinterpret_cast<Query>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "NtQueryInformationProcess"));
    if (!query) return NoSocket;
    std::vector<uint8_t> buffer(65536);
    for (int attempt = 0; attempt < 6; ++attempt) {
        ULONG needed = 0;
        LONG status = query(GetCurrentProcess(), 51 /* ProcessHandleInformation */, buffer.data(), static_cast<ULONG>(buffer.size()), &needed);
        if (status >= 0) {
            const auto *snapshot = reinterpret_cast<const Snapshot *>(buffer.data());
            const size_t maximum = (buffer.size() - offsetof(Snapshot, entries)) / sizeof(Entry);
            if (snapshot->count > maximum) return NoSocket;
            for (size_t i = 0; i < snapshot->count; ++i) {
                auto socket = reinterpret_cast<SOCKET>(snapshot->entries[i].handle);
                if (Matches(socket, port)) return socket;
            }
            return NoSocket;
        }
        if (static_cast<ULONG>(status) != 0xc0000004 && static_cast<ULONG>(status) != 0xc0000023) return NoSocket;
        const size_t next = needed > buffer.size() ? needed + 4096 : buffer.size() * 2;
        if (next > 16 * 1024 * 1024) return NoSocket;
        buffer.resize(next);
    }
#else
    DIR *directory = opendir("/proc/self/fd");
    if (!directory) return NoSocket;
    NativeSocket found = NoSocket;
    while (dirent *entry = readdir(directory)) {
        char *end = nullptr; long fd = std::strtol(entry->d_name, &end, 10);
        if (!entry->d_name[0] || *end || fd < 0 || fd > 0x7fffffff) continue;
        if (Matches(static_cast<int>(fd), port)) { found = static_cast<int>(fd); break; }
    }
    closedir(directory);
    return found;
#endif
    return NoSocket;
}
}

void UdpReplySender::Reset() { std::lock_guard<std::mutex> lock(mutex_); socket_ = ~uintptr_t(0); }
bool UdpReplySender::Send(uint16_t localPort, const void *data, int size, uint32_t ip, uint16_t port) {
    if (!localPort || !data || size < 1 || size > 16384) return false;
    std::lock_guard<std::mutex> lock(mutex_);
    auto socket = static_cast<NativeSocket>(socket_);
    if (!Matches(socket, localPort)) {
        socket = FindSocket(localPort);
        socket_ = static_cast<uintptr_t>(socket);
    }
    if (socket == NoSocket) return false;
    sockaddr_in destination{};
    destination.sin_family = AF_INET; destination.sin_port = htons(port); destination.sin_addr.s_addr = htonl(ip);
    // Let IP fragment a large browser datagram, rather than adding Source's
    // application split header (which Steam's player-query API rejects).
    // Restore the engine socket option immediately after this send.
    int previous = 0; AddressSize optionSize = sizeof(previous); bool changed = false;
#ifdef _WIN32
    constexpr int option = IP_DONTFRAGMENT, desired = 0;
#else
    constexpr int option = IP_MTU_DISCOVER, desired = IP_PMTUDISC_DONT;
#endif
    if (size > 1000 && getsockopt(socket, IPPROTO_IP, option, reinterpret_cast<char *>(&previous), &optionSize) == 0 && previous != desired)
        changed = setsockopt(socket, IPPROTO_IP, option, reinterpret_cast<const char *>(&desired), sizeof(desired)) == 0;
    int sent = static_cast<int>(sendto(socket, static_cast<const char *>(data), size, 0,
                                    reinterpret_cast<sockaddr *>(&destination), sizeof(destination)));
    if (changed) setsockopt(socket, IPPROTO_IP, option, reinterpret_cast<const char *>(&previous), sizeof(previous));
    return sent == size;
}
