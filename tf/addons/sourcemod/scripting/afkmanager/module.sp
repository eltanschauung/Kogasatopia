// AFK policy and real-input tracking, hosted by whalescramble.sp.

#define AFK_ACTION_BUTTONS (IN_ATTACK | IN_JUMP | IN_DUCK | IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_ATTACK2 | IN_RELOAD | IN_SCORE | IN_USE)
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
}

AFKClientState g_AFKClients[MAXPLAYERS + 1];
ConVar g_cvAFKEnabled;
ConVar g_cvAFKAction;
ConVar g_cvAFKAliveTime;
ConVar g_cvAFKSpecTime;
ConVar g_cvAFKSpecMovedTime;
ConVar g_cvAFKMinPlayerCount;
ConVar g_cvEngineIdleMethod;
int g_iOriginalIdleMethod;
GlobalForward g_fwAFKKick;
GlobalForward g_fwAFKSwitch;
Handle g_hAFKMaintenanceTimer;
float g_flNextQueueActivityCheck;
bool g_bAFKMapActive;
bool g_bAFKInitialized;

#include "spec-when-full.sp"

void AFK_RegisterPluginApi() {
    MarkNativeAsOptional("AdminsDB_GetClientWhitelistLevel");
    RegPluginLibrary("afkmanager");
    CreateNative("AFKManager_GetLastActivityTime", AFK_Native_GetLastActivityTime);
}

public any AFK_Native_GetLastActivityTime(Handle plugin, int numParams) {
    return view_as<int>(AFK_GetLastActivityTime(GetNativeCell(1)));
}

void AFK_OnPluginStart() {
    g_cvAFKEnabled = CreateConVar("sm_afkmanager_enabled", "1", "Enable AFK management; spectator queue controls are independent.", _, true, 0.0, true, 1.0);
    g_cvAFKAction = CreateConVar("sm_afkmanager_afk_action", "1", "AFK action: 0 = kick, 1 = move to spectator and kick idle spectators, 2 = move to spectator only.", _, true, 0.0, true, 2.0);
    g_cvAFKAliveTime = CreateConVar("sm_afkmanager_alive_time", "60", "Idle live-player timeout in seconds.", _, true, 60.0);
    g_cvAFKSpecTime = CreateConVar("sm_afkmanager_spec_time", "300", "Idle spectator timeout in seconds.", _, true, 60.0);
    g_cvAFKSpecMovedTime = CreateConVar("sm_afkmanager_spec_moved_time", "180", "Idle spectator timeout after being moved by AFK Manager.", _, true, 60.0);
    g_cvAFKMinPlayerCount = CreateConVar("sm_afkmanager_min_player_count", "2", "Minimum in-game player count before AFK actions.", _, true, 0.0);
    CreateConVar("sm_afkmanager_kick_spec_min_player_count", "24", "Legacy fallback threshold; integrated DGM now controls spectator capacity checks.", _, true, 0.0);
    g_cvAFKEnabled.AddChangeHook(AFK_OnEnabledChanged);

    g_fwAFKKick = new GlobalForward("OnAFKKick", ET_Hook, Param_Cell);
    g_fwAFKSwitch = new GlobalForward("OnAFKSwitch", ET_Ignore, Param_Cell);

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
    g_bAFKInitialized = true;
    AutoExecConfig(true, "afkmanager", "sourcemod");
}

void AFK_OnMapStart() {
    g_bAFKMapActive = true;
    AFK_ResetAllClients();
    SpecQueue_OnMapStart();
    AFK_StartMaintenance();
}

void AFK_OnMapEnd() {
    g_bAFKMapActive = false;
    AFK_StopMaintenance();
    SpecQueue_OnMapEnd();
}

void AFK_OnConfigsExecuted() {
    SpecQueue_OnConfigsExecuted();
}

void AFK_OnClientConnected(int client) {
    AFK_ResetClient(client);
    SpecQueue_OnClientConnected(client);
}

void AFK_OnClientPutInServer(int client) {
    AFK_ResetIdle(client, GetEngineTime());
    SpecQueue_OnClientPutInServer(client);
}

void AFK_OnClientDisconnect(int client) {
    SpecQueue_OnClientDisconnect(client);
    AFK_ResetClient(client);
}

void AFK_OnClientDisconnect_Post() {
    SpecQueue_OnClientDisconnect_Post();
}

void AFK_OnServerEnterHibernation() {
    AFK_StopMaintenance();
    SpecQueue_OnServerEnterHibernation();
}

void AFK_OnServerExitHibernation() {
    if (g_bAFKMapActive) {
        AFK_StartMaintenance();
    }
}

void AFK_OnPluginEnd() {
    if (!g_bAFKInitialized) {
        return;
    }
    g_bAFKInitialized = false;
    AFK_StopMaintenance();
    SpecQueue_Shutdown();
    if (g_cvEngineIdleMethod != null && g_cvEngineIdleMethod.IntValue == 0) {
        g_cvEngineIdleMethod.IntValue = g_iOriginalIdleMethod;
    }
    delete g_fwAFKKick;
    delete g_fwAFKSwitch;
}

void AFK_OnPlayerInput(int client, int buttons, int impulse, int weapon, const int mouse[2]) {
    if ((buttons & AFK_ACTION_BUTTONS) != 0 || impulse != 0 || weapon != 0
        || mouse[0] != 0 || mouse[1] != 0) {
        AFK_RecordActivity(client);
    }
}

public Action AFK_OnActivityCommand(int client, const char[] command, int argc) {
    AFK_RecordActivity(client);
    return Plugin_Continue;
}

void AFK_OnPlayerTeamEvent(Event event) {
    if (event.GetBool("disconnect")) {
        return;
    }
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!Client_IsHumanInGame(client)) {
        return;
    }
    int team = event.GetInt("team");
    TeamBalance_OnClientTeamChanged(client, team);
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
    AFK_ResetIdle(client, GetEngineTime());
}

void AFK_ResetAllClients() {
    for (int client = 1; client <= MaxClients; client++) {
        AFK_ResetClient(client);
    }
}

bool AFK_HasDoubleLiveTimeout(int client) {
    return GetFeatureStatus(FeatureType_Native, "AdminsDB_GetClientWhitelistLevel") == FeatureStatus_Available
        && AdminsDB_GetClientWhitelistLevel(client) == 2;
}

bool AFK_CanKickSpectators() {
    return DGM_ServerCapacitycheck(1.0, false);
}

bool AFK_KickClient(int client) {
    if (SpecQueue_BlocksAFKKick(client)
        || !TeamBalance_TryBegin(TeamBalance_AFKRemoval, TEAM_BALANCE_OPERATION_LEASE, true)) {
        return false;
    }
    int userId = GetClientUserId(client);
    int operation = g_iBalanceOperationGeneration;
    Action result = Plugin_Continue;
    Call_StartForward(g_fwAFKKick);
    Call_PushCell(client);
    Call_Finish(result);
    if (operation != g_iBalanceOperationGeneration) {
        return false;
    }
    if (result != Plugin_Continue || !Client_IsHumanInGame(client)
        || GetClientUserId(client) != userId) {
        TeamBalance_FinishOperation(false);
        return false;
    }
    TeamBalance_ClearRespawnState(client);
    ClearTeamSwapRequestsForClient(client);
    KickClient(client, "#TF_Idle_kicked");
    if (operation == g_iBalanceOperationGeneration) {
        TeamBalance_FinishOperation(true);
    }
    return true;
}

void AFK_MoveToSpectator(int client, float now) {
    if (!TeamBalance_MoveToSpectator(client, "afk_timeout", true)) {
        return;
    }
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
            if (action != AFKAction_Kick && AFK_HasDoubleLiveTimeout(client)) {
                timeout *= 2.0;
            }
        } else {
            timeout = action == AFKAction_Kick || !g_AFKClients[client].movedToSpec
                ? g_cvAFKSpecTime.FloatValue : g_cvAFKSpecMovedTime.FloatValue;
        }
        if (g_AFKClients[client].idleSeconds <= timeout) {
            continue;
        }
        // Keep accrued idle time while another team operation is in progress.
        if (!TeamBalance_CanRunAFKAction()) {
            continue;
        }
        if (playing && action != AFKAction_Kick) {
            AFK_MoveToSpectator(client, now);
        } else if (!AFK_KickClient(client)) {
            AFK_ResetIdle(client, now);
        }
    }
}
