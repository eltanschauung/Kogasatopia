bool GetClanWarInstanceIdSync(int warId, int createdAt, int &instanceId)
{
    instanceId = 0;

    if (!EnsureDatabaseReady() || warId <= 0 || createdAt <= 0)
    {
        return false;
    }

    char query[192];
    FormatEx(query, sizeof(query),
        "SELECT id FROM clan_war_instances WHERE war_id = %d AND created_at = %d LIMIT 1",
        warId,
        createdAt);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to fetch war instance %d/%d: %s", warId, createdAt, error);
        HandleDatabaseConnectionLoss(error);
        delete results;
        return false;
    }

    if (results.FetchRow())
    {
        instanceId = results.FetchInt(0);
    }

    delete results;
    return (instanceId > 0);
}

bool EnsureClanWarInstanceSync(int warId, int clanIdA, int clanIdB, int createdAt, int &instanceId)
{
    instanceId = 0;

    if (!EnsureDatabaseReady() || warId <= 0 || clanIdA <= 0 || clanIdB <= 0 || createdAt <= 0)
    {
        return false;
    }

    if (GetClanWarInstanceIdSync(warId, createdAt, instanceId))
    {
        return true;
    }

    if (!EnsureDatabaseReady() || g_Database == null)
    {
        return false;
    }

    char query[384];
    FormatEx(query, sizeof(query),
        "INSERT INTO clan_war_instances (war_id, clan_id_a, clan_id_b, score_a, score_b, winner_clan_id, status, created_at, finished_at) "
        ... "VALUES (%d, %d, %d, 0, 0, NULL, %d, %d, NULL)",
        warId,
        clanIdA,
        clanIdB,
        view_as<int>(ClanWarStatus_Active),
        createdAt);

    if (!SQL_FastQuery(g_Database, query))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to create war instance for %d/%d: %s", warId, createdAt, error);
        HandleDatabaseConnectionLoss(error);
        return false;
    }

    return GetClanWarInstanceIdSync(warId, createdAt, instanceId);
}

void UpdateClanWarInstanceFinalState(int instanceId, int scoreA, int scoreB, int winnerClanId, ClanWarStatus status, int finishedAt)
{
    if (instanceId <= 0 || !EnsureDatabaseReady())
    {
        return;
    }

    char winnerValue[16];
    if (winnerClanId > 0)
    {
        IntToString(winnerClanId, winnerValue, sizeof(winnerValue));
    }
    else
    {
        strcopy(winnerValue, sizeof(winnerValue), "NULL");
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "UPDATE clan_war_instances SET score_a = %d, score_b = %d, winner_clan_id = %s, status = %d, finished_at = %d "
        ... "WHERE id = %d",
        scoreA,
        scoreB,
        winnerValue,
        view_as<int>(status),
        finishedAt,
        instanceId);

    g_Database.Query(SQL_GenericQueryCallback, query);
}

void QueueClanWarKillDelta(int warInstanceId, int clanId, const char[] steamid64, int kills = 1, int currencyStolen = 0)
{
    if (warInstanceId <= 0 || clanId <= 0 || !steamid64[0] || kills <= 0)
    {
        return;
    }

    if (g_hPendingClanWarKillDeltas == null)
    {
        g_hPendingClanWarKillDeltas = new ArrayList(sizeof(PendingClanWarKillDelta));
    }

    PendingClanWarKillDelta delta;
    for (int i = 0; i < g_hPendingClanWarKillDeltas.Length; i++)
    {
        g_hPendingClanWarKillDeltas.GetArray(i, delta);
        if (delta.warInstanceId != warInstanceId || delta.clanId != clanId || !StrEqual(delta.steamid64, steamid64, false))
        {
            continue;
        }

        delta.kills += kills;
        delta.currencyStolen += currencyStolen;
        g_hPendingClanWarKillDeltas.SetArray(i, delta);
        return;
    }

    delta.warInstanceId = warInstanceId;
    delta.clanId = clanId;
    delta.kills = kills;
    delta.currencyStolen = currencyStolen;
    strcopy(delta.steamid64, sizeof(delta.steamid64), steamid64);
    g_hPendingClanWarKillDeltas.PushArray(delta);
}

void RecordClanWarKill(int warInstanceId, int clanId, const char[] steamid64, int currencyStolen = 0)
{
    QueueClanWarKillDelta(warInstanceId, clanId, steamid64, 1, currencyStolen);
}

bool FlushPendingClanWarKillWritesSync()
{
    if (!EnsureDatabaseReady() || g_hPendingClanWarKillDeltas == null || g_bClanWarKillFlushInFlight)
    {
        return false;
    }

    if (g_hPendingClanWarKillDeltas.Length <= 0)
    {
        return true;
    }

    ArrayList batch = g_hPendingClanWarKillDeltas;
    g_hPendingClanWarKillDeltas = new ArrayList(sizeof(PendingClanWarKillDelta));
    g_bClanWarKillFlushInFlight = true;
    FlushNextClanWarKillDelta(batch, 0);
    return true;
}

void RequeueClanWarKillBatch(ArrayList batch, int startIndex)
{
    if (batch == null)
    {
        return;
    }

    PendingClanWarKillDelta delta;
    for (int i = startIndex; i < batch.Length; i++)
    {
        batch.GetArray(i, delta);
        QueueClanWarKillDelta(delta.warInstanceId, delta.clanId, delta.steamid64, delta.kills, delta.currencyStolen);
    }
}

void FlushNextClanWarKillDelta(ArrayList batch, int index)
{
    if (batch == null)
    {
        g_bClanWarKillFlushInFlight = false;
        return;
    }

    if (!EnsureDatabaseReady())
    {
        RequeueClanWarKillBatch(batch, index);
        delete batch;
        g_bClanWarKillFlushInFlight = false;
        return;
    }

    if (index >= batch.Length)
    {
        delete batch;
        g_bClanWarKillFlushInFlight = false;
        return;
    }

    PendingClanWarKillDelta delta;
    batch.GetArray(index, delta);

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(delta.steamid64, escapedSteam, sizeof(escapedSteam));

    char query[512];
    if (IsMySql())
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO clan_war_member_kills (war_instance_id, clan_id, steamid64, kills, currency_stolen) "
            ... "VALUES (%d, %d, '%s', %d, %d) "
            ... "ON DUPLICATE KEY UPDATE kills = kills + %d, currency_stolen = currency_stolen + %d, clan_id = VALUES(clan_id)",
            delta.warInstanceId,
            delta.clanId,
            escapedSteam,
            delta.kills,
            delta.currencyStolen,
            delta.kills,
            delta.currencyStolen);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO clan_war_member_kills (war_instance_id, clan_id, steamid64, kills, currency_stolen) "
            ... "VALUES (%d, %d, '%s', %d, %d) "
            ... "ON CONFLICT(war_instance_id, steamid64) DO UPDATE SET kills = clan_war_member_kills.kills + %d, currency_stolen = clan_war_member_kills.currency_stolen + %d, clan_id = excluded.clan_id",
            delta.warInstanceId,
            delta.clanId,
            escapedSteam,
            delta.kills,
            delta.currencyStolen,
            delta.kills,
            delta.currencyStolen);
    }

    DataPack pack = new DataPack();
    pack.WriteCell(batch);
    pack.WriteCell(index);
    g_Database.Query(SQL_OnClanWarKillDeltaWritten, query, pack);
}

public void SQL_OnClanWarKillDeltaWritten(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    ArrayList batch = view_as<ArrayList>(pack.ReadCell());
    int index = pack.ReadCell();
    delete pack;

    PendingClanWarKillDelta delta;
    batch.GetArray(index, delta);

    if (error[0])
    {
        LogError("[Clans] Failed to persist war kill delta for instance %d/%s: %s", delta.warInstanceId, delta.steamid64, error);
        HandleDatabaseConnectionLoss(error);
        RequeueClanWarKillBatch(batch, index);
        delete batch;
        g_bClanWarKillFlushInFlight = false;
        return;
    }

    FlushNextClanWarKillDelta(batch, index + 1);
}

