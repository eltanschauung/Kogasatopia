// SPDX-License-Identifier: GPL-3.0-or-later
// Inspired by Sappykun's whitelist enabler plugin.
// Weapons binds this as the sole GetLoadoutItem owner. Configuration and
// inventory reconciliation stay in SourcePawn; frequent decisions stay native.
#include "smsdk_ext.h"
#include "policy.h"
#include "loadout_cache.h"
#include <safetyhook.hpp>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <memory>
#include <cstdint>
#include <thread>

using namespace SourceMod;
using namespace whitelist;
class WhitelistPolicy final : public SDKExtension, public IClientListener, public IPluginsListener {
public:
    bool SDK_OnLoad(char *, size_t, bool) override;
    void SDK_OnUnload() override;
    void OnClientDisconnected(int client) override;
    void OnPluginWillUnload(IPlugin *plugin) override;
    void OnPluginPauseChange(IPlugin *plugin, bool paused) override;
};
WhitelistPolicy g_Extension;
SMEXT_LINK(&g_Extension)

static IGameConfig *g_Config = nullptr;
using GetManager = void *(*)();
using GetItem = void *(*)(void *, int, int);
using GetIndex = int (*)(const void *);
static GetManager g_GetManager;
static GetItem g_GetSelected, g_GetBase;
static GetIndex g_GetIndex;
static int g_InventoryOffset, g_QualityOffset, g_InitializedOffset;
static std::unique_ptr<std::array<Definition, kDefinitions>> g_Policy, g_Staging;
static std::array<Transaction, SM_MAXPLAYERS + 1> g_Transactions;
static unsigned g_Checks, g_ComboScans, g_Denials, g_Generation;
static unsigned g_DefinitionsStaged;
static bool g_Ready;
static SafetyHookInline g_LoadoutHook;
static void *g_LoadoutTarget;
static IPluginContext *g_Owner = nullptr;
static IPluginFunction *g_Resolver = nullptr, *g_Notice = nullptr;
static int g_ItemOffset;
static int g_FlagsOffset = -1;
static std::thread::id g_GameThread;
static std::array<weapons_loadout::Cache, SM_MAXPLAYERS + 1> g_Loadouts;
static unsigned g_LoadoutCalls, g_ResolverCalls, g_CacheHits, g_StockFastPaths;

static void InvalidateLoadouts() {
    for (auto &cache : g_Loadouts) cache.Invalidate();
}

static void ResetTransactions() {
    for (auto &transaction : g_Transactions) transaction.Reset();
    InvalidateLoadouts();
}
static bool ValidDefinition(int index) { return index >= 0 && index < kDefinitions; }
static uint8_t Classify(void *view) {
    if (!view) return 0;
    int index = g_GetIndex(view);
    return ValidDefinition(index) ? (*g_Policy)[index].classification : 0;
}
static int Quality(void *view) {
    int quality;
    std::memcpy(&quality, static_cast<char *>(view) + g_QualityOffset, sizeof(quality));
    return quality;
}
static bool Initialized(void *view) {
    return view && *(static_cast<uint8_t *>(view) + g_InitializedOffset) != 0;
}
static bool Forbidden(void *inventory, int client, int playerClass) {
    auto &transaction = g_Transactions[client];
    if (transaction.depth && transaction.known) return transaction.forbidden;
    ++g_ComboScans;
    bool result = ForbiddenCombination(Classify(g_GetSelected(inventory, playerClass, 0)),
        Classify(g_GetSelected(inventory, playerClass, 1)),
        Classify(g_GetSelected(inventory, playerClass, 2)));
    if (transaction.depth) {
        transaction.known = true;
        transaction.forbidden = result;
    }
    return result;
}
static cell_t BeginPolicy(IPluginContext *context, const cell_t *params) {
    if (g_Staging) return context->ThrowNativeError("A whitelist policy rebuild is already in progress");
    g_Staging.reset(new std::array<Definition, kDefinitions>);
    for (auto &entry : *g_Staging) entry.allowed = params[1] != 0;
    g_DefinitionsStaged = 0;
    return 0;
}
static cell_t RegisterDefinition(IPluginContext *context, const cell_t *params) {
    if (!g_Staging) return context->ThrowNativeError("BeginPolicy must precede RegisterDefinition");
    if (!ValidDefinition(params[1]) || params[2] < 0 || params[2] > 7)
        return context->ThrowNativeError("Invalid definition or classification");
    (*g_Staging)[params[1]] = {static_cast<uint8_t>(params[2]), params[3] != 0};
    ++g_DefinitionsStaged;
    return 0;
}
static cell_t CommitPolicy(IPluginContext *context, const cell_t *) {
    if (!g_Staging || !g_DefinitionsStaged)
        return context->ThrowNativeError("Cannot commit an empty whitelist schema");
    g_Policy.swap(g_Staging);
    g_Staging.reset();
    g_Ready = true;
    ++g_Generation;
    ResetTransactions();
    return 0;
}
static cell_t ResetState(IPluginContext *, const cell_t *) {
    ResetTransactions();
    return 0;
}
static cell_t BeginInventory(IPluginContext *, const cell_t *params) {
    if (params[1] > 0 && params[1] < static_cast<int>(g_Transactions.size())) {
        if (!g_Transactions[params[1]].depth) g_Loadouts[params[1]].Invalidate();
        g_Transactions[params[1]].Begin();
    }
    return 0;
}
static cell_t EndInventory(IPluginContext *, const cell_t *params) {
    if (params[1] > 0 && params[1] < static_cast<int>(g_Transactions.size()))
        g_Transactions[params[1]].End();
    return 0;
}
static Reason EvaluatePlayer(void *entity, int client, int playerClass, int slot, void *&replacement) {
    replacement = nullptr;
    if (!g_Ready) return Allowed;
    if (client <= 0 || client > playerhelpers->GetMaxClients()
        || playerClass < 1 || playerClass > 9 || slot < 0 || slot > 18)
        return Allowed;
    IGamePlayer *player = playerhelpers->GetGamePlayer(client);
    if (!player || !player->IsInGame()) return Allowed;
    void *manager = g_GetManager();
    if (!entity || !manager) return Allowed;
    ++g_Checks;
    void *inventory = static_cast<char *>(entity) + g_InventoryOffset;
    Reason reason = Allowed;
    if (playerClass == 4 && slot <= 2 && Forbidden(inventory, client, playerClass))
        reason = Decide(true, false, 0, true);
    else {
        void *selected = g_GetSelected(inventory, playerClass, slot);
        if (Initialized(selected)) {
            int index = g_GetIndex(selected);
            if (ValidDefinition(index))
                reason = Decide(false, true, Quality(selected), (*g_Policy)[index].allowed);
        }
    }
    if (reason == Allowed) return Allowed;
    replacement = g_GetBase(manager, playerClass, slot);
    ++g_Denials;
    return reason;
}
static cell_t Evaluate(IPluginContext *context, const cell_t *params) {
    cell_t *replacement;
    if (context->LocalToPhysAddr(params[4], &replacement) != SP_ERROR_NONE)
        return context->ThrowNativeError("Invalid replacement output");
    *replacement = 0;
    if (!g_Ready) return context->ThrowNativeError("Whitelist policy has not been initialized");
    void *base;
    Reason reason = EvaluatePlayer(gamehelpers->ReferenceToEntity(params[1]), params[1], params[2], params[3], base);
    // Preserve Valve's null fallback for slots with no stock item.
#if defined(__x86_64__)
    *replacement = base ? static_cast<cell_t>(g_pSM->ToPseudoAddress(base)) : 0;
#else
    *replacement = static_cast<cell_t>(reinterpret_cast<uintptr_t>(base));
#endif
    return reason;
}

static void *ItemView(int reference) {
    CBaseEntity *entity = gamehelpers->ReferenceToEntity(reference);
    // Never retain CEconItemView pointers. ReferenceToEntity checks the serial
    // on every use, including a deferred placeholder being deleted by TF2.
    return entity ? reinterpret_cast<char *>(entity) + g_ItemOffset : nullptr;
}
static bool Removing(int reference) {
    CBaseEntity *entity = gamehelpers->ReferenceToEntity(reference);
    if (!entity) return true;
    if (g_FlagsOffset < 0) {
        sm_datatable_info_t flags;
        datamap_t *map = gamehelpers->GetDataMap(entity);
        if (!map || !gamehelpers->FindDataMapInfo(map, "m_fFlags", &flags))
            return true; // No layout guess: disable reuse of ordinary entities.
        g_FlagsOffset = static_cast<int>(flags.actual_offset);
    }
    uint32_t flags;
    std::memcpy(&flags, reinterpret_cast<char *>(entity) + g_FlagsOffset, sizeof(flags));
    return (flags & (1u << 27)) != 0; // TF2/HL2MP's FL_KILLME (not SM's remapped bit).
}
static void *ResolveCustom(int client, int playerClass, int slot) {
    if (!g_Resolver || !weapons_loadout::ValidSlot(playerClass, slot))
        return nullptr;
    auto &cache = g_Loadouts[client];
    auto &entry = cache.slots[playerClass][slot];
    if (!entry.selected) { ++g_StockFastPaths; return nullptr; }
    if (!g_Resolver->IsRunnable()) return nullptr;
    if (entry.resolving) return nullptr;
    const bool inInventory = g_Transactions[client].depth != 0;
    if (cache.Reusable(entry, inInventory)) {
        if (entry.reference == weapons_loadout::kNoEntity) { ++g_CacheHits; return nullptr; }
        if (entry.placeholder || !Removing(entry.reference)) {
            if (void *view = ItemView(entry.reference)) { ++g_CacheHits; return view; }
        }
    }
    const uint64_t epoch = cache.epoch;
    entry.resolving = true;
    ++g_ResolverCalls;
    g_Resolver->PushCell(client);
    g_Resolver->PushCell(playerClass);
    g_Resolver->PushCell(slot);
    cell_t reference = weapons_loadout::kNoEntity;
    const int error = g_Resolver->Execute(&reference);
    entry.resolving = false;
    if (error != SP_ERROR_NONE || epoch != cache.epoch) return nullptr;
    cache.Store(entry, epoch, reference, inInventory);
    // The existing deferred-equip placeholder intentionally has FL_KILLME.
    entry.placeholder = reference != weapons_loadout::kNoEntity && Removing(reference);
    return reference != weapons_loadout::kNoEntity ? ItemView(reference) : nullptr;
}
static void *GetLoadoutItem(void *entity, int playerClass, int slot, bool reportWhitelist) {
    // Inventory belongs to the game thread. An unexpected worker must not
    // enter SourcePawn, player helpers, or mutable selection/policy caches.
    if (std::this_thread::get_id() != g_GameThread)
        return g_LoadoutHook.call<void *>(entity, playerClass, slot, reportWhitelist);
    // TF2 uses the normal Linux member-function ABI: this is the first argument.
    // Main-thread-only inventory hook; never remove its trampoline in a callback.
    void *result = g_LoadoutHook.unsafe_call<void *>(entity, playerClass, slot, reportWhitelist);
    ++g_LoadoutCalls;
    int client = gamehelpers->EntityToBCompatRef(static_cast<CBaseEntity *>(entity));
    if (client <= 0 || client > playerhelpers->GetMaxClients()) return result;
    void *replacement;
    Reason reason = EvaluatePlayer(entity, client, playerClass, slot, replacement);
    if (reason != Allowed) {
        result = replacement;
        if (reportWhitelist && g_Notice && g_Notice->IsRunnable()) {
            g_Notice->PushCell(client);
            g_Notice->PushCell(reason);
            g_Notice->Execute(nullptr);
        }
    }
    // Combo denial precedes custom overrides. Ordinary bans retain Weapons'
    // original ability to override a stock fallback with a custom selection.
    if (reason == DemoCombination) return result;
    if (void *custom = ResolveCustom(client, playerClass, slot)) result = custom;
    return result;
}
static cell_t BindLoadout(IPluginContext *context, const cell_t *params) {
    if (g_Owner && g_Owner != context) return context->ThrowNativeError("Weapons loadout already has an owner");
    IPluginFunction *resolver = context->GetFunctionById(params[1]);
    IPluginFunction *notice = context->GetFunctionById(params[2]);
    if (!resolver || !notice) return context->ThrowNativeError("Invalid Weapons loadout callbacks");
    if (!g_LoadoutHook) {
        g_LoadoutHook = safetyhook::create_inline(g_LoadoutTarget, GetLoadoutItem);
        if (!g_LoadoutHook) return context->ThrowNativeError("Could not install native GetLoadoutItem hook");
    }
    g_Owner = context; g_Resolver = resolver; g_Notice = notice;
    for (auto &cache : g_Loadouts) cache.Reset();
    return 0;
}
static void ClearOwner() {
    g_Owner = nullptr; g_Resolver = nullptr; g_Notice = nullptr;
    for (auto &cache : g_Loadouts) cache.Reset();
    ResetTransactions();
}
static cell_t UnbindLoadout(IPluginContext *context, const cell_t *) {
    if (g_Owner == context) ClearOwner();
    return 0;
}
static cell_t PublishSelection(IPluginContext *context, const cell_t *params) {
    if (g_Owner != context) return context->ThrowNativeError("Only Weapons may publish a native loadout");
    int client = params[1], playerClass = params[2];
    if (client <= 0 || client > playerhelpers->GetMaxClients()
        || !weapons_loadout::ValidSlot(playerClass, 0)) return context->ThrowNativeError("Invalid loadout client/class");
    cell_t *selected;
    if (context->LocalToPhysAddr(params[3], &selected) != SP_ERROR_NONE)
        return context->ThrowNativeError("Invalid selected-slot array");
    auto &cache = g_Loadouts[client];
    cache.Invalidate();
    for (int slot = 0; slot < weapons_loadout::kSlots; ++slot)
        cache.slots[playerClass][slot].selected = selected[slot] != 0;
    return 0;
}
static cell_t InvalidateClient(IPluginContext *context, const cell_t *params) {
    if (g_Owner != context) return context->ThrowNativeError("Only Weapons may invalidate a native loadout");
    int client = params[1];
    if (client > 0 && client <= playerhelpers->GetMaxClients()) g_Loadouts[client].Invalidate();
    return 0;
}
static cell_t LoadoutStats(IPluginContext *context, const cell_t *params) {
    cell_t *output;
    if (context->LocalToPhysAddr(params[1], &output) != SP_ERROR_NONE)
        return context->ThrowNativeError("Invalid stats output");
    output[0] = g_LoadoutHook ? 1 : 0; output[1] = g_Owner != nullptr;
    output[2] = g_LoadoutCalls; output[3] = g_ResolverCalls;
    output[4] = g_CacheHits; output[5] = g_StockFastPaths;
    return 0;
}
static cell_t Stats(IPluginContext *context, const cell_t *params) {
    cell_t *output;
    if (context->LocalToPhysAddr(params[1], &output) != SP_ERROR_NONE)
        return context->ThrowNativeError("Invalid stats output");
    output[0] = g_Ready; output[1] = g_Generation;
    output[2] = g_Checks; output[3] = g_ComboScans; output[4] = g_Denials;
    return 0;
}
static sp_nativeinfo_t g_Natives[] = {
    {"WhitelistPolicy_BeginPolicy", BeginPolicy},
    {"WhitelistPolicy_RegisterDefinition", RegisterDefinition},
    {"WhitelistPolicy_CommitPolicy", CommitPolicy},
    {"WhitelistPolicy_ResetTransactions", ResetState},
    {"WhitelistPolicy_BeginInventory", BeginInventory},
    {"WhitelistPolicy_EndInventory", EndInventory},
    {"WhitelistPolicy_Evaluate", Evaluate},
    {"WhitelistPolicy_GetStats", Stats},
    {"WeaponsLoadout_Bind", BindLoadout},
    {"WeaponsLoadout_Unbind", UnbindLoadout},
    {"WeaponsLoadout_PublishSelection", PublishSelection},
    {"WeaponsLoadout_InvalidateClient", InvalidateClient},
    {"WeaponsLoadout_GetStats", LoadoutStats},
    {nullptr, nullptr}
};
bool WhitelistPolicy::SDK_OnLoad(char *error, size_t length, bool) {
    g_GameThread = std::this_thread::get_id();
#if !defined(__linux__) || (!defined(__x86_64__) && !defined(__i386__))
    std::snprintf(error, length, "Whitelist Policy supports Linux x86/x86-64 TF2 only");
    return false;
#endif
    if (std::strcmp(g_pSM->GetGameFolderName(), "tf") != 0) {
        std::snprintf(error, length, "Whitelist Policy requires TF2");
        return false;
    }
    auto fail = [&](const char *message) {
        std::snprintf(error, length, "%s", message);
        if (g_Config) { gameconfs->CloseGameConfigFile(g_Config); g_Config = nullptr; }
        return false;
    };
    char configError[256];
    if (!gameconfs->LoadGameConfigFile("tf2.whitelist_policy", &g_Config, configError, sizeof(configError)))
        return fail("Could not load tf2.whitelist_policy gamedata");
    void *managerFn, *selectedFn, *baseFn, *indexFn, *loadoutFn, *guardFn;
    if (!g_Config->GetMemSig("TFInventoryManager", &managerFn) || !managerFn
        || !g_Config->GetMemSig("GetItemInLoadout", &selectedFn) || !selectedFn
        || !g_Config->GetMemSig("GetBaseItemForClass", &baseFn) || !baseFn
        || !g_Config->GetMemSig("GetItemDefIndex", &indexFn) || !indexFn
        || !g_Config->GetMemSig("GetLoadoutItem", &loadoutFn) || !loadoutFn
        || !g_Config->GetMemSig("InventoryOffsetGuard", &guardFn) || !guardFn
        || !g_Config->GetOffset("Inventory", &g_InventoryOffset))
        return fail("Missing whitelist engine binding; update gamedata");
    const uintptr_t guard = reinterpret_cast<uintptr_t>(guardFn);
    const uintptr_t loadout = reinterpret_cast<uintptr_t>(loadoutFn);
    if (guard < loadout || guard - loadout > 1024)
        return fail("Inventory guard is outside GetLoadoutItem; unsupported TF2 build");
    int displacement, callDisplacement, inventoryPosition, callPosition;
    if (!g_Config->GetOffset("GuardInventoryDisplacement", &inventoryPosition)
        || !g_Config->GetOffset("GuardCallDisplacement", &callPosition)
        || inventoryPosition < 0 || inventoryPosition > 16 || callPosition < 0 || callPosition > 32)
        return fail("Missing or invalid inventory guard operand offsets");
    std::memcpy(&displacement, static_cast<char *>(guardFn) + inventoryPosition, 4);
    std::memcpy(&callDisplacement, static_cast<char *>(guardFn) + callPosition, 4);
    if (displacement != g_InventoryOffset
        || guard + callPosition + 4 + callDisplacement != reinterpret_cast<uintptr_t>(selectedFn))
        return fail("Inventory offset/call ABI guard failed; update gamedata");
    sm_sendprop_info_t item, quality, initialized;
    if (!gamehelpers->FindSendPropInfo("CEconEntity", "m_Item", &item)
        || !gamehelpers->FindSendPropInfo("CEconEntity", "m_iEntityQuality", &quality)
        || !gamehelpers->FindSendPropInfo("CEconEntity", "m_bInitialized", &initialized))
        return fail("Could not derive CEconItemView fields from sendprops");
    g_QualityOffset = static_cast<int>(quality.actual_offset) - static_cast<int>(item.actual_offset);
    g_ItemOffset = static_cast<int>(item.actual_offset);
    g_LoadoutTarget = loadoutFn;
    g_InitializedOffset = static_cast<int>(initialized.actual_offset) - static_cast<int>(item.actual_offset);
    if (g_QualityOffset < 0 || g_QualityOffset > 512
        || g_InitializedOffset < 0 || g_InitializedOffset > 512)
        return fail("Unexpected econ view sendprop layout");
    g_GetManager = reinterpret_cast<GetManager>(managerFn);
    g_GetSelected = reinterpret_cast<GetItem>(selectedFn);
    g_GetBase = reinterpret_cast<GetItem>(baseFn);
    g_GetIndex = reinterpret_cast<GetIndex>(indexFn);
    void *manager = g_GetManager();
    if (!manager) return fail("TFInventoryManager unavailable");
    for (int playerClass = 1; playerClass <= 9; ++playerClass) {
        for (int slot = 0; slot < 3; ++slot) {
            void *base = g_GetBase(manager, playerClass, slot);
            // Spy has no primary loadout slot: Valve returns an invalid view.
            if (playerClass == 8 && slot == 0) continue;
            if (!Initialized(base) || !ValidDefinition(g_GetIndex(base)) || Quality(base) != 0) {
                char detail[256];
                std::snprintf(detail, sizeof(detail),
                    "Stock econ validation failed: class=%d slot=%d present=%d initialized=%d quality=%d quality_offset=%d initialized_offset=%d",
                    playerClass, slot, base != nullptr, Initialized(base), base ? Quality(base) : -1,
                    g_QualityOffset, g_InitializedOffset);
                return fail(detail);
            }
        }
    }
    playerhelpers->AddClientListener(this);
    plsys->AddPluginsListener(this);
    sharesys->AddNatives(myself, g_Natives);
    sharesys->RegisterLibrary(myself, "whitelist_policy_native");
    return true;
}
void WhitelistPolicy::OnClientDisconnected(int client) {
    if (client > 0 && client < static_cast<int>(g_Transactions.size())) {
        g_Transactions[client].Reset();
        g_Loadouts[client].Reset();
    }
}
void WhitelistPolicy::OnPluginWillUnload(IPlugin *plugin) {
    if (plugin->GetBaseContext() == g_Owner) ClearOwner();
}
void WhitelistPolicy::OnPluginPauseChange(IPlugin *plugin, bool) {
    if (plugin->GetBaseContext() == g_Owner) InvalidateLoadouts();
}
void WhitelistPolicy::SDK_OnUnload() {
    // Engine and plugin lifecycle operations are main-thread-only. Retire the
    // trampoline only here, not while a SourcePawn resolver is on its stack.
    g_LoadoutHook.reset();
    ClearOwner();
    plsys->RemovePluginsListener(this);
    playerhelpers->RemoveClientListener(this);
    g_Ready = false;
    ResetTransactions();
    g_Policy.reset(); g_Staging.reset();
    if (g_Config) { gameconfs->CloseGameConfigFile(g_Config); g_Config = nullptr; }
}
