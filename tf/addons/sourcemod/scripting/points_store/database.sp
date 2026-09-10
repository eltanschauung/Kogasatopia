void ConnectDatabase()
{
    Db_CancelTimer(g_hDatabaseReconnectTimer);
    Db_Close(g_Database, g_DatabaseReady);
    g_IdempotentAwardsReady = false;
    g_PerMapAwardsReady = false;
    g_PerMapSchemaReady = false;
    g_BountyDatabaseReady = false;
    g_BountyExpiryPending = false;
    g_BountyProgressPending = false;
    g_BountyDisconnectRefundPending = false;
    g_BountyAutomaticPlacementPending = false;
    g_ActiveBountyCount = 0;
    MemomanEvent_OnDatabaseDisconnected();
    Lotteries_OnDatabaseDisconnected();

    char dbConfig[64];
    g_CvarDatabase.GetString(dbConfig, sizeof(dbConfig));
    TrimString(dbConfig);
    if (dbConfig[0] == '\0')
    {
        strcopy(dbConfig, sizeof(dbConfig), BP_TRANS_DB_CONFIG_DEFAULT);
    }

    if (!Db_CheckConfigOrLog("points_store", dbConfig))
    {
        return;
    }

    SQL_TConnect(SQL_OnDatabaseConnected, dbConfig);
}

public void SQL_OnDatabaseConnected(Handle owner, Handle hndl, const char[] error, any data)
{
    if (hndl == null)
    {
        LogError("[bonuspoints_transactions] Database connection failed: %s", error[0] ? error : "unknown error");
        ScheduleDatabaseReconnect();
        return;
    }

    g_Database = view_as<Database>(hndl);

    char driverIdent[32];
    DBDriver driver = g_Database.Driver;
    driver.GetIdentifier(driverIdent, sizeof(driverIdent));
    g_IsMySql = StrEqual(driverIdent, "mysql", false);
    Db_CancelTimer(g_hDatabaseReconnectTimer);

    EnsureSchema();
}

void ScheduleDatabaseReconnect(float delay = DB_RECONNECT_DELAY)
{
    g_DatabaseReady = false;
    g_IdempotentAwardsReady = false;
    g_BountyDatabaseReady = false;
    if (g_hDatabaseReconnectTimer == null)
    {
        g_hDatabaseReconnectTimer = CreateTimer(delay, Timer_ReconnectDatabase, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_ReconnectDatabase(Handle timer, any data)
{
    g_hDatabaseReconnectTimer = null;
    ConnectDatabase();
    return Plugin_Stop;
}

void EnsureSchema()
{
    if (g_Database == null)
    {
        return;
    }

    char query[1024];
    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "id INT NOT NULL AUTO_INCREMENT, "
            ... "steamid64 VARCHAR(32) NOT NULL, "
            ... "item_key VARCHAR(64) NOT NULL, "
            ... "price_paid INT NOT NULL, "
            ... "purchased_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
            ... "expires_at INT NOT NULL DEFAULT 0, "
            ... "uses_remaining INT NOT NULL DEFAULT -1, "
            ... "PRIMARY KEY (id), "
            ... "UNIQUE KEY unique_bonuspoints_purchase (steamid64, item_key), "
            ... "KEY idx_bonuspoints_transactions_steamid64 (steamid64), "
            ... "KEY idx_bonuspoints_transactions_item_key (item_key))",
            BP_TRANS_TABLE);
    }
    else
    {
        Format(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "id INTEGER PRIMARY KEY AUTOINCREMENT, "
            ... "steamid64 VARCHAR(32) NOT NULL, "
            ... "item_key VARCHAR(64) NOT NULL, "
            ... "price_paid INT NOT NULL, "
            ... "purchased_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
            ... "expires_at INTEGER NOT NULL DEFAULT 0, "
            ... "uses_remaining INTEGER NOT NULL DEFAULT -1, "
            ... "UNIQUE (steamid64, item_key))",
            BP_TRANS_TABLE);
    }

    g_Database.Query(SQL_OnPurchaseSchemaReady, query);
}

public void SQL_OnPurchaseSchemaReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[points_store] Purchase schema creation failed: %s", error);
        return;
    }

    char query[256];
    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "ALTER TABLE %s ADD COLUMN IF NOT EXISTS expires_at INT NOT NULL DEFAULT 0",
            BP_TRANS_TABLE);
    }
    else
    {
        Format(query, sizeof(query),
            "ALTER TABLE %s ADD COLUMN expires_at INTEGER NOT NULL DEFAULT 0",
            BP_TRANS_TABLE);
    }

    g_Database.Query(SQL_OnPurchaseExpiryColumnReady, query);
}

public void SQL_OnPurchaseExpiryColumnReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0' && !Db_IsDuplicateColumnError(error))
    {
        LogError("[points_store] Purchase expiry schema update failed: %s", error);
        return;
    }

    char query[256];
    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "ALTER TABLE %s ADD COLUMN IF NOT EXISTS uses_remaining INT NOT NULL DEFAULT -1",
            BP_TRANS_TABLE);
    }
    else
    {
        Format(query, sizeof(query),
            "ALTER TABLE %s ADD COLUMN uses_remaining INTEGER NOT NULL DEFAULT -1",
            BP_TRANS_TABLE);
    }

    g_Database.Query(SQL_OnPurchaseUsesColumnReady, query);
}

public void SQL_OnPurchaseUsesColumnReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0' && !Db_IsDuplicateColumnError(error))
    {
        LogError("[points_store] Purchase uses schema update failed: %s", error);
        return;
    }

    if (!g_IsMySql)
    {
        g_Database.Query(SQL_OnIgnoredResult, "CREATE INDEX IF NOT EXISTS idx_bonuspoints_transactions_steamid64 ON bonuspoints_transactions (steamid64)");
        g_Database.Query(SQL_OnIgnoredResult, "CREATE INDEX IF NOT EXISTS idx_bonuspoints_transactions_item_key ON bonuspoints_transactions (item_key)");
    }

    EnsureBalanceSchema();
}

void EnsureBalanceSchema()
{
    char query[512];
    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "steamid64 VARCHAR(32) NOT NULL, "
            ... "balance INT NOT NULL DEFAULT 0, "
            ... "updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, "
            ... "PRIMARY KEY (steamid64))",
            BP_BALANCE_TABLE);
    }
    else
    {
        Format(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "steamid64 VARCHAR(32) NOT NULL PRIMARY KEY, "
            ... "balance INT NOT NULL DEFAULT 0, "
            ... "updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)",
            BP_BALANCE_TABLE);
    }

    g_Database.Query(SQL_OnSchemaReady, query);
}

public void SQL_OnSchemaReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[points_store] Balance schema creation failed: %s", error);
        return;
    }

    EnsureLotterySchema();
}

void EnsureEconomySchema()
{
    if (g_Database == null)
    {
        return;
    }

    char query[512];
    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "stat_key VARCHAR(64) NOT NULL, "
            ... "value BIGINT NOT NULL DEFAULT 0, "
            ... "updated_at INT NOT NULL DEFAULT 0, "
            ... "PRIMARY KEY (stat_key))",
            BP_ECONOMY_TABLE);
    }
    else
    {
        Format(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "stat_key VARCHAR(64) NOT NULL PRIMARY KEY, "
            ... "value INTEGER NOT NULL DEFAULT 0, "
            ... "updated_at INTEGER NOT NULL DEFAULT 0)",
            BP_ECONOMY_TABLE);
    }

    g_Database.Query(SQL_OnEconomySchemaReady, query);
}

public void SQL_OnEconomySchemaReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[points_store] Economy schema creation failed: %s", error);
        FinishSchemaReady();
        return;
    }

    Transaction txn = new Transaction();
    char query[512];
    int now = GetTime();

    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "INSERT INTO %s (stat_key, value, updated_at) VALUES ('%s', 0, %d) ON DUPLICATE KEY UPDATE stat_key = stat_key",
            BP_ECONOMY_TABLE,
            BP_ECONOMY_WELFARE_POOL_KEY,
            now);
        txn.AddQuery(query);

        Format(query, sizeof(query),
            "INSERT INTO %s (stat_key, value, updated_at) VALUES ('%s', 0, %d) ON DUPLICATE KEY UPDATE stat_key = stat_key",
            BP_ECONOMY_TABLE,
            BP_ECONOMY_CUMULATIVE_SPENT_KEY,
            now);
        txn.AddQuery(query);
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT OR IGNORE INTO %s (stat_key, value, updated_at) VALUES ('%s', 0, %d)",
            BP_ECONOMY_TABLE,
            BP_ECONOMY_WELFARE_POOL_KEY,
            now);
        txn.AddQuery(query);

        Format(query, sizeof(query),
            "INSERT OR IGNORE INTO %s (stat_key, value, updated_at) VALUES ('%s', 0, %d)",
            BP_ECONOMY_TABLE,
            BP_ECONOMY_CUMULATIVE_SPENT_KEY,
            now);
        txn.AddQuery(query);
    }

    g_Database.Execute(txn, SQLTxn_OnEconomyRowsReady, SQLTxn_OnEconomyRowsFailure);
}

public void SQLTxn_OnEconomyRowsReady(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    FinishSchemaReady();
    LoadEconomyState();
}

public void SQLTxn_OnEconomyRowsFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    LogError("[points_store] Economy row initialization failed (query %d): %s", failIndex, error);
    FinishSchemaReady();
}

void FinishSchemaReady()
{
    g_DatabaseReady = true;
    EnsureIdempotentAwardsSchema();
    EnsurePerMapAwardsSchema();
    EnsureBountySchema();
    MemomanEvent_EnsureSchema();

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientAuthorizedHuman(i))
        {
            LoadClientPurchases(i);
            LoadClientBonusPoints(i);
        }
    }
    Lotteries_OnDatabaseReady();
}

void EnsureIdempotentAwardsSchema()
{
    if (g_Database == null)
    {
        return;
    }

    char query[1024];
    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "award_key VARCHAR(%d) NOT NULL, "
            ... "steamid64 VARCHAR(32) NOT NULL, "
            ... "amount INT NOT NULL, "
            ... "reason VARCHAR(64) NOT NULL DEFAULT '', "
            ... "created_at INT NOT NULL, "
            ... "PRIMARY KEY (award_key)"
            ... ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
            BP_IDEMPOTENT_AWARDS_TABLE,
            BP_IDEMPOTENT_KEY_MAX);
    }
    else
    {
        Format(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "award_key VARCHAR(%d) PRIMARY KEY, "
            ... "steamid64 VARCHAR(32) NOT NULL, "
            ... "amount INTEGER NOT NULL, "
            ... "reason VARCHAR(64) NOT NULL DEFAULT '', "
            ... "created_at INTEGER NOT NULL)",
            BP_IDEMPOTENT_AWARDS_TABLE,
            BP_IDEMPOTENT_KEY_MAX);
    }

    g_Database.Query(SQL_OnIdempotentAwardsSchemaReady, query);
}

public void SQL_OnIdempotentAwardsSchemaReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        g_IdempotentAwardsReady = false;
        LogError("[points_store] Idempotent award schema creation failed: %s", error);
        return;
    }

    g_IdempotentAwardsReady = true;
}

void RefreshPerMapAwardScope()
{
    ConVar hostPort = FindConVar("hostport");
    g_PerMapServerPort = hostPort != null ? hostPort.IntValue : 0;
    GetCurrentMap(g_PerMapName, sizeof(g_PerMapName));
}

void EnsurePerMapAwardsSchema()
{
    if (g_Database == null)
    {
        return;
    }

    char query[1024];
    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "server_port INT NOT NULL, "
            ... "map_name VARCHAR(128) NOT NULL, "
            ... "steamid64 VARCHAR(32) NOT NULL, "
            ... "reward_id VARCHAR(64) NOT NULL, "
            ... "award_count INT NOT NULL DEFAULT 0, "
            ... "updated_at INT NOT NULL DEFAULT 0, "
            ... "PRIMARY KEY (server_port, map_name, steamid64, reward_id)"
            ... ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
            BP_PER_MAP_AWARDS_TABLE);
    }
    else
    {
        Format(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "server_port INTEGER NOT NULL, "
            ... "map_name VARCHAR(128) NOT NULL, "
            ... "steamid64 VARCHAR(32) NOT NULL, "
            ... "reward_id VARCHAR(64) NOT NULL, "
            ... "award_count INTEGER NOT NULL DEFAULT 0, "
            ... "updated_at INTEGER NOT NULL DEFAULT 0, "
            ... "PRIMARY KEY (server_port, map_name, steamid64, reward_id))",
            BP_PER_MAP_AWARDS_TABLE);
    }

    g_Database.Query(SQL_OnPerMapAwardsSchemaReady, query);
}

public void SQL_OnPerMapAwardsSchemaReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        g_PerMapSchemaReady = false;
        g_PerMapAwardsReady = false;
        LogError("[points_store] Per-map award schema creation failed: %s", error);
        return;
    }

    g_PerMapSchemaReady = true;
    BeginPerMapStateAction();
}

void ResetPerMapAwardState()
{
    if (g_PerMapAwardCounts != null)
    {
        g_PerMapAwardCounts.Clear();
    }

    g_PerMapAwardsReady = false;
    g_PerMapStateAction = BP_PER_MAP_ACTION_RESET;
    if (g_PerMapSchemaReady && g_DatabaseReady)
    {
        BeginPerMapStateAction();
    }
}

void BeginPerMapStateAction()
{
    if (!g_PerMapSchemaReady || !g_DatabaseReady || g_Database == null)
    {
        return;
    }

    RefreshPerMapAwardScope();
    int generation = ++g_PerMapStateGeneration;

    if (g_PerMapStateAction == BP_PER_MAP_ACTION_NONE)
    {
        g_PerMapAwardsReady = true;
        return;
    }

    char query[768];
    if (g_PerMapStateAction == BP_PER_MAP_ACTION_RESET)
    {
        Format(query, sizeof(query),
            "DELETE FROM %s WHERE server_port = %d",
            BP_PER_MAP_AWARDS_TABLE,
            g_PerMapServerPort);
        g_Database.Query(SQL_OnPerMapAwardsReset, query, generation);
        return;
    }

    char escapedMap[257];
    if (!EscapeSql(g_PerMapName, escapedMap, sizeof(escapedMap)))
    {
        LogError("[points_store] Failed to escape the current map for per-map award restoration.");
        return;
    }

    Format(query, sizeof(query),
        "SELECT steamid64, reward_id, award_count FROM %s "
        ... "WHERE server_port = %d AND map_name = '%s'",
        BP_PER_MAP_AWARDS_TABLE,
        g_PerMapServerPort,
        escapedMap);
    g_Database.Query(SQL_OnPerMapAwardsRestored, query, generation);
}

public void SQL_OnPerMapAwardsReset(Database db, DBResultSet results, const char[] error, any data)
{
    if (data != g_PerMapStateGeneration)
    {
        return;
    }
    if (error[0] != '\0')
    {
        g_PerMapAwardsReady = false;
        LogError("[points_store] Failed to reset per-map awards: %s", error);
        return;
    }

    g_PerMapStateAction = BP_PER_MAP_ACTION_NONE;
    g_PerMapAwardsReady = true;
}

public void SQL_OnPerMapAwardsRestored(Database db, DBResultSet results, const char[] error, any data)
{
    if (data != g_PerMapStateGeneration)
    {
        return;
    }
    if (error[0] != '\0')
    {
        g_PerMapAwardsReady = false;
        LogError("[points_store] Failed to restore per-map awards: %s", error);
        return;
    }

    g_PerMapAwardCounts.Clear();
    char steamId[32];
    char rewardId[64];
    char key[128];
    int restored = 0;
    while (results != null && results.FetchRow())
    {
        results.FetchString(0, steamId, sizeof(steamId));
        results.FetchString(1, rewardId, sizeof(rewardId));
        int count = results.FetchInt(2);
        if (count > 0 && BuildPerMapAwardKeyForSteamId(steamId, rewardId, key, sizeof(key)))
        {
            g_PerMapAwardCounts.SetValue(key, count, true);
            restored++;
        }
    }

    g_PerMapStateAction = BP_PER_MAP_ACTION_NONE;
    g_PerMapAwardsReady = true;
    LogMessage("[points_store] Restored %d per-map reward counter(s) for %s on port %d.", restored, g_PerMapName, g_PerMapServerPort);
}

void LoadEconomyState()
{
    if (!g_DatabaseReady || g_Database == null)
    {
        return;
    }

    char query[256];
    Format(query, sizeof(query),
        "SELECT stat_key, value FROM %s WHERE stat_key IN ('%s', '%s')",
        BP_ECONOMY_TABLE,
        BP_ECONOMY_WELFARE_POOL_KEY,
        BP_ECONOMY_CUMULATIVE_SPENT_KEY);
    g_Database.Query(SQL_OnEconomyStateLoaded, query);
}

public void SQL_OnEconomyStateLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[points_store] Economy state load failed: %s", error);
        return;
    }

    int welfarePool = 0;
    int cumulativeSpent = 0;
    char statKey[BP_ECONOMY_KEY_MAX];
    while (results != null && results.FetchRow())
    {
        results.FetchString(0, statKey, sizeof(statKey));
        if (StrEqual(statKey, BP_ECONOMY_WELFARE_POOL_KEY, false))
        {
            welfarePool = results.FetchInt(1);
        }
        else if (StrEqual(statKey, BP_ECONOMY_CUMULATIVE_SPENT_KEY, false))
        {
            cumulativeSpent = results.FetchInt(1);
        }
    }

    g_WelfarePoolBalance = welfarePool;
    g_CumulativeSpentBalance = cumulativeSpent;
    g_EconomyStateLoaded = true;
}

