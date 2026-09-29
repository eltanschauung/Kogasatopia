// Spectate When Full by Eric Zhang (https://ericaftereric.top/).
// Owned by afkmanager.sp; do not compile/load as a standalone plugin.

#define SQ_BASE_STR_LEN 128
#define SQ_JOIN_RESERVATION_TIMEOUT 3.0
#define SQ_RECONCILE_DELAY 0.5
#define SQ_ACTIVITY_QUEUE_INTERVAL 3.0
#define SQ_ACTIVITY_QUEUE_IMMUNITY 60.0

#define SQ_JOIN_TEAM_BLU "blue"
#define SQ_JOIN_TEAM_RED "red"
#define SQ_JOIN_TEAM_AUTO "auto"
#define SQ_JOIN_TEAM_SPECTATOR "spectate"

ConVar g_cvSpecQueueMaxPlayers;
ConVar g_cvSpecQueueAutoJoin;
ConVar g_cvSpecQueueStatistics;
ConVar g_cvSpecQueueEnabled;
ConVar g_cvSpecQueueSuspendAt;

ConVar g_cvSpecQueueVisibleMaxPlayers;
bool g_bSpecQueueConfigsExecuted;
bool g_bSpecQueueCapacityWarningLogged;
bool g_bSpecQueueSuspended;

// store userid inside as it will persist during map resets
enum struct SpecQueueFIFO {
    ArrayList clients;

    void Init() {
        this.clients = new ArrayList();
    }

    void Deinit() {
        delete this.clients;
    }

    void OfferViaUserId(int userId) {
        if (userId > 0 && this.clients.FindValue(userId) == -1) {
            this.clients.Push(userId);
        }
    }

    void Offer(int client) {
        this.OfferViaUserId(GetClientUserId(client));
    }

    int Poll() {
        if (this.IsEmpty()) {
            return -1;
        }
        int value = this.clients.Get(0);
        this.clients.Erase(0);
        return GetClientOfUserId(value);
    }

    bool RemoveFromQueue(int client) {
        return this.RemoveUserIdFromQueue(GetClientUserId(client));
    }

    bool RemoveUserIdFromQueue(int userId) {
        int index = this.clients.FindValue(userId);
        if (index == -1) {
            return false;
        }
        this.clients.Erase(index);
        return true;
    }

    bool InQueue(int client) {
        return this.clients.FindValue(GetClientUserId(client)) != -1;
    }

    void Clear() {
        this.clients.Clear();
    }

    bool IsEmpty() {
        return this.clients.Length == 0;
    }

    int GetLength() {
        return this.clients.Length;
    }
}

SpecQueueFIFO g_SpecQueue;
int g_iSpecQueuePendingUserIds[MAXPLAYERS + 1];
int g_iSpecQueuePendingTeams[MAXPLAYERS + 1];
bool g_bSpecQueuePendingFromQueue[MAXPLAYERS + 1];
Handle g_hSpecQueueReconcileTimer;
Handle g_hSpecQueuePendingTimers[MAXPLAYERS + 1];
float g_flSpecQueueActivityBaseline[MAXPLAYERS + 1];
float g_flSpecQueueImmuneUntil[MAXPLAYERS + 1];

void SpecQueue_Init() {
    LoadTranslations("spec-when-full.phrases.txt");

    g_SpecQueue.Init();
    SpecQueue_ResetAutoQueueActivityBaselines();

    g_cvSpecQueueEnabled = CreateConVar("sm_spec_when_full_enabled", "1", "Enable Spectate When Full.", FCVAR_DONTRECORD, true, 0.0, true, 1.0);
    g_cvSpecQueueMaxPlayers = CreateConVar("sm_fullspec_maxplayers_in_game", "24", "Maximum amount of players allowed in game. Set to -1 to disable.");
    g_cvSpecQueueSuspendAt = CreateConVar("sm_fullspec_queue_suspend_at", "28", "Suspend the team-join queue at this many human RED, BLU, and Spectator clients; resume at the in-game player limit. Set to 0 to disable.", _, true, 0.0);
    g_cvSpecQueueAutoJoin = CreateConVar("sm_fullspec_put_spec_in_autojoin", "1", "Automatically put spectators into autojoin when server is full.");
    g_cvSpecQueueStatistics = CreateConVar(
        "sm_spec_when_full_log",
        "0",
        "Record client and team population snapshots through the plugin statistics service.",
        FCVAR_DONTRECORD,
        true,
        0.0,
        true,
        1.0
    );

    g_cvSpecQueueVisibleMaxPlayers = FindConVar("sv_visiblemaxplayers");

    g_cvSpecQueueEnabled.AddChangeHook(SpecQueue_OnEnabledCvarChanged);
    g_cvSpecQueueMaxPlayers.AddChangeHook(SpecQueue_OnMaxPlayerCvarChanged);
    g_cvSpecQueueSuspendAt.AddChangeHook(SpecQueue_OnQueueSuspendCvarChanged);
    g_cvSpecQueueAutoJoin.AddChangeHook(SpecQueue_OnAutoJoinCvarChanged);
    if (g_cvSpecQueueVisibleMaxPlayers != null) {
        g_cvSpecQueueVisibleMaxPlayers.AddChangeHook(SpecQueue_OnMaxPlayerCvarChanged);
    }

    RegConsoleCmd("sm_joinqueue", SpecQueue_Cmd_AutoJoin, "Join the auto-join queue.");
    RegConsoleCmd("sm_joinq", SpecQueue_Cmd_AutoJoin, "Join the auto-join queue.");
    RegConsoleCmd("sm_leavequeue", SpecQueue_Cmd_LeaveAutoJoin, "Leave the auto-join queue.");
    RegConsoleCmd("sm_leaveq", SpecQueue_Cmd_LeaveAutoJoin, "Leave the auto-join queue.");
    RegConsoleCmd("sm_checkautojoin", SpecQueue_Cmd_CheckAutoJoinQueue, "See the auto join queue.");
    RegConsoleCmd("sm_remove", SpecQueue_Cmd_Spectate, "Move yourself to spectator.");
    RegConsoleCmd("sm_afk", SpecQueue_Cmd_Spectate, "Move yourself to spectator.");
    RegConsoleCmd("sm_spec", SpecQueue_Cmd_Spectate, "Move yourself to spectator.");

    AddCommandListener(SpecQueue_OnClientJoinTeam, "jointeam");

    AutoExecConfig(true, "plugin.spec-when-full", "sourcemod");
}

void SpecQueue_MarkNativesOptional() {
    MarkNativeAsOptional("DGM_GetGameModeKey");
    MarkNativeAsOptional("DGM_NormalizeMapName");
    MarkNativeAsOptional("DGM_CurrentNormalizedMap");
    MarkNativeAsOptional("DGM_RealPlayerCount");
}

void SpecQueue_OnMapStart() {
    g_bSpecQueueConfigsExecuted = false;
    g_bSpecQueueCapacityWarningLogged = false;
    SpecQueue_CancelPlayerChangeChecks();
    SpecQueue_ClearAllPendingJoins();
    SpecQueue_ResetAutoQueueActivityBaselines();
}

void SpecQueue_OnMapEnd() {
    g_bSpecQueueConfigsExecuted = false;
    SpecQueue_CancelPlayerChangeChecks();
    SpecQueue_ClearAllPendingJoins();
}

void SpecQueue_OnClientConnected(int client) {
    g_flSpecQueueActivityBaseline[client] = GetEngineTime();
    g_flSpecQueueImmuneUntil[client] = 0.0;
    SpecQueue_LogPopulationSnapshot("client_connected", client);
}

void SpecQueue_OnClientPutInServer(int client) {
    if (!IsFakeClient(client)) {
        SpecQueue_LogPopulationSnapshot("client_put_in_server", client);
        SpecQueue_UpdateQueueSuspension();
    }
}

void SpecQueue_OnClientDisconnect_Post() {
    SpecQueue_UpdateQueueSuspension();
}

void SpecQueue_OnServerEnterHibernation() {
    SpecQueue_CancelPlayerChangeChecks();
    g_SpecQueue.Clear();
    SpecQueue_ClearAllPendingJoins();
    g_bSpecQueueSuspended = false;
}

void SpecQueue_OnConfigsExecuted() {
    g_bSpecQueueConfigsExecuted = true;
    if (SpecQueue_IsPluginEnabled()) {
        SpecQueue_ActivatePlugin();
    } else {
        SpecQueue_DeactivatePlugin();
    }
}

void SpecQueue_Shutdown() {
    SpecQueue_CancelPlayerChangeChecks();
    SpecQueue_ClearAllPendingJoins();
    g_SpecQueue.Deinit();
}

public void SpecQueue_OnMaxPlayerCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    if (SpecQueue_IsPluginEnabled()) {
        SpecQueue_UpdateQueueSuspension();
        SpecQueue_SetVisibleMaxPlayers();
        SpecQueue_SchedulePlayerChangeChecks();
    }
}

public void SpecQueue_OnQueueSuspendCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    SpecQueue_UpdateQueueSuspension();
}

public void SpecQueue_OnAutoJoinCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    SpecQueue_ResetAutoQueueActivityBaselines();
}

public void SpecQueue_OnEnabledCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    if (!g_bSpecQueueConfigsExecuted) {
        return;
    }
    if (SpecQueue_IsPluginEnabled()) {
        SpecQueue_ActivatePlugin();
    } else {
        SpecQueue_DeactivatePlugin();
    }
}

void SpecQueue_OnClientDisconnect(int client) {
    int userid = GetClientUserId(client);
    SpecQueue_RemoveUserIdFromWaitQueue(userid, "disconnect");
    SpecQueue_ClearPendingJoin(client);
    g_flSpecQueueActivityBaseline[client] = 0.0;
    g_flSpecQueueImmuneUntil[client] = 0.0;
    SpecQueue_LogPopulationSnapshot("client_disconnect", client, -1, -1, userid);
    SpecQueue_SchedulePlayerChangeChecks();
}

void SpecQueue_OnPlayerTeam(int client, int oldTeam, int newTeam) {
    SpecQueue_UpdateQueueSuspension();
    int userId = GetClientUserId(client);
    if (oldTeam != newTeam) {
        g_flSpecQueueActivityBaseline[client] = GetEngineTime();
    }
    if (!SpecQueue_IsPluginOperational()) {
        return;
    }
    bool wasPlaying = SpecQueue_IsPlayingTeam(oldTeam);
    bool isPlaying = SpecQueue_IsPlayingTeam(newTeam);

    if (isPlaying) {
        bool promotionConfirmed = SpecQueue_HasPendingJoin(client) && g_bSpecQueuePendingFromQueue[client];
        SpecQueue_RemoveClientFromWaitQueue(client, "joined_team");
        RequestFrame(SpecQueue_Frame_ConfirmPendingJoin, userId);
        if (!wasPlaying) {
            RequestFrame(SpecQueue_Frame_EnforcePlayingCapacity, userId);
        }
        if (promotionConfirmed) {
            SpecQueue_LogPopulationSnapshot("promotion_confirmed", client, oldTeam, newTeam, userId, "team_change");
        }
        SpecQueue_SchedulePlayerChangeChecks();
        SpecQueue_LogPopulationSnapshot("team_change", client, oldTeam, newTeam);
        return;
    }

    SpecQueue_ClearPendingJoin(client);
    if (wasPlaying && newTeam == view_as<int>(TFTeam_Spectator)) {
        SpecQueue_RemoveClientFromWaitQueue(client, "voluntary_spectator");
    }
    SpecQueue_SchedulePlayerChangeChecks();
    SpecQueue_LogPopulationSnapshot("team_change", client, oldTeam, newTeam);
}

void SpecQueue_LogPopulationSnapshot(
    const char[] eventName,
    int client = 0,
    int oldTeam = -1,
    int newTeam = -1,
    int userId = 0,
    const char[] reason = "") {
    if (!SpecQueue_IsPluginEnabled() || g_cvSpecQueueStatistics == null || !g_cvSpecQueueStatistics.BoolValue
        || GetFeatureStatus(FeatureType_Native, "PluginStats_Record") != FeatureStatus_Available) {
        return;
    }

    int red;
    int blue;
    int spectator;
    int unassigned;
    int other;
    SpecQueue_GetTeamCounts(red, blue, spectator, unassigned, other);

    char steamId64[32];
    if (client > 0 && IsClientConnected(client)) {
        if (userId == 0) {
            userId = GetClientUserId(client);
        }
        if (IsClientAuthorized(client)) {
            GetClientAuthId(client, AuthId_SteamID64, steamId64, sizeof(steamId64));
        }
    }

    char message[512];
    int playersInGame = SpecQueue_GetPlayersInGame();
    int pendingJoins = SpecQueue_GetPendingJoinCount();
    int pendingRed = SpecQueue_GetPendingJoinCountForTeam(view_as<int>(TFTeam_Red));
    int pendingBlue = SpecQueue_GetPendingJoinCountForTeam(view_as<int>(TFTeam_Blue));
    FormatEx(
        message,
        sizeof(message),
        "event=%s|client=%d|userid=%d|steamid64=%s|old_team=%d|new_team=%d|playercount=%d|players_in_game=%d|pending_joins=%d|pending_red=%d|pending_blu=%d|effective_players=%d|red=%d|blu=%d|spectator=%d|unassigned=%d|other=%d|queue=%d|max=%d|full=%d|reason=%s",
        eventName,
        client,
        userId,
        steamId64,
        oldTeam,
        newTeam,
        SpecQueue_GetHumanCount(),
        playersInGame,
        pendingJoins,
        pendingRed,
        pendingBlue,
        playersInGame + pendingJoins,
        red,
        blue,
        spectator,
        unassigned,
        other,
        g_SpecQueue.GetLength(),
        SpecQueue_GetPlayingLimit(),
        SpecQueue_IsServerFull() ? 1 : 0,
        reason
    );
    PluginStats_Record(eventName, message);
}

void SpecQueue_GetTeamCounts(int &red, int &blue, int &spectator, int &unassigned, int &other) {
    for (int client = 1; client <= MaxClients; client++) {
        if (!IsClientInGame(client) || IsClientSourceTV(client) || IsClientReplay(client)) {
            continue;
        }

        switch (GetClientTeam(client)) {
            case view_as<int>(TFTeam_Unassigned): unassigned++;
            case view_as<int>(TFTeam_Spectator): spectator++;
            case view_as<int>(TFTeam_Red): red++;
            case view_as<int>(TFTeam_Blue): blue++;
            default: other++;
        }
    }
}

void SpecQueue_SchedulePlayerChangeChecks() {
    if (SpecQueue_IsPluginOperational() && g_hSpecQueueReconcileTimer == null) {
        g_hSpecQueueReconcileTimer = CreateTimer(SQ_RECONCILE_DELAY, SpecQueue_Timer_RunPlayerCheck, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

void SpecQueue_CancelPlayerChangeChecks() {
    if (g_hSpecQueueReconcileTimer != null) {
        delete g_hSpecQueueReconcileTimer;
        g_hSpecQueueReconcileTimer = null;
    }
}

public Action SpecQueue_Timer_RunPlayerCheck(Handle timer) {
    g_hSpecQueueReconcileTimer = null;
    SpecQueue_RunPlayerChangeChecks();
    SpecQueue_LogPopulationSnapshot("reconcile_complete", 0, -1, -1, 0, "scheduled_check");
    return Plugin_Stop;
}

void SpecQueue_SetVisibleMaxPlayers() {
    if (!SpecQueue_IsPluginEnabled() || !g_bSpecQueueConfigsExecuted || g_cvSpecQueueVisibleMaxPlayers == null) {
        return;
    }
    if (g_cvSpecQueueMaxPlayers.IntValue == -1) {
        if (g_cvSpecQueueVisibleMaxPlayers.IntValue != -1) {
            g_cvSpecQueueVisibleMaxPlayers.IntValue = -1;
        }
        return;
    }
    int maxHumanPlayers = SpecQueue_GetActualMaxHumanPlayers();
    int playingLimit = SpecQueue_GetPlayingLimit();
    if (maxHumanPlayers < g_cvSpecQueueMaxPlayers.IntValue && !g_bSpecQueueCapacityWarningLogged) {
        LogError("Maximum players in game exceeds the engine's human-player capacity; using %d.", playingLimit);
        g_bSpecQueueCapacityWarningLogged = true;
    }
    if (g_cvSpecQueueVisibleMaxPlayers.IntValue != playingLimit) {
        g_cvSpecQueueVisibleMaxPlayers.IntValue = playingLimit;
    }
}

public Action SpecQueue_OnClientJoinTeam(int client, const char[] command, int argc) {
    SpecQueue_UpdateQueueSuspension();
    if (!SpecQueue_IsPluginOperational()) {
        return Plugin_Continue;
    }
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client)) {
        return Plugin_Continue;
    }
#if defined DEBUG
    int clientUserId = GetClientUserId(client);
    char clientName[MAX_NAME_LENGTH];
    GetClientName(client, clientName, sizeof(clientName));
#endif

    char team[SQ_BASE_STR_LEN];
    GetCmdArg(1, team, sizeof(team));

#if defined DEBUG
    LogMessage("Client %s (user id %d) issued \"jointeam %s\"", clientName, clientUserId, team);
#endif

    bool isClientJoiningGame = SpecQueue_IsPlayingTeamRequest(team);
    bool isClientJoiningSpec = SpecQueue_IsSpectatorTeamRequest(team);
    int requestedTeam = SpecQueue_GetRequestedJoinTeam(team);
    int currentTeam = GetClientTeam(client);
    bool clientWasPlaying = SpecQueue_IsPlayingTeam(currentTeam);
    bool putInAutoJoin = g_cvSpecQueueAutoJoin.BoolValue;
    if (isClientJoiningSpec) {
        SpecQueue_SuppressActivityAutoQueue(client);
#if defined DEBUG
        LogMessage("Clearing the pending join for %s (user id %d)", clientName, clientUserId);
#endif
        SpecQueue_ClearPendingJoin(client);
        SpecQueue_RemoveClientFromWaitQueue(client, "voluntary_spectator");
        ChangeClientTeam(client, TFTeam_Spectator);
        CPrintToChat(client, "%t", "SPEC_WHEN_FULL_JOIN_SPEC");
        SpecQueue_SchedulePlayerChangeChecks();
        return Plugin_Handled;
    }
    // just in case someone typed jointeam hdfsiufhsdfi
    if (!isClientJoiningGame) {
        return Plugin_Continue;
    }
    if (clientWasPlaying) {
        SpecQueue_ClearPendingJoin(client);
        SpecQueue_RemoveClientFromWaitQueue(client, "joined_team");
        SpecQueue_SchedulePlayerChangeChecks();
        return Plugin_Continue;
    }
#if defined DEBUG
    LogMessage("Client %s (user id %d) already has a reservation: %s", clientName, clientUserId, SpecQueue_HasPendingJoin(client) ? "true" : "false");
    LogMessage("Effective players: %d", SpecQueue_GetPlayersInGame() + SpecQueue_GetPendingJoinCount());
    LogMessage("SpecQueue_IsServerFull: %s", SpecQueue_IsServerFull() ? "true" : "false");
#endif
    if (!SpecQueue_ReservePendingJoin(client, false, requestedTeam)) {
        SpecQueue_LogPopulationSnapshot("join_blocked", client, currentTeam, requestedTeam, GetClientUserId(client), "capacity_or_team_unavailable");
        ChangeClientTeam(client, TFTeam_Spectator);
        if (putInAutoJoin && !g_SpecQueue.InQueue(client)) {
            SpecQueue_AddClientToWaitQueue(client, "full_join_attempt");
        }
#if defined DEBUG
        LogMessage("Preventing client %s (user id %d) from joining the game", clientName, clientUserId);
#endif
        CPrintToChat(client, "%t", putInAutoJoin ? "SPEC_WHEN_FULL_JOIN_SPEC_AUTO" : "SPEC_WHEN_FULL_JOIN_SPEC");
        SpecQueue_SchedulePlayerChangeChecks();
        return Plugin_Handled;
    }
#if defined DEBUG
    LogMessage("Reserved a pending join for %s (user id %d)", clientName, clientUserId);
#endif
    SpecQueue_RemoveClientFromWaitQueue(client, "joined_team");
    SpecQueue_LogPopulationSnapshot("join_allowed", client, currentTeam, requestedTeam, GetClientUserId(client), "capacity_reserved");
    return Plugin_Continue;
}

public Action SpecQueue_Cmd_AutoJoin(int client, int args) {
    if (!SpecQueue_QueueCommandAvailable(client)) {
        return Plugin_Handled;
    }
    if (!SpecQueue_IsServerFull()) {
        CReplyToCommand(client, "%t", "SPEC_WHEN_FULL_NOT_FULL");
        return Plugin_Handled;
    }
    if (GetClientTeam(client) != view_as<int>(TFTeam_Spectator)) {
        CReplyToCommand(client, "%t", "SPEC_WHEN_FULL_NOT_SPEC");
        return Plugin_Handled;
    }
    if (g_SpecQueue.InQueue(client)) {
        CReplyToCommand(client, "%t", "SPEC_WHEN_FULL_IN_QUEUE");
        return Plugin_Handled;
    }
    SpecQueue_AddClientToWaitQueue(client, "joinqueue_command");
    CReplyToCommand(client, "%t", "SPEC_WHEN_FULL_AUTOJOIN_PLACE_QUEUE");
    return Plugin_Handled;
}

public Action SpecQueue_Cmd_Spectate(int client, int args) {
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client)) {
        return Plugin_Handled;
    }

    SpecQueue_SuppressActivityAutoQueue(client);
    SpecQueue_ClearPendingJoin(client);
    SpecQueue_RemoveClientFromWaitQueue(client, "voluntary_spectator");

    int oldTeam = GetClientTeam(client);
    if (oldTeam == view_as<int>(TFTeam_Spectator)) {
        SpecQueue_SchedulePlayerChangeChecks();
        return Plugin_Handled;
    }

    ChangeClientTeam(client, TFTeam_Spectator);
    CPrintToChat(client, "%t", "SPEC_WHEN_FULL_JOIN_SPEC");

    if (SpecQueue_IsPlayingTeam(oldTeam)) {
        SpecQueue_RunPlayerChangeChecks();
    }
    SpecQueue_SchedulePlayerChangeChecks();
    return Plugin_Handled;
}

public Action SpecQueue_Cmd_LeaveAutoJoin(int client, int args) {
    if (SpecQueue_IsQueuedSpectator(client)) {
        SpecQueue_SuppressActivityAutoQueue(client);
        SpecQueue_ClearPendingJoin(client);
        SpecQueue_SchedulePlayerChangeChecks();
    }
    if (!SpecQueue_QueueCommandAvailable(client)) {
        return Plugin_Handled;
    }
    if (GetClientTeam(client) != view_as<int>(TFTeam_Spectator)) {
        CReplyToCommand(client, "%t", "SPEC_WHEN_FULL_NOT_SPEC");
        return Plugin_Handled;
    }
    if (g_SpecQueue.InQueue(client)) {
        SpecQueue_RemoveClientFromWaitQueue(client, "leavequeue_command");
        CReplyToCommand(client, "%t", "SPEC_WHEN_FULL_AUTOJOIN_REMOVE_QUEUE");
        return Plugin_Handled;
    }
    CReplyToCommand(client, "%t", "SPEC_WHEN_FULL_NOT_IN_QUEUE");
    return Plugin_Handled;
}

public Action SpecQueue_Cmd_CheckAutoJoinQueue(int client, int args) {
    if (!SpecQueue_QueueCommandAvailable(client)) {
        return Plugin_Handled;
    }
    SpecQueue_PruneWaitQueue();
    if (g_SpecQueue.IsEmpty()) {
        CReplyToCommand(client, "%t", "SPEC_WHEN_FULL_AUTOJOIN_EMPTY");
        return Plugin_Handled;
    }
    char title[SQ_BASE_STR_LEN];
    Format(title, sizeof(title), "%T", "SPEC_WHEN_FULL_SPEC_QUEUE_MENU_TITLE", client);
    Menu menu = new Menu(SpecQueue_Menu_AutoJoinList);
    menu.SetTitle(title);
    menu.Pagination = 10;
    menu.ExitButton = true;
    for (int i = 0; i < g_SpecQueue.GetLength(); i++) {
        int specClientIndex = GetClientOfUserId(g_SpecQueue.clients.Get(i));
        if (!SpecQueue_IsQueuedSpectator(specClientIndex)) {
            continue;
        }
        char clientName[MAX_NAME_LENGTH];
        GetClientName(specClientIndex, clientName, sizeof(clientName));
        menu.AddItem(clientName, clientName, ITEMDRAW_DISABLED);
    }
    menu.Display(client, MENU_TIME_FOREVER);
    return Plugin_Handled;
}

public void SpecQueue_Menu_AutoJoinList(Menu menu, MenuAction action, int param1, int param2) {
    if (action == MenuAction_End) {
        delete menu;
    }
}

bool SpecQueue_BlocksAFKKick(int client) {
    return SpecQueue_IsPluginOperational()
        && (g_SpecQueue.InQueue(client) || SpecQueue_HasPendingJoin(client));
}

void SpecQueue_OnAFKSwitch(int client) {
    if (!SpecQueue_IsPluginOperational()) {
        return;
    }
    SpecQueue_ClearPendingJoin(client);
    SpecQueue_SchedulePlayerChangeChecks();
}

void SpecQueue_ResetAutoQueueActivityBaselines() {
    float now = GetEngineTime();
    for (int client = 1; client <= MaxClients; client++) {
        g_flSpecQueueActivityBaseline[client] = now;
    }
}

void SpecQueue_SuppressActivityAutoQueue(int client) {
    float now = GetEngineTime();
    g_flSpecQueueActivityBaseline[client] = now;
    g_flSpecQueueImmuneUntil[client] = now + SQ_ACTIVITY_QUEUE_IMMUNITY;
}

void SpecQueue_CheckActivity(float now) {
    SpecQueue_UpdateQueueSuspension();
    if (!SpecQueue_IsPluginOperational() || !g_cvSpecQueueAutoJoin.BoolValue) {
        return;
    }

    bool queued = false;
    for (int client = 1; client <= MaxClients; client++) {
        if (!SpecQueue_IsQueuedSpectator(client) || g_SpecQueue.InQueue(client) || SpecQueue_HasPendingJoin(client)) {
            continue;
        }

        float activityTime = AFK_GetLastActivityTime(client);
        if (activityTime <= g_flSpecQueueActivityBaseline[client]) {
            continue;
        }
        g_flSpecQueueActivityBaseline[client] = activityTime;

        // Input during immunity must not be replayed after immunity expires.
        if (now < g_flSpecQueueImmuneUntil[client] || activityTime < g_flSpecQueueImmuneUntil[client]) {
            continue;
        }
        if (SpecQueue_AddClientToWaitQueue(client, "spectator_activity")) {
            CPrintToChat(client, "%t", "SPEC_WHEN_FULL_AUTOJOIN_PLACE_QUEUE");
            queued = true;
        }
    }

    if (queued) {
        SpecQueue_SchedulePlayerChangeChecks();
    }
}

void SpecQueue_RunPlayerChangeChecks() {
    if (!SpecQueue_IsPluginOperational()) {
        return;
    }
#if defined DEBUG
    LogMessage("SpecQueue_RunPlayerChangeChecks()");
#endif
    SpecQueue_PruneWaitQueue();
    while (!SpecQueue_IsServerFull() && !g_SpecQueue.IsEmpty()) {
        int client = g_SpecQueue.Poll();
        if (!SpecQueue_IsQueuedSpectator(client)) {
            continue;
        }
        SpecQueue_LogPopulationSnapshot("queue_removed", client, -1, -1, GetClientUserId(client), "promotion");
#if defined DEBUG
        int clientUserId = GetClientUserId(client);
        char name[MAX_NAME_LENGTH];
        GetClientName(client, name, sizeof(name));
        LogMessage("Pulling %s (user id %d) from auto join queue", name, clientUserId);
#endif
        if (!SpecQueue_ReservePendingJoin(client, true, 0)) {
            SpecQueue_AddClientToWaitQueue(client, "promotion_no_slot");
            break;
        }
        SpecQueue_LogPopulationSnapshot("promotion_requested", client, -1, -1, GetClientUserId(client), "queue_head");
        FakeClientCommand(client, "jointeam %s",
            g_iSpecQueuePendingTeams[client] == view_as<int>(TFTeam_Red) ? SQ_JOIN_TEAM_RED : SQ_JOIN_TEAM_BLU);
        SpecQueue_SchedulePlayerChangeChecks();
        break;
    }
}

bool SpecQueue_IsQueuedSpectator(int client) {
    return Client_IsHumanInGame(client)
        && GetClientTeam(client) == view_as<int>(TFTeam_Spectator);
}

void SpecQueue_PruneWaitQueue() {
    for (int i = g_SpecQueue.GetLength() - 1; i >= 0; i--) {
        int userId = g_SpecQueue.clients.Get(i);
        int client = GetClientOfUserId(userId);
        if (!SpecQueue_IsQueuedSpectator(client)) {
            g_SpecQueue.clients.Erase(i);
            SpecQueue_LogPopulationSnapshot("queue_removed", client, -1, -1, userId, "stale_entry");
        }
    }
}

bool SpecQueue_AddClientToWaitQueue(int client, const char[] reason) {
    if (!SpecQueue_IsQueuedSpectator(client) || g_SpecQueue.InQueue(client)) {
        return false;
    }
    g_SpecQueue.Offer(client);
    SpecQueue_LogPopulationSnapshot("queue_added", client, -1, -1, GetClientUserId(client), reason);
    return true;
}

bool SpecQueue_RemoveClientFromWaitQueue(int client, const char[] reason) {
    if (client <= 0 || !g_SpecQueue.RemoveFromQueue(client)) {
        return false;
    }
    SpecQueue_LogPopulationSnapshot("queue_removed", client, -1, -1, GetClientUserId(client), reason);
    return true;
}

bool SpecQueue_RemoveUserIdFromWaitQueue(int userId, const char[] reason) {
    if (!g_SpecQueue.RemoveUserIdFromQueue(userId)) {
        return false;
    }
    int client = GetClientOfUserId(userId);
    SpecQueue_LogPopulationSnapshot("queue_removed", client, -1, -1, userId, reason);
    return true;
}

int SpecQueue_CountPlayingHumansLocally() {
    int count = 0;
    for (int client = 1; client <= MaxClients; client++) {
        if (!IsClientInGame(client) || IsFakeClient(client)) {
            continue;
        }

        if (SpecQueue_IsPlayingTeam(GetClientTeam(client))) {
            count++;
        }
    }
    return count;
}

int SpecQueue_CountQueueHumans() {
    int count = 0;
    for (int client = 1; client <= MaxClients; client++) {
        if (!IsClientInGame(client) || IsFakeClient(client)) {
            continue;
        }
        int team = GetClientTeam(client);
        if (SpecQueue_IsPlayingTeam(team) || team == view_as<int>(TFTeam_Spectator)) {
            count++;
        }
    }
    return count;
}

bool SpecQueue_IsPlayingTeam(int team) {
    return team == view_as<int>(TFTeam_Red) || team == view_as<int>(TFTeam_Blue);
}

int SpecQueue_GetPlayersInGame() {
    if (GetFeatureStatus(FeatureType_Native, "DGM_RealPlayerCount") == FeatureStatus_Available) {
        return DGM_RealPlayerCount();
    }
    return SpecQueue_CountPlayingHumansLocally();
}

bool SpecQueue_IsServerFull() {
    int playingLimit = SpecQueue_GetPlayingLimit();
    if (playingLimit <= 0) {
        return false;
    }

    return SpecQueue_CountPlayingHumansLocally() + SpecQueue_GetPendingJoinCount() >= playingLimit;
}

bool SpecQueue_IsPluginEnabled() {
    return g_cvSpecQueueEnabled != null && g_cvSpecQueueEnabled.BoolValue;
}

bool SpecQueue_IsPluginOperational() {
    return g_bSpecQueueConfigsExecuted && SpecQueue_IsPluginEnabled() && !g_bSpecQueueSuspended && SpecQueue_GetPlayingLimit() > 0;
}

bool SpecQueue_QueueCommandAvailable(int client) {
    if (!Client_IsHumanInGame(client) || !g_bSpecQueueConfigsExecuted || !SpecQueue_IsPluginEnabled()) {
        return false;
    }
    SpecQueue_UpdateQueueSuspension();
    if (g_bSpecQueueSuspended) {
        CReplyToCommand(client, "%t", "SPEC_WHEN_FULL_QUEUE_SUSPENDED");
        return false;
    }
    return SpecQueue_IsPluginOperational();
}

void SpecQueue_UpdateQueueSuspension() {
    if (!g_bSpecQueueConfigsExecuted || !SpecQueue_IsPluginEnabled()) {
        return;
    }

    int suspendAt = g_cvSpecQueueSuspendAt.IntValue;
    int resumeAt = SpecQueue_GetPlayingLimit();
    bool shouldSuspend = false;
    if (suspendAt > 0 && resumeAt > 0) {
        // A misconfigured high threshold must not make resumption impossible.
        if (resumeAt >= suspendAt) {
            resumeAt = suspendAt - 1;
        }
        int population = SpecQueue_CountQueueHumans();
        shouldSuspend = g_bSpecQueueSuspended ? population > resumeAt : population >= suspendAt;
    }
    if (shouldSuspend == g_bSpecQueueSuspended) {
        return;
    }

    g_bSpecQueueSuspended = shouldSuspend;
    if (g_bSpecQueueSuspended) {
        SpecQueue_CancelPlayerChangeChecks();
        g_SpecQueue.Clear();
        SpecQueue_ClearAllPendingJoins();
        SpecQueue_LogPopulationSnapshot("queue_suspended", 0, -1, -1, 0, "population_high");
    } else {
        SpecQueue_ResetAutoQueueActivityBaselines();
        SpecQueue_LogPopulationSnapshot("queue_resumed", 0, -1, -1, 0, "population_at_limit");
        SpecQueue_SchedulePlayerChangeChecks();
    }
}

void SpecQueue_ActivatePlugin() {
    SpecQueue_ResetAutoQueueActivityBaselines();
    if (FindPluginByFile("reservedslots.smx") != INVALID_HANDLE) {
        LogMessage("Unloading reservedslots to prevent conflicts...");
        ServerCommand("sm plugins unload reservedslots");
    }
    SpecQueue_UpdateQueueSuspension();
    SpecQueue_SetVisibleMaxPlayers();
    SpecQueue_SchedulePlayerChangeChecks();
}

void SpecQueue_DeactivatePlugin() {
    SpecQueue_CancelPlayerChangeChecks();
    g_SpecQueue.Clear();
    SpecQueue_ClearAllPendingJoins();
}

int SpecQueue_GetPlayingLimit() {
    if (g_cvSpecQueueMaxPlayers == null || g_cvSpecQueueMaxPlayers.IntValue < 0) {
        return -1;
    }
    int configuredLimit = g_cvSpecQueueMaxPlayers.IntValue;
    int maxHumanPlayers = SpecQueue_GetActualMaxHumanPlayers();
    if (maxHumanPlayers > 0 && configuredLimit > maxHumanPlayers) {
        return maxHumanPlayers;
    }
    return configuredLimit;
}

bool SpecQueue_HasPendingJoin(int client) {
    return client > 0 && client <= MaxClients && IsClientConnected(client)
        && g_iSpecQueuePendingUserIds[client] == GetClientUserId(client);
}

bool SpecQueue_ReservePendingJoin(int client, bool fromQueue, int requestedTeam) {
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client) || SpecQueue_IsPlayingTeam(GetClientTeam(client))) {
        return false;
    }

    if (SpecQueue_HasPendingJoin(client)) {
        if (requestedTeam == 0 || g_iSpecQueuePendingTeams[client] == requestedTeam) {
            g_bSpecQueuePendingFromQueue[client] = g_bSpecQueuePendingFromQueue[client] || fromQueue;
            return true;
        }
        SpecQueue_ClearPendingJoin(client);
    }
    if (SpecQueue_IsServerFull()) {
        return false;
    }

    int userId = GetClientUserId(client);
    int reservedTeam = SpecQueue_SelectPendingJoinTeam(requestedTeam);
    if (!SpecQueue_IsPlayingTeam(reservedTeam)) {
        return false;
    }

    g_iSpecQueuePendingUserIds[client] = userId;
    g_iSpecQueuePendingTeams[client] = reservedTeam;
    g_bSpecQueuePendingFromQueue[client] = fromQueue;
    g_hSpecQueuePendingTimers[client] = CreateTimer(SQ_JOIN_RESERVATION_TIMEOUT, SpecQueue_Timer_ExpirePendingJoin, userId, TIMER_FLAG_NO_MAPCHANGE);
    return true;
}

void SpecQueue_ClearPendingJoin(int client) {
    if (client <= 0 || client > MaxClients) {
        return;
    }
    if (g_hSpecQueuePendingTimers[client] != null) {
        delete g_hSpecQueuePendingTimers[client];
        g_hSpecQueuePendingTimers[client] = null;
    }
    g_iSpecQueuePendingUserIds[client] = 0;
    g_iSpecQueuePendingTeams[client] = 0;
    g_bSpecQueuePendingFromQueue[client] = false;
}

void SpecQueue_ClearAllPendingJoins() {
    for (int client = 1; client <= MaxClients; client++) {
        SpecQueue_ClearPendingJoin(client);
    }
}

int SpecQueue_GetPendingJoinCount() {
    int count = 0;
    for (int client = 1; client <= MaxClients; client++) {
        if (!SpecQueue_HasPendingJoin(client)) {
            continue;
        }
        if (!IsClientInGame(client) || SpecQueue_IsPlayingTeam(GetClientTeam(client))) {
            SpecQueue_ClearPendingJoin(client);
            continue;
        }
        count++;
    }
    return count;
}

int SpecQueue_GetPendingJoinCountForTeam(int team) {
    int count = 0;
    for (int client = 1; client <= MaxClients; client++) {
        if (!SpecQueue_HasPendingJoin(client)) {
            continue;
        }
        if (!IsClientInGame(client) || SpecQueue_IsPlayingTeam(GetClientTeam(client))) {
            SpecQueue_ClearPendingJoin(client);
            continue;
        }
        if (g_iSpecQueuePendingTeams[client] == team) {
            count++;
        }
    }
    return count;
}

int SpecQueue_GetRequestedJoinTeam(const char[] team) {
    if (StrEqual(team, SQ_JOIN_TEAM_RED, false) || StrEqual(team, "2")) {
        return view_as<int>(TFTeam_Red);
    }
    if (StrEqual(team, SQ_JOIN_TEAM_BLU, false) || StrEqual(team, "blu", false) || StrEqual(team, "3")) {
        return view_as<int>(TFTeam_Blue);
    }
    return 0;
}

bool SpecQueue_IsPlayingTeamRequest(const char[] team) {
    return StrEqual(team, SQ_JOIN_TEAM_AUTO, false)
        || StrEqual(team, "0")
        || SpecQueue_GetRequestedJoinTeam(team) != 0;
}

bool SpecQueue_IsSpectatorTeamRequest(const char[] team) {
    return StrEqual(team, SQ_JOIN_TEAM_SPECTATOR, false)
        || StrEqual(team, "spectator", false)
        || StrEqual(team, "1");
}

int SpecQueue_SelectPendingJoinTeam(int requestedTeam) {
    int playingLimit = SpecQueue_GetPlayingLimit();
    if (playingLimit <= 0) {
        return 0;
    }

    int redTeam = view_as<int>(TFTeam_Red);
    int blueTeam = view_as<int>(TFTeam_Blue);
    int redLimit = playingLimit / 2;
    int blueLimit = playingLimit - redLimit;
    int redEffective = SpecQueue_CountPlayingHumansOnTeam(redTeam) + SpecQueue_GetPendingJoinCountForTeam(redTeam);
    int blueEffective = SpecQueue_CountPlayingHumansOnTeam(blueTeam) + SpecQueue_GetPendingJoinCountForTeam(blueTeam);

    if (requestedTeam == redTeam && redEffective < redLimit) {
        return redTeam;
    }
    if (requestedTeam == blueTeam && blueEffective < blueLimit) {
        return blueTeam;
    }
    if (requestedTeam != 0) {
        return 0;
    }
    if (redEffective >= redLimit) {
        return blueEffective < blueLimit ? blueTeam : 0;
    }
    if (blueEffective >= blueLimit) {
        return redTeam;
    }
    return redEffective <= blueEffective ? redTeam : blueTeam;
}

public void SpecQueue_Frame_ConfirmPendingJoin(any userId) {
    int client = GetClientOfUserId(userId);
    if (client > 0 && IsClientInGame(client) && SpecQueue_IsPlayingTeam(GetClientTeam(client))) {
        SpecQueue_ClearPendingJoin(client);
        SpecQueue_SchedulePlayerChangeChecks();
    }
}

public void SpecQueue_Frame_EnforcePlayingCapacity(any userId) {
    if (!SpecQueue_IsPluginOperational()) {
        return;
    }

    int client = GetClientOfUserId(userId);
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client)
        || !SpecQueue_IsPlayingTeam(GetClientTeam(client))
        || SpecQueue_CountPlayingHumansLocally() <= SpecQueue_GetPlayingLimit()) {
        return;
    }

    int oldTeam = GetClientTeam(client);
    SpecQueue_LogPopulationSnapshot("overflow_corrected", client, oldTeam, view_as<int>(TFTeam_Spectator), userId, "post_team_change");
    SpecQueue_ClearPendingJoin(client);
    ChangeClientTeam(client, TFTeam_Spectator);

    bool putInAutoJoin = g_cvSpecQueueAutoJoin.BoolValue;
    if (putInAutoJoin) {
        SpecQueue_AddClientToWaitQueue(client, "overflow_corrected");
    }
    CPrintToChat(client, "%t", putInAutoJoin ? "SPEC_WHEN_FULL_JOIN_SPEC_AUTO" : "SPEC_WHEN_FULL_JOIN_SPEC");
    SpecQueue_SchedulePlayerChangeChecks();
}

public Action SpecQueue_Timer_ExpirePendingJoin(Handle timer, any userId) {
    int client = GetClientOfUserId(userId);
    if (client > 0 && g_iSpecQueuePendingUserIds[client] == userId
        && g_hSpecQueuePendingTimers[client] == timer) {
        g_hSpecQueuePendingTimers[client] = null;
        bool requeue = g_bSpecQueuePendingFromQueue[client] && SpecQueue_IsQueuedSpectator(client);
        SpecQueue_LogPopulationSnapshot("promotion_failed", client, -1, -1, userId, "confirmation_timeout");
        SpecQueue_ClearPendingJoin(client);
        if (requeue) {
            SpecQueue_AddClientToWaitQueue(client, "promotion_retry");
        }
        SpecQueue_SchedulePlayerChangeChecks();
    }
    return Plugin_Stop;
}

int SpecQueue_GetActualMaxHumanPlayers() {
    return GetMaxHumanPlayers();
}

int SpecQueue_GetHumanCount() {
    int count = 0;
    for (int client = 1; client <= MaxClients; client++) {
        if (IsClientConnected(client) && !IsFakeClient(client)) {
            count++;
        }
    }
    return count;
}

int SpecQueue_CountPlayingHumansOnTeam(int team) {
    int count = 0;
    for (int client = 1; client <= MaxClients; client++) {
        if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) != team) {
            continue;
        }
        count++;
    }
    return count;
}
