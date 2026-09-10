public any Native_HasPendingTeamSwap(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    return HasPendingTeamSwap(client);
}

public any Native_TeamBalanceIsBusy(Handle plugin, int numParams)
{
    TeamBalance_RefreshState();
    return g_eTeamBalanceState != TeamBalance_Idle;
}

public any Native_TeamBalanceIsScrambleCooldownActive(Handle plugin, int numParams)
{
    return TeamBalance_IsScrambleCooldownActiveInternal();
}

public any Native_TeamBalanceBeginScrambleVote(Handle plugin, int numParams)
{
    float leaseSeconds = view_as<float>(GetNativeCell(1));
    if (leaseSeconds < 1.0)
    {
        leaseSeconds = 1.0;
    }

    return TeamBalance_TryBegin(TeamBalance_ScrambleVote, leaseSeconds + 2.0, false);
}

public any Native_TeamBalanceEndScrambleVote(Handle plugin, int numParams)
{
    TeamBalance_RefreshState();
    if (g_eTeamBalanceState == TeamBalance_ScrambleVote)
    {
        TeamBalance_SetState(TeamBalance_Idle, 0.0);
    }
    return 0;
}

public any Native_TeamBalanceBeginScramble(Handle plugin, int numParams)
{
    bool bypassCooldown = view_as<bool>(GetNativeCell(1));
    TeamBalance_RefreshState();
    if (g_eTeamBalanceState == TeamBalance_ScrambleVote)
    {
        TeamBalance_SetState(TeamBalance_ScramblePending, TEAM_BALANCE_OPERATION_LEASE);
        return true;
    }

    return TeamBalance_TryBegin(TeamBalance_ScramblePending, TEAM_BALANCE_OPERATION_LEASE, bypassCooldown);
}

public any Native_TeamBalanceCancelScramble(Handle plugin, int numParams)
{
    TeamBalance_RefreshState();
    if (g_eTeamBalanceState == TeamBalance_ScrambleVote
        || g_eTeamBalanceState == TeamBalance_ScramblePending
        || g_eTeamBalanceState == TeamBalance_ScrambleMoving)
    {
        TeamBalance_SetState(TeamBalance_Idle, 0.0);
    }
    return 0;
}

public any Native_TeamBalanceFinishScramble(Handle plugin, int numParams)
{
    bool movedPlayers = view_as<bool>(GetNativeCell(1));
    bool countForImmunity = view_as<bool>(GetNativeCell(2));
    TeamBalance_FinishScrambleInternal(movedPlayers, countForImmunity);
    return 0;
}

public any Native_TeamBalanceIsScrambleCandidate(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int expectedTeam = GetNativeCell(2);
    bool ignoreImmunity = view_as<bool>(GetNativeCell(3));
    bool allowBots = view_as<bool>(GetNativeCell(4));
    return TeamBalance_IsScrambleCandidateInternal(client, expectedTeam, ignoreImmunity, allowBots);
}

public any Native_TeamBalanceHasScramblePurchaseImmunity(Handle plugin, int numParams)
{
    return TeamBalance_HasScramblePurchaseImmunityInternal(GetNativeCell(1));
}

public any Native_TeamBalanceConsumeScramblePurchaseImmunity(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!TeamBalance_HasScramblePurchaseImmunityInternal(client))
    {
        return -1;
    }

    return PointsStore_ConsumePurchaseUse(client, POINTS_STORE_SCRAMBLE_IMMUNITY_ITEM);
}

public any Native_TeamBalanceMoveScramblePair(Handle plugin, int numParams)
{
    return TeamBalance_MoveScramblePairInternal(
        GetNativeCell(1),
        GetNativeCell(2),
        view_as<bool>(GetNativeCell(3)),
        view_as<bool>(GetNativeCell(4)),
        view_as<bool>(GetNativeCell(5))
    );
}

public any Native_TeamBalanceQueueRespawn(Handle plugin, int numParams)
{
    return TeamBalance_QueueRespawnInternal(GetNativeCell(1), GetNativeCell(2), false);
}

