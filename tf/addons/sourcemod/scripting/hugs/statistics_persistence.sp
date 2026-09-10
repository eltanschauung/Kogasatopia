#define HUGS_STATS_QUERY_MAX 4096

DataPack g_HugsStatsLoadRequest[MAXPLAYERS + 1];
Database g_HugsStatsLoadConnection[MAXPLAYERS + 1];
StringMap g_HugsStatsSaveOwners = null;
StringMap g_HugsStatsQueuedSaves = null;

enum struct HugsStatsSnapshot
{
    Database connection;
    char query[HUGS_STATS_QUERY_MAX];
}

void ResetClientStats(int client)
{
    if (!IsClientIndexValid(client))
    {
        return;
    }
    CancelStatsRetryTimer(client);
    // Outstanding SQL callbacks own their packs and will discard stale results.
    g_HugsStatsLoadRequest[client] = null;
    delete g_HugsStatsLoadConnection[client];
    g_HugsStatsLoadConnection[client] = null;
    g_iHugsReceived[client] = 0;
    g_iHugsGiven[client] = 0;
    g_iFeedsReceived[client] = 0;
    g_iFeedsGiven[client] = 0;
    g_iRapesReceived[client] = 0;
    g_iRapesGiven[client] = 0;
    for (int i = 0; i < MAX_HISTORY_ENTRIES; i++)
    {
        g_szLastHuggers[client][i][0] = '\0';
        g_szLastFeeders[client][i][0] = '\0';
    }
    g_szLastRapists[client][0] = '\0';
    g_szClientSteamId[client][0] = '\0';
    g_bStatsLoaded[client] = false;
    g_bStatsPending[client] = false;
}

bool EnsureStatsReady(int client, bool notify)
{
    if (!IsHumanClient(client))
    {
        return true;
    }
    if (g_bStatsLoaded[client])
    {
        return true;
    }
    if (notify)
    {
        PrintToChat(client, "[SM] Your hug/rape stats are still loading. Please wait.");
    }
    AttemptLoadClientStats(client);
    return false;
}

bool EnsureClientSteamId(int client)
{
    if (!IsClientIndexValid(client))
    {
        return false;
    }
    if (g_szClientSteamId[client][0])
    {
        return true;
    }
    char auth[32];
    if (!Kogasa_GetClientSteam2(client, auth, sizeof(auth), true)
        || StrEqual(auth, "STEAM_ID_PENDING"))
    {
        return false;
    }
    strcopy(g_szClientSteamId[client], sizeof(g_szClientSteamId[]), auth);
    return true;
}

bool IsDatabaseReady()
{
    return Db_IsReady(g_hDatabase, g_bDatabaseReady);
}

bool Hugs_HasPendingStatsSave(const char[] steamId)
{
    int owner;
    return g_HugsStatsSaveOwners != null
        && g_HugsStatsSaveOwners.GetValue(steamId, owner);
}

void AttemptLoadClientStats(int client)
{
    if (!IsHumanClient(client) || g_bStatsLoaded[client] || !IsDatabaseReady()
        || !EnsureClientSteamId(client))
    {
        return;
    }
    if (g_bStatsPending[client] && g_HugsStatsLoadRequest[client] != null
        && g_HugsStatsLoadConnection[client] != null
        && g_HugsStatsLoadConnection[client].IsSameConnection(g_hDatabase))
    {
        return;
    }
    // A returning session must not SELECT before the previous session's latest
    // coalesced snapshot has been submitted and completed.
    if (Hugs_HasPendingStatsSave(g_szClientSteamId[client]))
    {
        ScheduleStatsRetry(client);
        return;
    }
    char steamEsc[96];
    if (!Db_Escape(g_hDatabase, g_szClientSteamId[client], steamEsc, sizeof(steamEsc), "Hugs"))
    {
        ScheduleStatsRetry(client);
        return;
    }
    char query[768];
    FormatEx(query, sizeof(query),
        "SELECT hugs_given, hugs_received, feeds_given, feeds_received, rapes_given, rapes_received, "
        ... "last_hugger1, last_hugger2, last_hugger3, last_hugger4, last_hugger5, "
        ... "last_feeder1, last_feeder2, last_feeder3, last_feeder4, last_feeder5, last_rapists "
        ... "FROM %s WHERE steamid = '%s'", HUGS_DB_TABLE, steamEsc);
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientSerial(client));
    pack.WriteString(g_szClientSteamId[client]);
    delete g_HugsStatsLoadConnection[client];
    g_HugsStatsLoadConnection[client] = view_as<Database>(CloneHandle(g_hDatabase));
    g_HugsStatsLoadRequest[client] = pack;
    g_bStatsPending[client] = true;
    SQL_TQuery(g_hDatabase, SQL_OnStatsLoaded, query, pack);
}

public void SQL_OnStatsLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientFromSerial(pack.ReadCell());
    char expectedSteam[32];
    pack.ReadString(expectedSteam, sizeof(expectedSteam));
    bool ownsRequest = client > 0 && g_HugsStatsLoadRequest[client] == pack;
    delete pack;
    if (!ownsRequest)
    {
        return;
    }
    g_HugsStatsLoadRequest[client] = null;
    g_bStatsPending[client] = false;
    delete g_HugsStatsLoadConnection[client];
    g_HugsStatsLoadConnection[client] = null;
    if (!IsHumanClient(client) || !EnsureClientSteamId(client)
        || !StrEqual(expectedSteam, g_szClientSteamId[client]))
    {
        return;
    }
    if (!IsDatabaseReady() || db == null || !db.IsSameConnection(g_hDatabase))
    {
        ScheduleStatsRetry(client);
        return;
    }
    if (error[0] || results == null)
    {
        LogError("[Hugs] Failed to load stats for %s: %s", expectedSteam,
            error[0] ? error : "no result set");
        if (Db_IsTransientError(error))
        {
            ScheduleDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
        }
        ScheduleStatsRetry(client);
        return;
    }

    int values[6];
    char huggers[MAX_HISTORY_ENTRIES][MAX_NAME_LENGTH];
    char feeders[MAX_HISTORY_ENTRIES][MAX_NAME_LENGTH];
    char rapists[HISTORY_STRING_LEN];
    if (results.FetchRow())
    {
        for (int i = 0; i < sizeof(values); i++)
        {
            values[i] = results.FetchInt(i);
        }
        for (int i = 0; i < MAX_HISTORY_ENTRIES; i++)
        {
            results.FetchString(6 + i, huggers[i], sizeof(huggers[]));
            results.FetchString(11 + i, feeders[i], sizeof(feeders[]));
        }
        results.FetchString(16, rapists, sizeof(rapists));
    }
    g_iHugsGiven[client] = values[0];
    g_iHugsReceived[client] = values[1];
    g_iFeedsGiven[client] = values[2];
    g_iFeedsReceived[client] = values[3];
    g_iRapesGiven[client] = values[4];
    g_iRapesReceived[client] = values[5];
    for (int i = 0; i < MAX_HISTORY_ENTRIES; i++)
    {
        strcopy(g_szLastHuggers[client][i], MAX_NAME_LENGTH, huggers[i]);
        strcopy(g_szLastFeeders[client][i], MAX_NAME_LENGTH, feeders[i]);
    }
    strcopy(g_szLastRapists[client], HISTORY_STRING_LEN, rapists);
    g_bStatsLoaded[client] = true;
    CancelStatsRetryTimer(client);
}

void SaveClientStats(int client)
{
    if (!IsHumanClient(client) || !g_bStatsLoaded[client] || !IsDatabaseReady()
        || !EnsureClientSteamId(client))
    {
        return;
    }
    char steamEsc[96], name[MAX_NAME_LENGTH], nameEsc[MAX_NAME_LENGTH * 2 + 1];
    GetClientName(client, name, sizeof(name));
    if (!Db_Escape(g_hDatabase, g_szClientSteamId[client], steamEsc, sizeof(steamEsc), "Hugs")
        || !Db_Escape(g_hDatabase, name, nameEsc, sizeof(nameEsc), "Hugs"))
    {
        return;
    }
    char rapistsEsc[HISTORY_STRING_LEN * 2 + 1];
    char huggerEscaped[MAX_HISTORY_ENTRIES][MAX_NAME_LENGTH * 2 + 1];
    char feederEscaped[MAX_HISTORY_ENTRIES][MAX_NAME_LENGTH * 2 + 1];
    for (int i = 0; i < MAX_HISTORY_ENTRIES; i++)
    {
        if (!Db_Escape(g_hDatabase, g_szLastHuggers[client][i], huggerEscaped[i], sizeof(huggerEscaped[]), "Hugs")
            || !Db_Escape(g_hDatabase, g_szLastFeeders[client][i], feederEscaped[i], sizeof(feederEscaped[]), "Hugs"))
        {
            return;
        }
    }
    if (!Db_Escape(g_hDatabase, g_szLastRapists[client], rapistsEsc, sizeof(rapistsEsc), "Hugs"))
    {
        return;
    }
    HugsStatsSnapshot snapshot;
    FormatEx(snapshot.query, sizeof(snapshot.query),
        "REPLACE INTO %s (steamid, name, hugs_given, hugs_received, feeds_given, feeds_received, rapes_given, rapes_received, "
        ... "last_hugger1, last_hugger2, last_hugger3, last_hugger4, last_hugger5, "
        ... "last_feeder1, last_feeder2, last_feeder3, last_feeder4, last_feeder5, last_rapists) "
        ... "VALUES ('%s', '%s', %d, %d, %d, %d, %d, %d, '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s')",
        HUGS_DB_TABLE, steamEsc, nameEsc, g_iHugsGiven[client], g_iHugsReceived[client],
        g_iFeedsGiven[client], g_iFeedsReceived[client], g_iRapesGiven[client], g_iRapesReceived[client],
        huggerEscaped[0], huggerEscaped[1], huggerEscaped[2], huggerEscaped[3], huggerEscaped[4],
        feederEscaped[0], feederEscaped[1], feederEscaped[2], feederEscaped[3], feederEscaped[4], rapistsEsc);
    snapshot.connection = view_as<Database>(CloneHandle(g_hDatabase));
    if (g_HugsStatsSaveOwners == null)
    {
        g_HugsStatsSaveOwners = new StringMap();
        g_HugsStatsQueuedSaves = new StringMap();
    }
    if (Hugs_HasPendingStatsSave(g_szClientSteamId[client]))
    {
        HugsStatsSnapshot previous;
        if (g_HugsStatsQueuedSaves.GetArray(g_szClientSteamId[client], previous, sizeof(previous)))
        {
            delete previous.connection;
        }
        // Full snapshots subsume previous snapshots; only keep the latest one.
        g_HugsStatsQueuedSaves.SetArray(g_szClientSteamId[client], snapshot, sizeof(snapshot));
        return;
    }
    Hugs_SubmitStatsSnapshot(g_szClientSteamId[client], snapshot);
}

void Hugs_SubmitStatsSnapshot(const char[] steamId, HugsStatsSnapshot snapshot)
{
    DataPack pack = new DataPack();
    pack.WriteString(steamId);
    g_HugsStatsSaveOwners.SetValue(steamId, pack);
    // Query retains the connection; the captured account is independent of slots.
    snapshot.connection.Query(SQL_OnStatsSaved, snapshot.query, pack);
    delete snapshot.connection;
}

public void SQL_OnStatsSaved(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    char steamId[32];
    pack.ReadString(steamId, sizeof(steamId));
    int owner;
    bool ownsRequest = g_HugsStatsSaveOwners != null
        && g_HugsStatsSaveOwners.GetValue(steamId, owner) && owner == view_as<int>(pack);
    delete pack;
    if (!ownsRequest)
    {
        return;
    }
    g_HugsStatsSaveOwners.Remove(steamId);
    if (error[0] || results == null)
    {
        LogError("[Hugs] Failed to save stats for %s: %s", steamId,
            error[0] ? error : "no result set");
        if (Db_IsTransientError(error) && g_hDatabase != null
            && db != null && db.IsSameConnection(g_hDatabase))
        {
            ScheduleDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
        }
    }
    HugsStatsSnapshot next;
    if (g_HugsStatsQueuedSaves.GetArray(steamId, next, sizeof(next)))
    {
        g_HugsStatsQueuedSaves.Remove(steamId);
        Hugs_SubmitStatsSnapshot(steamId, next);
    }
    // Do not replay an ambiguous failed write. This preserves the existing
    // best-effort API; cross-server counters still need a separate delta ledger.
}

public void SQL_OnPrapeSaved(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0])
    {
        LogError("[Hugs] Failed to update rapes_given: %s", error);
        if (Db_IsTransientError(error) && g_hDatabase != null
            && db != null && db.IsSameConnection(g_hDatabase))
        {
            ScheduleDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
        }
    }
}
