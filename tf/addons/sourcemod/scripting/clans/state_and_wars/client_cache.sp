/**
 * Membership reads never block a gameplay callback. SQL owns request packs;
 * clearing an ownership slot invalidates a request without freeing its context.
 */
Database g_ClanCacheConnection = null;
DataPack g_ClanIdRebuildRequest = null;
DataPack g_ClanClientLoadRequest[MAXPLAYERS + 1];
int g_ClanClientLoadSerial[MAXPLAYERS + 1];
int g_ClanMembershipRevision = 0;
int g_ClanMembershipMutationVersion = 0;
bool g_ClanIdRebuildAgain = false;

bool ClanCache_UseCurrentConnection()
{
    if (!EnsureDatabaseReady() || g_Database == null)
    {
        return false;
    }
    if (g_ClanCacheConnection != null
        && g_ClanCacheConnection.IsSameConnection(g_Database))
    {
        return true;
    }

    delete g_ClanCacheConnection;
    g_ClanCacheConnection = view_as<Database>(CloneHandle(g_Database));
    g_ClanIdRebuildRequest = null;
    g_ClanIdRebuildAgain = false;
    g_ClanMembershipRevision++;
    g_bClanIdCacheReady = false;
    if (g_hClanIdCache != null)
    {
        g_hClanIdCache.Clear();
    }
    for (int client = 1; client <= MaxClients; client++)
    {
        g_ClanClientLoadRequest[client] = null;
        g_bClientClanLoadPending[client] = false;
        g_bClientClanLoaded[client] = false;
    }
    return true;
}

bool ClanCache_IsCurrentConnection(Database db)
{
    return db != null && g_Database != null && g_bDatabaseReady
        && db.IsSameConnection(g_Database);
}

void RebuildClanIdCache()
{
    if (!ClanCache_UseCurrentConnection())
    {
        g_bClanIdCacheReady = false;
        return;
    }
    if (g_ClanIdRebuildRequest != null)
    {
        g_ClanIdRebuildAgain = true;
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(g_ClanMembershipRevision);
    g_ClanIdRebuildRequest = pack;
    g_Database.Query(SQL_OnClanIdCacheRebuilt,
        "SELECT steamid64, clan_id FROM clan_members", pack);
}

public void SQL_OnClanIdCacheRebuilt(Database db, DBResultSet results,
    const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    bool ownsRequest = pack == g_ClanIdRebuildRequest;
    pack.Reset();
    int revision = pack.ReadCell();
    delete pack;
    if (!ownsRequest)
    {
        return;
    }
    g_ClanIdRebuildRequest = null;
    bool reload = g_ClanIdRebuildAgain || revision != g_ClanMembershipRevision;
    g_ClanIdRebuildAgain = false;
    if (!ClanCache_IsCurrentConnection(db))
    {
        RebuildClanIdCache();
        return;
    }
    if (error[0] || !HasUsableResultSet(results))
    {
        LogError("[Clans] Failed to rebuild clan id cache: %s",
            error[0] ? error : "no result set");
        HandleDatabaseConnectionLoss(error);
        return;
    }
    if (reload)
    {
        // A membership mutation committed after this SELECT was submitted.
        RebuildClanIdCache();
        return;
    }

    StringMap staged = new StringMap();
    char steamid64[STEAMID64_MAXLEN];
    while (results.FetchRow())
    {
        results.FetchString(0, steamid64, sizeof(steamid64));
        TrimString(steamid64);
        if (steamid64[0])
        {
            staged.SetValue(steamid64, results.FetchInt(1));
        }
    }
    delete g_hClanIdCache;
    g_hClanIdCache = staged;
    g_bClanIdCacheReady = true;
}

bool GetCachedClanIdForSteam64(const char[] steamid64, int &clanId)
{
    clanId = 0;
    return g_hClanIdCache != null && steamid64[0] != '\0'
        && g_hClanIdCache.GetValue(steamid64, clanId);
}

bool GetLoadedClientClanId(int client, int &clanId)
{
    clanId = 0;
    if (!Client_IsHumanInGame(client) || !g_bClientClanLoaded[client])
    {
        return false;
    }
    clanId = g_iClientClanId[client];
    return true;
}

bool ResolveClientClanIdForWarScoring(int client, int &clanId)
{
    // A cold cache used to issue SQL_Query in the death-event path. Queue a
    // bounded asynchronous load instead; unknown membership fails closed.
    return ResolveClientClanIdForTeamGuard(client, clanId);
}

void UpdateClanIdCacheEntry(const char[] steamid64, int clanId)
{
    if (!steamid64[0])
    {
        return;
    }
    if (g_hClanIdCache == null)
    {
        g_hClanIdCache = new StringMap();
    }
    int previous;
    if (!g_hClanIdCache.GetValue(steamid64, previous) || previous != clanId)
    {
        g_ClanMembershipRevision++;
    }
    // Cache a confirmed absence too, avoiding repeated reads for non-members.
    g_hClanIdCache.SetValue(steamid64, clanId > 0 ? clanId : 0);
}

void RemoveClanIdCacheMembers(int clanId)
{
    g_ClanMembershipMutationVersion++;
    if (clanId <= 0 || g_hClanIdCache == null)
    {
        return;
    }
    g_ClanMembershipRevision++;
    StringMapSnapshot snapshot = g_hClanIdCache.Snapshot();
    char steamid64[STEAMID64_MAXLEN];
    int cachedId;
    for (int i = 0, count = snapshot.Length; i < count; i++)
    {
        snapshot.GetKey(i, steamid64, sizeof(steamid64));
        if (g_hClanIdCache.GetValue(steamid64, cachedId) && cachedId == clanId)
        {
            g_hClanIdCache.SetValue(steamid64, 0);
        }
    }
    delete snapshot;
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
    int clanId;
    if (team <= 1 || !ResolveClientClanIdForTeamGuard(client, clanId) || clanId <= 0)
    {
        return 0;
    }
    int count = 0;
    for (int other = 1; other <= MaxClients; other++)
    {
        if (!Client_IsHumanInGame(other) || GetClientTeam(other) != team)
        {
            continue;
        }
        int otherClan;
        if (ResolveClientClanIdForTeamGuard(other, otherClan) && otherClan == clanId)
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
    if (GetCachedClanIdForSteam64(steamid64, clanId) || g_bClanIdCacheReady)
    {
        return true;
    }
    RequestClientClanIdLoad(client);
    return false;
}

void RequestClientClanIdLoad(int client)
{
    if (!Client_IsHumanInGame(client) || !ClanCache_UseCurrentConnection())
    {
        return;
    }
    int serial = GetClientSerial(client);
    if (g_bClientClanLoadPending[client] && g_ClanClientLoadRequest[client] != null
        && g_ClanClientLoadSerial[client] == serial)
    {
        return;
    }
    char steamid64[STEAMID64_MAXLEN];
    char escapedSteam[SQL_STEAMID64_MAXLEN];
    if (!GetClientSteam64(client, steamid64, sizeof(steamid64))
        || !g_Database.Escape(steamid64, escapedSteam, sizeof(escapedSteam)))
    {
        return;
    }
    char query[384];
    FormatEx(query, sizeof(query),
        "SELECT cm.clan_id, cm.rank, c.name, COALESCE(c.tag, '') "
        ... "FROM clan_members cm INNER JOIN clans c ON c.id = cm.clan_id "
        ... "WHERE cm.steamid64 = '%s' LIMIT 1", escapedSteam);
    DataPack pack = new DataPack();
    pack.WriteCell(serial);
    pack.WriteCell(g_ClanMembershipMutationVersion);
    pack.WriteString(steamid64);
    g_ClanClientLoadRequest[client] = pack;
    g_ClanClientLoadSerial[client] = serial;
    g_bClientClanLoadPending[client] = true;
    g_Database.Query(SQL_OnClientClanIdLoaded, query, pack);
}

public void SQL_OnClientClanIdLoaded(Database db, DBResultSet results,
    const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientFromSerial(pack.ReadCell());
    int mutationVersion = pack.ReadCell();
    char expectedSteam[STEAMID64_MAXLEN];
    pack.ReadString(expectedSteam, sizeof(expectedSteam));
    bool ownsRequest = client > 0 && g_ClanClientLoadRequest[client] == pack
        && g_bClientClanLoadPending[client];
    delete pack;
    if (!ownsRequest)
    {
        return;
    }
    g_ClanClientLoadRequest[client] = null;
    g_bClientClanLoadPending[client] = false;
    char steamid64[STEAMID64_MAXLEN];
    if (!Client_IsHumanInGame(client)
        || !GetClientSteam64(client, steamid64, sizeof(steamid64))
        || !StrEqual(steamid64, expectedSteam))
    {
        return;
    }
    if (!ClanCache_IsCurrentConnection(db)
        || mutationVersion != g_ClanMembershipMutationVersion)
    {
        RequestClientClanIdLoad(client);
        return;
    }
    if (error[0] || !HasUsableResultSet(results))
    {
        LogError("[Clans] Failed to load clan id for %s: %s", steamid64,
            error[0] ? error : "no result set");
        HandleDatabaseConnectionLoss(error);
        return;
    }
    int clanId = 0;
    ClanRank rank = ClanRank_Member;
    char clanName[CLAN_NAME_MAXLEN + 1];
    char clanTag[CLAN_TAG_STORE_MAXLEN];
    if (results.FetchRow())
    {
        clanId = results.FetchInt(0);
        rank = view_as<ClanRank>(results.FetchInt(1));
        results.FetchString(2, clanName, sizeof(clanName));
        results.FetchString(3, clanTag, sizeof(clanTag));
    }
    g_iClientClanId[client] = clanId;
    g_ClientClanRank[client] = rank;
    strcopy(g_sClientClanName[client], sizeof(g_sClientClanName[]), clanName);
    strcopy(g_sClientClanTag[client], sizeof(g_sClientClanTag[]), clanTag);
    g_bClientClanLoaded[client] = true;
    UpdateClanIdCacheEntry(steamid64, clanId);
}

bool GetLoadedClientClanContext(int client, char[] steamid64, int steamidLen,
    int &clanId, ClanRank &rank, char[] clanName, int clanNameLen,
    char[] clanTag, int clanTagLen)
{
    steamid64[0] = '\0';
    clanId = 0;
    rank = ClanRank_Member;
    clanName[0] = '\0';
    clanTag[0] = '\0';
    if (!Client_IsHumanInGame(client) || !g_bClientClanLoaded[client]
        || !GetClientSteam64(client, steamid64, steamidLen))
    {
        return false;
    }
    clanId = g_iClientClanId[client];
    rank = g_ClientClanRank[client];
    strcopy(clanName, clanNameLen, g_sClientClanName[client]);
    strcopy(clanTag, clanTagLen, g_sClientClanTag[client]);
    return clanId <= 0 || clanName[0] != '\0';
}

bool GetCachedOnlineClanSummary(int clanId, char[] clanName, int clanNameLen,
    char[] clanTag, int clanTagLen, char[] representativeName,
    int representativeNameLen, int &onlineCount)
{
    clanName[0] = '\0';
    clanTag[0] = '\0';
    representativeName[0] = '\0';
    onlineCount = 0;
    ClanRank bestRank = ClanRank_Member;
    bool hasRepresentative = false;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!Client_IsHumanInGame(client) || !g_bClientClanLoaded[client]
            || g_iClientClanId[client] != clanId)
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

void ClanCache_SetClientMembership(int client, int clanId)
{
    // Invalidates any read of membership from before the completed mutation.
    g_ClanClientLoadRequest[client] = null;
    g_bClientClanLoadPending[client] = false;
    g_iClientClanId[client] = clanId;
    g_bClientClanLoaded[client] = clanId <= 0;
    g_ClientClanRank[client] = ClanRank_Member;
    g_sClientClanName[client][0] = '\0';
    g_sClientClanTag[client][0] = '\0';
    if (clanId > 0)
    {
        RequestClientClanIdLoad(client);
        RequestClientClanTagsLoad(client, true);
    }
    else
    {
        ClearClientClanTagsCache(client, true);
    }
}

void SetClientClanIdBySteam64(const char[] steamid64, int clanId)
{
    g_ClanMembershipMutationVersion++;
    UpdateClanIdCacheEntry(steamid64, clanId);
    char currentSteam[STEAMID64_MAXLEN];
    for (int client = 1; client <= MaxClients; client++)
    {
        if (Client_IsHumanInGame(client)
            && GetClientSteam64(client, currentSteam, sizeof(currentSteam))
            && StrEqual(currentSteam, steamid64, false))
        {
            ClanCache_SetClientMembership(client, clanId);
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
        if (Client_IsHumanInGame(client) && g_iClientClanId[client] == clanId)
        {
            ClanCache_SetClientMembership(client, 0);
        }
    }
}
