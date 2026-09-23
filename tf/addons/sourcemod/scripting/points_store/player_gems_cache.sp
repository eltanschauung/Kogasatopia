void EnsurePlayerGemsCacheSchema()
{
    if (g_Database == null)
    {
        return;
    }

    char query[384];
    FormatEx(query, sizeof(query),
        "CREATE TABLE IF NOT EXISTS %s ("
        ... "steamid64 VARCHAR(32) NOT NULL PRIMARY KEY, "
        ... "balance INT NOT NULL DEFAULT 0, "
        ... "updated_at INT NOT NULL DEFAULT 0)",
        BP_PLAYER_GEMS_CACHE_TABLE);
    g_Database.Query(SQL_OnPlayerGemsCacheSchemaReady, query, g_CurrencySnapshotGeneration);
}

public void SQL_OnPlayerGemsCacheSchemaReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (data != g_CurrencySnapshotGeneration || !Store_IsCurrentConnection(db))
    {
        return;
    }
    if (error[0] != '\0')
    {
        LogError("[points_store] Player Gems cache schema creation failed: %s", error);
        return;
    }

    g_PlayerGemsCacheReady = true;
    char steamId[32];
    for (int i = 0; i < g_PendingPlayerGemsCacheSteamIds.Length; i++)
    {
        g_PendingPlayerGemsCacheSteamIds.GetString(i, steamId, sizeof(steamId));
        CachePlayerGemsBySteamId(steamId);
    }
    g_PendingPlayerGemsCacheSteamIds.Clear();
}

void CachePlayerGemsOnDisconnect(int client)
{
    char steamId[32];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId)))
    {
        return;
    }

    if (!g_PlayerGemsCacheReady || g_Database == null)
    {
        g_PendingPlayerGemsCacheSteamIds.PushString(steamId);
        return;
    }

    CachePlayerGemsBySteamId(steamId);
}

void CachePlayerGemsBySteamId(const char[] steamId)
{
    char escapedSteamId[65];
    if (!EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId)))
    {
        LogError("[points_store] Failed to escape SteamID64 for Player Gems cache.");
        return;
    }

    // Read the persisted balance at execution time. A zero tombstone removes
    // an old >100 display value when the player now has 100 or fewer Gems.
    char query[512];
    FormatEx(query, sizeof(query),
        "REPLACE INTO %s (steamid64, balance, updated_at) "
        ... "SELECT '%s', COALESCE((SELECT CASE WHEN balance > 100 THEN balance ELSE 0 END "
        ... "FROM %s WHERE steamid64 = '%s'), 0), %d",
        BP_PLAYER_GEMS_CACHE_TABLE,
        escapedSteamId,
        BP_BALANCE_TABLE,
        escapedSteamId,
        GetTime());
    g_Database.Query(SQL_OnPlayerGemsCached, query, g_CurrencySnapshotGeneration);
}

public void SQL_OnPlayerGemsCached(Database db, DBResultSet results, const char[] error, any data)
{
    if (data != g_CurrencySnapshotGeneration || !Store_IsCurrentConnection(db))
    {
        return;
    }
    if (error[0] != '\0')
    {
        LogError("[points_store] Failed to cache player Gems on disconnect: %s", error);
    }
}
