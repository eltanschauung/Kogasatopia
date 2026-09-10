bool GetClanInfoSummarySync(int clanId, char[] clanName, int clanNameLen, char[] clanTag, int clanTagLen, char[] ownerName, int ownerNameLen, int &memberCount)
{
    clanName[0] = '\0';
    clanTag[0] = '\0';
    ownerName[0] = '\0';
    memberCount = 0;

    if (!EnsureDatabaseReady() || clanId <= 0)
    {
        return false;
    }

    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT c.name, COALESCE(c.tag, ''), c.owner, ("
        ... "SELECT COUNT(1) FROM clan_members cm WHERE cm.clan_id = c.id"
        ... ") + ("
        ... "SELECT COUNT(1) "
        ... "FROM clan_members cm_child "
        ... "INNER JOIN clan_relations cr ON cr.clan_id_a = cm_child.clan_id "
        ... "WHERE cr.relation_type = 3 AND cr.clan_id_b = c.id"
        ... ") AS member_count "
        ... "FROM clans c "
        ... "WHERE c.id = %d "
        ... "LIMIT 1",
        clanId);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to fetch clan summary for %d: %s", clanId, error);
        HandleDatabaseConnectionLoss(error);
        delete results;
        return false;
    }

    if (!results.FetchRow())
    {
        delete results;
        return false;
    }

    char ownerSteam[STEAMID64_MAXLEN];
    results.FetchString(0, clanName, clanNameLen);
    results.FetchString(1, clanTag, clanTagLen);
    results.FetchString(2, ownerSteam, sizeof(ownerSteam));
    memberCount = results.FetchInt(3);
    delete results;

    ResolvePlayerDisplayName(ownerSteam, ownerName, ownerNameLen);
    return true;
}

bool GetClientClanContextSync(int client, char[] steamid64, int steamidLen, int &clanId, ClanRank &rank, char[] clanName, int clanNameLen, char[] clanTag, int clanTagLen)
{
    steamid64[0] = '\0';
    clanId = 0;
    rank = ClanRank_Member;
    clanName[0] = '\0';
    clanTag[0] = '\0';

    if (!EnsureDatabaseReady() || !GetClientSteam64(client, steamid64, steamidLen))
    {
        return false;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT c.id, c.name, COALESCE(c.tag, ''), cm.rank "
        ... "FROM clans c "
        ... "INNER JOIN clan_members cm ON cm.clan_id = c.id "
        ... "WHERE cm.steamid64 = '%s' "
        ... "LIMIT 1",
        escapedSteam);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to fetch client clan context for %N: %s", client, error);
        HandleDatabaseConnectionLoss(error);
        delete results;
        return false;
    }

    if (!results.FetchRow())
    {
        delete results;
        return true;
    }

    clanId = results.FetchInt(0);
    results.FetchString(1, clanName, clanNameLen);
    results.FetchString(2, clanTag, clanTagLen);
    rank = view_as<ClanRank>(results.FetchInt(3));
    delete results;
    return true;
}

bool GetActiveClanWarForClanSync(int clanId, int &warId, int &clanIdA, int &clanIdB, int &scoreA, int &scoreB)
{
    if (GetActiveClanWarForClanCached(clanId, warId, clanIdA, clanIdB, scoreA, scoreB))
    {
        return true;
    }

    if (g_bActiveWarCacheReady)
    {
        return false;
    }

    warId = 0;
    clanIdA = 0;
    clanIdB = 0;
    scoreA = 0;
    scoreB = 0;

    if (!EnsureDatabaseReady() || clanId <= 0)
    {
        return false;
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT id, clan_id_a, clan_id_b, score_a, score_b "
        ... "FROM clan_wars "
        ... "WHERE status = %d AND expires_at > %d AND (clan_id_a = %d OR clan_id_b = %d) "
        ... "LIMIT 1",
        view_as<int>(ClanWarStatus_Active),
        GetTime(),
        clanId,
        clanId);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to fetch active war for clan %d: %s", clanId, error);
        HandleDatabaseConnectionLoss(error);
        delete results;
        return false;
    }

    if (!results.FetchRow())
    {
        delete results;
        return false;
    }

    warId = results.FetchInt(0);
    clanIdA = results.FetchInt(1);
    clanIdB = results.FetchInt(2);
    scoreA = results.FetchInt(3);
    scoreB = results.FetchInt(4);
    delete results;
    return (warId > 0);
}

int GetPendingClanWarStolenTotal(int warInstanceId, int clanId)
{
    if (g_hPendingClanWarKillDeltas == null || warInstanceId <= 0 || clanId <= 0)
    {
        return 0;
    }

    int total = 0;
    PendingClanWarKillDelta delta;
    for (int i = 0; i < g_hPendingClanWarKillDeltas.Length; i++)
    {
        g_hPendingClanWarKillDeltas.GetArray(i, delta);
        if (delta.warInstanceId == warInstanceId && delta.clanId == clanId)
        {
            total += delta.currencyStolen;
        }
    }

    return total;
}

int GetClanWarStolenTotalSync(int warInstanceId, int clanId)
{
    int total = GetPendingClanWarStolenTotal(warInstanceId, clanId);
    if (!EnsureDatabaseReady() || warInstanceId <= 0 || clanId <= 0)
    {
        return total;
    }

    char query[192];
    FormatEx(query, sizeof(query),
        "SELECT COALESCE(SUM(currency_stolen), 0) FROM clan_war_member_kills WHERE war_instance_id = %d AND clan_id = %d",
        warInstanceId,
        clanId);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to fetch clan war stolen total: %s", error);
        delete results;
        return total;
    }

    if (results.FetchRow())
    {
        total += results.FetchInt(0);
    }
    delete results;
    return total;
}

bool GetClanWarRedeclareCooldownSync(int declaringClanId, int targetClanId, int &secondsLeft)
{
    secondsLeft = 0;
    if (!EnsureDatabaseReady() || declaringClanId <= 0 || targetClanId <= 0 || declaringClanId == targetClanId)
    {
        return false;
    }

    int clanIdA = 0;
    int clanIdB = 0;
    NormalizeClanWarPair(declaringClanId, targetClanId, clanIdA, clanIdB);

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT COALESCE(finished_at, 0) FROM clan_wars WHERE clan_id_a = %d AND clan_id_b = %d LIMIT 1",
        clanIdA,
        clanIdB);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to fetch clan war redeclare cooldown for pair %d/%d: %s", clanIdA, clanIdB, error);
        HandleDatabaseConnectionLoss(error);
        delete results;
        return false;
    }

    if (!results.FetchRow())
    {
        delete results;
        return false;
    }

    int finishedAt = results.FetchInt(0);
    delete results;

    if (finishedAt <= 0)
    {
        return false;
    }

    secondsLeft = (finishedAt + CLAN_WAR_REDECLARE_COOLDOWN_SECONDS) - GetTime();
    return secondsLeft > 0;
}

void GetClanWarTargetCooldownLabel(int targetClanId, char[] buffer, int maxlen)
{
    if (targetClanId <= 0 || maxlen <= 0)
    {
        return;
    }

    buffer[0] = '\0';

    char clanName[CLAN_NAME_MAXLEN + 1];
    char clanTag[CLAN_TAG_STORE_MAXLEN];
    char representativeName[MAX_NAME_LENGTH * 2];
    int onlineCount = 0;
    if (GetCachedOnlineClanSummary(targetClanId, clanName, sizeof(clanName), clanTag, sizeof(clanTag), representativeName, sizeof(representativeName), onlineCount))
    {
        BuildClanDisplayTag(clanTag, buffer, maxlen);
        if (!buffer[0])
        {
            strcopy(buffer, maxlen, clanName);
        }
        return;
    }

    FormatEx(clanName, sizeof(clanName), "%d", targetClanId);
    clanTag[0] = '\0';

    if (EnsureDatabaseReady())
    {
        char query[128];
        FormatEx(query, sizeof(query), "SELECT name, COALESCE(tag, '') FROM clans WHERE id = %d LIMIT 1", targetClanId);

        DBResultSet results = SQL_Query(g_Database, query);
        if (HasUsableResultSet(results) && results.FetchRow())
        {
            results.FetchString(0, clanName, sizeof(clanName));
            results.FetchString(1, clanTag, sizeof(clanTag));
        }
        delete results;
    }

    BuildClanDisplayTag(clanTag, buffer, maxlen);
    if (!buffer[0])
    {
        strcopy(buffer, maxlen, clanName);
    }
}

