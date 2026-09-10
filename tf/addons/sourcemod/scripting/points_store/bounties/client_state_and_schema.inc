void Bounties_OnClientAuthorized(int client)
{
    ResetBountyClientState(client);
    ClearBountyDisconnectForClient(client);
    LoadBountyPlacementCooldown(client);
}

void Bounties_OnClientDisconnect(int client)
{
    MarkBountyTargetDisconnected(client);
    ResetBountyClientState(client);
}

void ResetBountyClientState(int client)
{
    delete g_BountySearchResults[client];
    g_BountySearchResults[client] = null;
    g_BountyPendingSearch[client][0] = '\0';
    g_BountyPendingTargetSteamId[client][0] = '\0';
    g_BountyPendingTargetName[client][0] = '\0';
    g_BountyPendingAmount[client] = 0;
    g_BountyMedicAssistsLife[client] = 0;
    g_BountyPlacementPending[client] = false;
    g_BountyLastPlacementAt[client] = 0;
    g_BountySearchGeneration[client]++;
}

void EnsureBountySchema()
{
    if (g_Database == null)
    {
        return;
    }

    char query[4096];
    if (g_IsMySql)
    {
        FormatEx(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "bounty_id BIGINT NOT NULL AUTO_INCREMENT, "
            ... "sender_steamid64 VARCHAR(32) NOT NULL, "
            ... "sender_name VARCHAR(128) NOT NULL, "
            ... "target_steamid64 VARCHAR(32) NOT NULL, "
            ... "target_name VARCHAR(128) NOT NULL, "
            ... "amount INT NOT NULL, "
            ... "bonus_amount INT NOT NULL DEFAULT 0, "
            ... "placed_at INT NOT NULL, "
            ... "expires_at INT NOT NULL, "
            ... "qualifying_playtime_seconds INT NOT NULL DEFAULT 0, "
            ... "last_target_playtime_seconds INT NOT NULL DEFAULT 0, "
            ... "halftime_announced TINYINT NOT NULL DEFAULT 0, "
            ... "target_disconnected_at INT NOT NULL DEFAULT 0, "
            ... "status VARCHAR(16) NOT NULL DEFAULT 'active', "
            ... "resolved_at INT NOT NULL DEFAULT 0, "
            ... "resolution_token VARCHAR(128) NOT NULL DEFAULT '', "
            ... "claimed_by_steamid64 VARCHAR(32) NOT NULL DEFAULT '', "
            ... "claimed_by_name VARCHAR(128) NOT NULL DEFAULT '', "
            ... "PRIMARY KEY (bounty_id), "
            ... "KEY idx_bounties_active_target (status, target_steamid64, expires_at), "
            ... "KEY idx_bounties_resolution (resolution_token), "
            ... "KEY idx_bounties_sender_cooldown (sender_steamid64, placed_at)"
            ... ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
            BOUNTY_TABLE);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "bounty_id INTEGER PRIMARY KEY AUTOINCREMENT, "
            ... "sender_steamid64 VARCHAR(32) NOT NULL, "
            ... "sender_name VARCHAR(128) NOT NULL, "
            ... "target_steamid64 VARCHAR(32) NOT NULL, "
            ... "target_name VARCHAR(128) NOT NULL, "
            ... "amount INTEGER NOT NULL, "
            ... "bonus_amount INTEGER NOT NULL DEFAULT 0, "
            ... "placed_at INTEGER NOT NULL, "
            ... "expires_at INTEGER NOT NULL, "
            ... "qualifying_playtime_seconds INTEGER NOT NULL DEFAULT 0, "
            ... "last_target_playtime_seconds INTEGER NOT NULL DEFAULT 0, "
            ... "halftime_announced INTEGER NOT NULL DEFAULT 0, "
            ... "target_disconnected_at INTEGER NOT NULL DEFAULT 0, "
            ... "status VARCHAR(16) NOT NULL DEFAULT 'active', "
            ... "resolved_at INTEGER NOT NULL DEFAULT 0, "
            ... "resolution_token VARCHAR(128) NOT NULL DEFAULT '', "
            ... "claimed_by_steamid64 VARCHAR(32) NOT NULL DEFAULT '', "
            ... "claimed_by_name VARCHAR(128) NOT NULL DEFAULT '')"
            , BOUNTY_TABLE);
    }

    g_Database.Query(SQL_OnBountySchemaReady, query);
}

public void SQL_OnBountySchemaReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        g_BountyDatabaseReady = false;
        LogError("[points_store] Bounty schema creation failed: %s", error);
        return;
    }

    g_BountySchemaChecksPending = 5;
    g_BountySchemaCheckFailed = false;
    CheckBountySchemaColumn("bonus_amount", "INTEGER NOT NULL DEFAULT 0");
    CheckBountySchemaColumn("qualifying_playtime_seconds", "INTEGER NOT NULL DEFAULT 0");
    CheckBountySchemaColumn("last_target_playtime_seconds", "INTEGER NOT NULL DEFAULT 0");
    CheckBountySchemaColumn("halftime_announced", "INTEGER NOT NULL DEFAULT 0");
    CheckBountySchemaColumn("target_disconnected_at", "INTEGER NOT NULL DEFAULT 0");
}

void CheckBountySchemaColumn(const char[] column, const char[] definition)
{
    char query[256];
    FormatEx(query, sizeof(query), "SELECT %s FROM %s LIMIT 0", column, BOUNTY_TABLE);

    DataPack pack = new DataPack();
    pack.WriteString(column);
    pack.WriteString(definition);
    g_Database.Query(SQL_OnBountySchemaColumnChecked, query, pack);
}

public void SQL_OnBountySchemaColumnChecked(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    if (error[0] == '\0')
    {
        delete pack;
        FinishBountySchemaColumnCheck(true);
        return;
    }

    pack.Reset();
    char column[64];
    char definition[128];
    pack.ReadString(column, sizeof(column));
    pack.ReadString(definition, sizeof(definition));

    char query[384];
    FormatEx(query, sizeof(query), "ALTER TABLE %s ADD COLUMN %s %s", BOUNTY_TABLE, column, definition);
    g_Database.Query(SQL_OnBountySchemaColumnAdded, query, pack);
}

public void SQL_OnBountySchemaColumnAdded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    char column[64];
    pack.ReadString(column, sizeof(column));
    delete pack;

    if (error[0] != '\0')
    {
        LogError("[points_store] Could not add bounty column '%s': %s", column, error);
        FinishBountySchemaColumnCheck(false);
        return;
    }
    FinishBountySchemaColumnCheck(true);
}

void FinishBountySchemaColumnCheck(bool success)
{
    if (!success)
    {
        g_BountySchemaCheckFailed = true;
    }
    g_BountySchemaChecksPending--;
    if (g_BountySchemaChecksPending > 0)
    {
        return;
    }
    if (g_BountySchemaCheckFailed)
    {
        g_BountyDatabaseReady = false;
        return;
    }

    g_BountyDatabaseReady = true;
    if (!g_IsMySql)
    {
        g_Database.Query(SQL_OnIgnoredResult,
            "CREATE INDEX IF NOT EXISTS idx_bounties_active_target ON points_store_bounties (status, target_steamid64, expires_at)");
        g_Database.Query(SQL_OnIgnoredResult,
            "CREATE INDEX IF NOT EXISTS idx_bounties_resolution ON points_store_bounties (resolution_token)");
    }
    g_Database.Query(SQL_OnIgnoredResult,
        "CREATE INDEX IF NOT EXISTS idx_bounties_sender_cooldown ON points_store_bounties (sender_steamid64, placed_at)");
    ProcessExpiredBounties();
    RequestBountyProgress();
    ClearConnectedBountyDisconnects();
    for (int client = 1; client <= MaxClients; client++)
    {
        if (Client_IsHumanInGame(client))
        {
            LoadBountyPlacementCooldown(client);
        }
    }
    RefreshActiveBountyTargets();
}

