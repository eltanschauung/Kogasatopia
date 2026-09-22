void EnsureCurrencySnapshotSchema()
{
    if (g_Database == null)
    {
        return;
    }

    char query[512];
    Format(query, sizeof(query),
        "CREATE TABLE IF NOT EXISTS %s ("
        ... "id INT NOT NULL PRIMARY KEY, "
        ... "total_gems BIGINT NOT NULL DEFAULT 0, "
        ... "players_over_100 INT NOT NULL DEFAULT 0, "
        ... "welfare_pool_gems BIGINT NOT NULL DEFAULT 0, "
        ... "updated_at INT NOT NULL DEFAULT 0)",
        BP_CURRENCY_SNAPSHOT_TABLE);
    g_Database.Query(SQL_OnCurrencySnapshotSchemaReady, query, g_CurrencySnapshotGeneration);
}

public void SQL_OnCurrencySnapshotSchemaReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (data != g_CurrencySnapshotGeneration || g_Database == null)
    {
        return;
    }
    if (error[0] != '\0')
    {
        LogError("[points_store] Currency snapshot schema creation failed: %s", error);
        return;
    }

    char query[192];
    Format(query, sizeof(query),
        "SELECT updated_at FROM %s WHERE id = 1",
        BP_CURRENCY_SNAPSHOT_TABLE);
    g_Database.Query(SQL_OnCurrencySnapshotChecked, query, g_CurrencySnapshotGeneration);
}

public void SQL_OnCurrencySnapshotChecked(Database db, DBResultSet results, const char[] error, any data)
{
    if (data != g_CurrencySnapshotGeneration || g_Database == null)
    {
        return;
    }
    if (error[0] != '\0')
    {
        LogError("[points_store] Currency snapshot check failed: %s", error);
        return;
    }

    int now = GetTime();
    if (results != null && results.FetchRow())
    {
        int updatedAt = results.FetchInt(0);
        if (updatedAt > 0 && updatedAt <= now
            && now - updatedAt < BP_CURRENCY_SNAPSHOT_TTL_SECONDS)
        {
            return;
        }
    }

    RefreshCurrencySnapshot();
}

void RefreshCurrencySnapshot()
{
    // Aggregate in SQL so the sum is not limited by SourcePawn's 32-bit integers.
    char query[768];
    Format(query, sizeof(query),
        "REPLACE INTO %s (id, total_gems, players_over_100, welfare_pool_gems, updated_at) "
        ... "SELECT 1, "
        ... "COALESCE(SUM(balance), 0), "
        ... "COALESCE(SUM(CASE WHEN balance > 100 THEN 1 ELSE 0 END), 0), "
        ... "COALESCE((SELECT value FROM %s WHERE stat_key = '%s'), 0), "
        ... "%d FROM %s",
        BP_CURRENCY_SNAPSHOT_TABLE,
        BP_ECONOMY_TABLE,
        BP_ECONOMY_WELFARE_POOL_KEY,
        GetTime(),
        BP_BALANCE_TABLE);
    g_Database.Query(SQL_OnCurrencySnapshotRefreshed, query, g_CurrencySnapshotGeneration);
}

public void SQL_OnCurrencySnapshotRefreshed(Database db, DBResultSet results, const char[] error, any data)
{
    if (data != g_CurrencySnapshotGeneration || g_Database == null)
    {
        return;
    }
    if (error[0] != '\0')
    {
        LogError("[points_store] Currency snapshot refresh failed: %s", error);
    }
    else
    {
        LogMessage("[points_store] Currency snapshot refreshed.");
    }
}
