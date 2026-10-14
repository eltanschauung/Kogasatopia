// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "modules.h"
#include <IGameHelpers.h>
#include <eiface.h>
#include <isaverestore.h>
#include <server_class.h>
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <mathlib/vector.h>
#include <unordered_map>
#include <string>

extern CGlobalVars *gpGlobals;
namespace weapons_services {
template<class T> T &Field(void *base, int offset) {
    return *reinterpret_cast<T *>(static_cast<uint8_t *>(base) + offset);
}
template<class T> T Symbol(IGameConfig *conf, const char *name) {
    void *address = nullptr;
    return conf->GetMemSig(name, &address) ? reinterpret_cast<T>(address) : nullptr;
}
template<class R, class... Args> R Virtual(void *self, int slot, Args... args) {
    auto function = reinterpret_cast<R (*)(void *, Args...)>((*reinterpret_cast<void ***>(self))[slot]);
    return function(self, args...);
}
inline int Index(CBaseEntity *entity) {
    return entity ? gamehelpers->ReferenceToIndex(gamehelpers->EntityToReference(entity)) : -1;
}
inline CBaseEntity *Entity(IPluginContext *ctx, cell_t ref, bool player = false, bool nullable = false) {
    if (nullable && ref == -1) return nullptr;
    auto *entity = gamehelpers->ReferenceToEntity(ref);
    const int index = entity ? Index(entity) : -1;
    auto *client = player && index > 0 && index <= playerhelpers->GetMaxClients()
        ? playerhelpers->GetGamePlayer(index) : nullptr;
    if (!entity || (player && (!client || !client->IsInGame()))) {
        ctx->ThrowNativeError("Invalid %s reference %d", player ? "client" : "entity", ref);
        return nullptr;
    }
    return entity;
}
inline int HandleIndex(uint32_t handle) {
    return gamehelpers->ReferenceToIndex(static_cast<cell_t>(handle | 0x80000000u));
}
inline uint32_t EntityHandle(CBaseEntity *entity) {
    return entity ? uint32_t(gamehelpers->EntityToReference(entity)) & 0x7fffffffu : 0;
}
inline char *Text(IPluginContext *ctx, cell_t address) {
    char *text = nullptr;
    ctx->LocalToString(address, &text);
    return text;
}
// Cache offsets by engine-owned ServerClass, never by recycled entity index.
// The class tables last for the server image lifetime; entity data is never cached.
class SendOffsets {
    std::unordered_map<ServerClass *, std::unordered_map<std::string, int>> offsets_;
public:
    int Get(CBaseEntity *entity, const char *name) {
        auto *networkable = reinterpret_cast<IServerUnknown *>(entity)->GetNetworkable();
        if (!networkable) return -1;
        auto *serverClass = networkable->GetServerClass();
        auto &cache = offsets_[serverClass];
        auto found = cache.find(name);
        if (found != cache.end()) return found->second;
        sm_sendprop_info_t info;
        int offset = gamehelpers->FindSendPropInfo(serverClass->GetName(), name, &info)
            ? int(info.actual_offset) : -1;
        cache.emplace(name, offset);
        return offset;
    }
    void *Member(CBaseEntity *entity, const char *name) {
        const int offset = Get(entity, name);
        return offset > 0 ? static_cast<void *>(reinterpret_cast<uint8_t *>(entity) + offset) : nullptr;
    }
};
inline int SendOffset(const char *serverClass, const char *property) {
    sm_sendprop_info_t info;
    return gamehelpers->FindSendPropInfo(serverClass, property, &info) ? int(info.actual_offset) : -1;
}
inline int DataOffset(CBaseEntity *entity, const char *property) {
    sm_datatable_info_t info;
    return gamehelpers->FindDataMapInfo(gamehelpers->GetDataMap(entity), property, &info)
        ? int(info.actual_offset) : -1;
}
inline bool OpenConfig(const char *name, IGameConfig *&conf, char *error, size_t length) {
    char detail[256] = "";
    if (gameconfs->LoadGameConfigFile(name, &conf, detail, sizeof(detail))) return true;
    std::snprintf(error, length, "Weapons service gamedata %s: %s", name, detail);
    return false;
}
inline bool Offset(IGameConfig *conf, const char *name, int &value) {
    return conf->GetOffset(name, &value) && value >= 0 && value < 65536;
}
}
