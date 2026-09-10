bool g_bDbReady = false;
char g_sDbConfig[32] = FILTERS_DEFAULT_DB_CONFIG;
Handle g_hFiltersDbReconnectTimer = null;

bool Filters_DbAvailable()
{
    return Db_IsReady(g_hFiltersDb, g_bDbReady);
}

void Filters_SQLConnect()
{
    Db_CancelTimer(g_hFiltersDbReconnectTimer);
    Db_Close(g_hFiltersDb, g_bDbReady);
    if (!Db_CheckConfigOrLog("Filters", g_sDbConfig))
    {
        return;
    }

    Filters_LogDebug("Connecting to database config '%s'", g_sDbConfig);
    Database.Connect(T_Filters_SQLConnect, g_sDbConfig);
}

void Filters_ScheduleSqlReconnect(float delay = DB_RECONNECT_DELAY)
{
    g_bDbReady = false;
    if (g_hFiltersDbReconnectTimer == null)
    {
        g_hFiltersDbReconnectTimer = CreateTimer(delay, Timer_ReconnectFiltersSql, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_ReconnectFiltersSql(Handle timer, any data)
{
    g_hFiltersDbReconnectTimer = null;
    Filters_SQLConnect();
    return Plugin_Stop;
}

public void T_Filters_SQLConnect(Database db, const char[] error, any data)
{
    if (db == null)
    {
        LogError("[Filters] DB connection failed: %s", error);
        Filters_ScheduleSqlReconnect();
        return;
    }

    g_hFiltersDb = db;
    g_bDbReady = true;
    g_bOutboxStampReady = false;
    Db_CancelTimer(g_hFiltersDbReconnectTimer);
    if (!g_hFiltersDb.SetCharset("utf8mb4"))
    {
        LogError("[Filters] Failed to set utf8mb4 charset");
    }

    static const char schemaQueries[][] =
    {
        "CREATE TABLE IF NOT EXISTS whaletracker_chat ("
        ... "id INT AUTO_INCREMENT PRIMARY KEY,"
        ... "created_at INT NOT NULL,"
        ... "steamid VARCHAR(32) NULL,"
        ... "personaname VARCHAR(128) NULL,"
        ... "iphash VARCHAR(64) NULL,"
        ... "source_subnet VARCHAR(32) NULL,"
        ... "server_tag VARCHAR(64) NOT NULL DEFAULT '',"
        ... "message TEXT NOT NULL,"
        ... "alert TINYINT(1) NOT NULL DEFAULT 1,"
        ... "INDEX(created_at)) DEFAULT CHARSET=utf8mb4",
        "CREATE TABLE IF NOT EXISTS whaletracker_chat_outbox ("
        ... "id INT AUTO_INCREMENT PRIMARY KEY,"
        ... "created_at INT NOT NULL,"
        ... "iphash VARCHAR(64) NOT NULL,"
        ... "source_subnet VARCHAR(32) NULL,"
        ... "server_tag VARCHAR(64) NOT NULL DEFAULT '',"
        ... "display_name VARCHAR(128) DEFAULT '',"
        ... "message TEXT NOT NULL,"
        ... "host_ip VARCHAR(64) NOT NULL DEFAULT '',"
        ... "host_port INT NOT NULL DEFAULT 0,"
        ... "webchatonly TINYINT(1) NOT NULL DEFAULT 0,"
        ... "alert TINYINT(1) NOT NULL DEFAULT 1,"
        ... "server_ip VARCHAR(64) NULL,"
        ... "server_port INT NULL,"
        ... "delivered_to TEXT NULL,"
        ... "INDEX(created_at)) DEFAULT CHARSET=utf8mb4",
        "ALTER TABLE whaletracker_chat ADD COLUMN IF NOT EXISTS alert TINYINT(1) NOT NULL DEFAULT 1 AFTER message",
        "ALTER TABLE whaletracker_chat ADD COLUMN IF NOT EXISTS source_subnet VARCHAR(32) NULL AFTER iphash",
        "ALTER TABLE whaletracker_chat ADD COLUMN IF NOT EXISTS server_tag VARCHAR(64) NOT NULL DEFAULT '' AFTER source_subnet",
        "ALTER TABLE whaletracker_chat_outbox ADD COLUMN IF NOT EXISTS source_subnet VARCHAR(32) NULL AFTER iphash",
        "ALTER TABLE whaletracker_chat_outbox ADD COLUMN IF NOT EXISTS server_tag VARCHAR(64) NOT NULL DEFAULT '' AFTER source_subnet",
        "ALTER TABLE whaletracker_chat_outbox ADD COLUMN IF NOT EXISTS host_ip VARCHAR(64) NOT NULL DEFAULT '' AFTER message",
        "ALTER TABLE whaletracker_chat_outbox ADD COLUMN IF NOT EXISTS host_port INT NOT NULL DEFAULT 0 AFTER host_ip",
        "ALTER TABLE whaletracker_chat_outbox ADD COLUMN IF NOT EXISTS webchatonly TINYINT(1) NOT NULL DEFAULT 0 AFTER host_port",
        "ALTER TABLE whaletracker_chat_outbox ADD COLUMN IF NOT EXISTS alert TINYINT(1) NOT NULL DEFAULT 1 AFTER webchatonly",
        "ALTER TABLE whaletracker_chat_outbox ADD COLUMN IF NOT EXISTS server_ip VARCHAR(64) NULL AFTER webchatonly",
        "ALTER TABLE whaletracker_chat_outbox ADD COLUMN IF NOT EXISTS server_port INT NULL AFTER server_ip",
        "ALTER TABLE whaletracker_chat_outbox ADD COLUMN IF NOT EXISTS delivered_to TEXT NULL AFTER server_port",
        "CREATE TABLE IF NOT EXISTS whaletracker_chat_outbox_deliveries ("
        ... "outbox_id INT NOT NULL,"
        ... "server_stamp VARCHAR(96) NOT NULL,"
        ... "delivered_at INT NOT NULL,"
        ... "PRIMARY KEY(outbox_id, server_stamp),"
        ... "INDEX(delivered_at),"
        ... "INDEX(server_stamp)) DEFAULT CHARSET=utf8mb4",
        "CREATE TABLE IF NOT EXISTS prename_rules (pattern VARCHAR(64) PRIMARY KEY, newname VARCHAR(64) NOT NULL)",
        "CREATE TABLE IF NOT EXISTS filters_steam_names ("
        ... "steamid64 VARCHAR(32) PRIMARY KEY,"
        ... "last_name VARCHAR(128) NOT NULL DEFAULT '',"
        ... "last_name_lower VARCHAR(128) NOT NULL DEFAULT '',"
        ... "updated_at INT NOT NULL DEFAULT 0,"
        ... "INDEX(last_name_lower),"
        ... "INDEX(updated_at)) DEFAULT CHARSET=utf8mb4",
        "CREATE TABLE IF NOT EXISTS filters_namecolors (steamid VARCHAR(32) PRIMARY KEY, color VARCHAR(32) NOT NULL DEFAULT '', pattern VARCHAR(96) NOT NULL DEFAULT '', updated_at INT NOT NULL DEFAULT 0)",
        "ALTER TABLE filters_namecolors ADD COLUMN IF NOT EXISTS pattern VARCHAR(96) NOT NULL DEFAULT '' AFTER color",
        "ALTER TABLE filters_namecolors MODIFY COLUMN pattern VARCHAR(96) NOT NULL DEFAULT ''",
        "CREATE TABLE IF NOT EXISTS parsee_messages (date DATETIME NOT NULL, message TEXT NOT NULL, source_outbox_id INT NULL UNIQUE, INDEX(date)) DEFAULT CHARSET=utf8mb4",
        "ALTER TABLE parsee_messages ADD COLUMN IF NOT EXISTS source_outbox_id INT NULL UNIQUE AFTER message",
        "CREATE TABLE IF NOT EXISTS memoman_messages (date DATETIME NOT NULL, message TEXT NOT NULL, INDEX(date)) DEFAULT CHARSET=utf8mb4"
    };

    g_iPendingSchemaQueries = sizeof(schemaQueries);
    if (g_iPendingSchemaQueries <= 0)
    {
        g_bOutboxStampReady = true;
        g_PrenameRulesLoaded = false;
        Filters_PrenameLoadRules();
    }
    else
    {
        for (int i = 0; i < sizeof(schemaQueries); i++)
        {
            g_hFiltersDb.Query(Filters_SchemaQueryCallback, schemaQueries[i]);
        }
    }

    Filters_LogDebug("Database connection established");
}

public void Filters_SimpleSqlCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[Filters] SQL error: %s", error);
        if (Db_IsTransientError(error))
        {
            Filters_ScheduleSqlReconnect(DB_RECONNECT_FAST_DELAY);
        }
    }
}

public void Filters_SchemaQueryCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[Filters] Schema query failed: %s", error);
        if (Db_IsTransientError(error))
        {
            Filters_ScheduleSqlReconnect(DB_RECONNECT_FAST_DELAY);
        }
    }

    if (g_iPendingSchemaQueries > 0)
    {
        g_iPendingSchemaQueries--;
    }

    if (g_iPendingSchemaQueries <= 0)
    {
        g_bOutboxStampReady = true;
        Filters_LogDebug("Schema ready; host stamp support enabled");
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !IsFakeClient(i))
            {
                LoadNamePreferencesFromDb(i);
            }
        }
        if (!g_PrenameRulesLoaded)
        {
            Filters_PrenameLoadRules();
        }
        if (g_hParseeEnabled.BoolValue)
        {
            Filters_RefreshArchivedMessageCount(ArchivedSpeaker_Parsee);
        }
        Filters_RefreshArchivedMessageCount(ArchivedSpeaker_Memoman);
    }
}

