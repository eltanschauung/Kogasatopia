public Action Timer_StartAutobalance(Handle timer)
{
    if (timer != g_hAutoBalanceTimer)
    {
        return Plugin_Stop;
    }

    g_hAutoBalanceTimer = CreateTimer(CHECK_INTERVAL, Timer_Autobalance, _, TIMER_REPEAT);
    return Plugin_Stop;
}

public Action Timer_Autobalance(Handle timer)
{
    if (ShouldSuppressAutobalanceForGamemode())
    {
        return Plugin_Continue;
    }

    TeamBalance_RefreshState();
    if (g_eTeamBalanceState != TeamBalance_Idle)
    {
        return Plugin_Continue;
    }

    int teamCounts[6];

    for (int i = 1; i <= MaxClients; i++)
    {
        // Bots occupy real team slots and therefore count toward imbalance,
        // but IsBasicBalanceCandidate() keeps them out of every target pool.
        if (!IsClientInGame(i))
        {
            continue;
        }

        int team = GetClientTeam(i);
        if (!IsGameTeam(team))
        {
            continue;
        }

        teamCounts[team]++;
    }

    // Build the list of active teams (always RED + BLU; add GREEN/YELLOW if populated).
    int activeTeams[GAME_TEAM_COUNT];
    int activeCount = 0;
    activeTeams[activeCount++] = TEAM_RED;
    activeTeams[activeCount++] = TEAM_BLUE;

    if (teamCounts[TEAM_GREEN] > 0 || teamCounts[TEAM_YELLOW] > 0)
    {
        activeTeams[activeCount++] = TEAM_GREEN;
        activeTeams[activeCount++] = TEAM_YELLOW;
    }

    // Sort active teams by count descending (simple insertion sort; max 4 elements).
    int sortedTeams[GAME_TEAM_COUNT];
    int sortedCounts[GAME_TEAM_COUNT];
    for (int i = 0; i < activeCount; i++)
    {
        sortedTeams[i]  = activeTeams[i];
        sortedCounts[i] = teamCounts[activeTeams[i]];
    }

    for (int i = 1; i < activeCount; i++)
    {
        int keyTeam  = sortedTeams[i];
        int keyCount = sortedCounts[i];
        int j = i - 1;
        while (j >= 0 && sortedCounts[j] < keyCount)
        {
            sortedTeams[j + 1]  = sortedTeams[j];
            sortedCounts[j + 1] = sortedCounts[j];
            j--;
        }
        sortedTeams[j + 1]  = keyTeam;
        sortedCounts[j + 1] = keyCount;
    }

    int biggestTeam   = sortedTeams[0];
    int biggestCount  = sortedCounts[0];
    int smallestTeam  = sortedTeams[activeCount - 1];
    int smallestCount = sortedCounts[activeCount - 1];

    if (biggestTeam == 0 || smallestTeam == 0 || biggestTeam == smallestTeam)
    {
        return Plugin_Continue;
    }

    int diff = biggestCount - smallestCount;
    int diffThreshold = 1;
    if (g_hDiffThreshold != null)
    {
        diffThreshold = g_hDiffThreshold.IntValue;
        if (diffThreshold < 1) diffThreshold = 1;
    }

    if (diff <= diffThreshold)
    {
        g_fImbalanceDetectedAt = 0.0;
        return Plugin_Continue;
    }

    float now = GetEngineTime();
    if (g_fImbalanceDetectedAt <= 0.0)
    {
        g_fImbalanceDetectedAt = now;
    }

    float imbalanceAge = now - g_fImbalanceDetectedAt;
    float actionDelay = (g_hActionDelay != null) ? g_hActionDelay.FloatValue : 0.0;
    float maxUnbalanceTime = (g_hMaxUnbalanceTime != null) ? g_hMaxUnbalanceTime.FloatValue : 0.0;
    int forceThresholdDelta = (g_hForceThresholdDelta != null) ? g_hForceThresholdDelta.IntValue : 1;
    if (forceThresholdDelta < 0)
    {
        forceThresholdDelta = 0;
    }

    bool forceByThreshold = diff >= (diffThreshold + forceThresholdDelta);
    bool forceByTime = maxUnbalanceTime > 0.0 && imbalanceAge >= maxUnbalanceTime;
    bool forceBalance = forceByThreshold || forceByTime;
    if (!forceBalance && imbalanceAge < actionDelay)
    {
        if (IsBalanceLoggingEnabled())
        {
            LogBalance(
                "Delay balance: diff=%d threshold=%d age=%.1f actionDelay=%.1f forceThreshold=%d maxTime=%.1f",
                diff, diffThreshold, imbalanceAge, actionDelay, diffThreshold + forceThresholdDelta, maxUnbalanceTime
            );
        }
        return Plugin_Continue;
    }

    bool loggingEnabled = IsBalanceLoggingEnabled();
    bool clanProtectionAvailable = (GetFeatureStatus(FeatureType_Native, "Clans_GetSameTeamClanMemberCount") == FeatureStatus_Available);

    char fromTeamName[16];
    char toTeamName[16];
    AB_GetTeamName(biggestTeam,  fromTeamName, sizeof(fromTeamName));
    AB_GetTeamName(smallestTeam, toTeamName,   sizeof(toTeamName));
    char fromTeamChat[24];
    char toTeamChat[24];
    AB_GetTeamChatLabel(biggestTeam,  fromTeamChat, sizeof(fromTeamChat));
    AB_GetTeamChatLabel(smallestTeam, toTeamChat,   sizeof(toTeamChat));

    if (ShouldSkipWinningTeamAutobalance(biggestTeam, smallestTeam, diff))
    {
        if (loggingEnabled)
        {
            LogBalance(
                "Skip balance from %s to %s: sm_autobalance_ignore_winning=%.2f blocked losing-to-winning move at diff=%d",
                fromTeamName, toTeamName, g_hIgnoreWinning.FloatValue, diff
            );
        }
        return Plugin_Continue;
    }

    if (loggingEnabled)
    {
        LogBalance(
            "Imbalance: RED=%d BLU=%d GREEN=%d YELLOW=%d | from=%s(%d) to=%s(%d) force=%s age=%.1f",
            teamCounts[TEAM_RED], teamCounts[TEAM_BLUE], teamCounts[TEAM_GREEN], teamCounts[TEAM_YELLOW],
            fromTeamName, biggestCount, toTeamName, smallestCount,
            forceBalance ? "yes" : "no",
            imbalanceAge
        );
    }
    PrintToServer(
        "[whalebalance] Imbalance: RED=%d BLU=%d GREEN=%d YELLOW=%d | from=%s(%d) to=%s(%d) force=%s age=%.1f",
        teamCounts[TEAM_RED], teamCounts[TEAM_BLUE], teamCounts[TEAM_GREEN], teamCounts[TEAM_YELLOW],
        fromTeamName, biggestCount, toTeamName, smallestCount,
        forceBalance ? "yes" : "no",
        imbalanceAge
    );

    // ------------------------------------------------------------------
    // Candidate selection.
    //
    // Volunteer selection runs before normal candidate filters. Volunteers
    // intentionally bypass autobalance immunity, but still keep Engineer
    // and medic uber protection.
    //
    // By this point diff > threshold, so the balance is always forced.
    // Simple selection uses one scan and picks the most recent eligible
    // player by priority. Weighted selection scans once, then rolls among
    // all eligible candidates with a bias toward lower scores.
    // ------------------------------------------------------------------

    if (!TeamBalance_TryBegin(TeamBalance_Autobalance, TEAM_BALANCE_OPERATION_LEASE, true))
    {
        return Plugin_Continue;
    }

    int totalScore   = 0;
    int totalPlayers = 0;
    float avg = 0.0;
    int pick = 0;
    int candidateCount = 0;
    bool simpleSelection = (g_hSimpleSelection != null && g_hSimpleSelection.BoolValue);
    bool volunteerSelection = false;

    int volunteerNonMedicCount = 0;
    int volunteerMedicCount = 0;
    if (HasCachedVolunteers())
    {
        pick = SelectVolunteerPlayer(biggestTeam, volunteerNonMedicCount, volunteerMedicCount);
    }
    if (pick > 0)
    {
        volunteerSelection = true;
        candidateCount = (volunteerNonMedicCount > 0) ? volunteerNonMedicCount : volunteerMedicCount;

        if (loggingEnabled)
        {
            LogBalance(
                "Volunteer priority on %s: picked %N from %d non-medic and %d medic volunteer candidates",
                fromTeamName, pick, volunteerNonMedicCount, volunteerMedicCount
            );
        }
    }
    else if (simpleSelection)
    {
        pick = SelectPreferredRecentPlayer(biggestTeam, clanProtectionAvailable);
        candidateCount = (pick > 0) ? 1 : 0;
        if (pick <= 0)
        {
            if (loggingEnabled)
            {
                LogBalance("Skip balance on %s: simple selection found no eligible candidates", fromTeamName);
            }
            TeamBalance_FinishOperation(false);
            return Plugin_Continue;
        }
    }
    else
    {
        int candidates[MAXPLAYERS];

        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsEligiblePlayer(i, biggestTeam, clanProtectionAvailable))
            {
                continue;
            }

            totalScore += GetClientScore(i);
            totalPlayers++;
            candidates[candidateCount++] = i;
        }

        if (totalPlayers == 0)
        {
            if (loggingEnabled)
            {
                int immuneCount = 0;
                for (int i = 1; i <= MaxClients; i++)
                {
                    if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) != biggestTeam) continue;
                    if (IsClientImmune(i)) immuneCount++;
                }

                LogBalance(
                    "Skip balance on %s: no eligible players (teamPlayers=%d, immune=%d)",
                    fromTeamName, biggestCount, immuneCount
                );
            }

            TeamBalance_FinishOperation(false);
            return Plugin_Continue;
        }

        avg = float(totalScore) / float(totalPlayers);

        // Weight selection toward lowest-scoring candidates.
        // Build a cumulative-weight array where each candidate's weight is
        // (maxScore - score + 1) so the lowest scorer is most likely.
        int maxScore = 0;
        for (int i = 0; i < candidateCount; i++)
        {
            int s = GetClientScore(candidates[i]);
            if (s > maxScore) maxScore = s;
        }

        int weights[MAXPLAYERS];
        int totalWeight = 0;
        for (int i = 0; i < candidateCount; i++)
        {
            weights[i]   = maxScore - GetClientScore(candidates[i]) + 1;
            totalWeight += weights[i];
        }

        int roll = GetRandomInt(0, totalWeight - 1);
        pick = candidates[0];
        int running = 0;
        for (int i = 0; i < candidateCount; i++)
        {
            running += weights[i];
            if (roll < running)
            {
                pick = candidates[i];
                break;
            }
        }
    }

    if (!ResolveAutobalancePurchaseImmunity(pick, biggestTeam, clanProtectionAvailable, loggingEnabled))
    {
        TeamBalance_FinishOperation(false);
        return Plugin_Continue;
    }

    if (DuelDetection_IsClientInDuel(pick))
    {
        if (loggingEnabled)
        {
            LogBalance("Skip balance on %N: client entered a duel before move", pick);
        }
        TeamBalance_FinishOperation(false);
        return Plugin_Continue;
    }

    if (loggingEnabled)
    {
        LogBalance(
            "Autobalancing %N (%d) from %s to %s. score=%d avg=%.2f candidates=%d simple=%d volunteer=%d",
            pick, GetClientUserId(pick),
            fromTeamName, toTeamName,
            GetClientScore(pick), avg, candidateCount, simpleSelection ? 1 : 0, volunteerSelection ? 1 : 0
        );
    }
    PrintToServer(
        "[whalebalance] move %N (%d) %s -> %s | score=%d avg=%.2f candidates=%d simple=%d volunteer=%d",
        pick, GetClientUserId(pick),
        fromTeamName, toTeamName,
        GetClientScore(pick), avg, candidateCount, simpleSelection ? 1 : 0, volunteerSelection ? 1 : 0
    );

    if (GetFeatureStatus(FeatureType_Native, "FilterAlerts_MarkAutobalance") == FeatureStatus_Available)
    {
        FilterAlerts_MarkAutobalance(pick);
    }

    if (!TeamBalance_MoveAutobalanceClient(pick, biggestTeam, smallestTeam))
    {
        TeamBalance_FinishOperation(false);
        if (loggingEnabled)
        {
            LogBalance("Skip balance on %N: candidate became invalid before the authoritative move", pick);
        }
        return Plugin_Continue;
    }
    if (volunteerSelection && GetFeatureStatus(FeatureType_Native, "PointsStore_ApplyBonusPoints") == FeatureStatus_Available)
    {
        PointsStore_ApplyBonusPoints(pick, "autobalance_volunteer", true, true, 1.0, 0, 0.0);
    }
    g_fImbalanceDetectedAt = 0.0;
    SaySounds_TryPlayCommand(0, TEAM_MOVE_SAYSOUND, true);

    CPrintToChatAllEx(
        pick,
        "{tomato}[{purple}Gap{tomato}]{default} Sending {teamcolor}%N{default} from %s to %s",
        pick, fromTeamChat, toTeamChat
    );

    char teamColorName[24];
    AB_GetTeamColorName(smallestTeam, teamColorName, sizeof(teamColorName));
    CPrintToChatEx(pick, pick, "{lightgreen}[Server]{default} You've been autobalanced to %s{default}!", teamColorName);

    return Plugin_Continue;
}

