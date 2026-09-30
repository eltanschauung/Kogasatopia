// SPDX-License-Identifier: GPL-3.0-or-later
#include "extension.h"
#include "iservernetworkable.h"
#include "browser_hooks.h"
#include "team_mirrors.h"
#include <cstring>

OblivionNetwork g_Network;
SMEXT_LINK(&g_Network);
SH_DECL_HOOK3_void(IServerGameEnts, CheckTransmit, SH_NOATTRIB, 0,
                  CCheckTransmitInfo *, const unsigned short *, int);

static IServerGameEnts *g_GameEnts;
static IForward *g_TransmitForward;
static int g_HookId;
static unsigned int g_Packets, g_Removed;
#ifdef OBLIVION_NETWORK_TESTS
static bool g_SkipTestFilter;
#endif

static cell_t GetApiVersion(IPluginContext *, const cell_t *) { return 4; }
static cell_t GetCounters(IPluginContext *context, const cell_t *params)
{
    cell_t *packets, *removed;
    context->LocalToPhysAddr(params[1], &packets);
    context->LocalToPhysAddr(params[2], &removed);
    *packets = static_cast<cell_t>(g_Packets);
    *removed = static_cast<cell_t>(g_Removed);
    return 0;
}

#ifdef OBLIVION_NETWORK_TESTS
// Only compiled into the isolated-test binary. Executes the real game interface
// and its SourceHook chain; does not contact or instrument a TF2 client.
static cell_t TestTransmit(IPluginContext *context, const cell_t *params)
{
    const int viewer = params[1], count = params[3];
    IGamePlayer *player = playerhelpers->GetGamePlayer(viewer);
    if (!player || !player->IsInGame() || count < 1 || count > 64)
        return context->ThrowNativeError("Invalid transmission fixture");
    cell_t *entities, *output;
    context->LocalToPhysAddr(params[2], &entities);
    context->LocalToPhysAddr(params[4], &output);
    unsigned short indices[64];
    edict_t *edicts[64];
    int flags[64];
    for (int i = 0; i < count; ++i)
    {
        if (entities[i] < 1 || entities[i] >= MAX_EDICTS)
            return context->ThrowNativeError("Invalid fixture edict");
        edicts[i] = gamehelpers->EdictOfIndex(entities[i]);
        if (!edicts[i] || edicts[i]->IsFree())
            return context->ThrowNativeError("Fixture edict is free");
        for (int previous = 0; previous < i; ++previous)
            if (entities[previous] == entities[i])
                return context->ThrowNativeError("Duplicate fixture edict");
        indices[i] = static_cast<unsigned short>(entities[i]);
        flags[i] = edicts[i]->m_fStateFlags;
    }
    CCheckTransmitInfo info;
    std::memset(&info, 0, sizeof(info));
    CBitVec<MAX_EDICTS> bits;
    bits.ClearAll();
    info.m_pClientEnt = player->GetEdict();
    info.m_pTransmitEdict = &bits;
    for (int i = 0; i < count; ++i)
    {
        edicts[i]->m_fStateFlags = (flags[i] & ~(FL_EDICT_DONTSEND | FL_EDICT_PVSCHECK)) | FL_EDICT_ALWAYS;
        if (params[5]) bits.Set(indices[i]);
    }
    g_SkipTestFilter = !params[6];
    g_GameEnts->CheckTransmit(&info, indices, count);
    g_SkipTestFilter = false;
    for (int i = 0; i < count; ++i)
    {
        output[i] = bits.Get(indices[i]) ? 1 : 0;
        edicts[i]->m_fStateFlags = flags[i];
    }
    return 1;
}
#endif

static sp_nativeinfo_t g_Natives[] = {
    {"OblivionNet_ApiVersion", GetApiVersion},
    {"OblivionNet_GetCounters", GetCounters},
#ifdef OBLIVION_NETWORK_TESTS
    {"OblivionNet_TestTransmit", TestTransmit},
#endif
    {nullptr, nullptr}
};

bool OblivionNetwork::SDK_OnMetamodLoad(ISmmAPI *ismm, char *error, size_t maxlen, bool late)
{
    GET_V_IFACE_CURRENT(GetServerFactory, g_GameEnts, IServerGameEnts, INTERFACEVERSION_SERVERGAMEENTS);
    return BrowserMetamodLoad(ismm, error, maxlen);
}

bool OblivionNetwork::SDK_OnLoad(char *error, size_t maxlength, bool late)
{
    g_TransmitForward = forwards->CreateForward("OblivionNet_CheckTransmit", ET_Ignore, 4, nullptr,
                                               Param_Cell, Param_Array, Param_Cell, Param_Array);
    g_HookId = SH_ADD_HOOK(IServerGameEnts, CheckTransmit, g_GameEnts,
                         SH_MEMBER(this, &OblivionNetwork::CheckTransmitPost), true);
    if (!g_HookId)
    {
        forwards->ReleaseForward(g_TransmitForward);
        g_TransmitForward = nullptr;
        snprintf(error, maxlength, "Cannot hook IServerGameEnts::CheckTransmit");
        return false;
    }
    sharesys->AddNatives(myself, g_Natives);
    RegisterTeamMirrorNatives();
    sharesys->RegisterLibrary(myself, "oblivion_net");
    if (!BrowserStart(error, maxlength))
    {
        SH_REMOVE_HOOK_ID(g_HookId); g_HookId = 0;
        forwards->ReleaseForward(g_TransmitForward); g_TransmitForward = nullptr;
        return false;
    }
    return true;
}

void OblivionNetwork::SDK_OnUnload()
{
    StopTeamMirrors();
    BrowserStop();
    if (g_HookId) { SH_REMOVE_HOOK_ID(g_HookId); g_HookId = 0; }
    if (g_TransmitForward) { forwards->ReleaseForward(g_TransmitForward); g_TransmitForward = nullptr; }
}

void OblivionNetwork::CheckTransmitPost(CCheckTransmitInfo *info, const unsigned short *, int)
{
#ifdef OBLIVION_NETWORK_TESTS
    if (g_SkipTestFilter) RETURN_META(MRES_IGNORED);
#endif
    if (!info || !info->m_pTransmitEdict || !g_TransmitForward || !g_TransmitForward->GetFunctionCount())
        RETURN_META(MRES_IGNORED);
    int viewer = gamehelpers->IndexOfEdict(info->m_pClientEnt);
    if (viewer < 1 || viewer > playerhelpers->GetMaxClients()) RETURN_META(MRES_IGNORED);

    // Read the final bits, including ALWAYS entities and parents already marked
    // by another entity. SetTransmit callbacks miss both of those engine paths.
    cell_t entities[MAX_EDICTS], blocked[MAX_EDICTS] = {};
    unsigned int count = 0;
    for (int entity = 1; entity < MAX_EDICTS; ++entity)
        if (info->m_pTransmitEdict->Get(entity)) entities[count++] = entity;
    if (!count) RETURN_META(MRES_IGNORED);
    g_TransmitForward->PushCell(viewer);
    g_TransmitForward->PushArray(entities, count);
    g_TransmitForward->PushCell(count);
    g_TransmitForward->PushArray(blocked, count, SM_PARAM_COPYBACK);
    g_TransmitForward->Execute(nullptr);
    ++g_Packets;
    for (unsigned int i = 0; i < count; ++i)
    {
        // Never remove the recipient's own player entity, even on script error.
        if (!blocked[i] || entities[i] == viewer) continue;
        info->m_pTransmitEdict->Clear(entities[i]);
        if (info->m_pTransmitAlways) info->m_pTransmitAlways->Clear(entities[i]);
        ++g_Removed;
    }
    RETURN_META(MRES_IGNORED);
}
