// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <cstdint>
#include <mutex>
class UdpReplySender {
public:
    bool Send(uint16_t localPort, const void *, int, uint32_t ip, uint16_t port);
    void Reset();
private:
    std::mutex mutex_;
    uintptr_t socket_ = ~uintptr_t(0);
};
