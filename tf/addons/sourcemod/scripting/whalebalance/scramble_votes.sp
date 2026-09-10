void UpdateNativeVotes()
{
    g_bNativeVotes = LibraryExists("nativevotes") && NativeVotes_IsVoteTypeSupported(NativeVotesType_Custom_YesNo);
}

static void GetVoteActionName(WhaleVoteKind kind, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    switch (kind)
    {
        case WhaleVote_Surrender:
        {
            strcopy(buffer, maxlen, "surrender");
            return;
        }
    }

    strcopy(buffer, maxlen, "scramble");
}

static bool IsPlayerOnPlayableTeam(int client)
{
    int team = GetClientTeam(client);
    return team == TEAM_RED || team == TEAM_BLU;
}

static int GetOpposingTeam(int team)
{
    if (team == TEAM_RED)
    {
        return TEAM_BLU;
    }
    if (team == TEAM_BLU)
    {
        return TEAM_RED;
    }
    return 0;
}

static void GetColoredTeamName(int team, char[] buffer, int maxlen)
{
    if (team == TEAM_RED)
    {
        strcopy(buffer, maxlen, "{red}RED{default}");
        return;
    }
    if (team == TEAM_BLU)
    {
        strcopy(buffer, maxlen, "{blue}BLU{default}");
        return;
    }

    strcopy(buffer, maxlen, "{default}UNKNOWN{default}");
}

static void GetVoteKindName(WhaleVoteKind kind, char[] buffer, int maxlen)
{
    switch (kind)
    {
        case WhaleVote_Scramble:
        {
            strcopy(buffer, maxlen, "scramble");
            return;
        }
        case WhaleVote_Surrender:
        {
            strcopy(buffer, maxlen, "surrender");
            return;
        }
    }

    strcopy(buffer, maxlen, "none");
}

static int GetPlayableTeamClientCount(int team)
{
    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
        {
            continue;
        }

        if (GetClientTeam(i) == team)
        {
            count++;
        }
    }
    return count;
}

void GetScrambleTeamCounts(int &redCount, int &bluCount, int &totalPlayers)
{
    if (GetFeatureStatus(FeatureType_Native, "DGM_RealTeamPlayerCount") == FeatureStatus_Available)
    {
        redCount = DGM_RealTeamPlayerCount(TEAM_RED);
        bluCount = DGM_RealTeamPlayerCount(TEAM_BLU);
    }
    else
    {
        redCount = GetPlayableTeamClientCount(TEAM_RED);
        bluCount = GetPlayableTeamClientCount(TEAM_BLU);
    }

    totalPlayers = redCount + bluCount;
}

int CalculateDesiredScrambleSwapCount(int totalPlayers, int redCount, int bluCount, int maxSwapPairs)
{
    if (totalPlayers < MIN_SCRAMBLE_PLAYERS || redCount <= 0 || bluCount <= 0)
    {
        return 0;
    }

    int swapCount = (totalPlayers + SCRAMBLE_PLAYER_PERCENT_DIVISOR - 1) / SCRAMBLE_PLAYER_PERCENT_DIVISOR;
    if (swapCount < 1)
    {
        swapCount = 1;
    }
    if (swapCount > maxSwapPairs)
    {
        swapCount = maxSwapPairs;
    }
    if (swapCount > redCount)
    {
        swapCount = redCount;
    }
    if (swapCount > bluCount)
    {
        swapCount = bluCount;
    }

    return swapCount;
}

int LimitSwapCountToEligibility(int swapCount, int redEligible, int bluEligible)
{
    if (swapCount > redEligible)
    {
        swapCount = redEligible;
    }
    if (swapCount > bluEligible)
    {
        swapCount = bluEligible;
    }
    if (swapCount < 0)
    {
        swapCount = 0;
    }

    return swapCount;
}

void NotifySwapCountFailure(int issuer, bool broadcastFailures, int totalPlayers, int redCount, int bluCount, int redEligible, int bluEligible, const char[] modeName)
{
    if (totalPlayers < MIN_SCRAMBLE_PLAYERS)
    {
        NotifyFailure(issuer, broadcastFailures, "Need at least %d RED/BLU players (current: %d).", MIN_SCRAMBLE_PLAYERS, totalPlayers);
        LogWhale("%s scramble aborted: not enough players (total=%d min=%d).", modeName, totalPlayers, MIN_SCRAMBLE_PLAYERS);
        LogWhaleStat("scramble_result", "mode=%s|result=aborted|reason=not_enough_players|total=%d|min=%d|red=%d|blu=%d|eligible_red=%d|eligible_blu=%d", modeName, totalPlayers, MIN_SCRAMBLE_PLAYERS, redCount, bluCount, redEligible, bluEligible);
        return;
    }

    if (redCount <= 0 || bluCount <= 0)
    {
        NotifyFailure(issuer, broadcastFailures, "Each team needs at least 1 player (RED=%d BLU=%d).", redCount, bluCount);
        LogWhale("%s scramble aborted: one team empty (red=%d blu=%d).", modeName, redCount, bluCount);
        LogWhaleStat("scramble_result", "mode=%s|result=aborted|reason=empty_team|total=%d|red=%d|blu=%d|eligible_red=%d|eligible_blu=%d", modeName, totalPlayers, redCount, bluCount, redEligible, bluEligible);
        return;
    }

    NotifyFailure(issuer, broadcastFailures, "Not enough eligible players to swap (RED=%d BLU=%d).", redEligible, bluEligible);
    LogWhale("%s scramble aborted: not enough eligible players (red=%d blu=%d).", modeName, redEligible, bluEligible);
    LogWhaleStat("scramble_result", "mode=%s|result=aborted|reason=not_enough_eligible|total=%d|red=%d|blu=%d|eligible_red=%d|eligible_blu=%d", modeName, totalPlayers, redCount, bluCount, redEligible, bluEligible);
}

bool ShouldIgnoreScrambleImmunity(int totalPlayers, bool randomMode)
{
    if (randomMode)
    {
        return totalPlayers <= (MAX_RANDOM_SWAP * 2);
    }

    return totalPlayers <= (MAX_TOP_SWAP * 2);
}

void ApplyEngineScramblePolicy()
{
    if (g_hDisableTfAuto == null || !g_hDisableTfAuto.BoolValue)
    {
        return;
    }

    if (g_hMpScrambleTeamsAuto == null)
    {
        g_hMpScrambleTeamsAuto = FindConVar("mp_scrambleteams_auto");
    }

    if (g_hMpScrambleTeamsAuto == null)
    {
        LogWhale("Unable to find mp_scrambleteams_auto for policy enforcement.");
        return;
    }

    if (g_hMpScrambleTeamsAuto.BoolValue)
    {
        g_hMpScrambleTeamsAuto.SetBool(false);
        LogWhale("Disabled TF2 mp_scrambleteams_auto; WhaleScramble owns auto scrambles.");
    }
}

bool IsSmallFormatGamemode()
{
    if (GetFeatureStatus(FeatureType_Native, "DGM_IsSmallFormatGamemode") != FeatureStatus_Available)
    {
        return false;
    }

    return DGM_IsSmallFormatGamemode();
}

static int GetScrambleVoteRequestCount()
{
    return g_iScrambleVoteRequests;
}

static int GetSurrenderVoteCountForTeam(int team)
{
    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_bPlayerRequestedSurrender[i] && g_iPlayerSurrenderVoteTeam[i] == team)
        {
            count++;
        }
    }
    return count;
}

void LogSurrenderState(const char[] reason)
{
    char voteKind[16];
    GetVoteKindName(g_eActiveVoteKind, voteKind, sizeof(voteKind));

    LogWhale("Surrender state [%s]: reqRed=%d reqBlu=%d playersRed=%d playersBlu=%d voteRunning=%d voteKind=%s activeTeam=%d cooldown=%d.",
        reason,
        GetSurrenderVoteCountForTeam(TEAM_RED),
        GetSurrenderVoteCountForTeam(TEAM_BLU),
        GetPlayableTeamClientCount(TEAM_RED),
        GetPlayableTeamClientCount(TEAM_BLU),
        g_bVoteRunning ? 1 : 0,
        voteKind,
        g_iActiveSurrenderTeam,
        TeamBalance_IsScrambleCooldownActive() ? 1 : 0);
}

static void SetPlayerVoteRequested(int client, WhaleVoteKind kind, bool value)
{
    if (kind == WhaleVote_Surrender)
    {
        g_bPlayerRequestedSurrender[client] = value;
        return;
    }

    g_bPlayerRequestedScramble[client] = value;
}

void ClearClientSurrenderVote(int client)
{
    g_bPlayerRequestedSurrender[client] = false;
    g_iPlayerSurrenderVoteTeam[client] = 0;
}

static bool HasPlayerRequestedVote(int client, WhaleVoteKind kind)
{
    if (kind == WhaleVote_Surrender)
    {
        return g_bPlayerRequestedSurrender[client];
    }

    return g_bPlayerRequestedScramble[client];
}

static void IncrementScrambleVoteRequestCount()
{
    g_iScrambleVoteRequests++;
}

void HandleVoteRequest(int client, WhaleVoteKind kind)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
        return;

    if (kind == WhaleVote_Surrender && !IsPlayerOnPlayableTeam(client))
    {
        CPrintToChat(client, "{gold}[WhaleScramble] {default}Only teams {red}RED {default}and {blue}BLU{default} can surrender!");
        LogWhale("Surrender request rejected: invalid team (client %N team=%d).", client, GetClientTeam(client));
        LogWhaleStat("vote_request", "kind=surrender|result=rejected|reason=invalid_team|team=%d", GetClientTeam(client));
        return;
    }

    char actionName[16];
    GetVoteActionName(kind, actionName, sizeof(actionName));

    if (TeamBalance_IsScrambleCooldownActive())
    {
        CPrintToChat(client, "{blue}[WhaleScramble]{default} %s is on cooldown.", actionName);
        LogWhale("Vote request rejected: %s cooldown active (client %N).", actionName, client);
        LogWhaleStat("vote_request", "kind=%s|result=rejected|reason=cooldown", actionName);
        return;
    }

    if (g_bVoteRunning || NativeVotes_IsVoteInProgress() || IsVoteInProgress())
    {
        CPrintToChat(client, "{blue}[WhaleScramble]{default} A vote is already running.");
        LogWhale("Vote request rejected: vote already running (client %N kind=%s).", client, actionName);
        LogWhaleStat("vote_request", "kind=%s|result=rejected|reason=vote_running", actionName);
        return;
    }

    if (HasPlayerRequestedVote(client, kind))
    {
        CPrintToChat(client, "{blue}[WhaleScramble]{default} You already requested a %s vote.", actionName);
        LogWhale("Vote request rejected: already requested (client %N kind=%s).", client, actionName);
        LogWhaleStat("vote_request", "kind=%s|result=rejected|reason=already_requested", actionName);
        return;
    }

    SetPlayerVoteRequested(client, kind, true);
    if (kind == WhaleVote_Surrender)
    {
        g_iPlayerSurrenderVoteTeam[client] = GetClientTeam(client);
    }
    else
    {
        IncrementScrambleVoteRequestCount();
    }

    int requestCount = GetScrambleVoteRequestCount();
    if (kind == WhaleVote_Surrender)
    {
        requestCount = GetSurrenderVoteCountForTeam(g_iPlayerSurrenderVoteTeam[client]);
        LogWhale("Surrender request counted: %N team=%d teamCount=%d redRequests=%d bluRequests=%d.",
            client,
            g_iPlayerSurrenderVoteTeam[client],
            requestCount,
            GetSurrenderVoteCountForTeam(TEAM_RED),
            GetSurrenderVoteCountForTeam(TEAM_BLU));
        LogSurrenderState("request_counted");
    }
    CPrintToChatAll("{blue}[WhaleScramble]{default} %N requested a %s vote (%d/4).", client, actionName, requestCount);
    LogWhale("Vote request counted: %N kind=%s (%d/%d).", client, actionName, requestCount, 4);
    LogWhaleStat("vote_request", "kind=%s|result=counted|count=%d|threshold=4|team=%d", actionName, requestCount, GetClientTeam(client));

    if (requestCount >= 4)
    {
        if (kind == WhaleVote_Surrender)
        {
            LogWhale("Surrender threshold reached: team=%d trigger=%N.", g_iPlayerSurrenderVoteTeam[client], client);
        }
        StartVote(client, false, false, kind);
    }
}

bool StartVote(int client, bool suppressFeedback, bool allowLowPop, WhaleVoteKind kind)
{
    char actionName[16];
    GetVoteActionName(kind, actionName, sizeof(actionName));
    LogWhale("Starting %s vote: caller=%d allowLowPop=%d suppressFeedback=%d.", actionName, client, allowLowPop ? 1 : 0, suppressFeedback ? 1 : 0);

    if (kind == WhaleVote_Surrender)
    {
        if (client <= 0 || !IsClientInGame(client) || !IsPlayerOnPlayableTeam(client))
        {
            if (!suppressFeedback && client > 0 && IsClientInGame(client))
            {
                CPrintToChat(client, "{gold}[WhaleScramble] {default}Only teams {red}RED {default}and {blue}BLU{default} can surrender!");
            }
            LogWhale("Vote start failed: surrender caller invalid team (client=%d team=%d).", client, (client > 0 && IsClientInGame(client)) ? GetClientTeam(client) : 0);
            LogWhaleStat("vote_result", "kind=surrender|phase=start|result=failed|reason=invalid_team|team=%d", (client > 0 && IsClientInGame(client)) ? GetClientTeam(client) : 0);
            return false;
        }

        LogWhale("Starting surrender vote: caller=%N callerTeam=%d redRequests=%d bluRequests=%d allowLowPop=%d suppressFeedback=%d.",
            client,
            GetClientTeam(client),
            GetSurrenderVoteCountForTeam(TEAM_RED),
            GetSurrenderVoteCountForTeam(TEAM_BLU),
            allowLowPop ? 1 : 0,
            suppressFeedback ? 1 : 0);
    }

    if (TeamBalance_IsScrambleCooldownActive())
    {
        if (!suppressFeedback && client > 0 && IsClientInGame(client))
        {
            CPrintToChat(client, "{blue}[WhaleScramble]{default} %s is on cooldown.", actionName);
        }
        LogWhale("Vote start failed: %s cooldown active.", actionName);
        LogWhaleStat("vote_result", "kind=%s|phase=start|result=failed|reason=cooldown", actionName);
        return false;
    }

    if (!g_bNativeVotes)
    {
        if (!suppressFeedback && client > 0 && IsClientInGame(client))
        {
            CPrintToChat(client, "{blue}[WhaleScramble]{default} NativeVotes is unavailable.");
        }
        LogWhale("Vote start failed: NativeVotes unavailable.");
        LogWhaleStat("vote_result", "kind=%s|phase=start|result=failed|reason=nativevotes_unavailable", actionName);
        return false;
    }

    if (g_bVoteRunning || NativeVotes_IsVoteInProgress() || IsVoteInProgress())
    {
        if (!suppressFeedback && client > 0 && IsClientInGame(client))
        {
            CPrintToChat(client, "{blue}[WhaleScramble]{default} A vote is already running.");
        }
        LogWhale("Vote start failed: vote already running.");
        LogWhaleStat("vote_result", "kind=%s|phase=start|result=failed|reason=vote_running", actionName);
        return false;
    }

    int delay = NativeVotes_CheckVoteDelay();
    if (delay > 0)
    {
        if (!suppressFeedback && client > 0 && IsClientInGame(client))
        {
            NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_Recent, delay);
        }
        LogWhale("Vote start failed: vote delay %d.", delay);
        LogWhaleStat("vote_result", "kind=%s|phase=start|result=failed|reason=vote_delay|delay=%d", actionName, delay);
        return false;
    }

    if (!NativeVotes_IsNewVoteAllowed())
    {
        if (!suppressFeedback && client > 0 && IsClientInGame(client))
        {
            CPrintToChat(client, "{blue}[WhaleScramble]{default} A vote is not allowed right now.");
        }
        LogWhale("Vote start failed: new vote not allowed.");
        LogWhaleStat("vote_result", "kind=%s|phase=start|result=failed|reason=new_vote_not_allowed", actionName);
        return false;
    }

    if (g_hVote != null)
    {
        g_hVote.Close();
        g_hVote = null;
    }

    g_hVote = new NativeVote(ScrambleVoteHandler, NativeVotesType_Custom_YesNo, MENU_ACTIONS_ALL);
    if (kind == WhaleVote_Surrender)
    {
        NativeVotes_SetTitle(g_hVote, "Surrender round?");
    }
    else
    {
        NativeVotes_SetTitle(g_hVote, "Whale scramble teams?");
    }

    int voteTime = 4;
    if (g_hVoteTime != null)
    {
        voteTime = g_hVoteTime.IntValue;
    }
    if (voteTime < 1)
    {
        voteTime = 1;
    }

    if (!TeamBalance_BeginScrambleVote(float(voteTime)))
    {
        g_hVote.Close();
        g_hVote = null;
        if (!suppressFeedback && client > 0 && IsClientInGame(client))
        {
            CPrintToChat(client, "{blue}[WhaleScramble]{default} Team balancing is busy; try again in a moment.");
        }
        LogWhale("Vote start failed: authoritative team-balance state is busy.");
        LogWhaleStat("vote_result", "kind=%s|phase=start|result=failed|reason=balance_busy", actionName);
        return false;
    }

    g_bVoteRunning = NativeVotes_DisplayToAll(g_hVote, voteTime);
    if (!g_bVoteRunning)
    {
        TeamBalance_CancelScramble();
        g_hVote.Close();
        g_hVote = null;
        g_bVoteAllowLowPop = false;
        g_eActiveVoteKind = WhaleVote_None;
        LogWhale("Vote start failed: display to all returned false.");
        LogWhaleStat("vote_result", "kind=%s|phase=start|result=failed|reason=display_failed", actionName);
        return false;
    }

    g_bVoteAllowLowPop = allowLowPop;
    g_eActiveVoteKind = kind;
    if (kind == WhaleVote_Surrender && client > 0 && IsClientInGame(client))
    {
        g_iActiveSurrenderTeam = GetClientTeam(client);
    }
    else
    {
        g_iActiveSurrenderTeam = 0;
    }
    LogWhale("%s vote started: duration=%d allowLowPop=%d activeSurrenderTeam=%d.", actionName, voteTime, allowLowPop ? 1 : 0, g_iActiveSurrenderTeam);
    LogWhaleStat("vote_result", "kind=%s|phase=start|result=started|duration=%d|allow_low_pop=%d|active_team=%d", actionName, voteTime, allowLowPop ? 1 : 0, g_iActiveSurrenderTeam);
    if (kind == WhaleVote_Surrender)
    {
        LogSurrenderState("vote_started");
    }
    return true;
}

bool StartAutoScramble(bool suppressFeedback)
{
    if (g_bVoteRunning || NativeVotes_IsVoteInProgress() || IsVoteInProgress())
    {
        return false;
    }

    if (TeamBalance_IsScrambleCooldownActive())
    {
        LogWhale("Auto scramble aborted: scramble cooldown active.");
        LogWhaleStat("auto_scramble_decision", "trigger=auto|result=blocked|reason=cooldown");
        return false;
    }

    if (!suppressFeedback)
    {
        CPrintToChatAll("{blue}[WhaleScramble]{default} Auto scramble triggered.");
    }

    LogWhale("Auto scramble triggered.");
    LogWhaleStat("auto_scramble_decision", "trigger=auto|result=triggered");
    return StartConfiguredWhaleScramble(0, !suppressFeedback, false, false);
}

bool StartConfiguredWhaleScramble(int issuer, bool broadcastFailures, bool allowLowPop, bool forced)
{
    if (g_hTopSwap != null && g_hTopSwap.BoolValue)
    {
        LogWhale("Configured scramble mode: topswap forced=%d.", forced ? 1 : 0);
        return StartWhaleScramble(issuer, broadcastFailures, allowLowPop, forced);
    }
    else if (g_hWhaleRankBalance != null && g_hWhaleRankBalance.BoolValue)
    {
        LogWhale("Configured scramble mode: WhaleTracker ranks forced=%d.", forced ? 1 : 0);
        return StartWhaleRankBalanceScramble(issuer, broadcastFailures, allowLowPop, forced, 0);
    }
    else if (g_hFragBalance != null && g_hFragBalance.BoolValue)
    {
        LogWhale("Configured scramble mode: frags forced=%d.", forced ? 1 : 0);
        return StartFragBalanceWhaleScramble(issuer, broadcastFailures, allowLowPop, forced);
    }
    else if (g_hRandom != null && g_hRandom.BoolValue)
    {
        LogWhale("Configured scramble mode: random forced=%d.", forced ? 1 : 0);
        return StartRandomWhaleScramble(issuer, broadcastFailures, allowLowPop, forced);
    }

    NotifyFailure(issuer, broadcastFailures, "No scramble mode is enabled. Set sm_ws_topswap or sm_ws_random to 1.");
    LogWhale("Configured scramble aborted: no enabled modes.");
    LogWhaleStat("scramble_result", "mode=configured|result=aborted|reason=no_enabled_modes|forced=%d", forced ? 1 : 0);
    return false;
}

public int ScrambleVoteHandler(NativeVote vote, MenuAction action, int param1, int param2)
{
    WhaleVoteKind voteKind = g_eActiveVoteKind;
    char voteKindName[16];
    GetVoteKindName(voteKind, voteKindName, sizeof(voteKindName));
    if (voteKind == WhaleVote_Surrender)
    {
        LogWhale("Surrender vote action: action=%d param1=%d param2=%d activeTeam=%d voteRunning=%d.", action, param1, param2, g_iActiveSurrenderTeam, g_bVoteRunning ? 1 : 0);
    }

    switch (action)
    {
        case MenuAction_End:
        {
            TeamBalance_EndScrambleVote();
            vote.Close();
            g_hVote = null;
            g_bVoteRunning = false;
            g_bVoteAllowLowPop = false;
            g_eActiveVoteKind = WhaleVote_None;
            g_iActiveSurrenderTeam = 0;
            if (voteKind == WhaleVote_Scramble)
            {
                ResetScrambleVotes();
            }
            LogWhale("Vote ended.");
            if (voteKind == WhaleVote_Surrender)
            {
                LogSurrenderState("vote_end");
            }
            return 0;
        }
        case MenuAction_VoteCancel:
        {
            TeamBalance_CancelScramble();
            if (param1 == VoteCancel_NoVotes)
            {
                NativeVotes_DisplayFail(vote, NativeVotesFail_NotEnoughVotes);
            }
            else
            {
                NativeVotes_DisplayFail(vote, NativeVotesFail_Generic);
            }
            g_bVoteAllowLowPop = false;
            g_eActiveVoteKind = WhaleVote_None;
            g_iActiveSurrenderTeam = 0;
            if (voteKind == WhaleVote_Scramble)
            {
                ResetScrambleVotes();
            }
            LogWhale("Vote cancelled: %d.", param1);
            LogWhaleStat("vote_result", "kind=%s|phase=end|result=cancelled|reason=%d", voteKindName, param1);
            if (voteKind == WhaleVote_Surrender)
            {
                LogSurrenderState("vote_cancel");
            }
            return 0;
        }
        case MenuAction_VoteEnd:
        {
            if (voteKind == WhaleVote_None)
            {
                TeamBalance_CancelScramble();
                NativeVotes_DisplayFail(vote, NativeVotesFail_Generic);
                g_bVoteAllowLowPop = false;
                LogWhale("Vote end failed closed: active vote kind missing.");
                LogWhaleStat("vote_result", "kind=none|phase=end|result=failed|reason=missing_kind");
                return 0;
            }

            int votes = 0;
            int totalVotes = 0;
            NativeVotes_GetInfo(param2, votes, totalVotes);

            if (totalVotes <= 0)
            {
                TeamBalance_CancelScramble();
                NativeVotes_DisplayFail(vote, NativeVotesFail_NotEnoughVotes);
                LogWhale("Vote failed: no votes.");
                LogWhaleStat("vote_result", "kind=%s|phase=end|result=failed|reason=no_votes", voteKindName);
                return 0;
            }

            int yesVotes = (param1 == NATIVEVOTES_VOTE_YES) ? votes : (totalVotes - votes);
            float yesPercent = float(yesVotes) / float(totalVotes);

            if (yesPercent < 0.50)
            {
                TeamBalance_CancelScramble();
                NativeVotes_DisplayFail(vote, NativeVotesFail_Loses);
                CPrintToChatAll("Vote failed (Yes %.0f%%).", yesPercent * 100.0);
                g_bVoteAllowLowPop = false;
                LogWhale("Vote failed: yes=%d total=%d (%.1f%%).", yesVotes, totalVotes, yesPercent * 100.0);
                LogWhaleStat("vote_result", "kind=%s|phase=end|result=failed|reason=lost|yes=%d|total=%d|yes_percent=%.1f", voteKindName, yesVotes, totalVotes, yesPercent * 100.0);
                if (voteKind == WhaleVote_Surrender)
                {
                    LogSurrenderState("vote_fail");
                }
            }
            else
            {
                bool success = false;
                if (voteKind == WhaleVote_Surrender)
                {
                    int winningTeamNum = GetOpposingTeam(g_iActiveSurrenderTeam);
                    if (g_iActiveSurrenderTeam != TEAM_RED && g_iActiveSurrenderTeam != TEAM_BLU || winningTeamNum == 0)
                    {
                        NativeVotes_DisplayFail(vote, NativeVotesFail_Generic);
                        g_bVoteAllowLowPop = false;
                        LogWhale("Surrender vote failed closed: invalid active surrender team=%d.", g_iActiveSurrenderTeam);
                        LogWhaleStat("vote_result", "kind=surrender|phase=end|result=failed|reason=invalid_active_team|active_team=%d", g_iActiveSurrenderTeam);
                        return 0;
                    }
                    LogWhale("Surrender vote passed: issuing mp_scrambleteams surrenderTeam=%d winningTeam=%d yes=%d total=%d.",
                        g_iActiveSurrenderTeam,
                        winningTeamNum,
                        yesVotes,
                        totalVotes);
                    if (TeamBalance_BeginScramble(false))
                    {
                        TeamBalance_FinishScramble(true, false);
                        ServerCommand("mp_scrambleteams");
                        SaySounds_TryPlayCommand(0, TEAM_MOVE_SAYSOUND, true);
                        success = true;
                    }
                }
                else
                {
                    success = StartConfiguredWhaleScramble(0, true, g_bVoteAllowLowPop, false);
                }

                if (success)
                {
                    if (voteKind == WhaleVote_Surrender)
                    {
                        NativeVotes_DisplayPassCustom(vote, "Vote passed. Surrendering round...");
                        char surrenderTeam[32];
                        char winningTeam[32];
                        GetColoredTeamName(g_iActiveSurrenderTeam, surrenderTeam, sizeof(surrenderTeam));
                        GetColoredTeamName(GetOpposingTeam(g_iActiveSurrenderTeam), winningTeam, sizeof(winningTeam));
                        CPrintToChatAll("Team %s surrendered to %s!", surrenderTeam, winningTeam);
                        LogWhale("Surrender vote passed: yes=%d total=%d (%.1f%%).", yesVotes, totalVotes, yesPercent * 100.0);
                        LogWhaleStat("vote_result", "kind=surrender|phase=end|result=passed|success=1|yes=%d|total=%d|yes_percent=%.1f|surrender_team=%d|winning_team=%d", yesVotes, totalVotes, yesPercent * 100.0, g_iActiveSurrenderTeam, GetOpposingTeam(g_iActiveSurrenderTeam));
                        LogSurrenderState("vote_pass");
                    }
                    else
                    {
                        NativeVotes_DisplayPassCustom(vote, "Vote passed. Whale scrambling teams...");
                        LogWhale("Vote passed: yes=%d total=%d (%.1f%%).", yesVotes, totalVotes, yesPercent * 100.0);
                        LogWhaleStat("vote_result", "kind=scramble|phase=end|result=passed|success=1|yes=%d|total=%d|yes_percent=%.1f", yesVotes, totalVotes, yesPercent * 100.0);
                    }
                }
                else
                {
                    if (voteKind == WhaleVote_Surrender)
                    {
                        NativeVotes_DisplayPassCustom(vote, "Vote passed. Unable to surrender right now.");
                        LogWhale("Surrender vote passed but command could not be issued.");
                        LogWhaleStat("vote_result", "kind=surrender|phase=end|result=passed|success=0|reason=command_failed|yes=%d|total=%d|yes_percent=%.1f", yesVotes, totalVotes, yesPercent * 100.0);
                    }
                    else
                    {
                        NativeVotes_DisplayPassCustom(vote, "Vote passed. Scramble conditions not met.");
                        LogWhale("Vote passed but scramble conditions not met.");
                        LogWhaleStat("vote_result", "kind=scramble|phase=end|result=passed|success=0|reason=scramble_conditions|yes=%d|total=%d|yes_percent=%.1f", yesVotes, totalVotes, yesPercent * 100.0);
                    }
                    TeamBalance_CancelScramble();
                }
                g_bVoteAllowLowPop = false;
                g_eActiveVoteKind = WhaleVote_None;
                g_iActiveSurrenderTeam = 0;
            }
            return 0;
        }
    }
    return 0;
}

static void ResetScrambleVotes()
{
    g_iScrambleVoteRequests = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        g_bPlayerRequestedScramble[i] = false;
    }
}

void ResetVotes()
{
    ResetScrambleVotes();
    ResetSurrenderVotes("full_reset");
    g_bVoteRunning = false;
    g_eActiveVoteKind = WhaleVote_None;
    g_iActiveSurrenderTeam = 0;
}

void ResetSurrenderVotes(const char[] reason)
{
    bool preserveActiveSurrenderVote = g_bVoteRunning && g_eActiveVoteKind == WhaleVote_Surrender;
    LogWhale("Reset surrender votes: reason=%s preserveActive=%d.", reason, preserveActiveSurrenderVote ? 1 : 0);

    if (!preserveActiveSurrenderVote && g_eActiveVoteKind == WhaleVote_Surrender)
    {
        g_eActiveVoteKind = WhaleVote_None;
    }
    if (!preserveActiveSurrenderVote)
    {
        g_iActiveSurrenderTeam = 0;
    }
    for (int i = 1; i <= MaxClients; i++)
    {
        g_bPlayerRequestedSurrender[i] = false;
        g_iPlayerSurrenderVoteTeam[i] = 0;
    }
    LogSurrenderState(reason);
}

static void ArmAutoScrambleForNextRound()
{
    g_bAutoScramblePendingRoundStart = true;
    g_flAutoScramblePendingRoundStartUntil = GetEngineTime() + 20.0;
    LogWhale("Auto scramble armed for next round start.");
}

bool TryArmAutoScrambleForNextRound(const char[] reason)
{
    if (g_bAutoScramblePendingRoundStart)
    {
        LogWhale("Auto scramble already pending; reason=%s.", reason);
        LogWhaleStat("auto_scramble_decision", "trigger=%s|result=blocked|reason=already_pending", reason);
        return false;
    }

    if (g_hNoSequentialAuto != null && g_hNoSequentialAuto.BoolValue)
    {
        if (g_bScrambledThisRound)
        {
            LogWhale("Auto scramble blocked by no-sequential guard: already scrambled this round; reason=%s.", reason);
            LogWhaleStat("auto_scramble_decision", "trigger=%s|result=blocked|reason=scrambled_this_round", reason);
            return false;
        }

        if (g_bLastRoundHadScramble)
        {
            LogWhale("Auto scramble blocked by no-sequential guard: previous round scrambled; reason=%s.", reason);
            LogWhaleStat("auto_scramble_decision", "trigger=%s|result=blocked|reason=previous_round_scrambled", reason);
            return false;
        }
    }

    LogWhale("Auto scramble arming accepted: reason=%s.", reason);
    LogWhaleStat("auto_scramble_decision", "trigger=%s|result=armed", reason);
    ArmAutoScrambleForNextRound();
    return true;
}

bool ConsumeAutoScramblePending()
{
    if (!g_bAutoScramblePendingRoundStart)
    {
        return false;
    }

    if (GetEngineTime() > g_flAutoScramblePendingRoundStartUntil)
    {
        ClearAutoScramblePending();
        LogWhale("Auto scramble pending state expired before round start.");
        LogWhaleStat("auto_scramble_decision", "trigger=pending_round_start|result=expired");
        return false;
    }

    ClearAutoScramblePending();
    return true;
}

void ClearAutoScramblePending()
{
    g_bAutoScramblePendingRoundStart = false;
    g_flAutoScramblePendingRoundStartUntil = 0.0;
}

static bool StartWhaleScramble(int issuer, bool broadcastFailures, bool allowLowPop, bool forced)
{
    LogWhale("StartWhaleScramble: issuer=%d allowLowPop=%d forced=%d.", issuer, allowLowPop ? 1 : 0, forced ? 1 : 0);
    g_iRoundsSinceAuto = 0;
    int totalPlayers = 0;
    int redCount = 0;
    int bluCount = 0;
    int redEligible = 0;
    int bluEligible = 0;

    int topRed[MAX_SWAP_BUFFER];
    int topBlu[MAX_SWAP_BUFFER];
    int topRedScore[MAX_SWAP_BUFFER];
    int topBluScore[MAX_SWAP_BUFFER];

    for (int i = 0; i < MAX_SWAP_BUFFER; i++)
    {
        topRed[i] = 0;
        topBlu[i] = 0;
        topRedScore[i] = -999999;
        topBluScore[i] = -999999;
    }

    GetScrambleTeamCounts(redCount, bluCount, totalPlayers);

    bool smallFormatGamemode = IsSmallFormatGamemode();
    bool ignoreImmunity = smallFormatGamemode || ShouldIgnoreScrambleImmunity(totalPlayers, false);
    if (ignoreImmunity)
    {
        LogWhale(
            "Topswap scramble: ignoring immunity due to %s total=%d threshold=%d.",
            smallFormatGamemode ? "small-format gamemode" : "low player count",
            totalPlayers,
            MAX_TOP_SWAP * 2);
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!TeamBalance_IsScrambleCandidate(i, 0, ignoreImmunity, g_hCountBots != null && g_hCountBots.BoolValue)) continue;
        int team = GetClientTeam(i);

        if (team == TEAM_RED) redEligible++;
        else bluEligible++;

        int score = GetScrambleScore(i, false, forced);
        if (team == TEAM_RED)
        {
            InsertTopN(i, score, topRed, topRedScore, MAX_TOP_SWAP);
        }
        else
        {
            InsertTopN(i, score, topBlu, topBluScore, MAX_TOP_SWAP);
        }
    }

    int desiredSwapCount = CalculateDesiredScrambleSwapCount(totalPlayers, redCount, bluCount, MAX_TOP_SWAP);
    int swapCount = LimitSwapCountToEligibility(desiredSwapCount, redEligible, bluEligible);
    LogWhale("Counts: total=%d red=%d blu=%d eligibleRed=%d eligibleBlu=%d desiredSwap=%d swap=%d.", totalPlayers, redCount, bluCount, redEligible, bluEligible, desiredSwapCount, swapCount);

    bool needsFallback = (desiredSwapCount > 0 && swapCount < desiredSwapCount);
    if (needsFallback)
    {
        LogWhale("Eligibility low; recalculating without class filters.");
        redEligible = 0;
        bluEligible = 0;
        for (int i = 0; i < MAX_SWAP_BUFFER; i++)
        {
            topRed[i] = 0;
            topBlu[i] = 0;
            topRedScore[i] = -999999;
            topBluScore[i] = -999999;
        }

        for (int i = 1; i <= MaxClients; i++)
        {
            if (!TeamBalance_IsScrambleCandidate(i, 0, ignoreImmunity, g_hCountBots != null && g_hCountBots.BoolValue)) continue;
            int team = GetClientTeam(i);

            if (team == TEAM_RED) redEligible++;
            else bluEligible++;

            int score = GetScrambleScore(i, true, forced);
            if (team == TEAM_RED)
            {
                InsertTopN(i, score, topRed, topRedScore, MAX_TOP_SWAP);
            }
            else
            {
                InsertTopN(i, score, topBlu, topBluScore, MAX_TOP_SWAP);
            }
        }
        swapCount = LimitSwapCountToEligibility(desiredSwapCount, redEligible, bluEligible);
    }

    LogWhaleStat("scramble_attempt", "mode=topswap|issuer=%d|allow_low_pop=%d|forced=%d|total=%d|red=%d|blu=%d|eligible_red=%d|eligible_blu=%d|desired_swap=%d|swap=%d|ignore_immunity=%d|fallback=%d",
        issuer,
        allowLowPop ? 1 : 0,
        forced ? 1 : 0,
        totalPlayers,
        redCount,
        bluCount,
        redEligible,
        bluEligible,
        desiredSwapCount,
        swapCount,
        ignoreImmunity ? 1 : 0,
        needsFallback ? 1 : 0);

    if (swapCount == 0)
    {
        NotifySwapCountFailure(issuer, broadcastFailures, totalPlayers, redCount, bluCount, redEligible, bluEligible, "Topswap");
        return false;
    }

    if (redCount < swapCount || bluCount < swapCount)
    {
        NotifyFailure(issuer, broadcastFailures, "Each team needs at least %d players (RED=%d BLU=%d).", swapCount, redCount, bluCount);
        LogWhale("Scramble aborted: team size too small (swap=%d red=%d blu=%d).", swapCount, redCount, bluCount);
        LogWhaleStat("scramble_result", "mode=topswap|result=aborted|reason=team_size|swap=%d|red=%d|blu=%d", swapCount, redCount, bluCount);
        return false;
    }

    if (redEligible < swapCount || bluEligible < swapCount)
    {
        NotifyFailure(issuer, broadcastFailures, "Each team needs at least %d eligible players (RED=%d BLU=%d).", swapCount, redEligible, bluEligible);
        LogWhale("Scramble aborted: eligible too small (swap=%d red=%d blu=%d).", swapCount, redEligible, bluEligible);
        LogWhaleStat("scramble_result", "mode=topswap|result=aborted|reason=eligible_size|swap=%d|eligible_red=%d|eligible_blu=%d", swapCount, redEligible, bluEligible);
        return false;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(issuer > 0 ? GetClientUserId(issuer) : 0);
    pack.WriteCell(swapCount);
    pack.WriteCell(ignoreImmunity ? 1 : 0);
    pack.WriteString("topswap");
    for (int i = 0; i < swapCount; i++)
    {
        pack.WriteCell(GetClientUserId(topRed[i]));
    }
    for (int i = 0; i < swapCount; i++)
    {
        pack.WriteCell(GetClientUserId(topBlu[i]));
    }

    if (!TeamBalance_BeginScramble(forced))
    {
        delete pack;
        NotifyFailure(issuer, broadcastFailures, "Team balancing is busy; try again in a moment.");
        LogWhale("Topswap scramble aborted: authoritative team-balance state is busy.");
        return false;
    }

    if (g_bExecuteSwapImmediately)
    {
        LogWhale("Scramble executing immediately: swapCount=%d.", swapCount);
        Timer_DoSwap(null, pack);
    }
    else
    {
        CreateTimer(0.1, Timer_DoSwap, pack, TIMER_FLAG_NO_MAPCHANGE);
        LogWhale("Scramble scheduled: swapCount=%d.", swapCount);
    }
    return true;
}

static bool StartRandomWhaleScramble(int issuer, bool broadcastFailures, bool allowLowPop, bool forced)
{
    LogWhale("StartRandomWhaleScramble: issuer=%d allowLowPop=%d forced=%d.", issuer, allowLowPop ? 1 : 0, forced ? 1 : 0);
    g_iRoundsSinceAuto = 0;
    int totalPlayers = 0;
    int redCount = 0;
    int bluCount = 0;
    int redEligible = 0;
    int bluEligible = 0;
    int redCandidates[MAXPLAYERS + 1];
    int bluCandidates[MAXPLAYERS + 1];
    int redCandidateCount = 0;
    int bluCandidateCount = 0;
    int topRed[MAX_SWAP_BUFFER];
    int topBlu[MAX_SWAP_BUFFER];

    for (int i = 0; i < MAX_SWAP_BUFFER; i++)
    {
        topRed[i] = 0;
        topBlu[i] = 0;
    }

    GetScrambleTeamCounts(redCount, bluCount, totalPlayers);

    bool smallFormatGamemode = IsSmallFormatGamemode();
    bool ignoreImmunity = smallFormatGamemode || ShouldIgnoreScrambleImmunity(totalPlayers, true);
    if (ignoreImmunity)
    {
        LogWhale(
            "Random scramble: ignoring immunity due to %s total=%d threshold=%d.",
            smallFormatGamemode ? "small-format gamemode" : "low player count",
            totalPlayers,
            MAX_RANDOM_SWAP * 2);
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!TeamBalance_IsScrambleCandidate(i, 0, ignoreImmunity, g_hCountBots != null && g_hCountBots.BoolValue)) continue;
        int team = GetClientTeam(i);
        if (!IsSimpleScrambleEligibleClass(i, forced)) continue;

        if (team == TEAM_RED)
        {
            redEligible++;
            if (redCandidateCount < sizeof(redCandidates))
            {
                redCandidates[redCandidateCount++] = i;
            }
        }
        else
        {
            bluEligible++;
            if (bluCandidateCount < sizeof(bluCandidates))
            {
                bluCandidates[bluCandidateCount++] = i;
            }
        }
    }

    int desiredSwapCount = CalculateDesiredScrambleSwapCount(totalPlayers, redCount, bluCount, MAX_RANDOM_SWAP);
    int swapCount = LimitSwapCountToEligibility(desiredSwapCount, redEligible, bluEligible);
    LogWhale("Random counts: total=%d red=%d blu=%d eligibleRed=%d eligibleBlu=%d desiredSwap=%d swap=%d.", totalPlayers, redCount, bluCount, redEligible, bluEligible, desiredSwapCount, swapCount);

    bool needsFallback = (desiredSwapCount > 0 && swapCount < desiredSwapCount);
    if (needsFallback)
    {
        LogWhale("Random eligibility low; recalculating without class filters.");
        redEligible = 0;
        bluEligible = 0;
        redCandidateCount = 0;
        bluCandidateCount = 0;
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!TeamBalance_IsScrambleCandidate(i, 0, ignoreImmunity, g_hCountBots != null && g_hCountBots.BoolValue)) continue;
            int team = GetClientTeam(i);

            if (team == TEAM_RED)
            {
                redEligible++;
                if (redCandidateCount < sizeof(redCandidates))
                {
                    redCandidates[redCandidateCount++] = i;
                }
            }
            else
            {
                bluEligible++;
                if (bluCandidateCount < sizeof(bluCandidates))
                {
                    bluCandidates[bluCandidateCount++] = i;
                }
            }
        }
        swapCount = LimitSwapCountToEligibility(desiredSwapCount, redEligible, bluEligible);
    }

    LogWhaleStat("scramble_attempt", "mode=random|issuer=%d|allow_low_pop=%d|forced=%d|total=%d|red=%d|blu=%d|eligible_red=%d|eligible_blu=%d|candidate_red=%d|candidate_blu=%d|desired_swap=%d|swap=%d|ignore_immunity=%d|fallback=%d",
        issuer,
        allowLowPop ? 1 : 0,
        forced ? 1 : 0,
        totalPlayers,
        redCount,
        bluCount,
        redEligible,
        bluEligible,
        redCandidateCount,
        bluCandidateCount,
        desiredSwapCount,
        swapCount,
        ignoreImmunity ? 1 : 0,
        needsFallback ? 1 : 0);

    if (swapCount == 0)
    {
        NotifySwapCountFailure(issuer, broadcastFailures, totalPlayers, redCount, bluCount, redEligible, bluEligible, "Random");
        return false;
    }

    if (redCount < swapCount || bluCount < swapCount)
    {
        NotifyFailure(issuer, broadcastFailures, "Each team needs at least %d players (RED=%d BLU=%d).", swapCount, redCount, bluCount);
        LogWhale("Random scramble aborted: team size too small (swap=%d red=%d blu=%d).", swapCount, redCount, bluCount);
        LogWhaleStat("scramble_result", "mode=random|result=aborted|reason=team_size|swap=%d|red=%d|blu=%d", swapCount, redCount, bluCount);
        return false;
    }

    if (redEligible < swapCount || bluEligible < swapCount)
    {
        NotifyFailure(issuer, broadcastFailures, "Each team needs at least %d eligible players (RED=%d BLU=%d).", swapCount, redEligible, bluEligible);
        LogWhale("Random scramble aborted: eligible too small (swap=%d red=%d blu=%d).", swapCount, redEligible, bluEligible);
        LogWhaleStat("scramble_result", "mode=random|result=aborted|reason=eligible_size|swap=%d|eligible_red=%d|eligible_blu=%d", swapCount, redEligible, bluEligible);
        return false;
    }

    if (!SelectRandomPlayers(redCandidates, redCandidateCount, topRed, swapCount)
        || !SelectRandomPlayers(bluCandidates, bluCandidateCount, topBlu, swapCount))
    {
        NotifyFailure(issuer, broadcastFailures, "Failed to select random swap targets.");
        LogWhale("Random scramble aborted: random selection failed (swap=%d redCandidates=%d bluCandidates=%d).", swapCount, redCandidateCount, bluCandidateCount);
        LogWhaleStat("scramble_result", "mode=random|result=aborted|reason=selection_failed|swap=%d|candidate_red=%d|candidate_blu=%d", swapCount, redCandidateCount, bluCandidateCount);
        return false;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(issuer > 0 ? GetClientUserId(issuer) : 0);
    pack.WriteCell(swapCount);
    pack.WriteCell(ignoreImmunity ? 1 : 0);
    pack.WriteString("random");
    for (int i = 0; i < swapCount; i++)
    {
        pack.WriteCell(GetClientUserId(topRed[i]));
    }
    for (int i = 0; i < swapCount; i++)
    {
        pack.WriteCell(GetClientUserId(topBlu[i]));
    }

    if (!TeamBalance_BeginScramble(forced))
    {
        delete pack;
        NotifyFailure(issuer, broadcastFailures, "Team balancing is busy; try again in a moment.");
        LogWhale("Random scramble aborted: authoritative team-balance state is busy.");
        return false;
    }

    if (g_bExecuteSwapImmediately)
    {
        LogWhale("Random scramble executing immediately: swapCount=%d.", swapCount);
        Timer_DoSwap(null, pack);
    }
    else
    {
        CreateTimer(0.1, Timer_DoSwap, pack, TIMER_FLAG_NO_MAPCHANGE);
        LogWhale("Random scramble scheduled: swapCount=%d.", swapCount);
    }
    return true;
}

static bool StartFragBalanceWhaleScramble(int issuer, bool broadcastFailures, bool allowLowPop, bool forced)
{
    return StartScoreBalanceWhaleScramble(issuer, broadcastFailures, allowLowPop, forced, ScrambleScore_Frags, 0);
}

