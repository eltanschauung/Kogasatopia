bool StartWhaleRankBalanceScramble(int issuer, bool broadcastFailures, bool allowLowPop, bool forced, int favoredTeam)
{
    if (GetFeatureStatus(FeatureType_Native, "WhaleTracker_AreStatsLoaded") != FeatureStatus_Available
        || GetFeatureStatus(FeatureType_Native, "WhaleTracker_GetWhalePoints") != FeatureStatus_Available)
    {
        NotifyFailure(issuer, broadcastFailures, "WhaleTracker rank data is unavailable.");
        LogWhaleStat("scramble_result", "mode=whaletracker_rank|result=aborted|reason=native_unavailable");
        return false;
    }

    return StartScoreBalanceWhaleScramble(issuer, broadcastFailures, allowLowPop, forced, ScrambleScore_WhaleRank, favoredTeam);
}

static int GetScrambleBalanceScore(int client, ScrambleScoreKind scoreKind)
{
    if (scoreKind == ScrambleScore_Frags)
    {
        return GetClientFrags(client);
    }

    if (IsFakeClient(client) || !WhaleTracker_AreStatsLoaded(client))
    {
        return 0;
    }

    return WhaleTracker_GetWhalePoints(client);
}

bool StartScoreBalanceWhaleScramble(int issuer, bool broadcastFailures, bool allowLowPop, bool forced, ScrambleScoreKind scoreKind, int favoredTeam)
{
    char modeKey[32];
    char modeLabel[32];
    if (scoreKind == ScrambleScore_WhaleRank)
    {
        strcopy(modeKey, sizeof(modeKey), "whaletracker_rank");
        strcopy(modeLabel, sizeof(modeLabel), "WhaleTracker rank");
    }
    else
    {
        strcopy(modeKey, sizeof(modeKey), "frag_balance");
        strcopy(modeLabel, sizeof(modeLabel), "Frag balance");
    }

    LogWhale("StartScoreBalanceWhaleScramble: mode=%s issuer=%d allowLowPop=%d forced=%d favoredTeam=%d.", modeKey, issuer, allowLowPop ? 1 : 0, forced ? 1 : 0, favoredTeam);
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
    int clientScores[MAXPLAYERS + 1];
    int redScoreTotal = 0;
    int bluScoreTotal = 0;
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
            "%s scramble: ignoring immunity due to %s total=%d threshold=%d.",
            modeLabel,
            smallFormatGamemode ? "small-format gamemode" : "low player count",
            totalPlayers,
            MAX_RANDOM_SWAP * 2);
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        // Score accounting includes recently moved/immune players because they
        // still contribute to their team's total; the controller filters the
        // actual candidate pool below.
        if (!IsClientInGame(i)
            || (IsFakeClient(i) && (g_hCountBots == null || !g_hCountBots.BoolValue))
            || DuelDetection_IsClientInDuel(i))
            continue;
        int team = GetClientTeam(i);
        if (team != TEAM_RED && team != TEAM_BLU)
            continue;

        int score = GetScrambleBalanceScore(i, scoreKind);
        clientScores[i] = score;
        if (team == TEAM_RED)
        {
            redScoreTotal += score;
        }
        else
        {
            bluScoreTotal += score;
        }

        if (!TeamBalance_IsScrambleCandidate(i, team, ignoreImmunity, g_hCountBots != null && g_hCountBots.BoolValue))
            continue;
        if (scoreKind == ScrambleScore_WhaleRank && IsWhaleRankBalanceIgnoredClass(i))
            continue;
        if (!IsSimpleScrambleEligibleClass(i, forced))
            continue;

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
    LogWhale(
        "%s counts: total=%d red=%d blu=%d eligibleRed=%d eligibleBlu=%d desiredSwap=%d swap=%d redScore=%d bluScore=%d.",
        modeLabel,
        totalPlayers,
        redCount,
        bluCount,
        redEligible,
        bluEligible,
        desiredSwapCount,
        swapCount,
        redScoreTotal,
        bluScoreTotal);

    bool needsFallback = (desiredSwapCount > 0 && swapCount < desiredSwapCount);
    if (needsFallback)
    {
        LogWhale("%s eligibility low; recalculating without class filters.", modeLabel);
        redEligible = 0;
        bluEligible = 0;
        redCandidateCount = 0;
        bluCandidateCount = 0;

        for (int i = 1; i <= MaxClients; i++)
        {
            if (!TeamBalance_IsScrambleCandidate(i, 0, ignoreImmunity, g_hCountBots != null && g_hCountBots.BoolValue))
                continue;
            int team = GetClientTeam(i);
            if (scoreKind == ScrambleScore_WhaleRank && IsWhaleRankBalanceIgnoredClass(i))
                continue;

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

    LogWhaleStat("scramble_attempt", "mode=%s|issuer=%d|allow_low_pop=%d|forced=%d|total=%d|red=%d|blu=%d|eligible_red=%d|eligible_blu=%d|candidate_red=%d|candidate_blu=%d|desired_swap=%d|swap=%d|ignore_immunity=%d|fallback=%d|red_score=%d|blu_score=%d|favored_team=%d",
        modeKey,
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
        needsFallback ? 1 : 0,
        redScoreTotal,
        bluScoreTotal,
        favoredTeam);

    if (swapCount == 0)
    {
        NotifySwapCountFailure(issuer, broadcastFailures, totalPlayers, redCount, bluCount, redEligible, bluEligible, modeLabel);
        return false;
    }

    if (redCount < swapCount || bluCount < swapCount)
    {
        NotifyFailure(issuer, broadcastFailures, "Each team needs at least %d players (RED=%d BLU=%d).", swapCount, redCount, bluCount);
        LogWhale("%s scramble aborted: team size too small (swap=%d red=%d blu=%d).", modeLabel, swapCount, redCount, bluCount);
        LogWhaleStat("scramble_result", "mode=%s|result=aborted|reason=team_size|swap=%d|red=%d|blu=%d", modeKey, swapCount, redCount, bluCount);
        return false;
    }

    if (redEligible < swapCount || bluEligible < swapCount)
    {
        NotifyFailure(issuer, broadcastFailures, "Each team needs at least %d eligible players (RED=%d BLU=%d).", swapCount, redEligible, bluEligible);
        LogWhale("%s scramble aborted: eligible too small (swap=%d red=%d blu=%d).", modeLabel, swapCount, redEligible, bluEligible);
        LogWhaleStat("scramble_result", "mode=%s|result=aborted|reason=eligible_size|swap=%d|eligible_red=%d|eligible_blu=%d", modeKey, swapCount, redEligible, bluEligible);
        return false;
    }

    if (!SelectScoreBalancePlayers(redCandidates, bluCandidates, clientScores, redCandidateCount, bluCandidateCount, redScoreTotal, bluScoreTotal, topRed, topBlu, swapCount, favoredTeam))
    {
        NotifyFailure(issuer, broadcastFailures, "Failed to select %s swap targets.", modeLabel);
        LogWhale("%s scramble aborted: selection failed (swap=%d redCandidates=%d bluCandidates=%d redScore=%d bluScore=%d).", modeLabel, swapCount, redCandidateCount, bluCandidateCount, redScoreTotal, bluScoreTotal);
        LogWhaleStat("scramble_result", "mode=%s|result=aborted|reason=selection_failed|swap=%d|candidate_red=%d|candidate_blu=%d|red_score=%d|blu_score=%d", modeKey, swapCount, redCandidateCount, bluCandidateCount, redScoreTotal, bluScoreTotal);
        return false;
    }

    int selectedRedScore = 0;
    int selectedBluScore = 0;
    for (int i = 0; i < swapCount; i++)
    {
        selectedRedScore += clientScores[topRed[i]];
        selectedBluScore += clientScores[topBlu[i]];
    }

    int finalRedScore = redScoreTotal - selectedRedScore + selectedBluScore;
    int finalBluScore = bluScoreTotal - selectedBluScore + selectedRedScore;
    int beforeDiff = GetScoreBalanceDifference(redScoreTotal, bluScoreTotal, favoredTeam);
    int afterDiff = GetScoreBalanceDifference(finalRedScore, finalBluScore, favoredTeam);
    LogWhale(
        "%s selected: swap=%d redScore=%d bluScore=%d selectedRedScore=%d selectedBluScore=%d beforeDiff=%d afterDiff=%d.",
        modeLabel,
        swapCount,
        redScoreTotal,
        bluScoreTotal,
        selectedRedScore,
        selectedBluScore,
        beforeDiff,
        afterDiff);
    LogWhaleStat("scramble_result", "mode=%s|result=selected|swap=%d|red_score=%d|blu_score=%d|selected_red_score=%d|selected_blu_score=%d|before_diff=%d|after_diff=%d|favored_team=%d",
        modeKey,
        swapCount,
        redScoreTotal,
        bluScoreTotal,
        selectedRedScore,
        selectedBluScore,
        beforeDiff,
        afterDiff,
        favoredTeam);

    DataPack pack = new DataPack();
    pack.WriteCell(issuer > 0 ? GetClientUserId(issuer) : 0);
    pack.WriteCell(swapCount);
    pack.WriteCell(ignoreImmunity ? 1 : 0);
    pack.WriteString(modeKey);
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
        LogWhale("%s scramble aborted: authoritative team-balance state is busy.", modeLabel);
        return false;
    }

    if (g_bExecuteSwapImmediately)
    {
        LogWhale("%s scramble executing immediately: swapCount=%d.", modeLabel, swapCount);
        Timer_DoSwap(null, pack);
    }
    else
    {
        CreateTimer(0.1, Timer_DoSwap, pack, TIMER_FLAG_NO_MAPCHANGE);
        LogWhale("%s scramble scheduled: swapCount=%d.", modeLabel, swapCount);
    }

    return true;
}

static bool SelectScoreBalancePlayers(
    int redCandidates[MAXPLAYERS + 1],
    int bluCandidates[MAXPLAYERS + 1],
    int clientScores[MAXPLAYERS + 1],
    int redCandidateCount,
    int bluCandidateCount,
    int redScoreTotal,
    int bluScoreTotal,
    int selectedRed[MAX_SWAP_BUFFER],
    int selectedBlu[MAX_SWAP_BUFFER],
    int selectedCount,
    int favoredTeam)
{
    if (selectedCount <= 0 || selectedCount > MAX_SWAP_BUFFER || redCandidateCount < selectedCount || bluCandidateCount < selectedCount)
    {
        return false;
    }

    ArrayList bluSubsets = new ArrayList(SCORE_BALANCE_ENTRY_CELLS);
    int chosenBlu[MAX_SWAP_BUFFER];
    AddScoreBalanceSubsetsRecursive(bluCandidates, clientScores, bluCandidateCount, selectedCount, 0, 0, 0, chosenBlu, bluSubsets);
    if (bluSubsets.Length <= 0)
    {
        delete bluSubsets;
        return false;
    }

    bluSubsets.SortCustom(SortScoreBalanceSubsetBySum);

    int chosenRed[MAX_SWAP_BUFFER];
    int bestFinalDiff = 0;
    bool found = false;
    int redMultiplier;
    int bluMultiplier;
    GetScoreBalanceMultipliers(favoredTeam, redMultiplier, bluMultiplier);
    int swapMultiplier = redMultiplier + bluMultiplier;
    EvaluateScoreBalanceRedSubsetsRecursive(
        redCandidates,
        clientScores,
        redCandidateCount,
        selectedCount,
        0,
        0,
        0,
        chosenRed,
        bluSubsets,
        (redMultiplier * redScoreTotal) - (bluMultiplier * bluScoreTotal),
        swapMultiplier,
        selectedRed,
        selectedBlu,
        bestFinalDiff,
        found);

    delete bluSubsets;
    return found;
}

static void AddScoreBalanceSubsetsRecursive(
    int candidates[MAXPLAYERS + 1],
    int clientScores[MAXPLAYERS + 1],
    int candidateCount,
    int selectedCount,
    int start,
    int chosenCount,
    int currentSum,
    int chosen[MAX_SWAP_BUFFER],
    ArrayList subsets)
{
    if (chosenCount == selectedCount)
    {
        int entry[SCORE_BALANCE_ENTRY_CELLS];
        entry[SCORE_BALANCE_ENTRY_SUM] = currentSum;
        for (int i = 0; i < MAX_SWAP_BUFFER; i++)
        {
            entry[SCORE_BALANCE_ENTRY_CLIENT0 + i] = (i < selectedCount) ? chosen[i] : 0;
        }
        subsets.PushArray(entry, sizeof(entry));
        return;
    }

    int remainingNeeded = selectedCount - chosenCount;
    for (int i = start; i <= candidateCount - remainingNeeded; i++)
    {
        int client = candidates[i];
        chosen[chosenCount] = client;
        AddScoreBalanceSubsetsRecursive(candidates, clientScores, candidateCount, selectedCount, i + 1, chosenCount + 1, currentSum + clientScores[client], chosen, subsets);
    }
}

static void EvaluateScoreBalanceRedSubsetsRecursive(
    int redCandidates[MAXPLAYERS + 1],
    int clientScores[MAXPLAYERS + 1],
    int redCandidateCount,
    int selectedCount,
    int start,
    int chosenCount,
    int currentRedScore,
    int chosenRed[MAX_SWAP_BUFFER],
    ArrayList bluSubsets,
    int teamScoreDelta,
    int swapMultiplier,
    int selectedRed[MAX_SWAP_BUFFER],
    int selectedBlu[MAX_SWAP_BUFFER],
    int &bestFinalDiff,
    bool &found)
{
    if (chosenCount == selectedCount)
    {
        int targetScaled = (swapMultiplier * currentRedScore) - teamScoreDelta;
        int index = FindFirstScoreBalanceSubsetAtLeastScaled(bluSubsets, targetScaled, swapMultiplier);
        TryScoreBalanceCandidate(bluSubsets, index, selectedCount, currentRedScore, chosenRed, teamScoreDelta, swapMultiplier, selectedRed, selectedBlu, bestFinalDiff, found);
        TryScoreBalanceCandidate(bluSubsets, index - 1, selectedCount, currentRedScore, chosenRed, teamScoreDelta, swapMultiplier, selectedRed, selectedBlu, bestFinalDiff, found);
        return;
    }

    int remainingNeeded = selectedCount - chosenCount;
    for (int i = start; i <= redCandidateCount - remainingNeeded; i++)
    {
        int client = redCandidates[i];
        chosenRed[chosenCount] = client;
        EvaluateScoreBalanceRedSubsetsRecursive(
            redCandidates,
            clientScores,
            redCandidateCount,
            selectedCount,
            i + 1,
            chosenCount + 1,
            currentRedScore + clientScores[client],
            chosenRed,
            bluSubsets,
            teamScoreDelta,
            swapMultiplier,
            selectedRed,
            selectedBlu,
            bestFinalDiff,
            found);
    }
}

static void TryScoreBalanceCandidate(
    ArrayList bluSubsets,
    int index,
    int selectedCount,
    int currentRedScore,
    int chosenRed[MAX_SWAP_BUFFER],
    int teamScoreDelta,
    int swapMultiplier,
    int selectedRed[MAX_SWAP_BUFFER],
    int selectedBlu[MAX_SWAP_BUFFER],
    int &bestFinalDiff,
    bool &found)
{
    if (index < 0 || index >= bluSubsets.Length)
    {
        return;
    }

    int entry[SCORE_BALANCE_ENTRY_CELLS];
    bluSubsets.GetArray(index, entry, sizeof(entry));

    int finalDiff = ScoreBalanceAbs(teamScoreDelta - (swapMultiplier * currentRedScore) + (swapMultiplier * entry[SCORE_BALANCE_ENTRY_SUM]));
    if (found && finalDiff >= bestFinalDiff)
    {
        return;
    }

    for (int i = 0; i < MAX_SWAP_BUFFER; i++)
    {
        selectedRed[i] = (i < selectedCount) ? chosenRed[i] : 0;
        selectedBlu[i] = (i < selectedCount) ? entry[SCORE_BALANCE_ENTRY_CLIENT0 + i] : 0;
    }

    bestFinalDiff = finalDiff;
    found = true;
}

static int FindFirstScoreBalanceSubsetAtLeastScaled(ArrayList subsets, int targetScaled, int multiplier)
{
    int low = 0;
    int high = subsets.Length;
    int entry[SCORE_BALANCE_ENTRY_CELLS];

    while (low < high)
    {
        int mid = (low + high) / 2;
        subsets.GetArray(mid, entry, sizeof(entry));
        if ((multiplier * entry[SCORE_BALANCE_ENTRY_SUM]) < targetScaled)
        {
            low = mid + 1;
        }
        else
        {
            high = mid;
        }
    }

    return low;
}

static int SortScoreBalanceSubsetBySum(int index1, int index2, Handle array, Handle hndl)
{
    ArrayList subsets = view_as<ArrayList>(array);
    int entry1[SCORE_BALANCE_ENTRY_CELLS];
    int entry2[SCORE_BALANCE_ENTRY_CELLS];
    subsets.GetArray(index1, entry1, sizeof(entry1));
    subsets.GetArray(index2, entry2, sizeof(entry2));

    if (entry1[SCORE_BALANCE_ENTRY_SUM] < entry2[SCORE_BALANCE_ENTRY_SUM])
    {
        return -1;
    }
    if (entry1[SCORE_BALANCE_ENTRY_SUM] > entry2[SCORE_BALANCE_ENTRY_SUM])
    {
        return 1;
    }
    return 0;
}

static int ScoreBalanceAbs(int value)
{
    return value < 0 ? -value : value;
}

static void GetScoreBalanceMultipliers(int favoredTeam, int &redMultiplier, int &bluMultiplier)
{
    // A 60:40 target is equivalent to 2 * favored score == 3 * other score.
    redMultiplier = 1;
    bluMultiplier = 1;
    if (favoredTeam == TEAM_RED)
    {
        redMultiplier = 2;
        bluMultiplier = 3;
    }
    else if (favoredTeam == TEAM_BLU)
    {
        redMultiplier = 3;
        bluMultiplier = 2;
    }
}

static int GetScoreBalanceDifference(int redScore, int bluScore, int favoredTeam)
{
    int redMultiplier;
    int bluMultiplier;
    GetScoreBalanceMultipliers(favoredTeam, redMultiplier, bluMultiplier);
    return ScoreBalanceAbs((redMultiplier * redScore) - (bluMultiplier * bluScore));
}

