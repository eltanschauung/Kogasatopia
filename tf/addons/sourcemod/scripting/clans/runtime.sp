public void OnPluginEnd()
{
    if (g_hDbKeepaliveTimer != null)
    {
        delete g_hDbKeepaliveTimer;
        g_hDbKeepaliveTimer = null;
    }

    if (g_hDbInitTimer != null)
    {
        delete g_hDbInitTimer;
        g_hDbInitTimer = null;
    }

    if (g_hInviteCleanupTimer != null)
    {
        delete g_hInviteCleanupTimer;
        g_hInviteCleanupTimer = null;
    }

    FlushPendingClanWarPersistenceSync();

    if (g_hClanWarFlushTimer != null)
    {
        delete g_hClanWarFlushTimer;
        g_hClanWarFlushTimer = null;
    }

    if (g_hDbReconnectTimer != null)
    {
        delete g_hDbReconnectTimer;
        g_hDbReconnectTimer = null;
    }

    if (g_Database != null)
    {
        delete g_Database;
        g_Database = null;
    }

    if (g_hClanIdCache != null)
    {
        delete g_hClanIdCache;
        g_hClanIdCache = null;
    }

    if (g_hActiveWars != null)
    {
        delete g_hActiveWars;
        g_hActiveWars = null;
    }

    if (g_hPendingClanWarKillDeltas != null)
    {
        delete g_hPendingClanWarKillDeltas;
        g_hPendingClanWarKillDeltas = null;
    }
}

public void OnClientDisconnect(int client)
{
    ResetClientState(client);
}

public void OnClientPostAdminCheck(int client)
{
    if (!Client_IsHumanInGame(client))
    {
        return;
    }

    RequestClientClanIdLoad(client);
    RequestClientClanTagsLoad(client);
}

void ResetClientState(int client)
{
    g_PromptState[client] = Prompt_None;
    g_PendingAdminClanDescId[client] = 0;
    g_PendingAdminClanDescName[client][0] = '\0';
    g_iClientClanId[client] = 0;
    g_bClientClanLoaded[client] = false;
    g_bClientClanLoadPending[client] = false;
    g_ClientClanRank[client] = ClanRank_Member;
    g_sClientClanName[client][0] = '\0';
    g_sClientClanTag[client][0] = '\0';
    g_sClientClanTags[client][0] = '\0';
    g_bClientClanTagsLoaded[client] = false;
    g_bClientClanTagsPending[client] = false;
    g_iClanMembersMenuClanId[client] = 0;
    g_sClanMembersMenuClanName[client][0] = '\0';
    g_iClanHistoryMenuClanId[client] = 0;
    g_sClanHistoryMenuClanName[client][0] = '\0';
}

void ConnectDatabase()
{
    char configName[64];
    g_cvDatabaseConfig.GetString(configName, sizeof(configName));
    Database.Connect(SQL_OnDatabaseConnected, configName);
}

public void SQL_OnDatabaseConnected(Database db, const char[] error, any data)
{
    if (db == null)
    {
        LogError("[Clans] Database connection failed: %s", error);
        HandleDatabaseConnectionLoss(error);
        return;
    }

    if (!ValidateDatabaseHandle(db))
    {
        delete db;
        ScheduleDatabaseReconnect(1.0);
        return;
    }

    if (g_Database != null)
    {
        delete g_Database;
        g_Database = null;
    }

    g_Database = db;
    g_Database.Driver.GetIdentifier(g_sDbDriver, sizeof(g_sDbDriver));
    g_bDatabaseReady = false;
    g_bClanIdCacheReady = false;
    g_flDbReconnectDelay = CLAN_DB_RECONNECT_INITIAL_INTERVAL;
    ResetActiveWarCache();

    if (!g_Database.SetCharset("utf8mb4"))
    {
        LogError("[Clans] Failed to set utf8mb4 charset");
    }

    ScheduleDatabaseInitialization();
}

void ScheduleDatabaseInitialization()
{
    if (g_hDbInitTimer != null)
    {
        delete g_hDbInitTimer;
        g_hDbInitTimer = null;
    }

    g_hDbInitTimer = CreateTimer(0.5, Timer_FinishDatabaseInitialization);
}

public Action Timer_FinishDatabaseInitialization(Handle timer, any data)
{
    if (timer == g_hDbInitTimer)
    {
        g_hDbInitTimer = null;
    }

    FinishDatabaseInitialization();
    return Plugin_Stop;
}

void FinishDatabaseInitialization()
{
    if (g_Database == null)
    {
        return;
    }

    g_bDatabaseReady = true;
    EnsureClanWarMemberKillsSchema();

    if (!g_bActiveWarCacheReady || g_hActiveWars == null)
    {
        if (!LoadActiveClanWarsCacheSync() && !EnsureDatabaseReady())
        {
            return;
        }
    }
    if (!EnsureDatabaseReady())
    {
        return;
    }

    CleanupExpiredWars();
    if (!EnsureDatabaseReady())
    {
        return;
    }

    RebuildClanIdCache();
    if (!EnsureDatabaseReady())
    {
        return;
    }

    FlushPendingClanWarPersistenceSync();
    if (!EnsureDatabaseReady())
    {
        return;
    }

    if (g_hInviteCleanupTimer == null)
    {
        g_hInviteCleanupTimer = CreateTimer(INVITE_CLEANUP_INTERVAL, Timer_CleanupExpiredInvites, 0, TIMER_REPEAT);
    }

    if (g_hClanWarFlushTimer == null)
    {
        g_hClanWarFlushTimer = CreateTimer(CLAN_WAR_FLUSH_INTERVAL, Timer_FlushClanWarDeltas, 0, TIMER_REPEAT);
    }

    StartDatabaseKeepaliveTimer();
    PrintToServer("[Clans] Database ready using driver '%s'.", g_sDbDriver);

    CleanupExpiredInvites();

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            RequestClientClanIdLoad(i);
            RequestClientClanTagsLoad(i);
        }
    }
}

bool IsMySql()
{
    return StrEqual(g_sDbDriver, "mysql", false);
}

void EnsureClanWarMemberKillsSchema()
{
    if (g_Database == null)
    {
        return;
    }

    if (IsMySql())
    {
        SQL_FastQuery(g_Database, "ALTER TABLE clan_war_member_kills ADD COLUMN IF NOT EXISTS currency_stolen INT NOT NULL DEFAULT 0");
    }
}

bool IsDatabaseConnectionLostError(const char[] error)
{
    return Db_IsTransientError(error);
}

bool ValidateDatabaseHandle(Database db)
{
    if (db == null)
    {
        return false;
    }

    if (SQL_FastQuery(db, "SELECT 1"))
    {
        return true;
    }

    char error[256];
    SQL_GetError(db, error, sizeof(error));
    if (!IsDatabaseConnectionLostError(error))
    {
        LogError("[Clans] Database validation failed: %s", error);
    }

    return false;
}

void StopDatabaseKeepaliveTimer()
{
    if (g_hDbKeepaliveTimer != null)
    {
        delete g_hDbKeepaliveTimer;
        g_hDbKeepaliveTimer = null;
    }
}

void StartDatabaseKeepaliveTimer()
{
    if (g_hDbKeepaliveTimer != null)
    {
        return;
    }

    g_hDbKeepaliveTimer = CreateTimer(CLAN_DB_KEEPALIVE_INTERVAL, Timer_DatabaseKeepalive, 0, TIMER_REPEAT);
}

void DropDatabaseConnection()
{
    StopDatabaseKeepaliveTimer();
    if (g_hDbInitTimer != null)
    {
        delete g_hDbInitTimer;
        g_hDbInitTimer = null;
    }

    g_bDatabaseReady = false;
    g_bClanIdCacheReady = false;

    if (g_Database != null)
    {
        delete g_Database;
        g_Database = null;
    }
}

bool HasUsableResultSet(DBResultSet results)
{
    return (results != null && SQL_HasResultSet(results));
}

void ScheduleDatabaseReconnect(float delay = -1.0)
{
    if (g_hDbReconnectTimer != null)
    {
        return;
    }

    if (delay < 0.0)
    {
        delay = g_flDbReconnectDelay;
    }

    if (delay < CLAN_DB_RECONNECT_INITIAL_INTERVAL)
    {
        delay = CLAN_DB_RECONNECT_INITIAL_INTERVAL;
    }

    g_hDbReconnectTimer = CreateTimer(delay, Timer_ReconnectDatabase);

    g_flDbReconnectDelay *= 2.0;
    if (g_flDbReconnectDelay > CLAN_DB_RECONNECT_MAX_INTERVAL)
    {
        g_flDbReconnectDelay = CLAN_DB_RECONNECT_MAX_INTERVAL;
    }
}

public Action Timer_ReconnectDatabase(Handle timer, any data)
{
    if (timer == g_hDbReconnectTimer)
    {
        g_hDbReconnectTimer = null;
    }

    ConnectDatabase();
    return Plugin_Stop;
}

public Action Timer_DatabaseKeepalive(Handle timer, any data)
{
    if (timer != g_hDbKeepaliveTimer)
    {
        return Plugin_Stop;
    }

    if (g_Database == null || !g_bDatabaseReady)
    {
        return Plugin_Continue;
    }

    g_Database.Query(SQL_OnDatabaseKeepalive, "SELECT 1");
    return Plugin_Continue;
}

public void SQL_OnDatabaseKeepalive(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0])
    {
        LogError("[Clans] Database keepalive failed: %s", error);
        HandleDatabaseConnectionLoss(error);
    }
}

void HandleDatabaseConnectionLoss(const char[] error)
{
    if (!IsDatabaseConnectionLostError(error))
    {
        return;
    }

    DropDatabaseConnection();
    ScheduleDatabaseReconnect();
}

bool EnsureDatabaseReady(int client = 0)
{
    if (g_Database != null && g_bDatabaseReady)
    {
        return true;
    }

    if (client > 0 && IsClientInGame(client))
    {
        PrintToChat(client, "[Clans] Database is not ready yet. Please try again in a moment.");
    }

    return false;
}


