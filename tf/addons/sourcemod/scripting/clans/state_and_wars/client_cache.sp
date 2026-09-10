void RebuildClanIdCache()
{
    g_bClanIdCacheReady = false;

    if (!EnsureDatabaseReady() || g_Database == null)
    {
        return;
    }

    char query[128];
    FormatEx(query, sizeof(query), "SELECT steamid64, clan_id FROM clan_members");
    g_Database.Query(SQL_OnClanIdCacheRebuilt, query);
}

public void SQL_OnClanIdCacheRebuilt(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0])
    {
        LogError("[Clans] Failed to rebuild clan id cache: %s", error);
        HandleDatabaseConnectionLoss(error);
        return;
    }

    if (!HasUsableResultSet(results))
    {
        LogError("[Clans] Failed to rebuild clan id cache: query returned no result set.");
        return;
    }

    if (g_hClanIdCache != null)
    {
        delete g_hClanIdCache;
    }

    g_hClanIdCache = new StringMap();

    char steamid64[STEAMID64_MAXLEN];
    while (results.FetchRow())
    {
        results.FetchString(0, steamid64, sizeof(steamid64));
        TrimString(steamid64);
        if (!steamid64[0])
        {
            continue;
        }

        g_hClanIdCache.SetValue(steamid64, results.FetchInt(1), true);
    }

    g_bClanIdCacheReady = true;
}

bool GetCachedClanIdForSteam64(const char[] steamid64, int &clanId)
{
    clanId = 0;
    return (g_hClanIdCache != null && steamid64[0] != '\0' && g_hClanIdCache.GetValue(steamid64, clanId));
}

bool GetLoadedClientClanId(int client, int &clanId)
{
    clanId = 0;

    if (!Client_IsHumanInGame(client))
    {
        return false;
    }

    if (!g_bClientClanLoaded[client])
    {
        return false;
    }

    clanId = g_iClientClanId[client];
    return true;
}

bool ResolveClientClanIdForWarScoring(int client, int &clanId)
{
    clanId = 0;

    if (GetLoadedClientClanId(client, clanId))
    {
        return true;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        return false;
    }

    if (GetCachedClanIdForSteam64(steamid64, clanId))
    {
        return true;
    }

    if (!EnsureDatabaseReady() || g_Database == null)
    {
        return false;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[160];
    FormatEx(query, sizeof(query), "SELECT clan_id FROM clan_members WHERE steamid64 = '%s' LIMIT 1", escapedSteam);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to resolve scoring clan id for %N: %s", client, error);
        HandleDatabaseConnectionLoss(error);
        delete results;
        return false;
    }

    if (results.FetchRow())
    {
        clanId = results.FetchInt(0);
        UpdateClanIdCacheEntry(steamid64, clanId);
    }

    delete results;
    return true;
}

void UpdateClanIdCacheEntry(const char[] steamid64, int clanId)
{
    if (steamid64[0] == '\0')
    {
        return;
    }

    if (g_hClanIdCache == null)
    {
        g_hClanIdCache = new StringMap();
    }

    if (clanId > 0)
    {
        g_hClanIdCache.SetValue(steamid64, clanId, true);
    }
    else
    {
        g_hClanIdCache.Remove(steamid64);
    }
}

void RemoveClanIdCacheMembers(int clanId)
{
    if (clanId <= 0 || g_hClanIdCache == null)
    {
        return;
    }

    StringMapSnapshot snap = g_hClanIdCache.Snapshot();
    if (snap == null)
    {
        return;
    }

    char steamid64[STEAMID64_MAXLEN];
    int cachedClanId = 0;
    for (int i = 0; i < snap.Length; i++)
    {
        snap.GetKey(i, steamid64, sizeof(steamid64));
        if (!g_hClanIdCache.GetValue(steamid64, cachedClanId) || cachedClanId != clanId)
        {
            continue;
        }

        g_hClanIdCache.Remove(steamid64);
    }

    delete snap;
}

int GetSameTeamClanMemberCount(int client, int team = 0)
{
    if (!Client_IsHumanInGame(client))
    {
        return 0;
    }

    if (team <= 1)
    {
        team = GetClientTeam(client);
    }

    if (team <= 1)
    {
        return 0;
    }

    int clanId = 0;
    if (!ResolveClientClanIdForTeamGuard(client, clanId))
    {
        return 0;
    }

    if (clanId <= 0)
    {
        return 0;
    }

    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!Client_IsHumanInGame(i) || GetClientTeam(i) != team)
        {
            continue;
        }

        int currentClanId = 0;
        if (!ResolveClientClanIdForTeamGuard(i, currentClanId))
        {
            continue;
        }

        if (currentClanId == clanId)
        {
            count++;
        }
    }

    return count;
}

bool ResolveClientClanIdForTeamGuard(int client, int &clanId)
{
    clanId = 0;

    if (!Client_IsHumanInGame(client))
    {
        return false;
    }

    if (GetLoadedClientClanId(client, clanId))
    {
        return true;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        return false;
    }

    if (GetCachedClanIdForSteam64(steamid64, clanId))
    {
        return true;
    }

    if (g_bClanIdCacheReady)
    {
        return true;
    }

    if (!g_bClientClanLoadPending[client])
    {
        RequestClientClanIdLoad(client);
    }

    return false;
}

void RequestClientClanIdLoad(int client)
{
    if (!EnsureDatabaseReady() || !Client_IsHumanInGame(client))
    {
        return;
    }

    if (g_bClientClanLoadPending[client])
    {
        return;
    }

    char steamid64[STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT cm.clan_id, cm.rank, c.name, COALESCE(c.tag, '') "
        ... "FROM clan_members cm "
        ... "INNER JOIN clans c ON c.id = cm.clan_id "
        ... "WHERE cm.steamid64 = '%s' LIMIT 1",
        escapedSteam);

    g_bClientClanLoadPending[client] = true;
    g_Database.Query(SQL_OnClientClanIdLoaded, query, GetClientUserId(client));
}

public void SQL_OnClientClanIdLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    int client = GetClientOfUserId(data);
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    g_bClientClanLoadPending[client] = false;

    if (!IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    if (error[0])
    {
        LogError("[Clans] Failed to load clan id for %N: %s", client, error);
        HandleDatabaseConnectionLoss(error);
        return;
    }

    g_iClientClanId[client] = 0;
    g_ClientClanRank[client] = ClanRank_Member;
    g_sClientClanName[client][0] = '\0';
    g_sClientClanTag[client][0] = '\0';

    if (HasUsableResultSet(results) && results.FetchRow())
    {
        g_iClientClanId[client] = results.FetchInt(0);
        g_ClientClanRank[client] = view_as<ClanRank>(results.FetchInt(1));
        results.FetchString(2, g_sClientClanName[client], sizeof(g_sClientClanName[]));
        results.FetchString(3, g_sClientClanTag[client], sizeof(g_sClientClanTag[]));
    }
    g_bClientClanLoaded[client] = true;

    char steamid64[STEAMID64_MAXLEN];
    if (GetClientSteam64(client, steamid64, sizeof(steamid64)))
    {
        UpdateClanIdCacheEntry(steamid64, g_iClientClanId[client]);
    }
}

bool GetLoadedClientClanContext(int client, char[] steamid64, int steamidLen, int &clanId, ClanRank &rank, char[] clanName, int clanNameLen, char[] clanTag, int clanTagLen)
{
    steamid64[0] = '\0';
    clanId = 0;
    rank = ClanRank_Member;
    clanName[0] = '\0';
    clanTag[0] = '\0';

    if (!Client_IsHumanInGame(client) || !g_bClientClanLoaded[client] || !GetClientSteam64(client, steamid64, steamidLen))
    {
        return false;
    }

    clanId = g_iClientClanId[client];
    rank = g_ClientClanRank[client];
    strcopy(clanName, clanNameLen, g_sClientClanName[client]);
    strcopy(clanTag, clanTagLen, g_sClientClanTag[client]);
    return (clanId <= 0 || clanName[0] != '\0');
}

bool GetCachedOnlineClanSummary(int clanId, char[] clanName, int clanNameLen, char[] clanTag, int clanTagLen, char[] representativeName, int representativeNameLen, int &onlineCount)
{
    clanName[0] = '\0';
    clanTag[0] = '\0';
    representativeName[0] = '\0';
    onlineCount = 0;

    ClanRank bestRank = ClanRank_Member;
    bool hasRepresentative = false;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!Client_IsHumanInGame(client) || !g_bClientClanLoaded[client] || g_iClientClanId[client] != clanId)
        {
            continue;
        }

        onlineCount++;
        if (!clanName[0])
        {
            strcopy(clanName, clanNameLen, g_sClientClanName[client]);
            strcopy(clanTag, clanTagLen, g_sClientClanTag[client]);
        }

        if (!hasRepresentative || g_ClientClanRank[client] > bestRank)
        {
            GetClientName(client, representativeName, representativeNameLen);
            bestRank = g_ClientClanRank[client];
            hasRepresentative = true;
        }
    }

    return clanName[0] != '\0';
}

void SetClientClanIdBySteam64(const char[] steamid64, int clanId)
{
    UpdateClanIdCacheEntry(steamid64, clanId);

    char currentSteam[STEAMID64_MAXLEN];

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!Client_IsHumanInGame(client))
        {
            continue;
        }

        if (!GetClientSteam64(client, currentSteam, sizeof(currentSteam)))
        {
            continue;
        }

        if (!StrEqual(currentSteam, steamid64, false))
        {
            continue;
        }

        g_iClientClanId[client] = clanId;
        g_bClientClanLoaded[client] = true;
        g_bClientClanLoadPending[client] = false;
        g_ClientClanRank[client] = ClanRank_Member;
        g_sClientClanName[client][0] = '\0';
        g_sClientClanTag[client][0] = '\0';

        if (clanId > 0)
        {
            /* Refresh the extended context cache asynchronously. */
            g_bClientClanLoaded[client] = false;
            RequestClientClanIdLoad(client);
            RequestClientClanTagsLoad(client, true);
        }
        else
        {
            ClearClientClanTagsCache(client, true);
        }
    }
}

void ClearConnectedClanId(int clanId)
{
    if (clanId <= 0)
    {
        return;
    }

    RemoveClanIdCacheMembers(clanId);

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!Client_IsHumanInGame(client))
        {
            continue;
        }

        if (g_iClientClanId[client] != clanId)
        {
            continue;
        }

        g_iClientClanId[client] = 0;
        g_bClientClanLoaded[client] = true;
        g_bClientClanLoadPending[client] = false;
        g_ClientClanRank[client] = ClanRank_Member;
        g_sClientClanName[client][0] = '\0';
        g_sClientClanTag[client][0] = '\0';
        ClearClientClanTagsCache(client, true);
    }
}

