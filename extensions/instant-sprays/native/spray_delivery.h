// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <algorithm>
#include <utility>
#include <vector>

namespace spray_delivery {
// A placement can be re-sent once per viewer by moderation plugins. Retain
// the union of those accepted recipients, using connection serials throughout.
struct Audience {
    std::vector<std::pair<int,unsigned>> members;
    void Add(int client,unsigned serial) {
        if(client<1||!serial)return;
        for(auto &member:members)if(member.first==client){member.second=serial;return;}
        members.emplace_back(client,serial);
        std::sort(members.begin(),members.end());
    }
    bool Contains(int client,unsigned serial) const {
        for(auto member:members)if(member.first==client&&member.second==serial)return true;
        return false;
    }
    void Merge(const Audience &other) {
        for(auto member:other.members)Add(member.first,member.second);
    }
};
}
