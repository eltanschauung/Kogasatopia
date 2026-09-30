#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <dhooks>
#include <collisionhook>
#include <tf2utils>
#include <oblivion_net>

#define VERSION "0.2.2"
#define AUTH_LEN 40
#define ENTITY_LIMIT 2049

public Plugin myinfo =
{
    name = "Oblivion",
    author = "Codex",
    description = "Persistent directional player isolation for TF2",
    version = VERSION
};

enum struct Pair
{
    char viewer[AUTH_LEN];
    char subject[AUTH_LEN];
}

ArrayList g_Pairs;
char g_Auth[MAXPLAYERS + 1][AUTH_LEN];
bool g_Hidden[MAXPLAYERS + 1][MAXPLAYERS + 1];
bool g_HasRules[MAXPLAYERS + 1];
bool g_VoiceOwned[MAXPLAYERS + 1][MAXPLAYERS + 1];
ListenOverride g_VoicePrevious[MAXPLAYERS + 1][MAXPLAYERS + 1];
int g_Actor[ENTITY_LIMIT];
int g_ActorSerial[ENTITY_LIMIT];
char g_EntityAuth[ENTITY_LIMIT][AUTH_LEN];
int g_OwnerProps[ENTITY_LIMIT];
bool g_Ragdoll[ENTITY_LIMIT];
bool g_DroppedWeapon[ENTITY_LIMIT];
int g_DroppedOwnerOffset;
bool g_EntityHooked[ENTITY_LIMIT];
GlobalForward g_StateChanged;
char g_Store[PLATFORM_MAX_PATH];
bool g_Ready;
bool g_MapActive;
bool g_BrowserDisconnecting[MAXPLAYERS + 1];

#include "oblivion/pairs.sp"
#include "oblivion/roster.sp"
#include "oblivion/teams.sp"
#include "oblivion/entities.sp"
#include "oblivion/messages.sp"
#include "oblivion/interactions.sp"
#include "oblivion/effects.sp"
#include "oblivion/browser.sp"

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int maxlength)
{
    RegPluginLibrary("oblivion");
    CreateNative("Oblivion_IsHidden", Native_IsHidden);
    CreateNative("Oblivion_CanInteract", Native_CanInteract);
    CreateNative("Oblivion_IsSteamHidden", Native_IsSteamHidden);
    CreateNative("Oblivion_RegisterEntityOwner", Native_RegisterEntityOwner);
    return APLRes_Success;
}

public void OnPluginStart()
{
    if (GetEngineVersion() != Engine_TF2)
        SetFailState("Oblivion requires Team Fortress 2.");
    if (OblivionNet_ApiVersion() != 4)
        SetFailState("Unsupported Oblivion Network extension API.");
    // SDK CTFDroppedWeapon: the private CHandle<CTFPlayer> immediately follows
    // the networked float m_flChargeLevel. Both fields are four bytes on TF2's
    // supported 32/64-bit platforms. The real death/drop regression checks this.
    g_DroppedOwnerOffset = FindSendPropInfo("CTFDroppedWeapon", "m_flChargeLevel");
    if (g_DroppedOwnerOffset <= 0) SetFailState("Cannot locate dropped-weapon ownership.");
    g_DroppedOwnerOffset += 4;
    g_StateChanged = new GlobalForward("Oblivion_OnStateChanged", ET_Ignore);
    Roster_Reset();
    OblivionNet_TeamStart();
    Teams_Reset();
    g_Pairs = new ArrayList(sizeof(Pair));
    BuildPath(Path_SM, g_Store, sizeof(g_Store), "data/oblivion_pairs.kv");
    LoadPairs();
    RegAdminCmd("sm_oblivion", Command_Oblivion, ADMFLAG_ROOT, "sm_oblivion <viewer> <hidden player> [on|off]");
    RegAdminCmd("sm_oblivion_list", Command_List, ADMFLAG_ROOT, "List persistent directional oblivion pairings.");
    RegAdminCmd("sm_oblivion_status", Command_Status, ADMFLAG_ROOT, "Report isolation state and dependencies.");
    Messages_Start();
    Interactions_Start();
    Effects_Start();
    Browser_Start();
    AddNormalSoundHook(FilterSound);
    CreateTimer(0.10, Maintenance, _, TIMER_REPEAT);
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client)) OnClientPutInServer(client);
    g_Ready = true;
    RebuildPairs();
    CreateTimer(0.2, LateStart, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action LateStart(Handle timer)
{
    g_MapActive = true;
    Roster_Start();
    Teams_Update();
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client)) RememberSharedState(client);
    for (int entity = MaxClients + 1; entity < GetMaxEntities() && entity < ENTITY_LIMIT; entity++)
        if (IsValidEntity(entity)) HookEntity(entity);
    Browser_Publish();
    return Plugin_Stop;
}

public void OnMapStart()
{
    g_MapActive = true;
    PrecacheSound("common/null.wav", true);
    Effects_Reset();
    if (g_SharedClients != null) g_SharedClients.Clear();
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client)) RememberSharedState(client);
    Roster_Reset();
    Teams_Reset();
    Teams_Start();
    Browser_Publish();
    CreateTimer(0.2, LateStart, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd()
{
    g_MapActive = false;
    Effects_Reset();
    Roster_Reset();
    Teams_Reset();
    Browser_Publish();
}

public void OnClientConnected(int client)
{
    g_BrowserDisconnecting[client] = false;
    g_BrowserConnectedAt[client] = GetEngineTime();
    g_Auth[client][0] = '\0';
    g_HasRules[client] = false;
    for (int other = 1; other <= MaxClients; other++)
    {
        g_Hidden[client][other] = false;
        g_Hidden[other][client] = false;
        g_VoiceOwned[client][other] = false;
        g_VoiceOwned[other][client] = false;
    }
    char pending[AUTH_LEN];
    if (GetClientAuthId(client, AuthId_Steam2, pending, sizeof(pending), false))
        CanonicalAuth(pending, g_Auth[client], AUTH_LEN);
    if (g_Ready) RebuildPairs();
}

public void OnClientAuthorized(int client, const char[] auth)
{
    CanonicalAuth(auth, g_Auth[client], AUTH_LEN);
    if (g_Ready) RebuildPairs();
}

public void OnClientPutInServer(int client)
{
    char auth[AUTH_LEN];
    if (GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), false))
        CanonicalAuth(auth, g_Auth[client], AUTH_LEN);
    SDKHook(client, SDKHook_OnTakeDamage, FilterDamage);
    SDKHook(client, SDKHook_TraceAttack, FilterTraceAttack);
    SDKHook(client, SDKHook_StartTouch, FilterTouch);
    SDKHook(client, SDKHook_Touch, FilterTouch);
    Interactions_HookEntity(client);
    if (g_Ready) RebuildPairs();
}

public void OnClientDisconnect(int client)
{
    g_BrowserDisconnecting[client] = true;
    Teams_Remove(client);
    Browser_Publish();
    // Keep identity until the slot is reused so disconnect notifications can
    // still be checked by this plugin and by Kogasa's alert integration.
    for (int i = 1; i <= MaxClients; i++)
    {
        g_VoiceOwned[client][i] = false;
        g_VoiceOwned[i][client] = false;
    }
}

public void OnPluginEnd()
{
    Teams_Release();
    OblivionNet_BrowserClear();
    for (int viewer = 1; viewer <= MaxClients; viewer++)
        for (int subject = 1; subject <= MaxClients; subject++)
            if (g_VoiceOwned[viewer][subject] && IsClientInGame(viewer) && IsClientInGame(subject))
                SetListenOverride(viewer, subject, g_VoicePrevious[viewer][subject]);
    Roster_Release();
}

public Action Maintenance(Handle timer)
{
    if (!g_Ready || !g_MapActive) return Plugin_Continue;
    Roster_Update();
    Teams_Update();
    Browser_Publish();
    for (int v = 1; v <= MaxClients; v++)
    {
        if (!IsClientInGame(v)) continue;
        for (int s = 1; s <= MaxClients; s++)
        {
            if (!IsClientInGame(s) || v == s) continue;
            if (g_Hidden[v][s])
            {
                if (!g_VoiceOwned[v][s]) g_VoicePrevious[v][s] = GetListenOverride(v, s);
                g_VoiceOwned[v][s] = true;
                if (GetListenOverride(v, s) != Listen_No) SetListenOverride(v, s, Listen_No);
            }
            else if (g_VoiceOwned[v][s])
            {
                if (GetListenOverride(v, s) == Listen_No) SetListenOverride(v, s, g_VoicePrevious[v][s]);
                g_VoiceOwned[v][s] = false;
            }
        }
        if (!IsPlayerAlive(v) && HasEntProp(v, Prop_Send, "m_hObserverTarget"))
        {
            int target = GetEntPropEnt(v, Prop_Send, "m_hObserverTarget");
            if (Hidden(v, target))
            {
                SetEntPropEnt(v, Prop_Send, "m_hObserverTarget", -1);
                SetEntProp(v, Prop_Send, "m_iObserverMode", 6);
            }
        }
    }
    return Plugin_Continue;
}

bool Hidden(int viewer, int subject)
{
    return viewer > 0 && viewer <= MaxClients && subject > 0 && subject <= MaxClients && g_Hidden[viewer][subject];
}

bool Blocked(int first, int second)
{
    return Hidden(first, second) || Hidden(second, first);
}

public any Native_IsHidden(Handle plugin, int numParams)
{
    return Hidden(GetNativeCell(1), GetNativeCell(2));
}

public any Native_CanInteract(Handle plugin, int numParams)
{
    return !Blocked(GetNativeCell(1), GetNativeCell(2));
}

public any Native_IsSteamHidden(Handle plugin, int numParams)
{
    char auth[AUTH_LEN], canonical[AUTH_LEN];
    GetNativeString(2, auth, sizeof(auth));
    if (!CanonicalAuth(auth, canonical, sizeof(canonical))) return false;
    return HiddenAuth(GetNativeCell(1), canonical);
}

public any Native_RegisterEntityOwner(Handle plugin, int numParams)
{
    int entity = GetNativeCell(1), owner = GetNativeCell(2);
    if (entity <= MaxClients || entity >= ENTITY_LIMIT || !IsValidEntity(entity)
        || owner < 1 || owner > MaxClients || !IsClientConnected(owner))
        return ThrowNativeError(SP_ERROR_NATIVE, "Expected a valid entity and connected owner.");
    HookEntity(entity);
    RememberActor(entity, owner);
    return true;
}

public Action Command_Status(int client, int args)
{
    ReplyToCommand(client, "[Oblivion] %s; %d persistent pairs; resource=%d; TF2Utils=%s.", VERSION,
        g_Pairs.Length, EntRefToEntIndex(g_Resource),
        GetFeatureStatus(FeatureType_Native, "TF2Util_GetPlayerConditionProvider") == FeatureStatus_Available ? "available" : "unavailable");
    int snapshots, removed;
    OblivionNet_GetCounters(snapshots, removed);
    ReplyToCommand(client, "[Oblivion] Final transmission filter: %d snapshots, %d entity exclusions.", snapshots, removed);
    Browser_Status(client);
    Teams_Status(client);
    return Plugin_Handled;
}
