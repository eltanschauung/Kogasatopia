void StopAutobalanceTimer()
{
    if (g_hAutoBalanceTimer == INVALID_HANDLE)
    {
        return;
    }

    KillTimer(g_hAutoBalanceTimer);
    g_hAutoBalanceTimer = INVALID_HANDLE;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

bool ShouldSuppressAutobalanceForGamemode()
{
    if (GetFeatureStatus(FeatureType_Native, "DGM_IsSmallFormatGamemode") != FeatureStatus_Available)
    {
        return false;
    }

    return DGM_IsSmallFormatGamemode();
}

bool ShouldSkipWinningTeamAutobalance(int fromTeam, int toTeam, int diff)
{
    if (g_hIgnoreWinning == null || g_hIgnoreWinning.FloatValue <= 0.0)
    {
        return false;
    }

    if (GetFeatureStatus(FeatureType_Native, "DGM_GetObjectiveLeaderTeam") != FeatureStatus_Available)
    {
        return false;
    }

    int winningTeam = DGM_GetObjectiveLeaderTeam();
    int losingTeam = AB_GetOpposingCoreTeam(winningTeam);

    if (losingTeam == 0 || fromTeam != losingTeam || toTeam != winningTeam)
    {
        return false;
    }

    float ignoreWinning = g_hIgnoreWinning.FloatValue;
    if (ignoreWinning > 1.0 && ignoreWinning >= float(diff))
    {
        return false;
    }

    return true;
}

static int AB_GetOpposingCoreTeam(int team)
{
    if (team == TEAM_RED)
    {
        return TEAM_BLUE;
    }

    if (team == TEAM_BLUE)
    {
        return TEAM_RED;
    }

    return 0;
}

bool IsEligiblePlayer(int client, int team, bool clanProtectionAvailable)
{
    if (!IsBasicBalanceCandidate(client, team)) return false;
    if (IsProtectedBalanceCandidate(client, team, clanProtectionAvailable)) return false;

    return true;
}

bool IsBasicBalanceCandidate(int client, int team)
{
    if (client <= 0 || client > MaxClients) return false;
    if (!IsClientInGame(client) || IsFakeClient(client)) return false;
    if (GetClientTeam(client) != team) return false;
    if (DuelDetection_IsClientInDuel(client)) return false;
    if (TeamBalance_IsRecentlyMoved(client)) return false;
    if (ClientHasDecapitationHeads(client)) return false;

    return true;
}

static bool ClientHasDecapitationHeads(int client)
{
    if (!HasEntProp(client, Prop_Send, "m_iDecapitations"))
    {
        return false;
    }

    int heads = GetEntProp(client, Prop_Send, "m_iDecapitations");
    return heads != 0;
}

static bool IsProtectedBalanceCandidate(int client, int team, bool clanProtectionAvailable)
{
    if (IsMedicWithProtectedUber(client)) return true;
    if (Kogasa_IsEngineerWithBuildings(client)) return true;
    if (IsClientImmune(client)) return true;
    if (HasClanTeammateProtection(client, team, clanProtectionAvailable)) return true;

    return false;
}

static bool IsMedicWithProtectedUber(int client)
{
    if (TF2_GetPlayerClass(client) != TFClass_Medic)
    {
        return false;
    }

    int medigun = GetPlayerWeaponSlot(client, 1);
    if (medigun <= MaxClients || !IsValidEntity(medigun))
    {
        return false;
    }

    if (!HasEntProp(medigun, Prop_Send, "m_flChargeLevel"))
    {
        return false;
    }

    // m_flChargeLevel is normalized: 0.05 is 5% uber.
    return GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel") > MEDIC_AUTOBALANCE_UBER_FLOOR;
}

bool HasClanTeammateProtection(int client, int team, bool clanProtectionAvailable)
{
    if (!clanProtectionAvailable)
    {
        return false;
    }

    int count = Clans_GetSameTeamClanMemberCount(client, team);
    // Clans returns -1 while its cache/client state is unavailable. Fail open
    // here; treating unknown as protected can block every autobalance candidate.
    return count > 1;
}

static int GetSimpleSelectionPriority(int client)
{
    int priority = 0;

    if (!IsPlayerAlive(client))
    {
        priority += 2;
    }

    if (!Kogasa_IsEngineerWithBuildings(client))
    {
        priority += 1;
    }

    return priority;
}

int SelectPreferredRecentPlayer(int team, bool clanProtectionAvailable)
{
    int pick = 0;
    int bestPriority = -1;
    int highestUserId = -1;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsBasicBalanceCandidate(i, team)) continue;

        int priority = GetSimpleSelectionPriority(i);
        int currentUserId = GetClientUserId(i);
        if (priority < bestPriority || (priority == bestPriority && currentUserId <= highestUserId))
        {
            continue;
        }

        if (IsProtectedBalanceCandidate(i, team, clanProtectionAvailable))
        {
            continue;
        }

        if (priority > bestPriority || (priority == bestPriority && currentUserId > highestUserId))
        {
            bestPriority = priority;
            highestUserId = currentUserId;
            pick = i;
        }
    }

    return pick;
}

static bool IsVolunteerCandidate(int client, int team)
{
    if (!IsBasicBalanceCandidate(client, team)) return false;
    if (!IsClientVolunteer(client)) return false;
    if (IsClientImmune(client)) return false;
    if (HasAutobalancePurchaseImmunity(client)) return false;
    if (Kogasa_IsEngineerWithBuildings(client)) return false;
    if (IsMedicWithProtectedUber(client)) return false;

    return true;
}

int SelectVolunteerPlayer(int team, int &nonMedicCount, int &medicCount)
{
    int nonMedics[MAXPLAYERS];
    int medics[MAXPLAYERS];
    nonMedicCount = 0;
    medicCount = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsVolunteerCandidate(i, team)) continue;

        if (TF2_GetPlayerClass(i) == TFClass_Medic)
        {
            medics[medicCount++] = i;
        }
        else
        {
            nonMedics[nonMedicCount++] = i;
        }
    }

    if (nonMedicCount > 0)
    {
        return nonMedics[GetRandomInt(0, nonMedicCount - 1)];
    }

    if (medicCount > 0)
    {
        return medics[GetRandomInt(0, medicCount - 1)];
    }

    return 0;
}

bool IsClientImmune(int client)
{
    return IsClientMapImmune(client) || IsClientPersistentlyImmune(client);
}

bool HasAutobalancePurchaseImmunity(int client)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
    {
        return false;
    }

    if (GetFeatureStatus(FeatureType_Native, "PointsStore_HasPurchase") != FeatureStatus_Available)
    {
        return false;
    }

    if (GetFeatureStatus(FeatureType_Native, "PointsStore_ConsumePurchaseUse") != FeatureStatus_Available)
    {
        return false;
    }

    return PointsStore_HasPurchase(client, POINTS_STORE_AB_IMMUNITY_ITEM);
}

bool ResolveAutobalancePurchaseImmunity(int &pick, int team, bool clanProtectionAvailable, bool loggingEnabled)
{
    if (!HasAutobalancePurchaseImmunity(pick))
    {
        return true;
    }

    int replacement = SelectAutobalanceReplacementForPass(pick, team, clanProtectionAvailable);
    if (replacement <= 0)
    {
        if (loggingEnabled)
        {
            LogBalance("Skip balance on %N: protected by paid immunity and no replacement was available", pick);
        }
        return false;
    }

    int usesRemaining = PointsStore_ConsumePurchaseUse(pick, POINTS_STORE_AB_IMMUNITY_ITEM);
    CPrintToChat(pick, "{magenta}[Store]{default} You were protected by your {gold}Autobalance Immunity (16 times){default}! Uses remaining: {lightgreen}%d", usesRemaining);
    if (loggingEnabled)
    {
        LogBalance("Paid autobalance immunity protected %N; replacement=%N usesRemaining=%d", pick, replacement, usesRemaining);
    }

    pick = replacement;
    return true;
}

static int SelectAutobalanceReplacementForPass(int protectedClient, int team, bool clanProtectionAvailable)
{
    int bestClient = 0;
    int bestScore = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (i == protectedClient)
        {
            continue;
        }

        if (!IsEligiblePlayer(i, team, clanProtectionAvailable))
        {
            continue;
        }

        if (HasAutobalancePurchaseImmunity(i))
        {
            continue;
        }

        int score = GetClientScore(i);
        if (bestClient == 0 || score < bestScore)
        {
            bestClient = i;
            bestScore = score;
        }
    }

    return bestClient;
}

static bool IsClientPersistentlyImmune(int client)
{
    if (g_hPersistentImmunity == null || !IsClientInGame(client))
    {
        return false;
    }

    char steamId[32];
    if (!Kogasa_GetClientSteamId64(client, steamId, sizeof(steamId), true))
    {
        return false;
    }

    int dummy = 0;
    return g_hPersistentImmunity.GetValue(steamId, dummy);
}

static bool IsClientMapImmune(int client)
{
    if (g_hMapImmunity == null || !IsClientInGame(client)) return false;

    char steamId[32];
    if (!Kogasa_GetClientSteamId64(client, steamId, sizeof(steamId), true))
    {
        return false;
    }

    int dummy = 0;
    return g_hMapImmunity.GetValue(steamId, dummy);
}

bool SetClientMapImmunity(int client, bool immune)
{
    if (g_hMapImmunity == null || !IsClientInGame(client) || IsFakeClient(client))
    {
        return false;
    }

    char steamId[32];
    if (!Kogasa_GetClientSteamId64(client, steamId, sizeof(steamId), true))
    {
        return false;
    }

    if (immune)
    {
        g_hMapImmunity.SetValue(steamId, 1, true);
    }
    else
    {
        g_hMapImmunity.Remove(steamId);
    }
    return true;
}

bool IsClientVolunteer(int client)
{
    if (g_hVolunteers == null || !IsClientInGame(client))
    {
        return false;
    }

    char steamId[32];
    if (!Kogasa_GetClientSteamId64(client, steamId, sizeof(steamId), true))
    {
        return false;
    }

    int dummy = 0;
    return g_hVolunteers.GetValue(steamId, dummy);
}

bool HasCachedVolunteers()
{
    return g_bVolunteerDbReady && g_hVolunteers != null && g_iPersistentVolunteerCount > 0;
}

void SetPersistentVolunteerCache(const char[] steamId, bool volunteer)
{
    if (g_hVolunteers == null || !steamId[0])
    {
        return;
    }

    int existing = 0;
    bool wasVolunteer = g_hVolunteers.GetValue(steamId, existing);

    if (volunteer)
    {
        g_hVolunteers.SetValue(steamId, 1, true);
        if (!wasVolunteer)
        {
            g_iPersistentVolunteerCount++;
        }
    }
    else
    {
        if (wasVolunteer)
        {
            g_hVolunteers.Remove(steamId);
            if (g_iPersistentVolunteerCount > 0)
            {
                g_iPersistentVolunteerCount--;
            }
        }
    }
}

