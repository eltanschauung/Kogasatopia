#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdktools_voice>
#include <tf2_stocks>
#include <morecolors>

#undef REQUIRE_PLUGIN
#include <dgm_api>
#include <plugin_statistics>
#define REQUIRE_PLUGIN

#include "include/client_validation.inc"

public Plugin myinfo = {
    name = "AFK Manager",
    author = "random, Hombre, Eric Zhang",
    description = "AFK management and spectator capacity/queue management",
    version = "2.0",
    url = "http://castaway.tf"
};

#define AFK_ACTION_BUTTONS (IN_ATTACK | IN_JUMP | IN_DUCK | IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_ATTACK2 | IN_RELOAD | IN_SCORE | IN_USE)
#define AFK_DOUBLE_LIVE_TIMEOUT_STEAMID64 "76561198163255365"
#define AFK_MAINTENANCE_INTERVAL 1.0

enum AFKAction {
    AFKAction_Kick,
    AFKAction_SpectateAndKick,
    AFKAction_SpectateOnly
}

enum struct AFKClientState {
    float lastActivityTime;
    float lastIdleCheck;
    float idleSeconds;
    bool movedToSpec;
    bool doubleLiveTimeout;
}

AFKClientState g_AFKClients[MAXPLAYERS + 1];
ConVar g_cvAFKEnabled;
ConVar g_cvAFKAction;
ConVar g_cvAFKAliveTime;
ConVar g_cvAFKSpecTime;
ConVar g_cvAFKSpecMovedTime;
ConVar g_cvAFKMinPlayerCount;
ConVar g_cvAFKKickSpecMinPlayerCount;
ConVar g_cvEngineIdleMethod;
int g_iOriginalIdleMethod;
GlobalForward g_fwAFKKick;
GlobalForward g_fwAFKSwitch;
Handle g_hAFKMaintenanceTimer;
float g_flNextQueueActivityCheck;
bool g_bAFKMapActive;

#include "afkmanager/spec-when-full.sp"

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int errMax) {
    MarkNativeAsOptional("DGM_ServerCapacitycheck");
    SpecQueue_MarkNativesOptional();
    RegPluginLibrary("afkmanager");
    CreateNative("AFKManager_GetLastActivityTime", Native_GetLastActivityTime);
    return APLRes_Success;
}

public any Native_GetLastActivityTime(Handle plugin, int numParams) {
    return view_as<int>(AFK_GetLastActivityTime(GetNativeCell(1)));
}

public void OnPluginStart() {
    // A late-load migration must not leave two owners of jointeam and !spec.
    if (FindPluginByFile("spec-when-full.smx") != null) {
        ServerCommand("sm plugins unload spec-when-full");
        ServerExecute();
        // SourceMod defers plugin removal until this startup callback returns.
        RequestFrame(AFK_VerifyLegacyPluginRetired);
    }

    g_cvAFKEnabled = CreateConVar("sm_afkmanager_enabled", "1", "Enable AFK management; spectator queue controls are independent.", _, true, 0.0, true, 1.0);
    g_cvAFKAction = CreateConVar("sm_afkmanager_afk_action", "1", "AFK action: 0 = kick, 1 = move to spectator and kick idle spectators, 2 = move to spectator only.", _, true, 0.0, true, 2.0);
    g_cvAFKAliveTime = CreateConVar("sm_afkmanager_alive_time", "60", "Idle live-player timeout in seconds.", _, true, 60.0);
    g_cvAFKSpecTime = CreateConVar("sm_afkmanager_spec_time", "300", "Idle spectator timeout in seconds.", _, true, 60.0);
    g_cvAFKSpecMovedTime = CreateConVar("sm_afkmanager_spec_moved_time", "180", "Idle spectator timeout after being moved by AFK Manager.", _, true, 60.0);
    g_cvAFKMinPlayerCount = CreateConVar("sm_afkmanager_min_player_count", "2", "Minimum in-game player count before AFK actions.", _, true, 0.0);
    g_cvAFKKickSpecMinPlayerCount = CreateConVar("sm_afkmanager_kick_spec_min_player_count", "24", "Fallback population threshold for kicking idle spectators without DGM.", _, true, 0.0);
    g_cvAFKEnabled.AddChangeHook(AFK_OnEnabledChanged);

    g_fwAFKKick = new GlobalForward("OnAFKKick", ET_Hook, Param_Cell);
    g_fwAFKSwitch = new GlobalForward("OnAFKSwitch", ET_Ignore, Param_Cell);

    HookEvent("player_team", AFK_EventPlayerTeam, EventHookMode_Post);
    HookEvent("player_changeclass", AFK_EventPlayerClass, EventHookMode_Post);

    static const char activityCommands[][] = {
        "spec_next", "spec_prev", "spec_mode", "say", "say_team", "voicemenu"
    };
    for (int i = 0; i < sizeof(activityCommands); i++) {
        AddCommandListener(AFK_OnActivityCommand, activityCommands[i]);
    }

    g_cvEngineIdleMethod = FindConVar("mp_idledealmethod");
    if (g_cvEngineIdleMethod != null) {
        g_iOriginalIdleMethod = g_cvEngineIdleMethod.IntValue;
        g_cvEngineIdleMethod.IntValue = 0;
    }

    AFK_ResetAllClients();
    SpecQueue_Init();
    AutoExecConfig(true, "afkmanager", "sourcemod");
}

public void AFK_VerifyLegacyPluginRetired(any data) {
    if (FindPluginByFile("spec-when-full.smx") != null) {
        SetFailState("Unload the retired spec-when-full plugin before loading AFK Manager");
    }
}

public void OnMapStart() {
    g_bAFKMapActive = true;
    AFK_ResetAllClients();
    SpecQueue_OnMapStart();
    AFK_StartMaintenance();
}

public void OnMapEnd() {
    g_bAFKMapActive = false;
    AFK_StopMaintenance();
    SpecQueue_OnMapEnd();
}

public void OnConfigsExecuted() {
    SpecQueue_OnConfigsExecuted();
}

public void OnClientConnected(int client) {
    AFK_ResetClient(client);
    SpecQueue_OnClientConnected(client);
}

public void OnClientPutInServer(int client) {
    AFK_ResetIdle(client, GetEngineTime());
    SpecQueue_OnClientPutInServer(client);
}

public void OnClientPostAdminCheck(int client) {
    AFK_CacheTimeoutException(client);
}

public void OnClientDisconnect(int client) {
    SpecQueue_OnClientDisconnect(client);
    AFK_ResetClient(client);
}

public void OnClientDisconnect_Post(int client) {
    SpecQueue_OnClientDisconnect_Post();
}

public void OnServerEnterHibernation() {
    AFK_StopMaintenance();
    SpecQueue_OnServerEnterHibernation();
}

public void OnServerExitHibernation() {
    if (g_bAFKMapActive) {
        AFK_StartMaintenance();
    }
}

public void OnPluginEnd() {
    AFK_StopMaintenance();
    SpecQueue_Shutdown();
    if (g_cvEngineIdleMethod != null && g_cvEngineIdleMethod.IntValue == 0) {
        g_cvEngineIdleMethod.IntValue = g_iOriginalIdleMethod;
    }
    delete g_fwAFKKick;
    delete g_fwAFKSwitch;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse,
    float velocity[3], float angles[3], int &weapon, int &subtype,
    int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
    if ((buttons & AFK_ACTION_BUTTONS) != 0 || impulse != 0 || weapon != 0
        || mouse[0] != 0 || mouse[1] != 0) {
        AFK_RecordActivity(client);
    }
    return Plugin_Continue;
}

public void OnClientSpeaking(int client) {
    AFK_RecordActivity(client);
}

public Action AFK_OnActivityCommand(int client, const char[] command, int argc) {
    AFK_RecordActivity(client);
    return Plugin_Continue;
}

public void AFK_EventPlayerTeam(Event event, const char[] name, bool dontBroadcast) {
    if (event.GetBool("disconnect")) {
        return;
    }
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!Client_IsHumanInGame(client)) {
        return;
    }
    int team = event.GetInt("team");
    AFK_ResetIdle(client, GetEngineTime());
    if (SpecQueue_IsPlayingTeam(team)) {
        g_AFKClients[client].movedToSpec = false;
    }
    SpecQueue_OnPlayerTeam(client, event.GetInt("oldteam"), team);
}

public void AFK_EventPlayerClass(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (Client_IsHumanInGame(client)) {
        AFK_ResetIdle(client, GetEngineTime());
    }
}

public void AFK_OnEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    float now = GetEngineTime();
    for (int client = 1; client <= MaxClients; client++) {
        AFK_ResetIdle(client, now);
    }
}

void AFK_StartMaintenance() {
    if (g_hAFKMaintenanceTimer == null) {
        g_flNextQueueActivityCheck = GetEngineTime() + SQ_ACTIVITY_QUEUE_INTERVAL;
        g_hAFKMaintenanceTimer = CreateTimer(AFK_MAINTENANCE_INTERVAL, AFK_TimerMaintenance, _, TIMER_REPEAT);
    }
}

void AFK_StopMaintenance() {
    if (g_hAFKMaintenanceTimer != null) {
        delete g_hAFKMaintenanceTimer;
        g_hAFKMaintenanceTimer = null;
    }
}

public Action AFK_TimerMaintenance(Handle timer) {
    float now = GetEngineTime();
    if (g_cvAFKEnabled.BoolValue) {
        AFK_ManageClients(now);
    }
    if (now >= g_flNextQueueActivityCheck) {
        g_flNextQueueActivityCheck = now + SQ_ACTIVITY_QUEUE_INTERVAL;
        SpecQueue_CheckActivity(now);
    }
    return Plugin_Continue;
}

float AFK_GetLastActivityTime(int client) {
    return Client_IsHumanInGame(client) ? g_AFKClients[client].lastActivityTime : 0.0;
}

void AFK_ResetIdle(int client, float now) {
    g_AFKClients[client].idleSeconds = 0.0;
    g_AFKClients[client].lastIdleCheck = now;
}

void AFK_AdvanceIdle(int client, float now, bool countIdle) {
    float elapsed = now - g_AFKClients[client].lastIdleCheck;
    g_AFKClients[client].lastIdleCheck = now;
    if (countIdle && elapsed > 0.0) {
        g_AFKClients[client].idleSeconds += elapsed;
    }
}

void AFK_RecordActivity(int client) {
    if (!Client_IsHumanInGame(client)) {
        return;
    }
    float now = GetEngineTime();
    g_AFKClients[client].lastActivityTime = now;
    AFK_ResetIdle(client, now);
}

void AFK_ResetClient(int client) {
    g_AFKClients[client].lastActivityTime = 0.0;
    g_AFKClients[client].movedToSpec = false;
    g_AFKClients[client].doubleLiveTimeout = false;
    AFK_ResetIdle(client, GetEngineTime());
}

void AFK_ResetAllClients() {
    for (int client = 1; client <= MaxClients; client++) {
        AFK_ResetClient(client);
        AFK_CacheTimeoutException(client);
    }
}

void AFK_CacheTimeoutException(int client) {
    if (!Client_IsHumanInGame(client) || !IsClientAuthorized(client)) {
        return;
    }
    char steamId64[32];
    g_AFKClients[client].doubleLiveTimeout = GetClientAuthId(client, AuthId_SteamID64, steamId64, sizeof(steamId64), true)
        && StrEqual(steamId64, AFK_DOUBLE_LIVE_TIMEOUT_STEAMID64);
}

bool AFK_CanKickSpectators() {
    if (GetFeatureStatus(FeatureType_Native, "DGM_ServerCapacitycheck") == FeatureStatus_Available) {
        return DGM_ServerCapacitycheck(1.0, false);
    }
    return GetClientCount(false) >= g_cvAFKKickSpecMinPlayerCount.IntValue;
}

bool AFK_KickClient(int client) {
    if (SpecQueue_BlocksAFKKick(client)) {
        return false;
    }
    int userId = GetClientUserId(client);
    Action result = Plugin_Continue;
    Call_StartForward(g_fwAFKKick);
    Call_PushCell(client);
    Call_Finish(result);
    if (result != Plugin_Continue || !Client_IsHumanInGame(client)
        || GetClientUserId(client) != userId) {
        return false;
    }
    KickClient(client, "#TF_Idle_kicked");
    return true;
}

void AFK_MoveToSpectator(int client, float now) {
    TF2_ChangeClientTeam(client, TFTeam_Spectator);
    AFK_ResetIdle(client, now);
    if (Client_IsHumanInGame(client) && GetClientTeam(client) == view_as<int>(TFTeam_Spectator)) {
        g_AFKClients[client].movedToSpec = true;
        SpecQueue_OnAFKSwitch(client);
        Call_StartForward(g_fwAFKSwitch);
        Call_PushCell(client);
        Call_Finish();
    }
}

void AFK_ManageClients(float now) {
    AFKAction action = view_as<AFKAction>(g_cvAFKAction.IntValue);
    bool belowMinimum = GetClientCount(true) < g_cvAFKMinPlayerCount.IntValue;
    bool canKickSpectators = AFK_CanKickSpectators();

    for (int client = 1; client <= MaxClients; client++) {
        if (!Client_IsHumanInGame(client)) {
            continue;
        }
        int team = GetClientTeam(client);
        bool playing = SpecQueue_IsPlayingTeam(team);
        bool observing = team == view_as<int>(TFTeam_Unassigned) || team == view_as<int>(TFTeam_Spectator);
        if (belowMinimum || (!playing && (!observing || !canKickSpectators))) {
            AFK_ResetIdle(client, now);
            continue;
        }

        bool deadWithClass = playing && !IsPlayerAlive(client) && TF2_GetPlayerClass(client) != TFClass_Unknown;
        AFK_AdvanceIdle(client, now, !deadWithClass);
        if (deadWithClass || (!playing && action == AFKAction_SpectateOnly)) {
            continue;
        }

        float timeout;
        if (playing) {
            timeout = g_cvAFKAliveTime.FloatValue;
            if (action != AFKAction_Kick && g_AFKClients[client].doubleLiveTimeout) {
                timeout *= 2.0;
            }
        } else {
            timeout = action == AFKAction_Kick || !g_AFKClients[client].movedToSpec
                ? g_cvAFKSpecTime.FloatValue : g_cvAFKSpecMovedTime.FloatValue;
        }
        if (g_AFKClients[client].idleSeconds <= timeout) {
            continue;
        }
        if (playing && action != AFKAction_Kick) {
            AFK_MoveToSpectator(client, now);
        } else if (!AFK_KickClient(client)) {
            AFK_ResetIdle(client, now);
        }
    }
}
