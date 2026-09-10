bool StartClanWarAsync(int client, int declaringClanId, int targetClanId, const char[] declarerSteam)
{
    if (!EnsureClanWarsAvailable(client) || declaringClanId <= 0 || targetClanId <= 0 || declaringClanId == targetClanId)
    {
        return false;
    }

    int clanIdA = 0;
    int clanIdB = 0;
    NormalizeClanWarPair(declaringClanId, targetClanId, clanIdA, clanIdB);

    int existingWarId = 0;
    int existingClanIdA = 0;
    int existingClanIdB = 0;
    int existingScoreA = 0;
    int existingScoreB = 0;
    if (GetActiveClanWarByPairCached(declaringClanId, targetClanId, existingWarId, existingClanIdA, existingClanIdB, existingScoreA, existingScoreB))
    {
        return false;
    }

    char escapedDeclarer[SQL_STEAMID64_MAXLEN];
    EscapeSql(declarerSteam, escapedDeclarer, sizeof(escapedDeclarer));

    int now = GetTime();
    char query[2048];
    if (IsMySql())
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO clan_wars (clan_id_a, clan_id_b, declared_by, score_a, score_b, winner_clan_id, status, created_at, expires_at, finished_at) "
            ... "VALUES (%d, %d, '%s', 0, 0, NULL, %d, %d, %d, NULL) "
            ... "ON DUPLICATE KEY UPDATE declared_by = IF(status = %d, declared_by, VALUES(declared_by)), score_a = IF(status = %d, score_a, 0), score_b = IF(status = %d, score_b, 0), winner_clan_id = IF(status = %d, winner_clan_id, NULL), created_at = IF(status = %d, created_at, VALUES(created_at)), expires_at = IF(status = %d, expires_at, VALUES(expires_at)), finished_at = IF(status = %d, finished_at, NULL), status = IF(status = %d, status, VALUES(status))",
            clanIdA,
            clanIdB,
            escapedDeclarer,
            view_as<int>(ClanWarStatus_Active),
            now,
            now + CLAN_WAR_EXPIRE_SECONDS,
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active));
    }
    else
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO clan_wars (clan_id_a, clan_id_b, declared_by, score_a, score_b, winner_clan_id, status, created_at, expires_at, finished_at) "
            ... "VALUES (%d, %d, '%s', 0, 0, NULL, %d, %d, %d, NULL) "
            ... "ON CONFLICT(clan_id_a, clan_id_b) DO UPDATE SET declared_by = CASE WHEN status = %d THEN declared_by ELSE excluded.declared_by END, score_a = CASE WHEN status = %d THEN score_a ELSE 0 END, score_b = CASE WHEN status = %d THEN score_b ELSE 0 END, winner_clan_id = CASE WHEN status = %d THEN winner_clan_id ELSE NULL END, created_at = CASE WHEN status = %d THEN created_at ELSE excluded.created_at END, expires_at = CASE WHEN status = %d THEN expires_at ELSE excluded.expires_at END, finished_at = CASE WHEN status = %d THEN finished_at ELSE NULL END, status = CASE WHEN status = %d THEN status ELSE excluded.status END",
            clanIdA,
            clanIdB,
            escapedDeclarer,
            view_as<int>(ClanWarStatus_Active),
            now,
            now + CLAN_WAR_EXPIRE_SECONDS,
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active),
            view_as<int>(ClanWarStatus_Active));
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(declaringClanId);
    pack.WriteCell(targetClanId);
    pack.WriteCell(clanIdA);
    pack.WriteCell(clanIdB);
    pack.WriteCell(now);
    g_Database.Query(SQL_OnStartClanWarUpsert, query, pack);
    return true;
}

public void SQL_OnStartClanWarUpsert(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int declaringClanId = pack.ReadCell();
    int targetClanId = pack.ReadCell();
    int clanIdA = pack.ReadCell();
    int clanIdB = pack.ReadCell();
    int createdAt = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    if (error[0])
    {
        LogError("[Clans] Failed to start war between %d and %d: %s", clanIdA, clanIdB, error);
        HandleDatabaseConnectionLoss(error);
        if (client > 0 && IsClientInGame(client))
        {
            PrintToChat(client, "[Clans] Failed to declare war.");
        }
        return;
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT id, score_a, score_b, created_at, expires_at, status FROM clan_wars WHERE clan_id_a = %d AND clan_id_b = %d LIMIT 1",
        clanIdA,
        clanIdB);

    DataPack next = new DataPack();
    next.WriteCell(userId);
    next.WriteCell(declaringClanId);
    next.WriteCell(targetClanId);
    next.WriteCell(clanIdA);
    next.WriteCell(clanIdB);
    next.WriteCell(createdAt);
    db.Query(SQL_OnStartClanWarSelected, query, next);
}

public void SQL_OnStartClanWarSelected(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userId = pack.ReadCell();
    int declaringClanId = pack.ReadCell();
    int targetClanId = pack.ReadCell();
    int clanIdA = pack.ReadCell();
    int clanIdB = pack.ReadCell();
    int createdAt = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    if (error[0] || results == null || !results.FetchRow())
    {
        if (error[0])
        {
            LogError("[Clans] Failed to fetch newly started war for pair %d/%d: %s", clanIdA, clanIdB, error);
            HandleDatabaseConnectionLoss(error);
        }
        if (client > 0 && IsClientInGame(client))
        {
            PrintToChat(client, "[Clans] Failed to declare war.");
        }
        return;
    }

    int warId = results.FetchInt(0);
    int scoreA = results.FetchInt(1);
    int scoreB = results.FetchInt(2);
    int rowCreatedAt = results.FetchInt(3);
    int expiresAt = results.FetchInt(4);
    ClanWarStatus status = view_as<ClanWarStatus>(results.FetchInt(5));

    if (status == ClanWarStatus_Active && rowCreatedAt != createdAt)
    {
        int instanceId = 0;
        EnsureClanWarInstanceSync(warId, clanIdA, clanIdB, rowCreatedAt, instanceId);
        UpsertActiveWarCacheEntry(warId, clanIdA, clanIdB, scoreA, scoreB, rowCreatedAt, expiresAt, instanceId);

        if (client > 0 && IsClientInGame(client))
        {
            PrintToChat(client, "[Clans] These clans are already at war.");
        }
        return;
    }

    if (status != ClanWarStatus_Active || rowCreatedAt != createdAt)
    {
        LogError("[Clans] Unexpected war row state after declaring pair %d/%d: status=%d created_at=%d expected_created_at=%d", clanIdA, clanIdB, view_as<int>(status), rowCreatedAt, createdAt);
        if (client > 0 && IsClientInGame(client))
        {
            PrintToChat(client, "[Clans] Failed to declare war.");
        }
        return;
    }

    UpsertActiveWarCacheEntry(warId, clanIdA, clanIdB, 0, 0, createdAt, expiresAt, 0);

    char declaringClanName[CLAN_NAME_MAXLEN + 1];
    char declaringClanTag[CLAN_TAG_STORE_MAXLEN];
    char declaringRepresentative[MAX_NAME_LENGTH * 2];
    char targetClanName[CLAN_NAME_MAXLEN + 1];
    char targetClanTag[CLAN_TAG_STORE_MAXLEN];
    char targetRepresentative[MAX_NAME_LENGTH * 2];
    int onlineCount = 0;

    if (!GetCachedOnlineClanSummary(declaringClanId, declaringClanName, sizeof(declaringClanName), declaringClanTag, sizeof(declaringClanTag), declaringRepresentative, sizeof(declaringRepresentative), onlineCount))
    {
        FormatEx(declaringClanName, sizeof(declaringClanName), "%d", declaringClanId);
        declaringClanTag[0] = '\0';
    }
    if (!GetCachedOnlineClanSummary(targetClanId, targetClanName, sizeof(targetClanName), targetClanTag, sizeof(targetClanTag), targetRepresentative, sizeof(targetRepresentative), onlineCount))
    {
        FormatEx(targetClanName, sizeof(targetClanName), "%d", targetClanId);
        targetClanTag[0] = '\0';
    }

    char declaringHistoryLabel[96];
    char targetHistoryLabel[96];
    char declaringAnnounceLabel[96];
    char targetAnnounceLabel[96];
    BuildClanHistoryTagLabel(declaringClanTag, declaringClanName, declaringHistoryLabel, sizeof(declaringHistoryLabel));
    BuildClanHistoryTagLabel(targetClanTag, targetClanName, targetHistoryLabel, sizeof(targetHistoryLabel));
    BuildClanWarTagLabel(declaringClanTag, declaringClanName, declaringAnnounceLabel, sizeof(declaringAnnounceLabel));
    BuildClanWarTagLabel(targetClanTag, targetClanName, targetAnnounceLabel, sizeof(targetAnnounceLabel));

    AddClanHistoryEntry(declaringClanId, "Declared war on %s", targetHistoryLabel);
    AddClanHistoryEntry(targetClanId, "War declared by %s", declaringHistoryLabel);
    CPrintToChatAll("{gold}[Clans]{default} %s has declared war on %s!", declaringAnnounceLabel, targetAnnounceLabel);

    if (client > 0 && IsClientInGame(client))
    {
        PrintToChat(client, "[Clans] War declared.");
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

    DataPack next = new DataPack();
    next.WriteCell(warId);
    next.WriteCell(createdAt);
    db.Query(SQL_OnStartClanWarInstanceInserted, query, next);
}

public void SQL_OnStartClanWarInstanceInserted(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int warId = pack.ReadCell();
    int createdAt = pack.ReadCell();
    delete pack;

    if (error[0])
    {
        LogError("[Clans] Failed to create war instance for %d/%d: %s", warId, createdAt, error);
        HandleDatabaseConnectionLoss(error);
        return;
    }

    char query[192];
    FormatEx(query, sizeof(query), "SELECT id FROM clan_war_instances WHERE war_id = %d AND created_at = %d LIMIT 1", warId, createdAt);

    DataPack next = new DataPack();
    next.WriteCell(warId);
    next.WriteCell(createdAt);
    db.Query(SQL_OnStartClanWarInstanceSelected, query, next);
}

public void SQL_OnStartClanWarInstanceSelected(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int warId = pack.ReadCell();
    int createdAt = pack.ReadCell();
    delete pack;

    if (error[0] || results == null || !results.FetchRow())
    {
        if (error[0])
        {
            LogError("[Clans] Failed to fetch war instance for %d/%d: %s", warId, createdAt, error);
            HandleDatabaseConnectionLoss(error);
        }
        return;
    }

    int index = FindActiveWarIndexByWarId(warId);
    if (index == -1)
    {
        return;
    }

    ActiveClanWar war;
    g_hActiveWars.GetArray(index, war);
    if (war.createdAt == createdAt)
    {
        war.instanceId = results.FetchInt(0);
        g_hActiveWars.SetArray(index, war);
    }
}

