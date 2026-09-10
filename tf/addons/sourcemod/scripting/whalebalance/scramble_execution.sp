public Action Timer_DoSwap(Handle timer, DataPack pack)
{
    pack.Reset();
    int issuerUserId = pack.ReadCell();
    int swapCount = pack.ReadCell();
    bool ignoreImmunity = view_as<bool>(pack.ReadCell());
    char scrambleMode[32];
    pack.ReadString(scrambleMode, sizeof(scrambleMode));

    int redIds[MAX_SWAP_BUFFER];
    int bluIds[MAX_SWAP_BUFFER];

    for (int i = 0; i < swapCount; i++)
    {
        redIds[i] = pack.ReadCell();
    }
    for (int i = 0; i < swapCount; i++)
    {
        bluIds[i] = pack.ReadCell();
    }

    delete pack;

    bool suppressRespawn = g_bSuppressSwapRespawn;
    bool setupScramble = IsSetupActive();
    if (GetFeatureStatus(FeatureType_Native, "FilterAlerts_SuppressTeamAlertWindow") == FeatureStatus_Available)
    {
        FilterAlerts_SuppressTeamAlertWindow(2.0);
    }

    int moved = 0;
    int pairR[MAX_SWAP_BUFFER];
    int pairB[MAX_SWAP_BUFFER];
    int pairCount = 0;
    bool allowBots = g_hCountBots != null && g_hCountBots.BoolValue;
    for (int i = 0; i < swapCount; i++)
    {
        int r = GetClientOfUserId(redIds[i]);
        int b = GetClientOfUserId(bluIds[i]);

        if (r <= 0 || b <= 0) continue;
        if (!IsClientInGame(r) || !IsClientInGame(b)) continue;
        if (GetClientTeam(r) != TEAM_RED || GetClientTeam(b) != TEAM_BLU) continue;
        if (DuelDetection_IsClientInDuel(r) || DuelDetection_IsClientInDuel(b))
        {
            LogWhale("Skipping scramble pair: duel active before immunity pass (red=%N blu=%N).", r, b);
            LogWhaleStat("immunity_skip", "type=duel|phase=before_immunity|mode=%s", scrambleMode);
            continue;
        }
        if (!ResolveScramblePurchaseImmunity(r, TEAM_RED, redIds, bluIds, swapCount, i, ignoreImmunity)) continue;
        if (!ResolveScramblePurchaseImmunity(b, TEAM_BLU, redIds, bluIds, swapCount, i, ignoreImmunity)) continue;
        if (GetClientTeam(r) != TEAM_RED || GetClientTeam(b) != TEAM_BLU) continue;
        if (DuelDetection_IsClientInDuel(r) || DuelDetection_IsClientInDuel(b))
        {
            LogWhale("Skipping scramble pair: duel active after immunity pass (red=%N blu=%N).", r, b);
            LogWhaleStat("immunity_skip", "type=duel|phase=after_immunity|mode=%s", scrambleMode);
            continue;
        }

        if (!TeamBalance_MoveScramblePair(r, b, ignoreImmunity, allowBots, suppressRespawn))
        {
            LogWhale("Skipping scramble pair: authoritative validation rejected red=%N blu=%N.", r, b);
            LogWhaleStat("scramble_pair", "result=rejected|reason=controller_validation|mode=%s", scrambleMode);
            continue;
        }

        if (pairCount < MAX_SWAP_BUFFER)
        {
            pairR[pairCount] = r;
            pairB[pairCount] = b;
            pairCount++;
        }
    }

    moved = pairCount * 2;
    if (moved > 0)
    {
        TeamBalance_FinishScramble(true);
        g_bScrambledThisRound = true;
        ResetSurrenderVotes("whalescramble_execute");
        CPrintToChatAll("{tomato}[{purple}Gap{tomato}]{default} {gold}Whalescrambling{default} %d players!", moved);
        SaySounds_TryPlayCommand(0, TEAM_MOVE_SAYSOUND, true);
        LogWhale("Scramble executed: moved=%d pairs=%d suppressRespawn=%d.", moved, pairCount, suppressRespawn ? 1 : 0);
        LogWhaleStat("scramble_result", "mode=%s|result=executed|moved=%d|pairs=%d|suppress_respawn=%d|setup=%d|ignore_immunity=%d", scrambleMode, moved, pairCount, suppressRespawn ? 1 : 0, setupScramble ? 1 : 0, ignoreImmunity ? 1 : 0);
        if (suppressRespawn)
        {
            QueuePostAutoScrambleRespawnSweep();
        }
        if (setupScramble)
        {
            ApplySetupScramblePolish();
        }
        for (int i = 0; i < pairCount; i++)
        {
            int r = pairR[i];
            int b = pairB[i];

            char nameR[256];
            char nameB[256];
            bool hasFilterR = GetFiltersNameOrEmpty(r, nameR, sizeof(nameR));
            bool hasFilterB = GetFiltersNameOrEmpty(b, nameB, sizeof(nameB));

            int srcClient = r;
            bool useTeamColorR = false;
            bool useTeamColorB = false;

            if (!hasFilterR && !hasFilterB)
            {
                srcClient = r;
                useTeamColorR = true;
            }
            else if (!hasFilterR)
            {
                srcClient = r;
                useTeamColorR = true;
            }
            else if (!hasFilterB)
            {
                srcClient = b;
                useTeamColorB = true;
            }

            if (!hasFilterR)
            {
                BuildFallbackName(r, useTeamColorR, nameR, sizeof(nameR));
            }
            if (!hasFilterB)
            {
                BuildFallbackName(b, useTeamColorB, nameB, sizeof(nameB));
            }

            CPrintToChatAllEx(srcClient, "%s <-> %s", nameR, nameB);
            LogWhale("Pair %d: %N <-> %N.", i + 1, r, b);
        }

        for (int i = 0; i < pairCount; i++)
        {
            int r = pairR[i];
            int b = pairB[i];
            if (r > 0 && IsClientInGame(r))
            {
                PrintCenterText(r, "You have been scrambled!");
            }
            if (b > 0 && IsClientInGame(b))
            {
                PrintCenterText(b, "You have been scrambled!");
            }
        }
    }
    else
    {
        TeamBalance_FinishScramble(false);
        int issuer = GetClientOfUserId(issuerUserId);
        if (issuer > 0 && IsClientInGame(issuer))
        {
            ReplyToCommand(issuer, "[whalescramble] No eligible players to swap.");
        }
        LogWhale("Scramble executed: no eligible pairs.");
        LogWhaleStat("scramble_result", "mode=%s|result=aborted|reason=no_eligible_pairs|swap=%d|ignore_immunity=%d", scrambleMode, swapCount, ignoreImmunity ? 1 : 0);
    }
    return Plugin_Stop;
}

static bool IsSetupActive()
{
    if (GetFeatureStatus(FeatureType_Native, "DGM_IsSetupActive") != FeatureStatus_Available)
    {
        LogWhale("Setup scramble polish skipped: DGM_IsSetupActive unavailable.");
        return false;
    }

    return DGM_IsSetupActive();
}

static void ApplySetupScramblePolish()
{
    RestoreSetupTimerAfterScramble();
    CreateTimer(SCRAMBLE_SETUP_POLISH_DELAY, Timer_ApplySetupScramblePolish, 0, TIMER_FLAG_NO_MAPCHANGE);
    LogWhale("Setup scramble polish: queued delayed respawn verification.");
    LogWhaleStat("respawn_recovery", "context=setup_polish|result=queued");
}

public Action Timer_ApplySetupScramblePolish(Handle timer, any data)
{
    QueueScrambleRespawnsForActiveTeams("setup polish");
    CreateTimer(SCRAMBLE_SETUP_UBER_DELAY, Timer_FillSetupMedicUbers, 0, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

static void QueuePostAutoScrambleRespawnSweep()
{
    CreateTimer(SCRAMBLE_AUTO_RESPAWN_SWEEP_DELAY, Timer_PostAutoScrambleRespawnSweep, SCRAMBLE_AUTO_RESPAWN_SWEEP_COUNT, TIMER_FLAG_NO_MAPCHANGE);
    LogWhale("Post-auto scramble respawn sweep queued.");
    LogWhaleStat("respawn_recovery", "context=post_auto_sweep|result=queued|sweeps=%d", SCRAMBLE_AUTO_RESPAWN_SWEEP_COUNT);
}

public Action Timer_PostAutoScrambleRespawnSweep(Handle timer, any remainingSweeps)
{
    QueueScrambleRespawnsForActiveTeams("post-auto sweep");

    int remaining = remainingSweeps - 1;
    if (remaining > 0)
    {
        CreateTimer(SCRAMBLE_AUTO_RESPAWN_SWEEP_REPEAT_DELAY, Timer_PostAutoScrambleRespawnSweep, remaining, TIMER_FLAG_NO_MAPCHANGE);
    }

    return Plugin_Stop;
}

static void RestoreSetupTimerAfterScramble()
{
    int elapsed = GetTime() - g_iRoundStartTimestamp;
    if (elapsed <= 0)
    {
        return;
    }

    int timerEnt = FindEntityByClassname(-1, "team_round_timer");
    if (timerEnt == -1)
    {
        return;
    }

    SetVariantInt(elapsed);
    AcceptEntityInput(timerEnt, "AddTime");
    g_iRoundStartTimestamp = GetTime();
    LogWhale("Setup scramble polish: restored %d seconds to setup timer.", elapsed);
    LogWhaleStat("respawn_recovery", "context=setup_timer|result=restored|seconds=%d", elapsed);
}

static void QueueScrambleRespawnsForActiveTeams(const char[] context)
{
    int queued = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || DuelDetection_IsClientInDuel(i))
        {
            continue;
        }

        int team = GetClientTeam(i);
        if (team != TEAM_RED && team != TEAM_BLU)
        {
            continue;
        }

        if (TeamBalance_QueueRespawn(i, team))
        {
            queued++;
        }
    }

    LogWhale("%s: queued respawn verification for %d active team client(s).", context, queued);
    LogWhaleStat("respawn_recovery", "context=%s|result=queued|queued=%d", context, queued);
}

public Action Timer_FillSetupMedicUbers(Handle timer, any data)
{
    FillSetupMedicUbers();
    return Plugin_Stop;
}

static void FillSetupMedicUbers()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || DuelDetection_IsClientInDuel(i) || TF2_GetPlayerClass(i) != TFClass_Medic)
        {
            continue;
        }

        int medigun = GetPlayerWeaponSlot(i, 1);
        if (medigun <= MaxClients || !IsValidEntity(medigun) || !HasEntProp(medigun, Prop_Send, "m_flChargeLevel"))
        {
            continue;
        }

        SetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel", 1.0);
    }
}

void NotifyFailure(int issuer, bool broadcastFailures, const char[] fmt, any ...)
{
    char buffer[256];
    VFormat(buffer, sizeof(buffer), fmt, 4);
    if (issuer > 0 && IsClientInGame(issuer))
    {
        ReplyToCommand(issuer, "[whalescramble] %s", buffer);
        return;
    }
    if (broadcastFailures)
    {
        CPrintToChatAll("{blue}[WhaleScramble]{default} %s", buffer);
    }
}

void InsertTopN(int client, int score, int clients[MAX_SWAP_BUFFER], int scores[MAX_SWAP_BUFFER], int maxCount)
{
    for (int i = 0; i < maxCount; i++)
    {
        if (score > scores[i])
        {
            for (int j = maxCount - 1; j > i; j--)
            {
                scores[j] = scores[j - 1];
                clients[j] = clients[j - 1];
            }
            scores[i] = score;
            clients[i] = client;
            return;
        }
    }
}

int GetScrambleScore(int client, bool ignoreClass, bool forced)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return 0;
    }
    if (DuelDetection_IsClientInDuel(client))
    {
        return 0;
    }

    if (!ignoreClass)
    {
        TFClassType cls = TF2_GetPlayerClass(client);
        if (cls == TFClass_Spy
            || (forced && (Kogasa_IsEngineerWithBuildings(client) || cls == TFClass_Medic)))
        {
            return 0;
        }
    }

    return GetClientFrags(client);
}

bool IsSimpleScrambleEligibleClass(int client, bool forced)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return false;
    }
    if (DuelDetection_IsClientInDuel(client))
    {
        return false;
    }

    TFClassType cls = TF2_GetPlayerClass(client);
    return !forced || (!Kogasa_IsEngineerWithBuildings(client) && cls != TFClass_Medic);
}

bool IsWhaleRankBalanceIgnoredClass(int client)
{
    TFClassType playerClass = TF2_GetPlayerClass(client);
    return playerClass == TFClass_Medic || playerClass == TFClass_Engineer;
}

bool SelectRandomPlayers(const int candidates[MAXPLAYERS + 1], int candidateCount, int selected[MAX_SWAP_BUFFER], int selectedCount)
{
    if (selectedCount <= 0 || selectedCount > MAX_SWAP_BUFFER || candidateCount < selectedCount)
    {
        return false;
    }

    int pool[MAXPLAYERS + 1];
    for (int i = 0; i < candidateCount; i++)
    {
        pool[i] = candidates[i];
    }

    for (int i = 0; i < selectedCount; i++)
    {
        int remaining = candidateCount - i;
        int pick = GetRandomInt(0, remaining - 1);
        selected[i] = pool[pick];
        pool[pick] = pool[remaining - 1];
    }

    return true;
}

static bool ResolveScramblePurchaseImmunity(int &client, int team, int redIds[MAX_SWAP_BUFFER], int bluIds[MAX_SWAP_BUFFER], int swapCount, int pairIndex, bool ignoreImmunity)
{
    if (!HasScramblePurchaseImmunity(client))
    {
        return true;
    }

    int replacement = SelectScrambleReplacementForPass(client, team, redIds, bluIds, swapCount, ignoreImmunity);
    if (replacement <= 0)
    {
        LogWhale("Skipping scramble target %N: paid immunity available and no replacement found.", client);
        LogWhaleStat("immunity_skip", "type=paid|result=blocked|team=%d|pair_index=%d", team, pairIndex);
        return false;
    }

    int usesRemaining = TeamBalance_ConsumeScramblePurchaseImmunity(client);
    if (usesRemaining < 0)
    {
        return true;
    }

    CPrintToChat(client, "{magenta}[Store]{default} You were protected by your {gold}Scramble Immunity (8 times){default}! Uses remaining: {lightgreen}%d", usesRemaining);
    LogWhale("Paid scramble immunity protected %N; replacement=%N usesRemaining=%d.", client, replacement, usesRemaining);
    LogWhaleStat("immunity_skip", "type=paid|result=replaced|team=%d|uses_remaining=%d|pair_index=%d", team, usesRemaining, pairIndex);

    client = replacement;
    if (team == TEAM_RED)
    {
        redIds[pairIndex] = GetClientUserId(replacement);
    }
    else if (team == TEAM_BLU)
    {
        bluIds[pairIndex] = GetClientUserId(replacement);
    }

    return true;
}

static int SelectScrambleReplacementForPass(int protectedClient, int team, int redIds[MAX_SWAP_BUFFER], int bluIds[MAX_SWAP_BUFFER], int swapCount, bool ignoreImmunity)
{
    int candidates[MAXPLAYERS + 1];
    int candidateCount = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (i == protectedClient)
        {
            continue;
        }

        if (!TeamBalance_IsScrambleCandidate(i, team, ignoreImmunity, g_hCountBots != null && g_hCountBots.BoolValue))
        {
            continue;
        }

        if (IsClientSelectedForScramble(i, redIds, bluIds, swapCount))
        {
            continue;
        }

        if (HasScramblePurchaseImmunity(i))
        {
            continue;
        }

        candidates[candidateCount++] = i;
    }

    if (candidateCount <= 0)
    {
        return 0;
    }

    return candidates[GetRandomInt(0, candidateCount - 1)];
}

static bool IsClientSelectedForScramble(int client, int redIds[MAX_SWAP_BUFFER], int bluIds[MAX_SWAP_BUFFER], int swapCount)
{
    int userId = GetClientUserId(client);
    for (int i = 0; i < swapCount; i++)
    {
        if (redIds[i] == userId || bluIds[i] == userId)
        {
            return true;
        }
    }

    return false;
}

static bool HasScramblePurchaseImmunity(int client)
{
    return TeamBalance_HasScramblePurchaseImmunity(client);
}

void LogWhale(const char[] fmt, any ...)
{
    if (g_hScrambleLogEnabled == null || !g_hScrambleLogEnabled.BoolValue)
    {
        return;
    }

    char buffer[512];
    VFormat(buffer, sizeof(buffer), fmt, 2);
    LogMessage("[whalescramble] %s", buffer);
}

void LogWhaleStat(const char[] eventName, const char[] fmt, any ...)
{
    char detail[WHALESCRAMBLE_STATS_DETAIL_MAX];
    detail[0] = '\0';
    if (fmt[0] != '\0')
    {
        VFormat(detail, sizeof(detail), fmt, 3);
        SanitizeWhaleStatField(detail, sizeof(detail));
    }

    char message[512];
    if (detail[0] != '\0')
    {
        Format(message, sizeof(message), "event=%s|%s", eventName, detail);
    }
    else
    {
        Format(message, sizeof(message), "event=%s", eventName);
    }

    PluginStats_Record(eventName, message);
}

static void SanitizeWhaleStatField(char[] value, int maxlen)
{
    for (int i = 0; i < maxlen && value[i] != '\0'; i++)
    {
        if (value[i] == '\n' || value[i] == '\r' || value[i] == '\t')
        {
            value[i] = ' ';
        }
    }
}

static bool GetFiltersNameOrEmpty(int client, char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    if (client <= 0 || !IsClientInGame(client))
    {
        return false;
    }

    if (GetFeatureStatus(FeatureType_Native, "Filters_GetChatName") == FeatureStatus_Available)
    {
        if (Filters_GetChatName(client, buffer, maxlen) && buffer[0] != '\0')
        {
            return true;
        }
    }
    return false;
}

static void BuildFallbackName(int client, bool useTeamColor, char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));

    if (useTeamColor)
    {
        Format(buffer, maxlen, "{teamcolor}%s{default}", name);
        return;
    }

    char colorTag[16];
    switch (GetClientTeam(client))
    {
        case TEAM_RED: strcopy(colorTag, sizeof(colorTag), "{red}");
        case TEAM_BLU: strcopy(colorTag, sizeof(colorTag), "{blue}");
        case 4: strcopy(colorTag, sizeof(colorTag), "{green}");
        case 5: strcopy(colorTag, sizeof(colorTag), "{yellow}");
        default: strcopy(colorTag, sizeof(colorTag), "{default}");
    }

    Format(buffer, maxlen, "%s%s{default}", colorTag, name);
}
