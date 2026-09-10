// One owned verification timer per client. A generation also protects against
// synchronous engine hooks replacing a request while its callback is executing.
Handle g_hBalanceRespawnTimer[MAXPLAYERS + 1];
int g_iBalanceRespawnGeneration[MAXPLAYERS + 1];
int g_iBalanceOperationGeneration;

bool TeamBalance_IsScrambleCooldownActive()
{
    return TeamBalance_IsScrambleCooldownActiveInternal();
}

bool TeamBalance_BeginScrambleVote(float leaseSeconds)
{
    if (!(leaseSeconds >= 1.0)) leaseSeconds = 1.0;
    return TeamBalance_TryBegin(TeamBalance_ScrambleVote, leaseSeconds + 2.0, false);
}

void TeamBalance_EndScrambleVote()
{
    TeamBalance_RefreshState();
    if (g_eTeamBalanceState == TeamBalance_ScrambleVote) TeamBalance_SetState(TeamBalance_Idle, 0.0);
}

bool TeamBalance_BeginScramble(bool bypassCooldown = false)
{
    TeamBalance_RefreshState();
    if (g_eTeamBalanceState == TeamBalance_ScrambleVote)
    {
        TeamBalance_SetState(TeamBalance_ScramblePending, TEAM_BALANCE_OPERATION_LEASE);
        return true;
    }
    return TeamBalance_TryBegin(TeamBalance_ScramblePending, TEAM_BALANCE_OPERATION_LEASE, bypassCooldown);
}

void TeamBalance_CancelScramble()
{
    TeamBalance_RefreshState();
    if (g_eTeamBalanceState == TeamBalance_ScrambleVote
        || g_eTeamBalanceState == TeamBalance_ScramblePending
        || g_eTeamBalanceState == TeamBalance_ScrambleMoving)
    {
        TeamBalance_SetState(TeamBalance_Idle, 0.0);
    }
}

void TeamBalance_FinishScramble(bool movedPlayers, bool countForImmunity = true)
{
    TeamBalance_FinishScrambleInternal(movedPlayers, countForImmunity);
}

bool TeamBalance_IsScrambleCandidate(int client, int expectedTeam, bool ignoreImmunity, bool allowBots)
{
    return TeamBalance_IsScrambleCandidateInternal(client, expectedTeam, ignoreImmunity, allowBots);
}

bool TeamBalance_HasScramblePurchaseImmunity(int client)
{
    return TeamBalance_HasScramblePurchaseImmunityInternal(client);
}

int TeamBalance_ConsumeScramblePurchaseImmunity(int client)
{
    if (!TeamBalance_HasScramblePurchaseImmunityInternal(client)) return -1;
    return PointsStore_ConsumePurchaseUse(client, POINTS_STORE_SCRAMBLE_IMMUNITY_ITEM);
}

bool TeamBalance_MoveScramblePair(int redClient, int bluClient, bool ignoreImmunity,
    bool allowBots, bool suppressRespawn)
{
    return TeamBalance_MoveScramblePairInternal(redClient, bluClient, ignoreImmunity, allowBots, suppressRespawn);
}

bool TeamBalance_QueueRespawn(int client, int expectedTeam)
{
    return TeamBalance_QueueRespawnInternal(client, expectedTeam, false);
}

void TeamBalance_SetState(TeamBalanceState state, float leaseSeconds)
{
    if (state != g_eTeamBalanceState) g_iBalanceOperationGeneration++;
    g_eTeamBalanceState = state;
    // A malformed native argument must not create an unexpiring busy state.
    if (state != TeamBalance_Idle && !(leaseSeconds > 0.0))
        leaseSeconds = TEAM_BALANCE_OPERATION_LEASE;
    if (leaseSeconds > 3600.0) leaseSeconds = 3600.0;
    g_fTeamBalanceStateUntil = state != TeamBalance_Idle ? GetEngineTime() + leaseSeconds : 0.0;
}

void TeamBalance_RefreshState()
{
    if (g_eTeamBalanceState == TeamBalance_Idle || g_fTeamBalanceStateUntil <= 0.0) return;
    if (GetEngineTime() >= g_fTeamBalanceStateUntil)
    {
        LogBalance("Balance state lease expired: state=%d", view_as<int>(g_eTeamBalanceState));
        TeamBalance_SetState(TeamBalance_Idle, 0.0);
    }
}

bool TeamBalance_IsScrambleCooldownActiveInternal()
{
    if (g_fScrambleCooldownUntil <= 0.0) return false;
    if (GetEngineTime() >= g_fScrambleCooldownUntil)
    {
        g_fScrambleCooldownUntil = 0.0;
        LogBalance("Scramble cooldown expired.");
        return false;
    }
    return true;
}

bool TeamBalance_TryBegin(TeamBalanceState state, float leaseSeconds, bool bypassScrambleCooldown)
{
    TeamBalance_RefreshState();
    if (g_eTeamBalanceState != TeamBalance_Idle) return false;
    if (!bypassScrambleCooldown
        && (state == TeamBalance_ScrambleVote || state == TeamBalance_ScramblePending)
        && TeamBalance_IsScrambleCooldownActiveInternal()) return false;
    TeamBalance_SetState(state, leaseSeconds);
    return true;
}

void TeamBalance_FinishOperation(bool movedPlayers)
{
    TeamBalance_SetState(movedPlayers ? TeamBalance_Settling : TeamBalance_Idle,
        movedPlayers ? TEAM_BALANCE_SETTLE_TIME : 0.0);
}

void TeamBalance_FinishScrambleInternal(bool movedPlayers, bool countForImmunity)
{
    TeamBalance_RefreshState();
    if (g_eTeamBalanceState != TeamBalance_ScramblePending && g_eTeamBalanceState != TeamBalance_ScrambleMoving)
    {
        LogBalance("Ignored invalid scramble completion transition from state=%d", view_as<int>(g_eTeamBalanceState));
        return;
    }
    if (!movedPlayers)
    {
        TeamBalance_FinishOperation(false);
        return;
    }
    g_fScrambleCooldownUntil = GetEngineTime() + TEAM_BALANCE_SCRAMBLE_COOLDOWN;
    if (countForImmunity && ++g_iScramblesSinceImmunityClear >= 2)
    {
        if (g_hScrambleImmunity != null) g_hScrambleImmunity.Clear();
        g_iScramblesSinceImmunityClear = 0;
        LogBalance("Cleared scramble immunity after two completed scrambles.");
    }
    TeamBalance_FinishOperation(true);
    LogBalance("Scramble completed; cooldown and settle window started.");
}

bool TeamBalance_IsScrambleCandidateInternal(int client, int expectedTeam, bool ignoreImmunity, bool allowBots)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client)) return false;
    if (!allowBots && IsFakeClient(client)) return false;
    int team = GetClientTeam(client);
    if ((expectedTeam == TEAM_RED || expectedTeam == TEAM_BLUE) && team != expectedTeam) return false;
    if (team != TEAM_RED && team != TEAM_BLUE) return false;
    if (DuelDetection_IsClientInDuel(client) || TeamBalance_IsRecentlyMoved(client)) return false;
    return ignoreImmunity || !TeamBalance_IsScrambleImmuneInternal(client);
}

static bool TeamBalance_IsScrambleImmuneInternal(int client)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || g_hScrambleImmunity == null) return false;
    bool clanProtectionAvailable = GetFeatureStatus(FeatureType_Native, "Clans_GetSameTeamClanMemberCount") == FeatureStatus_Available;
    if (HasClanTeammateProtection(client, GetClientTeam(client), clanProtectionAvailable)) return true;
    char steamId[32];
    if (!Kogasa_GetClientSteamId64(client, steamId, sizeof(steamId), true)) return false;
    return g_hScrambleImmunity.ContainsKey(steamId);
}

static void TeamBalance_MarkScrambleImmune(int client)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || g_hScrambleImmunity == null) return;
    char steamId[32];
    if (Kogasa_GetClientSteamId64(client, steamId, sizeof(steamId), true)) g_hScrambleImmunity.SetValue(steamId, 1);
}

bool TeamBalance_HasScramblePurchaseImmunityInternal(int client)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client)) return false;
    if (GetFeatureStatus(FeatureType_Native, "PointsStore_HasPurchase") != FeatureStatus_Available
        || GetFeatureStatus(FeatureType_Native, "PointsStore_ConsumePurchaseUse") != FeatureStatus_Available) return false;
    return PointsStore_HasPurchase(client, POINTS_STORE_SCRAMBLE_IMMUNITY_ITEM);
}

bool TeamBalance_IsSessionOnTeam(int serial, int team)
{
    int client = GetClientFromSerial(serial);
    return client > 0 && IsClientInGame(client) && GetClientTeam(client) == team;
}

bool TeamBalance_MoveScramblePairInternal(int redClient, int bluClient, bool ignoreImmunity,
    bool allowBots, bool suppressRespawn)
{
    TeamBalance_RefreshState();
    if (g_eTeamBalanceState != TeamBalance_ScramblePending && g_eTeamBalanceState != TeamBalance_ScrambleMoving) return false;
    if (!TeamBalance_IsScrambleCandidateInternal(redClient, TEAM_RED, ignoreImmunity, allowBots)
        || !TeamBalance_IsScrambleCandidateInternal(bluClient, TEAM_BLUE, ignoreImmunity, allowBots)
        || TeamBalance_HasScramblePurchaseImmunityInternal(redClient)
        || TeamBalance_HasScramblePurchaseImmunityInternal(bluClient)) return false;

    int redSerial = GetClientSerial(redClient), blueSerial = GetClientSerial(bluClient);
    TeamBalance_SetState(TeamBalance_ScrambleMoving, TEAM_BALANCE_OPERATION_LEASE);
    int operation = g_iBalanceOperationGeneration;
    ChangeClientTeam(redClient, TEAM_BLUE);
    // Changing a team synchronously dispatches hooks. Never reuse pre-hook indices.
    if (operation != g_iBalanceOperationGeneration
        || !TeamBalance_IsSessionOnTeam(redSerial, TEAM_BLUE)
        || !TeamBalance_IsSessionOnTeam(blueSerial, TEAM_BLUE))
    {
        LogBalance("Scramble pair interrupted after its first move; stale continuation discarded.");
        return false;
    }
    bluClient = GetClientFromSerial(blueSerial);
    ChangeClientTeam(bluClient, TEAM_RED);
    if (operation != g_iBalanceOperationGeneration
        || !TeamBalance_IsSessionOnTeam(redSerial, TEAM_BLUE)
        || !TeamBalance_IsSessionOnTeam(blueSerial, TEAM_RED)) return false;
    redClient = GetClientFromSerial(redSerial);
    bluClient = GetClientFromSerial(blueSerial);
    TeamBalance_MarkRecentlyMoved(redClient);
    TeamBalance_MarkRecentlyMoved(bluClient);
    if (!suppressRespawn)
    {
        TeamBalance_QueueRespawnInternal(redClient, TEAM_BLUE, false);
        TeamBalance_QueueRespawnInternal(bluClient, TEAM_RED, false);
    }
    TeamBalance_MarkScrambleImmune(redClient);
    TeamBalance_MarkScrambleImmune(bluClient);
    return true;
}

bool TeamBalance_MoveAutobalanceClient(int client, int expectedTeam, int targetTeam)
{
    if (g_eTeamBalanceState != TeamBalance_Autobalance
        || !IsGameTeam(expectedTeam) || !IsGameTeam(targetTeam) || expectedTeam == targetTeam
        || !IsBasicBalanceCandidate(client, expectedTeam)
        || IsClientImmune(client) || HasAutobalancePurchaseImmunity(client)) return false;
    int serial = GetClientSerial(client), operation = g_iBalanceOperationGeneration;
    ChangeClientTeam(client, targetTeam);
    if (operation != g_iBalanceOperationGeneration || !TeamBalance_IsSessionOnTeam(serial, targetTeam)) return false;
    client = GetClientFromSerial(serial);
    TeamBalance_MarkRecentlyMoved(client);
    TeamBalance_QueueRespawnInternal(client, targetTeam, true);
    client = GetClientFromSerial(serial);
    if (client > 0 && IsClientInGame(client)) SetClientMapImmunity(client, true);
    if (operation == g_iBalanceOperationGeneration) TeamBalance_FinishOperation(true);
    return true;
}

bool TeamBalance_IsRespawnRequestCurrent(int client, int serial, int generation)
{
    return GetClientFromSerial(serial) == client && IsClientInGame(client)
        && g_iBalanceRespawnGeneration[client] == generation;
}

void TeamBalance_ScheduleRespawnCheck(int client, int serial, int generation)
{
    if (!TeamBalance_IsRespawnRequestCurrent(client, serial, generation)) return;
    DataPack pack;
    g_hBalanceRespawnTimer[client] = CreateDataTimer(TEAM_BALANCE_RESPAWN_RETRY_DELAY,
        Timer_TeamBalanceVerifyRespawn, pack, TIMER_FLAG_NO_MAPCHANGE);
    pack.WriteCell(serial);
    pack.WriteCell(generation);
}

bool TeamBalance_QueueRespawnInternal(int client, int expectedTeam, bool immediate)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || DuelDetection_IsClientInDuel(client)) return false;
    if (!IsGameTeam(expectedTeam)) expectedTeam = GetClientTeam(client);
    if (!IsGameTeam(expectedTeam)) return false;

    // Replacing the request cancels the previous chain, rather than resetting
    // counters shared by several timers which all continue to decrement them.
    TeamBalance_ClearRespawnState(client);
    int serial = GetClientSerial(client), generation = g_iBalanceRespawnGeneration[client];
    g_iBalanceRespawnAttempts[client] = TEAM_BALANCE_RESPAWN_RETRY_COUNT;
    g_iBalanceRespawnExpectedTeam[client] = expectedTeam;
    if (immediate && GetClientTeam(client) == expectedTeam)
    {
        if (TF2_GetPlayerClass(client) == TFClass_Unknown) TF2_SetPlayerClass(client, TFClass_Scout);
        if (!TeamBalance_IsRespawnRequestCurrent(client, serial, generation)) return true;
        if (GetClientTeam(client) == expectedTeam && !IsPlayerAlive(client)) TF2_RespawnPlayer(client);
        if (!TeamBalance_IsRespawnRequestCurrent(client, serial, generation)) return true;
    }
    TeamBalance_ScheduleRespawnCheck(client, serial, generation);
    return true;
}

void TeamBalance_ClearRespawnState(int client)
{
    if (client <= 0 || client > MaxClients) return;
    Handle timer = g_hBalanceRespawnTimer[client];
    g_hBalanceRespawnTimer[client] = null;
    g_iBalanceRespawnGeneration[client]++;
    g_iBalanceRespawnAttempts[client] = 0;
    g_iBalanceRespawnExpectedTeam[client] = 0;
    delete timer;
}

bool TeamBalance_IsRecentlyMoved(int client)
{
    return client > 0 && client <= MaxClients && g_fBalanceMovedUntil[client] > GetEngineTime();
}

void TeamBalance_MarkRecentlyMoved(int client)
{
    if (client > 0 && client <= MaxClients) g_fBalanceMovedUntil[client] = GetEngineTime() + TEAM_BALANCE_MOVE_PROTECTION;
}

void TeamBalance_ResetRuntime()
{
    g_iBalanceOperationGeneration++;
    TeamBalance_SetState(TeamBalance_Idle, 0.0);
    g_fScrambleCooldownUntil = 0.0;
    g_iScramblesSinceImmunityClear = 0;
    if (g_hScrambleImmunity != null) g_hScrambleImmunity.Clear();
    for (int client = 1; client <= MaxClients; client++)
    {
        TeamBalance_ClearRespawnState(client);
        g_fBalanceMovedUntil[client] = 0.0;
    }
}

public Action Timer_TeamBalanceVerifyRespawn(Handle timer, DataPack pack)
{
    pack.Reset();
    int serial = pack.ReadCell(), generation = pack.ReadCell();
    int client = GetClientFromSerial(serial);
    if (client == 0 || g_hBalanceRespawnTimer[client] != timer
        || g_iBalanceRespawnGeneration[client] != generation) return Plugin_Stop;
    // The timer is firing: relinquish ownership before any engine native. It
    // and its DataPack are closed by SourceMod when this callback returns Stop.
    g_hBalanceRespawnTimer[client] = null;
    if (!IsClientInGame(client) || DuelDetection_IsClientInDuel(client)
        || g_iBalanceRespawnAttempts[client] <= 0)
    {
        TeamBalance_ClearRespawnState(client);
        return Plugin_Stop;
    }
    int expectedTeam = g_iBalanceRespawnExpectedTeam[client];
    g_iBalanceRespawnAttempts[client]--;
    if (GetClientTeam(client) == expectedTeam)
    {
        if (TF2_GetPlayerClass(client) == TFClass_Unknown) TF2_SetPlayerClass(client, TFClass_Scout);
        if (!TeamBalance_IsRespawnRequestCurrent(client, serial, generation)) return Plugin_Stop;
        if (GetClientTeam(client) == expectedTeam && !IsPlayerAlive(client)) TF2_RespawnPlayer(client);
        if (!TeamBalance_IsRespawnRequestCurrent(client, serial, generation)) return Plugin_Stop;
        if (GetClientTeam(client) == expectedTeam && IsPlayerAlive(client))
        {
            TeamBalance_ClearRespawnState(client);
            return Plugin_Stop;
        }
    }
    if (g_iBalanceRespawnAttempts[client] <= 0) TeamBalance_ClearRespawnState(client);
    else TeamBalance_ScheduleRespawnCheck(client, serial, generation);
    return Plugin_Stop;
}
