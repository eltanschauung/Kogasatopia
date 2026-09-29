// SPDX-License-Identifier: GPL-3.0-or-later
#include "extension.h"
#include "dt_send.h"
#include "server_class.h"
#include <array>
#include <atomic>
#include <climits>
#include <cstdint>
#include <cstring>

RestoreScoreDisplay g_RestoreScore;
SMEXT_LINK(&g_RestoreScore);
SH_DECL_HOOK0_void(IServerGameDLL, LevelShutdown, SH_NOATTRIB, 0);
SH_DECL_HOOK3_void(IServerGameDLL, ServerActivate, SH_NOATTRIB, 0, edict_t *, int, int);

namespace {
constexpr int Slots = SM_MAXPLAYERS + 1;
struct Slot {
    SendProp *prop = nullptr;
    SendVarProxyFn original = nullptr;
    SendProp *connected = nullptr;
    std::atomic<int64_t> offset{0};
    std::atomic<unsigned> encoded{0};
    std::atomic<int> lastEncoded{0};
};
std::array<Slot, Slots> slots;
int count, scoreOffset, connectedOffset;
const CGlobalVars *globals;
IServerGameDLL *serverDll;
int shutdownHook, activateHook;
std::atomic<bool> worldActive{false};
IPluginContext *owner;
bool installed;
std::atomic<bool> paused{false};
thread_local bool diagnosticRead;

int Calculate(int raw, int64_t offset) {
    const int64_t value = static_cast<int64_t>(raw) + offset;
    return value <= 0 ? 0 : value >= INT_MAX ? INT_MAX : static_cast<int>(value);
}
bool IsResource(CBaseEntity *entity) {
    auto cls = entity ? gamehelpers->FindEntityServerClass(entity) : nullptr;
    return cls && !std::strcmp(cls->GetName(), "CTFPlayerResource");
}
void Dirty(int client = -1) {
    if (!globals || !worldActive.load()) return;
    for (int id = globals->maxClients + 1; id < globals->maxEntities; ++id) {
        auto edict = gamehelpers->EdictOfIndex(id);
        if (!edict || edict->IsFree() || !IsResource(gamehelpers->ReferenceToEntity(id))) continue;
        // Invalidate the encoder cache even though the underlying score never
        // changes. Include Oblivion's private player-resource copies.
        gamehelpers->SetEdictStateChanged(edict, client > 0 ? scoreOffset + client * sizeof(int) : 0);
    }
}
void Clear() {
    bool changed = false;
    for (auto &slot : slots) if (slot.offset.exchange(0)) changed = true;
    if (changed) Dirty();
}
void ScoreProxy(const SendProp *prop, const void *base, const void *data, DVariant *out, int element, int id) {
    const int client = prop->GetOffset() / sizeof(int);
    if (client < 0 || client >= count || prop->GetOffset() % sizeof(int)) {
        std::memcpy(&out->m_Int,data,sizeof(int)); return;
    }
    // Only validated members of this Array3 table point at this callback.
    auto &slot = slots[client];
    struct Sample {
        Slot &slot; DVariant *out; bool record;
        ~Sample() { if (record) { slot.lastEncoded.store(out->m_Int); ++slot.encoded; } }
    } sample{slot,out,!diagnosticRead};
    slot.original(prop, base, data, out, element, id);
    if (client == 0 || paused || !worldActive.load()) return;
    const auto offset = slot.offset.load();
    if (!offset) return;
    auto entity = gamehelpers->ReferenceToEntity(id);
    if (!entity) return;
    auto connectionBase = reinterpret_cast<const char *>(entity) + connectedOffset;
    DVariant connected{};
    slot.connected->GetProxyFn()(slot.connected, connectionBase,
        connectionBase + slot.connected->GetOffset(), &connected, 0, id);
    // A hidden/disconnected row must remain hidden, including private rosters.
    if (!connected.m_Int) return;
    out->m_Int = Calculate(out->m_Int, offset);
}
bool Locate(char *error, size_t length) {
    sm_sendprop_info_t score{}, connected{};
    if (!gamehelpers->FindSendPropInfo("CTFPlayerResource", "m_iTotalScore", &score)
        || !gamehelpers->FindSendPropInfo("CTFPlayerResource", "m_bConnected", &connected)
        || score.prop->GetType() != DPT_DataTable || connected.prop->GetType() != DPT_DataTable
        || !score.prop->GetDataTable() || !connected.prop->GetDataTable()) {
        snprintf(error,length,"TF2 score/connection Array3 properties are unavailable"); return false;
    }
    auto scores = score.prop->GetDataTable(), connections = connected.prop->GetDataTable();
    count = scores->GetNumProps(); scoreOffset = score.actual_offset; connectedOffset = connected.actual_offset;
    if (count < globals->maxClients + 1 || count > Slots || connections->GetNumProps() != count
        || scoreOffset < 1 || connectedOffset < 1 || scoreOffset + count * sizeof(int) > USHRT_MAX) {
        snprintf(error,length,"Unsupported TF2 score-array layout"); return false;
    }
    for (int i = 0; i < count; ++i) {
        auto value = scores->GetProp(i), connection = connections->GetProp(i);
        if (value->GetType() != DPT_Int || value->GetOffset() != i * sizeof(int)
            || !value->GetProxyFn() || value->GetProxyFn() == ScoreProxy
            || connection->GetType() != DPT_Int || !connection->GetProxyFn()) {
            snprintf(error,length,"Unsupported TF2 score-array member %d",i); return false;
        }
        slots[i].prop = value; slots[i].original = value->GetProxyFn(); slots[i].connected = connection;
    }
    return true;
}
bool Claim(IPluginContext *context) {
    if (owner && owner != context) { context->ThrowNativeError("Score display already has a controlling plugin"); return false; }
    owner = context; return true;
}
cell_t Api(IPluginContext *, const cell_t *) { return 1; }
cell_t Set(IPluginContext *context, const cell_t *params) {
    const int client = params[1];
    if (client < 1 || client >= count || client > globals->maxClients)
        return context->ThrowNativeError("Invalid scoreboard client index");
    if (!Claim(context)) return 0;
    const int64_t value = static_cast<int64_t>(params[2]) + params[3];
    if (slots[client].offset.exchange(value) != value) Dirty(client);
    return 0;
}
cell_t Reset(IPluginContext *context, const cell_t *) {
    if (!Claim(context)) return 0;
    Clear(); return 0;
}
cell_t Compute(IPluginContext *, const cell_t *params) {
    return Calculate(params[1], static_cast<int64_t>(params[2]) + params[3]);
}
cell_t ReadWireValue(IPluginContext *context, const cell_t *params) {
    const int id = params[1], client = params[2];
    auto entity = gamehelpers->ReferenceToEntity(id);
    if (!IsResource(entity) || client < 0 || client >= count)
        return context->ThrowNativeError("Invalid player resource or array index");
    auto &slot = slots[client]; auto base = reinterpret_cast<const char *>(entity) + scoreOffset;
    DVariant out{};
    const bool previous = diagnosticRead; diagnosticRead = true;
    slot.prop->GetProxyFn()(slot.prop, base, base + slot.prop->GetOffset(), &out, 0, id);
    diagnosticRead = previous;
    return out.m_Int;
}
cell_t NetworkSample(IPluginContext *context, const cell_t *params) {
    if(params[1]<1 || params[1]>=count) return context->ThrowNativeError("Invalid client index");
    cell_t *out; context->LocalToPhysAddr(params[2],&out);
    *out=slots[params[1]].lastEncoded.load();
    return static_cast<cell_t>(slots[params[1]].encoded.load());
}
#ifdef RESTORESCORE_TEST
cell_t TestPause(IPluginContext *, const cell_t *params) {
    auto iter=plsys->GetPluginIterator(); bool changed=false;
    while(iter->MorePlugins()) {
        auto plugin=iter->GetPlugin();
        if(plugin->GetBaseContext()==owner) { changed=plugin->SetPauseState(params[1]!=0); break; }
        iter->NextPlugin();
    }
    iter->Release(); return changed;
}
#endif
sp_nativeinfo_t natives[] = {
    {"RSDisplay_ApiVersion",Api}, {"RSDisplay_Set",Set}, {"RSDisplay_Reset",Reset},
    {"RSDisplay_Calculate",Compute}, {"RSDisplay_ReadSerialized",ReadWireValue},
    {"RSDisplay_NetworkSample",NetworkSample},
#ifdef RESTORESCORE_TEST
    {"RSTest_SetOwnerPaused",TestPause},
#endif
    {nullptr,nullptr}
};
class MapHooks {
public:
    void Shutdown() {
        // Disconnect callbacks can follow destruction of map entities. Never
        // enumerate/dirty edicts during that interval.
        worldActive.store(false); Clear(); RETURN_META(MRES_IGNORED);
    }
    void Activate(edict_t *,int,int) { worldActive.store(true); RETURN_META(MRES_IGNORED); }
} mapHooks;
}
bool RestoreScoreDisplay::SDK_OnMetamodLoad(ISmmAPI *ismm, char *error, size_t maxlen, bool) {
    GET_V_IFACE_CURRENT(GetServerFactory, serverDll, IServerGameDLL, INTERFACEVERSION_SERVERGAMEDLL);
    globals = ismm->GetCGlobals(); return true;
}
bool RestoreScoreDisplay::SDK_OnLoad(char *error, size_t length, bool) {
    if (!Locate(error,length)) return false;
    shutdownHook=SH_ADD_HOOK(IServerGameDLL,LevelShutdown,serverDll,SH_MEMBER(&mapHooks,&MapHooks::Shutdown),false);
    activateHook=SH_ADD_HOOK(IServerGameDLL,ServerActivate,serverDll,SH_MEMBER(&mapHooks,&MapHooks::Activate),true);
    if (!shutdownHook || !activateHook) {
        if(shutdownHook) SH_REMOVE_HOOK_ID(shutdownHook);
        if(activateHook) SH_REMOVE_HOOK_ID(activateHook);
        snprintf(error,length,"Cannot install map lifecycle hooks"); return false;
    }
    worldActive.store(smutils->IsMapRunning());
    for (int i = 0; i < count; ++i) slots[i].prop->SetProxyFn(ScoreProxy);
    installed = true;
    sharesys->AddNatives(myself,natives); sharesys->RegisterLibrary(myself,"restore_score_display");
    playerhelpers->AddClientListener(this); plsys->AddPluginsListener(this);
    Dirty(); return true;
}
void RestoreScoreDisplay::SDK_OnUnload() {
    if (!installed) return;
    playerhelpers->RemoveClientListener(this); plsys->RemovePluginsListener(this);
    Clear();
    for (int i = 0; i < count; ++i)
        if (slots[i].prop->GetProxyFn() == ScoreProxy) slots[i].prop->SetProxyFn(slots[i].original);
    Dirty(); owner = nullptr; installed = false;
    if(shutdownHook) SH_REMOVE_HOOK_ID(shutdownHook);
    if(activateHook) SH_REMOVE_HOOK_ID(activateHook);
}
void RestoreScoreDisplay::OnClientConnected(int client) {
    if (client > 0 && client < count && slots[client].offset.exchange(0)) Dirty(client);
}
void RestoreScoreDisplay::OnClientDisconnected(int client) { OnClientConnected(client); }
void RestoreScoreDisplay::OnPluginUnloaded(IPlugin *plugin) {
    if (plugin->GetBaseContext() == owner) { Clear(); owner = nullptr; paused = false; }
}
void RestoreScoreDisplay::OnPluginPauseChange(IPlugin *plugin, bool state) {
    if (plugin->GetBaseContext() == owner) { paused = state; Dirty(); }
}
