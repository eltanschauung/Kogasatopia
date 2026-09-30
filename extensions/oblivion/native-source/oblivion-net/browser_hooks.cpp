// SPDX-License-Identifier: GPL-3.0-or-later
#include "browser_hooks.h"
#include "browser_protocol.h"
#include "udp_reply_sender.h"
#include "steam/isteamgameserver.h"
#include <cstring>
#ifndef _WIN32
#include <dlfcn.h>
#include <link.h>
#endif

SH_DECL_HOOK4(ISteamGameServer, HandleIncomingPacket, SH_NOATTRIB, 0, bool, const void *, int, uint32, uint16);
SH_DECL_HOOK4(ISteamGameServer, GetNextOutgoingPacket, SH_NOATTRIB, 0, int, void *, int, uint32 *, uint16 *);
SH_DECL_HOOK0_void(IServerGameDLL, GameShutdown, SH_NOATTRIB, 0);

namespace {
oblivion_browser::Service service;
UdpReplySender sender;
std::atomic<uint32_t> rawSent{0}, rawErrors{0};
std::shared_ptr<oblivion_browser::Snapshot> staging;
ISteamGameServer *steamServer;
IServerGameDLL *serverDll;
int incomingHook, outgoingHook, infoHook, shutdownHook;
std::chrono::steady_clock::time_point nextAttach;

void *SteamSymbol(const char *name) {
#ifdef _WIN32
    auto library = GetModuleHandleA(sizeof(void *) == 8 ? "steam_api64.dll" : "steam_api.dll");
    return library ? reinterpret_cast<void *>(GetProcAddress(library, name)) : nullptr;
#else
    if (void *symbol = dlsym(RTLD_DEFAULT, name)) return symbol;
    // Also handle engines which load Steam's API in a local ELF symbol scope.
    struct Search { const char *name; void *symbol; } search{name, nullptr};
    dl_iterate_phdr([](dl_phdr_info *info, size_t, void *raw) -> int {
        auto *query = static_cast<Search *>(raw);
        const char *path = info->dlpi_name;
        const char *base = std::strrchr(path, '/'); base = base ? base + 1 : path;
        if (std::strcmp(base, "libsteam_api.so") != 0) return 0;
        void *library = dlopen(path, RTLD_NOW | RTLD_NOLOAD);
        if (!library) return 0;
        query->symbol = dlsym(library, query->name); dlclose(library);
        return query->symbol ? 1 : 0;
    }, &search);
    return search.symbol;
#endif
}
ISteamGameServer *FindSteamServer() {
    using User = int (*)();
    using Interface = void *(*)(int, const char *);
    auto user = reinterpret_cast<User>(SteamSymbol("SteamGameServer_GetHSteamUser"));
    auto interface = reinterpret_cast<Interface>(SteamSymbol("SteamInternal_FindOrCreateGameServerInterface"));
    if (!user || !interface) return nullptr;
    int handle = user();
    return handle ? static_cast<ISteamGameServer *>(interface(handle, STEAMGAMESERVER_INTERFACE_VERSION)) : nullptr;
}
void DetachSteam() {
    if (incomingHook) { SH_REMOVE_HOOK_ID(incomingHook); incomingHook = 0; }
    if (outgoingHook) { SH_REMOVE_HOOK_ID(outgoingHook); outgoingHook = 0; }
    if (infoHook) { SH_REMOVE_HOOK_ID(infoHook); infoHook = 0; }
    steamServer = nullptr;
}
class Hooks {
public:
    bool Incoming(const void *data, int size, uint32 ip, uint16 port) {
        if (service.Incoming(data, size, ip, port)) RETURN_META_VALUE(MRES_SUPERCEDE, true);
        RETURN_META_VALUE(MRES_IGNORED, false);
    }
    int Outgoing(void *data, int maxSize, uint32 *ip, uint16 *port) {
        for (int attempt = 0; attempt < 128; ++attempt) {
            int size = service.Outgoing(data, maxSize, ip, port);
            if (!size) break;
            if (sender.Send(service.QueryPort(), data, size, *ip, *port)) { ++rawSent; continue; }
            ++rawErrors;
            // Preserve delivery of small replies if socket discovery fails.
            // The reply remains filtered; never substitute an unfiltered list.
            RETURN_META_VALUE(MRES_SUPERCEDE, size);
        }
        RETURN_META_VALUE(MRES_IGNORED, 0);
    }
    int Info(void *data, int maxSize, uint32 *ip, uint16 *port) {
        int size = META_RESULT_STATUS >= MRES_OVERRIDE ? META_RESULT_OVERRIDE_RET(int) : META_RESULT_ORIG_RET(int);
        if (size > 0 && size <= maxSize && ip) service.FilterInfo(data, size, *ip);
        RETURN_META_VALUE(MRES_IGNORED, 0);
    }
    void Shutdown() {
        service.Clear(); sender.Reset(); DetachSteam();
        RETURN_META(MRES_IGNORED);
    }
} hooks;

void Frame(bool) {
    const auto now = std::chrono::steady_clock::now();
    if (now < nextAttach) return;
    nextAttach = now + std::chrono::milliseconds(250);
    ISteamGameServer *current = FindSteamServer();
    if (!current || current == steamServer) return;
    DetachSteam(); steamServer = current;
    incomingHook = SH_ADD_HOOK(ISteamGameServer, HandleIncomingPacket, steamServer, SH_MEMBER(&hooks, &Hooks::Incoming), false);
    outgoingHook = SH_ADD_HOOK(ISteamGameServer, GetNextOutgoingPacket, steamServer, SH_MEMBER(&hooks, &Hooks::Outgoing), false);
    infoHook = SH_ADD_HOOK(ISteamGameServer, GetNextOutgoingPacket, steamServer, SH_MEMBER(&hooks, &Hooks::Info), true);
    if (!incomingHook || !outgoingHook || !infoHook) {
        DetachSteam(); smutils->LogError(myself, "Cannot attach SteamGameServer015 browser packet hooks.");
    } else smutils->LogMessage(myself, "SteamGameServer015 browser packet hooks attached.");
}

cell_t Begin(IPluginContext *context, const cell_t *params) {
    if (params[2] < 1 || params[2] > 65535) return context->ThrowNativeError("Invalid browser query port");
    staging = std::make_shared<oblivion_browser::Snapshot>();
    staging->enabled = params[1] != 0;
    staging->queryPort = static_cast<uint16_t>(params[2]);
    return 0;
}
cell_t Player(IPluginContext *context, const cell_t *params) {
    if (!staging) return context->ThrowNativeError("Begin the browser snapshot first");
    const int slot = params[1];
    if (slot < 1 || slot > static_cast<int>(oblivion_browser::MaxPlayers))
        return context->ThrowNativeError("Invalid browser player slot");
    char *ip, *name;
    context->LocalToString(params[2], &ip); context->LocalToString(params[3], &name);
    uint32_t address = 0;
    if (*ip && !oblivion_browser::ParseIpv4(ip, address)) return context->ThrowNativeError("Expected an IPv4 address or empty string");
    auto &row = staging->players[slot];
    row.present = true; row.bot = params[6] != 0; row.viewerIp = address;
    size_t size = std::strlen(name);
    if (size > oblivion_browser::MaxNameBytes) {
        size = oblivion_browser::MaxNameBytes;
        while (size && (static_cast<unsigned char>(name[size]) & 0xc0) == 0x80) --size;
    }
    row.name.assign(name, size); row.score = params[4]; row.seconds = sp_ctof(params[5]);
    return 0;
}
cell_t Hide(IPluginContext *context, const cell_t *params) {
    if (!staging) return context->ThrowNativeError("Begin the browser snapshot first");
    int viewer = params[1], subject = params[2];
    if (viewer < 1 || subject < 1 || viewer > static_cast<int>(oblivion_browser::MaxPlayers)
        || subject > static_cast<int>(oblivion_browser::MaxPlayers) || viewer == subject)
        return context->ThrowNativeError("Invalid browser pairing");
    if (staging->players[viewer].present && staging->players[subject].present)
        staging->hidden[viewer].set(subject);
    return 0;
}
cell_t HideAddress(IPluginContext *context, const cell_t *params) {
    if (!staging) return context->ThrowNativeError("Begin the browser snapshot first");
    char *text;
    context->LocalToString(params[1], &text);
    uint32_t ip;
    const int subject = params[2];
    if (!oblivion_browser::ParseIpv4(text, ip) || subject < 1
        || subject > static_cast<int>(oblivion_browser::MaxPlayers))
        return context->ThrowNativeError("Invalid browser address rule");
    if (staging->players[subject].present) staging->addressRules[ip].set(subject);
    return 0;
}
cell_t Commit(IPluginContext *context, const cell_t *) {
    if (!staging) return context->ThrowNativeError("Begin the browser snapshot first");
    service.Publish(std::move(staging));
    return 0;
}
cell_t Clear(IPluginContext *, const cell_t *) { staging.reset(); service.Clear(); return 0; }
cell_t Transport(IPluginContext *context, const cell_t *params) {
    cell_t *sent, *errors;
    context->LocalToPhysAddr(params[1], &sent); context->LocalToPhysAddr(params[2], &errors);
    *sent = static_cast<cell_t>(rawSent.load()); *errors = static_cast<cell_t>(rawErrors.load());
    return 0;
}
cell_t Status(IPluginContext *context, const cell_t *params) {
    cell_t values[] = {static_cast<cell_t>(service.AddressCount()), static_cast<cell_t>(service.stats.requests.load()),
        static_cast<cell_t>(service.stats.lists.load()), static_cast<cell_t>(service.stats.filtered.load()),
        static_cast<cell_t>(service.stats.rows.load()), static_cast<cell_t>(service.stats.infos.load())};
    for (int i = 0; i < 6; ++i) { cell_t *out; context->LocalToPhysAddr(params[i + 1], &out); *out = values[i]; }
    return incomingHook && outgoingHook && infoHook;
}
sp_nativeinfo_t natives[] = {
    {"OblivionNet_BrowserBegin", Begin}, {"OblivionNet_BrowserPlayer", Player},
    {"OblivionNet_BrowserHide", Hide}, {"OblivionNet_BrowserCommit", Commit},
    {"OblivionNet_BrowserHideAddress", HideAddress},
    {"OblivionNet_BrowserClear", Clear}, {"OblivionNet_BrowserStatus", Status},
    {"OblivionNet_BrowserTransport", Transport}, {nullptr, nullptr}
};
}

bool BrowserMetamodLoad(ISmmAPI *ismm, char *error, size_t maxlen) {
    GET_V_IFACE_CURRENT(GetServerFactory, serverDll, IServerGameDLL, INTERFACEVERSION_SERVERGAMEDLL);
    return true;
}
bool BrowserStart(char *error, size_t maxlength) {
    if (!service.Initialize()) { snprintf(error, maxlength, "Cannot initialize browser query challenge key"); return false; }
    sharesys->AddNatives(myself, natives);
    shutdownHook = SH_ADD_HOOK(IServerGameDLL, GameShutdown, serverDll, SH_MEMBER(&hooks, &Hooks::Shutdown), false);
    if (!shutdownHook) { snprintf(error, maxlength, "Cannot hook browser shutdown cleanup"); return false; }
    smutils->AddGameFrameHook(Frame);
    Frame(false);
    return true;
}
void BrowserStop() {
    smutils->RemoveGameFrameHook(Frame);
    if (shutdownHook) { SH_REMOVE_HOOK_ID(shutdownHook); shutdownHook = 0; }
    staging.reset(); service.Clear(); sender.Reset(); DetachSteam();
}
