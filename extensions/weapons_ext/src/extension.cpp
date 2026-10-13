// SPDX-License-Identifier: GPL-3.0-or-later
#include "modules.h"
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <sys/stat.h>
#include <link.h>
#include <tier1/convar.h>

static constexpr const char *kStandaloneFiles[] = {
    "game.tf2.ext.2.tf2.so", "game.tf2.ext.so", "tf2items.ext.2.ep2v.so",
    "tf2items.ext.2.tf2.so", "tf2items.ext.so", "conch_no_speed.ext.2.tf2.so",
    "scattergun_pellets.ext.2.tf2.so", "tf2_spread_patterns.ext.2.tf2.so",
    "whitelist_policy.ext.2.tf2.so", "tf2_sentry_newtarget_dist.ext.2.tf2.so"
};
static int FindStandaloneImage(dl_phdr_info *image, size_t, void *out) {
    const char *name = std::strrchr(image->dlpi_name, '/');
    name = name ? name + 1 : image->dlpi_name;
    for (const char *legacy : kStandaloneFiles) {
        if (!std::strcmp(name, legacy)) {
            *static_cast<const char **>(out) = legacy;
            return 1;
        }
    }
    return 0;
}

namespace weapons_ext {
static ClientDispatch dispatch;
ClientDispatch &Clients() { return dispatch; }
void ClientDispatch::Add(IClientListener *listener) {
    if (std::find(listeners_.begin(), listeners_.end(), listener) != listeners_.end()) return;
    auto slot = std::find(listeners_.begin(), listeners_.end(), nullptr);
    if (slot != listeners_.end()) *slot = listener;
}
void ClientDispatch::Remove(IClientListener *listener) {
    for (auto &entry : listeners_) if (entry == listener) entry = nullptr;
}
void ClientDispatch::OnClientPutInServer(int client) {
    for (auto listener : listeners_) if (listener) listener->OnClientPutInServer(client);
}
void ClientDispatch::OnClientDisconnecting(int client) {
    for (auto listener : listeners_) if (listener) listener->OnClientDisconnecting(client);
}
void ClientDispatch::OnClientDisconnected(int client) {
    for (auto listener : listeners_) if (listener) listener->OnClientDisconnected(client);
}
}

class WeaponsExtension final : public SDKExtension {
    std::array<SDKExtension *, 7> modules_{};
    size_t loaded_ = 0;
    size_t metamod_ = 0;
    bool listening_ = false;
    ISmmAPI *metamod_api_ = nullptr;
public:
    bool SDK_OnMetamodLoad(ISmmAPI *api, char *error, size_t length, bool late) override {
        modules_ = { &ToolsModule(), &ItemsModule(), &ConchModule(), &PelletsModule(),
                     &SpreadModule(), &WhitelistModule(), &SentryModule() };
        // Component hooks wait until SourceMod interfaces are available and
        // the duplicate-owner guard succeeds. Merely dlopen'ing a candidate
        // must not attach hooks beside the original seven extensions.
        metamod_api_ = api;
        return true;
    }
    bool SDK_OnLoad(char *error, size_t length, bool late) override {
        if (std::strcmp(g_pSM->GetGameFolderName(), "tf")) {
            std::snprintf(error, length, "weapons_ext supports Linux x86 TF2 only");
            return false;
        }
        const char *resident = nullptr;
        dl_iterate_phdr(FindStandaloneImage, &resident);
        if (resident) {
            std::snprintf(error, length, "%s is still resident; restart before loading weapons_ext", resident);
            return false;
        }
        for (const char *file : kStandaloneFiles) {
            char path[PLATFORM_MAX_PATH];
            g_pSM->BuildPath(Path_SM, path, sizeof(path), "extensions/%s", file);
            struct stat info;
            if (!stat(path, &info)) {
                std::snprintf(error, length, "Retire %s and restart before loading weapons_ext", file);
                return false;
            }
        }
        for (; metamod_ < modules_.size();) {
            auto *module = modules_[metamod_++];
            if (!module->SDK_OnMetamodLoad(metamod_api_, error, length, late)) {
                SDK_OnUnload();
                return false;
            }
        }
        playerhelpers->AddClientListener(&weapons_ext::Clients());
        listening_ = true;
        for (; loaded_ < modules_.size();) {
            auto *module = modules_[loaded_++];
            if (!module->SDK_OnLoad(error, length, late)) {
                SDK_OnUnload();
                return false;
            }
        }
        sharesys->RegisterLibrary(myself, "weapons_ext");
        return true;
    }
    void SDK_OnAllLoaded() override {
        for (size_t i = 0; i < loaded_; ++i) modules_[i]->SDK_OnAllLoaded();
    }
    size_t LoadedModules() const { return loaded_; }
    bool QueryRunning(char *error, size_t length) override {
        for (size_t i = 0; i < loaded_; ++i)
            if (!static_cast<IExtensionInterface *>(modules_[i])->QueryRunning(error, length)) return false;
        return loaded_ == modules_.size();
    }
    bool QueryInterfaceDrop(SMInterface *iface) override {
        for (size_t i = 0; i < loaded_; ++i)
            if (!modules_[i]->QueryInterfaceDrop(iface)) return false;
        return true;
    }
    void NotifyInterfaceDrop(SMInterface *iface) override {
        for (size_t i = 0; i < loaded_; ++i) modules_[i]->NotifyInterfaceDrop(iface);
    }
    void SDK_OnUnload() override {
        while (loaded_) modules_[--loaded_]->SDK_OnUnload();
        if (listening_) {
            playerhelpers->RemoveClientListener(&weapons_ext::Clients());
            listening_ = false;
        }
        while (metamod_)
            modules_[--metamod_]->SDK_OnMetamodUnload(nullptr, 0);
    }
    bool SDK_OnMetamodUnload(char *error, size_t length) override {
        SDK_OnUnload();
        return true;
    }
};
static WeaponsExtension extension;
SDKExtension *g_pExtensionIface = &extension;

CON_COMMAND(sm_weapons_ext_status, "Report unified Weapons native module ownership")
{
    META_CONPRINTF("[weapons_ext] modules=%u/7 extension_interfaces=1 client_dispatchers=1 detour_runtimes=1\n",
        unsigned(extension.LoadedModules()));
    META_CONPRINTF("[weapons_ext] shared_trace_vtables=%u\n", unsigned(PelletSharedTraceTables()));
}
