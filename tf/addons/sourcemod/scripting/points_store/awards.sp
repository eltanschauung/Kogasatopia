void PlayBonusPointsSound(int client, bool force)
{
    SaySounds_TryPlayCommand(client, BP_SOUND_COMMAND, force);
}

void PlayWelfareSound()
{
    SaySounds_TryPlayCommand(0, BP_WELFARE_SOUND_COMMAND);
}

void PlayLevelUpSound(int client)
{
    SaySounds_TryPlayCommand(client, BP_LEVEL_UP_SOUND_COMMAND, true);
}

bool CrossedBonusPointsMilestone(int balanceBefore, int balanceAfter)
{
    return balanceAfter > balanceBefore
        && (balanceBefore / BP_BALANCE_MILESTONE) < (balanceAfter / BP_BALANCE_MILESTONE);
}

void AnnounceBonusPointsMilestone(int client, int balance)
{
    if (!Client_IsHumanInGame(client))
    {
        return;
    }

    char prefix[96];
    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    char currencyLong[BP_CURRENCY_LONG_MAX];
    char displayName[256];
    GetCurrencyPrefix(prefix, sizeof(prefix));
    GetCurrencyColorTag(colorTag, sizeof(colorTag));
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
    BuildPurchaseDisplayName(client, displayName, sizeof(displayName));

    CPrintToChatAllEx(client, "%s %s{default} now has %s%d %s{default}!", prefix, displayName, colorTag, balance, currencyLong);
    PlayLevelUpSound(client);
}


bool BuildPerMapAwardKeyForSteamId(const char[] steamId, const char[] type, char[] key, int maxlen)
{
    key[0] = '\0';

    if (g_PerMapAwardCounts == null || steamId[0] == '\0' || type[0] == '\0')
    {
        return false;
    }

    Format(key, maxlen, "%s:%s", steamId, type);
    return true;
}

bool BuildPerMapAwardKey(int client, const char[] type, char[] key, int maxlen)
{
    char steamId[32];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId)))
    {
        key[0] = '\0';
        return false;
    }

    return BuildPerMapAwardKeyForSteamId(steamId, type, key, maxlen);
}

int GetPerMapAwardCount(int client, const char[] type)
{
    if (!g_PerMapAwardsReady)
    {
        return 0;
    }

    char key[128];
    if (!BuildPerMapAwardKey(client, type, key, sizeof(key)))
    {
        return 0;
    }

    int count = 0;
    g_PerMapAwardCounts.GetValue(key, count);
    return count;
}

bool CanApplyPerMapAward(int client, int points, const char[] type, int perMap, int &used)
{
    char steamId[32];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId)))
    {
        used = 0;
        return false;
    }

    return CanApplyPerMapAwardForSteamId(steamId, points, type, perMap, used);
}

bool CanApplyPerMapAwardForSteamId(const char[] steamId, int points, const char[] type, int perMap, int &used)
{
    used = 0;
    if (points <= 0 || perMap <= 0)
    {
        return true;
    }
    if (!g_PerMapAwardsReady)
    {
        return false;
    }

    char key[128];
    if (!BuildPerMapAwardKeyForSteamId(steamId, type, key, sizeof(key)))
    {
        return false;
    }

    g_PerMapAwardCounts.GetValue(key, used);
    return used < perMap;
}

int IncrementPerMapAwardCount(int client, const char[] type)
{
    char steamId[32];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId)))
    {
        return 0;
    }

    return IncrementPerMapAwardCountForSteamId(steamId, type);
}

int IncrementPerMapAwardCountForSteamId(const char[] steamId, const char[] type)
{
    char key[128];
    if (!BuildPerMapAwardKeyForSteamId(steamId, type, key, sizeof(key)))
    {
        return 0;
    }

    int count = 0;
    g_PerMapAwardCounts.GetValue(key, count);
    count++;
    g_PerMapAwardCounts.SetValue(key, count, true);
    if (!QueuePerMapAwardIncrement(steamId, type))
    {
        LogError("[points_store] Failed to persist per-map award '%s' for %s.", type, steamId);
    }
    return count;
}

bool QueuePerMapAwardIncrement(const char[] steamId, const char[] type)
{
    if (!g_PerMapAwardsReady || !g_DatabaseReady || g_Database == null
        || steamId[0] == '\0' || type[0] == '\0')
    {
        return false;
    }

    char escapedMap[257];
    char escapedSteamId[65];
    char escapedType[129];
    if (!EscapeSql(g_PerMapName, escapedMap, sizeof(escapedMap))
        || !EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId))
        || !EscapeSql(type, escapedType, sizeof(escapedType)))
    {
        return false;
    }

    char query[1024];
    int now = GetTime();
    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "INSERT INTO %s (server_port, map_name, steamid64, reward_id, award_count, updated_at) "
            ... "VALUES (%d, '%s', '%s', '%s', 1, %d) "
            ... "ON DUPLICATE KEY UPDATE award_count = award_count + 1, updated_at = VALUES(updated_at)",
            BP_PER_MAP_AWARDS_TABLE,
            g_PerMapServerPort,
            escapedMap,
            escapedSteamId,
            escapedType,
            now);
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO %s (server_port, map_name, steamid64, reward_id, award_count, updated_at) "
            ... "VALUES (%d, '%s', '%s', '%s', 1, %d) "
            ... "ON CONFLICT(server_port, map_name, steamid64, reward_id) DO UPDATE SET "
            ... "award_count = award_count + 1, updated_at = excluded.updated_at",
            BP_PER_MAP_AWARDS_TABLE,
            g_PerMapServerPort,
            escapedMap,
            escapedSteamId,
            escapedType,
            now);
    }

    g_Database.Query(SQL_OnIgnoredResult, query);
    return true;
}

void BuildPerMapAwardSuffix(int perMapUsed, int perMap, char[] suffix, int maxlen)
{
    suffix[0] = '\0';
    if (perMap > 0 && perMapUsed > 0)
    {
        Format(suffix, maxlen, " (%d/%d)", perMapUsed, perMap);
    }
}

bool ApplyBonusPointsNow(int client, int points = 1, bool playSound = true, bool chatAlert = true, float randomChance = 1.0, const char[] type = "", int target = 0, int perMap = 0, const char[] targetNameSnapshot = "", bool announceMilestone = false)
{
    if (!Client_IsHumanInGame(client) || points == 0)
    {
        LogBonusPointsRejected(!Client_IsHumanInGame(client) ? "invalid_client" : "zero_delta", client, points, type, target, 0, randomChance, 0.0);
        return false;
    }

    if (!AreBonusPointsReady(client))
    {
        LoadClientBonusPoints(client);
        LogBonusPointsRejected("balance_not_loaded", client, points, type, target, 0, randomChance, 0.0);
        return false;
    }

    if (points < 0 && g_BountyPlacementPending[client])
    {
        LogBonusPointsRejected("bounty_placement_pending", client, points, type, target, g_ClientBonusPoints[client], randomChance, 0.0);
        return false;
    }

    if (randomChance < 0.1)
    {
        randomChance = 0.1;
    }
    else if (randomChance > 1.0)
    {
        randomChance = 1.0;
    }

    float randomRoll = GetRandomFloat(0.0, 1.0);
    if (randomRoll > randomChance)
    {
        if (g_CvarLogRandomMisses != null && g_CvarLogRandomMisses.BoolValue)
        {
            LogBonusPointsRejected("random_chance_failed", client, points, type, target, GetCachedBonusPoints(client), randomChance, randomRoll);
        }
        return false;
    }

    if (points < 0 && g_ClientBonusPoints[client] < -points)
    {
        LogBonusPointsRejected("insufficient_points", client, points, type, target, g_ClientBonusPoints[client], randomChance, randomRoll, perMap, 0);
        return false;
    }

    int perMapUsed = 0;
    if (points > 0 && perMap > 0 && !g_PerMapAwardsReady)
    {
        LogBonusPointsRejected("per_map_state_not_ready", client, points, type, target, g_ClientBonusPoints[client], randomChance, randomRoll, perMap, 0);
        return false;
    }
    if (!CanApplyPerMapAward(client, points, type, perMap, perMapUsed))
    {
        LogBonusPointsRejected("per_map_limit", client, points, type, target, g_ClientBonusPoints[client], randomChance, randomRoll, perMap, perMapUsed);
        return false;
    }

    int balanceBefore = g_ClientBonusPoints[client];
    g_ClientBonusPoints[client] += points;
    if (g_ClientBonusPoints[client] < 0)
    {
        g_ClientBonusPoints[client] = 0;
    }

    bool saveQueued = QueueBonusPointsDeltaSave(client, points);
    if (points > 0 && perMap > 0)
    {
        perMapUsed = IncrementPerMapAwardCount(client, type);
    }
    LogBonusPointsDelta(client, points, balanceBefore, g_ClientBonusPoints[client], type, target, playSound, chatAlert, randomChance, saveQueued, perMap, perMapUsed, targetNameSnapshot);
    if (!saveQueued)
    {
        LogBonusPointsRejected("save_not_queued", client, points, type, target, g_ClientBonusPoints[client], randomChance, randomRoll, perMap, perMapUsed);
    }
    else if (points < 0)
    {
        RecordCurrencySpend(client, -points, type, target);
    }

    if (saveQueued && announceMilestone && points > 0 && CrossedBonusPointsMilestone(balanceBefore, g_ClientBonusPoints[client]))
    {
        AnnounceBonusPointsMilestone(client, g_ClientBonusPoints[client]);
    }

    if (saveQueued && points > 0 && perMap > 1 && perMapUsed == perMap)
    {
        CreateTimer(3.0, Timer_CompletionBonus, GetClientUserId(client));
    }

    if (playSound)
    {
        PlayBonusPointsSound(client, true);
    }

    if (!chatAlert)
    {
        return true;
    }

    PrintBonusPointsDelta(client, points, type, target, perMapUsed, perMap, targetNameSnapshot);
    return true;
}

public Action Timer_CompletionBonus(Handle timer, any userId)
{
    int client = GetClientOfUserId(userId);
    RewardDefinition reward;
    if (GetRewardDefinition("completion_bonus", reward)
        && ApplyBonusPointsNow(
            client,
            reward.amount,
            false,
            true,
            1.0,
            reward.id,
            0,
            reward.perMapLimit))
    {
        PlayLevelUpSound(client);
    }
    return Plugin_Stop;
}

bool ApplyBonusPoints(int client, int points = 1, bool playSound = true, bool chatAlert = true, float randomChance = 1.0, const char[] type = "", int target = 0, float delay = 3.0, int perMap = 0, bool announceMilestone = false)
{
    if (delay < 0.0)
    {
        delay = 0.0;
    }

    if (delay == 0.0)
    {
        return ApplyBonusPointsNow(client, points, playSound, chatAlert, randomChance, type, target, perMap, "", announceMilestone);
    }

    if (!Client_IsHumanInGame(client) || points == 0)
    {
        LogBonusPointsRejected(!Client_IsHumanInGame(client) ? "deferred_invalid_client" : "deferred_zero_delta", client, points, type, target, 0, randomChance, 0.0);
        return false;
    }

    LogBonusPointsDeferredQueue(client, points, type, target, delay, playSound, chatAlert, randomChance, perMap);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(points);
    pack.WriteCell(playSound ? 1 : 0);
    pack.WriteCell(chatAlert ? 1 : 0);
    pack.WriteFloat(randomChance);
    pack.WriteString(type);
    pack.WriteCell(perMap);
    char targetNameSnapshot[256];
    targetNameSnapshot[0] = '\0';
    if (IsBonusPointsNumericTargetType(type))
    {
        pack.WriteCell(target);
    }
    else
    {
        if (Client_IsHumanInGame(target))
        {
            BuildPurchaseDisplayName(target, targetNameSnapshot, sizeof(targetNameSnapshot));
        }
        pack.WriteCell(Client_IsHumanInGame(target) ? GetClientUserId(target) : 0);
    }
    pack.WriteString(targetNameSnapshot);
    pack.WriteCell(announceMilestone ? 1 : 0);

    CreateTimer(delay, Timer_DeferredApplyBonusPoints, pack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
    return true;
}

bool ApplyBonusPointsSteamId(const char[] steamId, int points, bool playSound = true, bool chatAlert = true, const char[] type = "", int perMap = 0, bool announceMilestone = false)
{
    if (steamId[0] == '\0' || points == 0 || !g_DatabaseReady || g_Database == null)
    {
        return false;
    }

    int client = Kogasa_FindClientBySteamId64(steamId);
    if (client > 0 && AreBonusPointsReady(client))
    {
        return ApplyBonusPointsNow(client, points, playSound, chatAlert, 1.0, type, 0, perMap, "", announceMilestone);
    }

    int perMapUsed = 0;
    if (!CanApplyPerMapAwardForSteamId(steamId, points, type, perMap, perMapUsed))
    {
        return false;
    }

    if (points > 0 && perMap > 0)
    {
        perMapUsed = IncrementPerMapAwardCountForSteamId(steamId, type);
    }

    if (!QueueBonusPointsDeltaSaveForSteamIdWithCacheRefresh(steamId, points, type, perMap, perMapUsed))
    {
        return false;
    }

    return true;
}

bool SpendBonusPointsWithContext(int client, int points, const char[] type, int target = 0)
{
    if (points <= 0)
    {
        return false;
    }

    return ApplyBonusPoints(client, -points, false, false, 1.0, type, target, 0.0);
}

int StealBonusPointsWithContext(int victim, int recipient, int points, const char[] type)
{
    if (points <= 0 || victim == recipient || !g_DatabaseReady || g_Database == null)
    {
        return 0;
    }

    if (!Client_IsHumanInGame(victim) || !Client_IsHumanInGame(recipient))
    {
        return 0;
    }

    if (!AreBonusPointsReady(victim))
    {
        LoadClientBonusPoints(victim);
        return 0;
    }

    if (!AreBonusPointsReady(recipient))
    {
        LoadClientBonusPoints(recipient);
        return 0;
    }

    int actual = points;
    if (g_ClientBonusPoints[victim] < actual)
    {
        actual = g_ClientBonusPoints[victim];
    }

    if (actual <= 0)
    {
        return 0;
    }

    int victimBefore = g_ClientBonusPoints[victim];
    int recipientBefore = g_ClientBonusPoints[recipient];

    g_ClientBonusPoints[victim] -= actual;
    if (g_ClientBonusPoints[victim] < 0)
    {
        g_ClientBonusPoints[victim] = 0;
    }
    g_ClientBonusPoints[recipient] += actual;

    bool victimSaveQueued = QueueBonusPointsDeltaSave(victim, -actual);
    bool recipientSaveQueued = QueueBonusPointsDeltaSave(recipient, actual);

    LogBonusPointsDelta(victim, -actual, victimBefore, g_ClientBonusPoints[victim], type, recipient, false, false, 1.0, victimSaveQueued);
    LogBonusPointsDelta(recipient, actual, recipientBefore, g_ClientBonusPoints[recipient], type, victim, false, false, 1.0, recipientSaveQueued);

    if (!victimSaveQueued || !recipientSaveQueued)
    {
        LogBonusPointsRejected("steal_save_not_queued", victim, -actual, type, recipient, g_ClientBonusPoints[victim], 1.0, 0.0);
        LogBonusPointsRejected("steal_save_not_queued", recipient, actual, type, victim, g_ClientBonusPoints[recipient], 1.0, 0.0);
    }

    return actual;
}

void BuildCallerSpendType(Handle plugin, char[] type, int maxlen)
{
    char filename[PLATFORM_MAX_PATH];
    GetPluginFilename(plugin, filename, sizeof(filename));
    if (filename[0] == '\0')
    {
        strcopy(type, maxlen, "spend_unknown");
        return;
    }

    ReplaceString(filename, sizeof(filename), ".smx", "", false);
    ReplaceString(filename, sizeof(filename), "/", "_", false);
    ReplaceString(filename, sizeof(filename), "\\", "_", false);
    Format(type, maxlen, "spend_%s", filename);
}

public Action Timer_DeferredApplyBonusPoints(Handle timer, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int client = GetClientOfUserId(pack.ReadCell());
    int points = pack.ReadCell();
    bool playSound = pack.ReadCell() != 0;
    bool chatAlert = pack.ReadCell() != 0;
    float randomChance = pack.ReadFloat();
    char type[64];
    pack.ReadString(type, sizeof(type));
    int perMap = pack.ReadCell();
    int targetValue = pack.ReadCell();
    char targetNameSnapshot[256];
    pack.ReadString(targetNameSnapshot, sizeof(targetNameSnapshot));
    bool announceMilestone = pack.ReadCell() != 0;
    int target = IsBonusPointsNumericTargetType(type) ? targetValue : GetClientOfUserId(targetValue);

    ApplyBonusPointsNow(client, points, playSound, chatAlert, randomChance, type, target, perMap, targetNameSnapshot, announceMilestone);
    return Plugin_Stop;
}

void PrintBonusPointsDelta(int client, int points, const char[] type, int target, int perMapUsed = 0, int perMap = 0, const char[] targetNameSnapshot = "")
{
    char prefix[96];
    GetCurrencyPrefix(prefix, sizeof(prefix));

    if (points < 0)
    {
        CPrintToChat(client, "%s{limegreen}%i", prefix, points);
        return;
    }

    char sign[2];
    sign[0] = '+';
    sign[1] = '\0';

    char perMapSuffix[24];
    BuildPerMapAwardSuffix(perMapUsed, perMap, perMapSuffix, sizeof(perMapSuffix));

    if (StrEqual(type, "points_diff", false) && Client_IsHumanInGame(target))
    {
        char targetName[256];
        BuildPurchaseDisplayName(target, targetName, sizeof(targetName));
        CPrintToChat(client, "%s {limegreen}%s%i{default} for {gold}killing{default} %s%s", prefix, sign, points, targetName, perMapSuffix);
        return;
    }
    if (StrEqual(type, "points_diff", false) && targetNameSnapshot[0] != '\0')
    {
        CPrintToChat(client, "%s {limegreen}%s%i{default} for {gold}killing{default} %s%s", prefix, sign, points, targetNameSnapshot, perMapSuffix);
        return;
    }

    if (StrEqual(type, "top_score_kill", false) && Client_IsHumanInGame(target))
    {
        char targetName[256];
        BuildPurchaseDisplayName(target, targetName, sizeof(targetName));
        CPrintToChat(client, "%s {limegreen}%s%i{default} for killing {gold}Top-scoring player{default} (%s)%s", prefix, sign, points, targetName, perMapSuffix);
        return;
    }
    if (StrEqual(type, "top_score_kill", false) && targetNameSnapshot[0] != '\0')
    {
        CPrintToChat(client, "%s {limegreen}%s%i{default} for killing {gold}Top-scoring player{default} (%s)%s", prefix, sign, points, targetNameSnapshot, perMapSuffix);
        return;
    }

    if (StrEqual(type, "player_dom", false) && Client_IsHumanInGame(target))
    {
        CPrintToChat(client, "%s {limegreen}%s%i{default} for {gold}Dominating{default} %N%s", prefix, sign, points, target, perMapSuffix);
        return;
    }

    if (StrEqual(type, "player_revenge", false) && Client_IsHumanInGame(target))
    {
        CPrintToChat(client, "%s {limegreen}%s%i{default} for {gold}Revenge{default} on %N%s", prefix, sign, points, target, perMapSuffix);
        return;
    }
    if (StrEqual(type, "player_revenge", false) && targetNameSnapshot[0] != '\0')
    {
        CPrintToChat(client, "%s {limegreen}%s%i{default} for {gold}Revenge{default} on %s%s", prefix, sign, points, targetNameSnapshot, perMapSuffix);
        return;
    }

    if (StrEqual(type, "killstreak", false)
        || StrEqual(type, "killstreak_5_10", false)
        || StrEqual(type, "killstreak_above_10", false))
    {
        CPrintToChat(client, "%s {limegreen}%s%i{default} for {gold}Killstreak: %d{default}%s", prefix, sign, points, target, perMapSuffix);
        return;
    }

    if (StrEqual(type, "multikill", false)
        || StrEqual(type, "multikill_3_4", false)
        || StrEqual(type, "multikill_5_plus", false))
    {
        char multikillLabel[32];
        GetMultikillBonusPointsLabel(target, multikillLabel, sizeof(multikillLabel));
        if (multikillLabel[0] != '\0')
        {
            CPrintToChat(client, "%s {limegreen}%s%i{default} for {gold}%s{default}%s", prefix, sign, points, multikillLabel, perMapSuffix);
        }
        else
        {
            CPrintToChat(client, "%s {limegreen}%s%i{default} for {gold}Multikill: %d{default}%s", prefix, sign, points, target, perMapSuffix);
        }
        return;
    }

    if (StrEqual(type, "medic_assists", false))
    {
        CPrintToChat(client, "%s {limegreen}%s%i{default} for {gold}Assists: %d{default}%s", prefix, sign, points, target, perMapSuffix);
        return;
    }

    if (StrEqual(type, "medic_high_uber_kill", false))
    {
        CPrintToChat(client, "%s {limegreen}%s%i{default} for {gold}Medic high ÜberCharge kill (%d%%){default}%s", prefix, sign, points, target, perMapSuffix);
        return;
    }

    if (StrEqual(type, "medic_assists_life", false) && target > 0)
    {
        CPrintToChat(client, "%s {limegreen}%s%i{default} for {gold}%d assists life{default}%s", prefix, sign, points, target, perMapSuffix);
        return;
    }

    char label[64];
    GetBonusPointsTypeLabel(type, label, sizeof(label));
    if (label[0] != '\0')
    {
        CPrintToChat(client, "%s {limegreen}%s%i{default} for {gold}%s{default}%s", prefix, sign, points, label, perMapSuffix);
        return;
    }

    GetBonusPointsFallbackLabel(type, label, sizeof(label));
    if (label[0] != '\0')
    {
        CPrintToChat(client, "%s {limegreen}%s%i{default} for {gold}%s{default}%s", prefix, sign, points, label, perMapSuffix);
        return;
    }

    CPrintToChat(client, "%s {limegreen}%s%i%s", prefix, sign, points, perMapSuffix);
}

