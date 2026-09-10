public Action Command_RequestTeamSwap(int client, int args)
{
    if (!IsTeamSwapClient(client))
    {
        return Plugin_Handled;
    }

    if (args < 1)
    {
        ShowTeamSwapMenu(client);
        return Plugin_Handled;
    }

    char targetArg[MAX_TARGET_LENGTH];
    GetCmdArgString(targetArg, sizeof(targetArg));
    StripQuotes(targetArg);
    TrimString(targetArg);

    int target = FindTarget(client, targetArg, true, false);
    if (target > 0)
    {
        SendTeamSwapRequest(client, target);
    }

    return Plugin_Handled;
}

public Action Command_ForceTeamSwap(int client, int args)
{
    if (args < 1 || args > 2 || (args == 1 && client == 0))
    {
        ReplyToCommand(client, "[Team Swap] Usage: sm_forceswap <name> [name]");
        return Plugin_Handled;
    }

    int first = client;
    int second;
    char targetArg[MAX_TARGET_LENGTH];

    if (args == 1)
    {
        GetCmdArg(1, targetArg, sizeof(targetArg));
        second = FindTarget(client, targetArg, true, false);
    }
    else
    {
        GetCmdArg(1, targetArg, sizeof(targetArg));
        first = FindTarget(client, targetArg, true, false);
        if (first <= 0)
        {
            return Plugin_Handled;
        }

        GetCmdArg(2, targetArg, sizeof(targetArg));
        second = FindTarget(client, targetArg, true, false);
    }

    if (first <= 0 || second <= 0)
    {
        return Plugin_Handled;
    }

    if (first == second)
    {
        ReplyToCommand(client, "[Team Swap] Select two different players.");
        return Plugin_Handled;
    }

    int firstTeam = GetClientTeam(first);
    int secondTeam = GetClientTeam(second);
    if (!IsTeamSwapClient(first) || !IsTeamSwapClient(second)
        || !IsGameTeam(firstTeam) || !IsGameTeam(secondTeam) || firstTeam == secondTeam)
    {
        ReplyToCommand(client, "[Team Swap] Both players must be on different playing teams.");
        return Plugin_Handled;
    }

    if (DuelDetection_IsClientInDuel(first) || DuelDetection_IsClientInDuel(second))
    {
        ReplyToCommand(client, "[Team Swap] Players in a duel cannot swap teams.");
        return Plugin_Handled;
    }

    ClearTeamSwapRequestsForClient(first);
    ClearTeamSwapRequestsForClient(second);
    if (!TeamBalance_MoveManualPair(first, second))
    {
        ReplyToCommand(client, "[Team Swap] Team balancing is busy; try again in a moment.");
        return Plugin_Handled;
    }

    ReplyToCommand(client, "[Team Swap] Force-swapped %N with %N.", first, second);
    if (first != client)
    {
        CPrintToChat(first, "[Team Swap] An admin force-swapped you with %N.", second);
    }
    if (second != client)
    {
        CPrintToChat(second, "[Team Swap] An admin force-swapped you with %N.", first);
    }
    return Plugin_Handled;
}

public Action Command_AcceptTeamSwap(int client, int args)
{
    if (!IsTeamSwapClient(client) || !HasPendingTeamSwap(client))
    {
        return Plugin_Continue;
    }

    if (g_bSwapRequestFinalizing[client])
    {
        return Plugin_Handled;
    }

    int sender = GetClientOfUserId(g_iSwapRequestSenderUserId[client]);
    int senderTeam = g_iSwapRequestSenderTeam[client];
    int targetTeam = g_iSwapRequestTargetTeam[client];
    BeginTeamSwapRequestFinalization(client);

    if (!IsTeamSwapClient(sender))
    {
        CPrintToChat(client, "[Team Swap] The requester is no longer available.");
        return Plugin_Handled;
    }

    if (GetClientTeam(sender) != senderTeam || GetClientTeam(client) != targetTeam
        || senderTeam == targetTeam || !IsGameTeam(senderTeam) || !IsGameTeam(targetTeam))
    {
        CPrintToChat(client, "[Team Swap] The request is no longer valid because someone changed teams.");
        CPrintToChat(sender, "[Team Swap] Your request is no longer valid because someone changed teams.");
        return Plugin_Handled;
    }

    if (DuelDetection_IsClientInDuel(sender) || DuelDetection_IsClientInDuel(client))
    {
        CPrintToChat(client, "[Team Swap] Players in a duel cannot swap teams.");
        CPrintToChat(sender, "[Team Swap] Players in a duel cannot swap teams.");
        return Plugin_Handled;
    }

    TeamBalance_RefreshState();
    if (g_eTeamBalanceState != TeamBalance_Idle)
    {
        CPrintToChat(client, "[Team Swap] Team balancing is busy; try again in a moment.");
        CPrintToChat(sender, "[Team Swap] Team balancing is busy; try again in a moment.");
        return Plugin_Handled;
    }

    if (!CanUseTeamSwapStore(sender, true) || !CanUseTeamSwapStore(client, false))
    {
        CPrintToChat(client, "[Team Swap] The Gems store is not ready for both players.");
        CPrintToChat(sender, "[Team Swap] The Gems store is not ready for both players.");
        return Plugin_Handled;
    }

    if (PointsStore_GetBonusPoints(sender) < TEAM_SWAP_COST)
    {
        CPrintToChat(sender, "[Team Swap] You need {gold}%d Gems{default} to swap teams.", TEAM_SWAP_COST);
        CPrintToChat(client, "[Team Swap] The requester can no longer afford the team swap.");
        return Plugin_Handled;
    }

    if (!PointsStore_SpendBonusPoints(sender, TEAM_SWAP_COST))
    {
        CPrintToChat(sender, "[Team Swap] The {gold}%d Gem{default} payment failed.", TEAM_SWAP_COST);
        CPrintToChat(client, "[Team Swap] The requester's payment failed.");
        return Plugin_Handled;
    }

    if (!PointsStore_ApplyBonusPoints(client, TEAM_SWAP_REWARD_ID, true, true, 1.0, sender, 0.0))
    {
        PointsStore_RefundBonusPoints(sender, TEAM_SWAP_COST, "team_swap_refund");
        CPrintToChat(sender, "[Team Swap] The receiver reward failed; your Gems were refunded.");
        CPrintToChat(client, "[Team Swap] Your reward could not be applied, so the swap was cancelled.");
        return Plugin_Handled;
    }

    TeamBalance_MoveManualPair(sender, client);

    char senderName[256];
    char targetName[256];
    BuildTeamSwapDisplayName(sender, senderName, sizeof(senderName));
    BuildTeamSwapDisplayName(client, targetName, sizeof(targetName));
    CPrintToChatEx(sender, client, "[Team Swap] You swapped teams with %s{default} for {gold}%d Gems{default}.", targetName, TEAM_SWAP_COST);
    int teamSwapReward = PointsStore_GetRewardAmount(TEAM_SWAP_REWARD_ID);
    CPrintToChatEx(client, sender, "[Team Swap] You swapped teams with %s{default} and received {green}+%d Gems{default}.", senderName, teamSwapReward);
    return Plugin_Handled;
}

static void ShowTeamSwapMenu(int client)
{
    int clientTeam = GetClientTeam(client);
    if (!IsGameTeam(clientTeam))
    {
        CPrintToChat(client, "[Team Swap] Join a playing team before requesting a swap.");
        return;
    }

    Menu menu = new Menu(MenuHandler_TeamSwap);
    menu.SetTitle("Swap teams with an enemy - %d Gems", TEAM_SWAP_COST);

    int targetCount = 0;
    for (int target = 1; target <= MaxClients; target++)
    {
        if (!IsTeamSwapClient(target) || target == client || !IsGameTeam(GetClientTeam(target))
            || GetClientTeam(target) == clientTeam || DuelDetection_IsClientInDuel(target))
        {
            continue;
        }

        char userId[16];
        char name[MAX_NAME_LENGTH];
        IntToString(GetClientUserId(target), userId, sizeof(userId));
        GetClientName(target, name, sizeof(name));
        menu.AddItem(userId, name);
        targetCount++;
    }

    if (targetCount == 0)
    {
        delete menu;
        CPrintToChat(client, "[Team Swap] No enemy players are available.");
        return;
    }

    menu.ExitButton = true;
    menu.Display(client, 30);
}

public int MenuHandler_TeamSwap(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(item, info, sizeof(info));
        int target = GetClientOfUserId(StringToInt(info));
        SendTeamSwapRequest(client, target);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

static bool SendTeamSwapRequest(int sender, int target)
{
    if (!IsTeamSwapClient(sender) || !IsTeamSwapClient(target))
    {
        return false;
    }

    int senderTeam = GetClientTeam(sender);
    int targetTeam = GetClientTeam(target);
    if (sender == target || !IsGameTeam(senderTeam) || !IsGameTeam(targetTeam) || senderTeam == targetTeam)
    {
        CPrintToChat(sender, "[Team Swap] Select a player on an enemy team.");
        return false;
    }

    if (DuelDetection_IsClientInDuel(sender) || DuelDetection_IsClientInDuel(target))
    {
        CPrintToChat(sender, "[Team Swap] Players in a duel cannot swap teams.");
        return false;
    }

    if (!CanUseTeamSwapStore(sender, true))
    {
        return false;
    }

    if (PointsStore_GetBonusPoints(sender) < TEAM_SWAP_COST)
    {
        CPrintToChat(sender, "[Team Swap] You need {gold}%d Gems{default} to swap teams.", TEAM_SWAP_COST);
        return false;
    }

    if (FindOutgoingTeamSwapRequest(sender) > 0)
    {
        CPrintToChat(sender, "[Team Swap] You already have a pending request.");
        return false;
    }

    if (HasPendingTeamSwap(target))
    {
        CPrintToChat(sender, "[Team Swap] That player already has a pending request.");
        return false;
    }

    g_iSwapRequestSenderUserId[target] = GetClientUserId(sender);
    g_iSwapRequestSenderTeam[target] = senderTeam;
    g_iSwapRequestTargetTeam[target] = targetTeam;
    g_bSwapRequestFinalizing[target] = false;
    g_hSwapRequestTimer[target] = CreateTimer(TEAM_SWAP_TIMEOUT, Timer_ExpireTeamSwapRequest, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);

    char senderName[256];
    BuildTeamSwapDisplayName(sender, senderName, sizeof(senderName));
    CPrintToChat(sender, "[Team Swap] Request sent to %N. You will be charged {gold}%d Gems{default} if accepted.", target, TEAM_SWAP_COST);
    CPrintToChatEx(target, sender, "[Team Swap] %s{default} wants to swap teams with you! Use {gold}!yes{default} to accept.", senderName);
    return true;
}

public Action Timer_ExpireTeamSwapRequest(Handle timer, any targetUserId)
{
    int target = GetClientOfUserId(targetUserId);
    if (!IsTeamSwapClient(target))
    {
        return Plugin_Stop;
    }

    g_hSwapRequestTimer[target] = null;
    int sender = GetClientOfUserId(g_iSwapRequestSenderUserId[target]);
    if (IsTeamSwapClient(sender))
    {
        CPrintToChat(sender, "[Team Swap] Your request to %N expired.", target);
    }
    CPrintToChat(target, "[Team Swap] The pending team-swap request expired.");
    ClearTeamSwapRequest(target);
    return Plugin_Stop;
}

static void BeginTeamSwapRequestFinalization(int target)
{
    g_bSwapRequestFinalizing[target] = true;
    if (g_hSwapRequestTimer[target] != null)
    {
        delete g_hSwapRequestTimer[target];
        g_hSwapRequestTimer[target] = null;
    }
    RequestFrame(Frame_ClearFinalizedTeamSwap, target);
}

public void Frame_ClearFinalizedTeamSwap(any target)
{
    if (target > 0 && target <= MaxClients && g_bSwapRequestFinalizing[target])
    {
        ClearTeamSwapRequest(target);
    }
}

bool HasPendingTeamSwap(int target)
{
    return target > 0 && target <= MaxClients && g_iSwapRequestSenderUserId[target] > 0;
}

static int FindOutgoingTeamSwapRequest(int sender)
{
    int senderUserId = GetClientUserId(sender);
    for (int target = 1; target <= MaxClients; target++)
    {
        if (g_iSwapRequestSenderUserId[target] == senderUserId)
        {
            return target;
        }
    }
    return 0;
}

static void ClearTeamSwapRequest(int target)
{
    if (target <= 0 || target > MaxClients)
    {
        return;
    }

    if (g_hSwapRequestTimer[target] != null)
    {
        delete g_hSwapRequestTimer[target];
        g_hSwapRequestTimer[target] = null;
    }
    g_iSwapRequestSenderUserId[target] = 0;
    g_iSwapRequestSenderTeam[target] = 0;
    g_iSwapRequestTargetTeam[target] = 0;
    g_bSwapRequestFinalizing[target] = false;
}

void ClearTeamSwapRequestsForClient(int client)
{
    int userId = GetClientUserId(client);
    ClearTeamSwapRequest(client);
    for (int target = 1; target <= MaxClients; target++)
    {
        if (g_iSwapRequestSenderUserId[target] == userId)
        {
            ClearTeamSwapRequest(target);
        }
    }
}

void ClearAllTeamSwapRequests()
{
    for (int target = 1; target <= MaxClients; target++)
    {
        ClearTeamSwapRequest(target);
    }
}

static bool IsTeamSwapClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}

static bool TeamBalance_MoveManualPair(int first, int second)
{
    if (!TeamBalance_TryBegin(TeamBalance_ManualSwap, TEAM_BALANCE_OPERATION_LEASE, true))
    {
        return false;
    }

    int firstTeam = GetClientTeam(first);
    int secondTeam = GetClientTeam(second);
    bool firstWasAlive = IsPlayerAlive(first);
    bool secondWasAlive = IsPlayerAlive(second);

    ChangeClientTeam(first, secondTeam);
    ChangeClientTeam(second, firstTeam);
    TeamBalance_MarkRecentlyMoved(first);
    TeamBalance_MarkRecentlyMoved(second);
    if (firstWasAlive)
    {
        TeamBalance_QueueRespawnInternal(first, secondTeam, true);
    }
    if (secondWasAlive)
    {
        TeamBalance_QueueRespawnInternal(second, firstTeam, true);
    }
    TeamBalance_FinishOperation(true);
    return true;
}

static bool CanUseTeamSwapStore(int client, bool printFailure)
{
    bool available = GetFeatureStatus(FeatureType_Native, "PointsStore_AreBonusPointsLoaded") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "PointsStore_GetBonusPoints") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "PointsStore_SpendBonusPoints") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "PointsStore_ApplyBonusPoints") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "PointsStore_GetRewardAmount") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "PointsStore_RefundBonusPoints") == FeatureStatus_Available;
    if (!available)
    {
        if (printFailure)
        {
            CPrintToChat(client, "[Team Swap] The Gems store is unavailable.");
        }
        return false;
    }

    if (!PointsStore_AreBonusPointsLoaded(client))
    {
        if (printFailure)
        {
            CPrintToChat(client, "[Team Swap] Your Gems are still loading.");
        }
        return false;
    }
    return true;
}

static void BuildTeamSwapDisplayName(int client, char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    if (GetFeatureStatus(FeatureType_Native, "Filters_GetChatName") == FeatureStatus_Available
        && Filters_GetChatName(client, buffer, maxlen) && buffer[0] != '\0')
    {
        return;
    }

    Format(buffer, maxlen, "{teamcolor}%N", client);
}

// ---------------------------------------------------------------------------
// Main balance timer
// ---------------------------------------------------------------------------

