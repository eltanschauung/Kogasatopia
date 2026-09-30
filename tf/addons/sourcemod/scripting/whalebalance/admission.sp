// Coordinate admission/AFK moves without sharing autobalance immunity policy.
bool TeamBalance_CanAdmitClients()
{
    TeamBalance_RefreshState();
    return g_eTeamBalanceState == TeamBalance_Idle
        || g_eTeamBalanceState == TeamBalance_QueueJoin;
}

bool TeamBalance_CanRunAFKAction()
{
    TeamBalance_RefreshState();
    return g_eTeamBalanceState == TeamBalance_Idle
        && (!SpecQueue_IsPluginOperational() || SpecQueue_GetPendingJoinCount() == 0);
}

void TeamBalance_OnClientTeamChanged(int client, int team)
{
    if (g_iBalanceRespawnExpectedTeam[client] != team)
        TeamBalance_ClearRespawnState(client);
    if (!IsGameTeam(team))
        ClearTeamSwapRequestsForClient(client);
    g_fImbalanceDetectedAt = 0.0;
}

bool TeamBalance_MoveToSpectator(int client, const char[] reason, bool automatic = false)
{
    if (!Client_IsHumanInGame(client)) return false;
    if (GetClientTeam(client) == view_as<int>(TFTeam_Spectator)) return true;

    // Voluntary exits and capacity correction must remain possible even when busy.
    bool ownsOperation = TeamBalance_TryBegin(
        automatic ? TeamBalance_AFKRemoval : TeamBalance_SpectatorMove,
        TEAM_BALANCE_OPERATION_LEASE, true);
    if (automatic && !ownsOperation) return false;

    int serial = GetClientSerial(client);
    int operation = g_iBalanceOperationGeneration;
    int oldTeam = GetClientTeam(client);
    TeamBalance_ClearRespawnState(client);
    ClearTeamSwapRequestsForClient(client);
    ChangeClientTeam(client, view_as<int>(TFTeam_Spectator));
    bool moved = TeamBalance_IsSessionOnTeam(serial, view_as<int>(TFTeam_Spectator));
    if (ownsOperation && operation == g_iBalanceOperationGeneration)
        TeamBalance_FinishOperation(moved);
    if (moved)
        LogBalance("Team transition: userid=%d from=%d to=1 reason=%s",
            GetClientUserId(GetClientFromSerial(serial)), oldTeam, reason);
    return moved;
}
