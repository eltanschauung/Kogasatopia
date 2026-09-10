bool QueueBonusPointsDeltaSaveForSteamId(const char[] steamId, int delta)
{
    if (delta == 0 || !g_DatabaseReady || g_Database == null)
    {
        return false;
    }

    if (steamId[0] == '\0')
    {
        return false;
    }

    char escapedSteamId[65];
    if (!EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId)))
    {
        LogError("[points_store] Failed to escape SteamID64 for bonus-point save.");
        return false;
    }

    char query[512];
    Format(query, sizeof(query),
        "INSERT INTO %s (steamid64, balance) "
        ... "VALUES ('%s', %d) "
        ... "ON DUPLICATE KEY UPDATE "
        ... "balance = GREATEST(0, balance + VALUES(balance))",
        BP_BALANCE_TABLE,
        escapedSteamId,
        delta);

    g_Database.Query(SQL_OnIgnoredResult, query);
    return true;
}

bool QueueBonusPointsDeltaSaveForSteamIdWithCacheRefresh(const char[] steamId, int delta, const char[] type, int perMap, int perMapUsed)
{
    if (delta == 0 || !g_DatabaseReady || g_Database == null)
    {
        return false;
    }

    if (steamId[0] == '\0')
    {
        return false;
    }

    char escapedSteamId[65];
    if (!EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId)))
    {
        LogError("[points_store] Failed to escape SteamID64 for bonus-point save.");
        return false;
    }

    char query[512];
    Format(query, sizeof(query),
        "INSERT INTO %s (steamid64, balance) "
        ... "VALUES ('%s', %d) "
        ... "ON DUPLICATE KEY UPDATE "
        ... "balance = GREATEST(0, balance + VALUES(balance))",
        BP_BALANCE_TABLE,
        escapedSteamId,
        delta);

    DataPack pack = new DataPack();
    pack.WriteString(steamId);
    pack.WriteCell(delta);
    pack.WriteString(type);
    pack.WriteCell(perMap);
    pack.WriteCell(perMapUsed);

    g_Database.Query(SQL_OnBonusPointsSteamIdDeltaSaved, query, pack);
    return true;
}

public void SQL_OnBonusPointsSteamIdDeltaSaved(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    char steamId[32];
    pack.ReadString(steamId, sizeof(steamId));
    int delta = pack.ReadCell();
    char type[64];
    pack.ReadString(type, sizeof(type));
    int perMap = pack.ReadCell();
    int perMapUsed = pack.ReadCell();
    delete pack;

    if (error[0] != '\0')
    {
        LogError("[points_store] Failed direct SteamID64 bonus-point save for %s: %s", steamId, error);
        return;
    }

    int client = Kogasa_FindClientBySteamId64(steamId);
    int balanceAfter = -1;
    if (client > 0 && g_ClientBonusPointsLoaded[client])
    {
        g_ClientBonusPoints[client] += delta;
        if (g_ClientBonusPoints[client] < 0)
        {
            g_ClientBonusPoints[client] = 0;
        }
        balanceAfter = g_ClientBonusPoints[client];
    }

    char safeType[64];
    strcopy(safeType, sizeof(safeType), type);
    SanitizeLogField(safeType, sizeof(safeType));
    LogPointsStoreEvent(
        "event=bp_delta_offline|time=%d|steamid64=%s|delta=%d|type=%s|per_map=%d|per_map_used=%d|client=%d|balance_after=%d",
        GetTime(),
        steamId,
        delta,
        safeType,
        perMap,
        perMapUsed,
        client,
        balanceAfter);
}

void FireIdempotentAwardResult(const char[] awardKey, bool success, bool newlyApplied)
{
    if (g_IdempotentAwardForward == null)
    {
        return;
    }

    Call_StartForward(g_IdempotentAwardForward);
    Call_PushString(awardKey);
    Call_PushCell(success);
    Call_PushCell(newlyApplied);
    Call_Finish();
}

void ApplyIdempotentAwardToCache(const char[] steamId, int amount, const char[] type)
{
    int client = Kogasa_FindClientBySteamId64(steamId);
    int balanceAfter = -1;
    if (client > 0 && g_ClientBonusPointsLoaded[client])
    {
        g_ClientBonusPoints[client] += amount;
        balanceAfter = g_ClientBonusPoints[client];
    }

    char safeType[64];
    strcopy(safeType, sizeof(safeType), type);
    SanitizeLogField(safeType, sizeof(safeType));
    LogPointsStoreEvent(
        "event=bp_idempotent_award|time=%d|steamid64=%s|amount=%d|type=%s|client=%d|balance_after=%d",
        GetTime(),
        steamId,
        amount,
        safeType,
        client,
        balanceAfter);
}

bool QueueIdempotentBonusPointsAward(const char[] steamId, int amount, const char[] awardKey, const char[] type)
{
    if (!g_DatabaseReady || !g_IdempotentAwardsReady || g_Database == null
        || steamId[0] == '\0' || amount <= 0 || awardKey[0] == '\0')
    {
        return false;
    }

    int steamLen = strlen(steamId);
    if (steamLen < 16 || steamLen >= 32 || strlen(awardKey) >= BP_IDEMPOTENT_KEY_MAX)
    {
        return false;
    }

    for (int i = 0; i < steamLen; i++)
    {
        if (!IsCharNumeric(steamId[i]))
        {
            return false;
        }
    }

    char escapedSteam[65];
    char escapedKey[(BP_IDEMPOTENT_KEY_MAX * 2) + 1];
    char escapedType[129];
    if (!EscapeSql(steamId, escapedSteam, sizeof(escapedSteam))
        || !EscapeSql(awardKey, escapedKey, sizeof(escapedKey))
        || !EscapeSql(type, escapedType, sizeof(escapedType)))
    {
        return false;
    }

    Transaction txn = new Transaction();
    char query[768];
    Format(query, sizeof(query),
        "INSERT INTO %s (award_key, steamid64, amount, reason, created_at) "
        ... "VALUES ('%s', '%s', %d, '%s', %d)",
        BP_IDEMPOTENT_AWARDS_TABLE,
        escapedKey,
        escapedSteam,
        amount,
        escapedType,
        GetTime());
    txn.AddQuery(query);

    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "INSERT INTO %s (steamid64, balance) VALUES ('%s', %d) "
            ... "ON DUPLICATE KEY UPDATE balance = GREATEST(0, balance + VALUES(balance))",
            BP_BALANCE_TABLE,
            escapedSteam,
            amount);
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO %s (steamid64, balance) VALUES ('%s', %d) "
            ... "ON CONFLICT(steamid64) DO UPDATE SET balance = MAX(0, balance + excluded.balance)",
            BP_BALANCE_TABLE,
            escapedSteam,
            amount);
    }
    txn.AddQuery(query);

    DataPack pack = new DataPack();
    pack.WriteString(awardKey);
    pack.WriteString(steamId);
    pack.WriteCell(amount);
    pack.WriteString(type);
    g_Database.Execute(txn, SQLTxn_OnIdempotentAwardSuccess, SQLTxn_OnIdempotentAwardFailure, pack);
    return true;
}

public void SQLTxn_OnIdempotentAwardSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    char awardKey[BP_IDEMPOTENT_KEY_MAX];
    char steamId[32];
    char type[64];
    pack.ReadString(awardKey, sizeof(awardKey));
    pack.ReadString(steamId, sizeof(steamId));
    int amount = pack.ReadCell();
    pack.ReadString(type, sizeof(type));
    delete pack;

    ApplyIdempotentAwardToCache(steamId, amount, type);
    FireIdempotentAwardResult(awardKey, true, true);
}

public void SQLTxn_OnIdempotentAwardFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    char awardKey[BP_IDEMPOTENT_KEY_MAX];
    char steamId[32];
    char type[64];
    pack.ReadString(awardKey, sizeof(awardKey));
    pack.ReadString(steamId, sizeof(steamId));
    pack.ReadCell();
    pack.ReadString(type, sizeof(type));

    bool duplicate = StrContains(error, "Duplicate entry", false) != -1
        || StrContains(error, "UNIQUE constraint failed", false) != -1;
    if (!duplicate)
    {
        LogError("[points_store] Idempotent award '%s' failed at query %d: %s", awardKey, failIndex, error);
        delete pack;
        FireIdempotentAwardResult(awardKey, false, false);
        return;
    }

    char escapedKey[(BP_IDEMPOTENT_KEY_MAX * 2) + 1];
    if (!EscapeSql(awardKey, escapedKey, sizeof(escapedKey)))
    {
        delete pack;
        FireIdempotentAwardResult(awardKey, false, false);
        return;
    }

    char query[384];
    Format(query, sizeof(query),
        "SELECT steamid64, amount, reason FROM %s WHERE award_key = '%s' LIMIT 1",
        BP_IDEMPOTENT_AWARDS_TABLE,
        escapedKey);
    g_Database.Query(SQL_OnIdempotentAwardVerified, query, pack);
}

public void SQL_OnIdempotentAwardVerified(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    char awardKey[BP_IDEMPOTENT_KEY_MAX];
    char expectedSteamId[32];
    char expectedType[64];
    pack.ReadString(awardKey, sizeof(awardKey));
    pack.ReadString(expectedSteamId, sizeof(expectedSteamId));
    int expectedAmount = pack.ReadCell();
    pack.ReadString(expectedType, sizeof(expectedType));
    delete pack;

    if (error[0] != '\0' || results == null || !results.FetchRow())
    {
        LogError("[points_store] Could not verify existing idempotent award '%s': %s", awardKey, error);
        FireIdempotentAwardResult(awardKey, false, false);
        return;
    }

    char actualSteamId[32];
    char actualType[64];
    results.FetchString(0, actualSteamId, sizeof(actualSteamId));
    int actualAmount = results.FetchInt(1);
    results.FetchString(2, actualType, sizeof(actualType));

    bool matches = StrEqual(actualSteamId, expectedSteamId, false)
        && actualAmount == expectedAmount
        && StrEqual(actualType, expectedType, false);
    if (!matches)
    {
        LogError("[points_store] Idempotent award key collision for '%s'.", awardKey);
    }
    FireIdempotentAwardResult(awardKey, matches, false);
}

bool QueueBonusPointsDeltaSave(int client, int delta)
{
    char steamId[32];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId)))
    {
        return false;
    }

    return QueueBonusPointsDeltaSaveForSteamId(steamId, delta);
}

bool ShouldRecordCurrencySpend(const char[] type)
{
    if (StrEqual(type, "transfer_out", false)
        || StrEqual(type, "transfer_in", false)
        || StrEqual(type, "transfer_refund", false)
        || StrEqual(type, "welfare", false))
    {
        return false;
    }

    if (StrContains(type, "lottery_", false) == 0)
    {
        return false;
    }

    return true;
}

bool QueueEconomyDelta(const char[] statKey, int delta)
{
    if (delta == 0 || !g_DatabaseReady || g_Database == null)
    {
        return false;
    }

    char escapedKey[(BP_ECONOMY_KEY_MAX * 2) + 1];
    if (!EscapeSql(statKey, escapedKey, sizeof(escapedKey)))
    {
        LogError("[points_store] Failed to escape economy key '%s'.", statKey);
        return false;
    }

    char query[512];
    int now = GetTime();
    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "INSERT INTO %s (stat_key, value, updated_at) VALUES ('%s', %d, %d) ON DUPLICATE KEY UPDATE value = GREATEST(0, value + VALUES(value)), updated_at = VALUES(updated_at)",
            BP_ECONOMY_TABLE,
            escapedKey,
            delta,
            now);
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO %s (stat_key, value, updated_at) VALUES ('%s', %d, %d) ON CONFLICT(stat_key) DO UPDATE SET value = MAX(0, value + excluded.value), updated_at = excluded.updated_at",
            BP_ECONOMY_TABLE,
            escapedKey,
            delta,
            now);
    }

    g_Database.Query(SQL_OnIgnoredResult, query);
    return true;
}

void LogEconomyEvent(const char[] eventName, int client, int amount, const char[] type, int target, int welfarePool, int cumulativeSpent)
{
    char steamId[32];
    char clientName[MAX_NAME_LENGTH];
    char clientClass[16];
    GetClientLogIdentity(client, steamId, sizeof(steamId), clientName, sizeof(clientName));
    GetClientLogClass(client, clientClass, sizeof(clientClass));

    char safeEvent[64];
    char safeType[64];
    strcopy(safeEvent, sizeof(safeEvent), eventName);
    if (type[0] == '\0')
    {
        strcopy(safeType, sizeof(safeType), "unspecified");
    }
    else
    {
        strcopy(safeType, sizeof(safeType), type);
    }
    SanitizeLogField(safeEvent, sizeof(safeEvent));
    SanitizeLogField(safeType, sizeof(safeType));

    char message[BP_EVENT_LOG_LINE_MAX];
    Format(message, sizeof(message),
        "event=%s|time=%d|client=%d|steamid64=%s|name=\"%s\"|class=%s|amount=%d|type=%s|target_value=%d|welfare_pool=%d|cumulative_spent=%d",
        safeEvent,
        GetTime(),
        client,
        steamId,
        clientName,
        clientClass,
        amount,
        safeType,
        target,
        welfarePool,
        cumulativeSpent);
    QueuePointsStoreEvent(message);
}

void RecordCurrencySpend(int client, int amount, const char[] type, int target)
{
    if (amount <= 0 || !ShouldRecordCurrencySpend(type))
    {
        return;
    }

    if (QueueEconomyDelta(BP_ECONOMY_WELFARE_POOL_KEY, amount))
    {
        g_WelfarePoolBalance += amount;
    }
    if (QueueEconomyDelta(BP_ECONOMY_CUMULATIVE_SPENT_KEY, amount))
    {
        g_CumulativeSpentBalance += amount;
    }

    LogEconomyEvent("currency_spent", client, amount, type, target, g_WelfarePoolBalance, g_CumulativeSpentBalance);
}

