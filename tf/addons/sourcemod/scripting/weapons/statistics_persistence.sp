/** Statistics I/O is threaded. A generation owns each connect/schema/retry cycle. */
int g_WeaponsStatsConnectionGeneration;

void WeaponsStats_StopConnection()
{
    g_WeaponsStatsConnectionGeneration++;
    Db_CancelTimer(g_hWeaponsStatsDbReconnectTimer);
    Db_Close(g_WeaponsStatsDb, g_WeaponsStatsDbReady);
}

void OnWeaponsStatisticsEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (StringToInt(newValue)) ConnectWeaponsStatisticsDatabase();
    else WeaponsStats_StopConnection();
}

void OnWeaponsStatisticsDatabaseChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    ConnectWeaponsStatisticsDatabase();
}

bool WeaponsStats_IsEnabled()
{
    return sm_weapons_statistics == null || sm_weapons_statistics.BoolValue;
}

bool WeaponsStats_CanWriteState()
{
    return WeaponsStats_IsEnabled() && Db_IsReady(g_WeaponsStatsDb, g_WeaponsStatsDbReady);
}

bool WeaponsStats_IsCurrentConnection(Database db, int generation)
{
    return generation == g_WeaponsStatsConnectionGeneration && WeaponsStats_IsEnabled()
        && db != null && g_WeaponsStatsDb != null && db.IsSameConnection(g_WeaponsStatsDb);
}

void ConnectWeaponsStatisticsDatabase()
{
    WeaponsStats_StopConnection();
    if (!WeaponsStats_IsEnabled()) return;
    char config[64];
    sm_weapons_statistics_database.GetString(config, sizeof(config));
    TrimString(config);
    if (!config[0]) strcopy(config, sizeof(config), WEAPONS_STATS_DB_CONFIG_DEFAULT);
    if (!Db_CheckConfigOrLog("weapons", config)) return;
    SQL_TConnect(WeaponsStats_OnDatabaseConnected, config, g_WeaponsStatsConnectionGeneration);
}

public void WeaponsStats_OnDatabaseConnected(Handle owner, Handle hndl, const char[] error, any generation)
{
    if (generation != g_WeaponsStatsConnectionGeneration || !WeaponsStats_IsEnabled())
    {
        delete hndl;
        return;
    }
    if (hndl == null)
    {
        LogError("[Weapons] Statistics database connection failed: %s", error[0] ? error : "unknown error");
        ScheduleWeaponsStatsDatabaseReconnect();
        return;
    }
    Db_Close(g_WeaponsStatsDb, g_WeaponsStatsDbReady);
    g_WeaponsStatsDb = view_as<Database>(hndl);
    char driverName[32];
    DBDriver driver = g_WeaponsStatsDb.Driver;
    driver.GetIdentifier(driverName, sizeof(driverName));
    g_WeaponsStatsIsMySql = StrEqual(driverName, "mysql", false);
    if (g_WeaponsStatsIsMySql && !g_WeaponsStatsDb.SetCharset("utf8mb4"))
    {
        LogError("[Weapons] Failed to set statistics database charset to utf8mb4.");
    }
    EnsureWeaponsStatsSchema();
}

void ScheduleWeaponsStatsDatabaseReconnect(float delay = DB_RECONNECT_DELAY)
{
    g_WeaponsStatsDbReady = false;
    if (!WeaponsStats_IsEnabled() || g_hWeaponsStatsDbReconnectTimer != null) return;
    // Persistent, explicitly owned: map cancellation must not leave a stale handle.
    g_hWeaponsStatsDbReconnectTimer = CreateTimer(delay, Timer_ReconnectWeaponsStatsDatabase,
        g_WeaponsStatsConnectionGeneration);
}

public Action Timer_ReconnectWeaponsStatsDatabase(Handle timer, any generation)
{
    if (timer != g_hWeaponsStatsDbReconnectTimer) return Plugin_Stop;
    g_hWeaponsStatsDbReconnectTimer = null;
    if (generation == g_WeaponsStatsConnectionGeneration) ConnectWeaponsStatisticsDatabase();
    return Plugin_Stop;
}

void EnsureWeaponsStatsSchema()
{
    if (g_WeaponsStatsDb == null) return;
    char query[2048];
    char smallInt[16], booleanType[16], suffix[512];
    strcopy(smallInt, sizeof(smallInt), g_WeaponsStatsIsMySql ? "TINYINT" : "INTEGER");
    strcopy(booleanType, sizeof(booleanType), g_WeaponsStatsIsMySql ? "TINYINT(1)" : "INTEGER");
    if (g_WeaponsStatsIsMySql)
    {
        strcopy(suffix, sizeof(suffix),
            ", KEY idx_cwx_weapon_equipped (weapon_uid, equipped), "
            ... "KEY idx_cwx_weapon_unique (weapon_uid, steamid64), "
            ... "KEY idx_cwx_class_weapon (class_name, weapon_uid)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    }
    else
    {
        strcopy(suffix, sizeof(suffix), ")");
    }
    FormatEx(query, sizeof(query),
        "CREATE TABLE IF NOT EXISTS %s (steamid64 VARCHAR(32) NOT NULL, "
        ... "player_name VARCHAR(128) NOT NULL DEFAULT '', class_index %s NOT NULL, "
        ... "class_name VARCHAR(16) NOT NULL DEFAULT '', loadout_slot %s NOT NULL, "
        ... "weapon_uid VARCHAR(64) NOT NULL, weapon_name VARCHAR(128) NOT NULL DEFAULT '', "
        ... "equipped %s NOT NULL DEFAULT 0, first_equipped_at INTEGER NOT NULL DEFAULT 0, "
        ... "last_equipped_at INTEGER NOT NULL DEFAULT 0, last_unequipped_at INTEGER NOT NULL DEFAULT 0, "
        ... "equip_count INTEGER NOT NULL DEFAULT 0, unequip_count INTEGER NOT NULL DEFAULT 0, "
        ... "updated_at INTEGER NOT NULL DEFAULT 0, "
        ... "PRIMARY KEY (steamid64, class_index, loadout_slot, weapon_uid)%s",
        WEAPONS_STATS_STATE_TABLE, smallInt, smallInt, booleanType, suffix);
    g_WeaponsStatsDb.Query(WeaponsStats_OnSchemaReady, query, g_WeaponsStatsConnectionGeneration);
}

public void WeaponsStats_OnSchemaReady(Database db, DBResultSet results, const char[] error, any generation)
{
    if (!WeaponsStats_IsCurrentConnection(db, generation)) return;
    if (error[0])
    {
        LogError("[Weapons] Failed to create statistics schema: %s", error);
        if (Db_IsTransientError(error)) ScheduleWeaponsStatsDatabaseReconnect();
        return;
    }
    g_WeaponsStatsDbReady = true;
    Db_CancelTimer(g_hWeaponsStatsDbReconnectTimer);
    if (!g_WeaponsStatsIsMySql)
    {
        g_WeaponsStatsDb.Query(WeaponsStats_OnQueryComplete,
            "CREATE INDEX IF NOT EXISTS idx_cwx_weapon_equipped ON cwx_weapon_popularity (weapon_uid, equipped)", generation);
        g_WeaponsStatsDb.Query(WeaponsStats_OnQueryComplete,
            "CREATE INDEX IF NOT EXISTS idx_cwx_weapon_unique ON cwx_weapon_popularity (weapon_uid, steamid64)", generation);
        g_WeaponsStatsDb.Query(WeaponsStats_OnQueryComplete,
            "CREATE INDEX IF NOT EXISTS idx_cwx_class_weapon ON cwx_weapon_popularity (class_name, weapon_uid)", generation);
    }
    WeaponsStats_MirrorLoadedClients();
}

public void WeaponsStats_OnQueryComplete(Database db, DBResultSet results, const char[] error, any generation)
{
    if (!error[0]) return;
    LogError("[Weapons] Statistics query failed: %s", error);
    if (WeaponsStats_IsCurrentConnection(db, generation) && Db_IsTransientError(error))
    {
        ScheduleWeaponsStatsDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
    }
}

public void WeaponsStats_OnTransitionCommitted(Database db, any generation, int numQueries,
    DBResultSet[] results, any[] queryData)
{
    // Statistics have no optimistic client cache to overwrite on completion.
}

public void WeaponsStats_OnTransitionFailed(Database db, any generation, int numQueries,
    const char[] error, int failIndex, any[] queryData)
{
    LogError("[Weapons] Statistics transaction failed at query %d: %s", failIndex, error);
    if (WeaponsStats_IsCurrentConnection(db, generation) && Db_IsTransientError(error))
    {
        ScheduleWeaponsStatsDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
    }
    // Never replay a counter increment after an ambiguous commit result.
}

void WeaponsStats_RecordEquip(int client, int playerClass, int slot, const char[] uid,
    const CustomItemDefinition item)
{
    if (!WeaponsStats_IsEnabled()) return;
    char weaponName[MAX_ITEM_NAME_LENGTH];
    strcopy(weaponName, sizeof(weaponName), item.displayName[0] ? item.displayName : uid);
    WeaponsStats_LogTransition("weapon_equip", client, playerClass, slot, uid, weaponName);
    char steamId[KOGASA_STEAMID_MAX], playerName[MAX_NAME_LENGTH];
    if (!WeaponsStats_GetClientStateIdentity(client, steamId, sizeof(steamId), playerName, sizeof(playerName))) return;
    char clearQuery[1024], equipQuery[2048];
    if (!WeaponsStats_BuildClearSlotQuery(steamId, playerClass, slot, true, clearQuery, sizeof(clearQuery))
        || !WeaponsStats_BuildEquipQuery(steamId, playerName, playerClass, slot, uid, weaponName,
            true, equipQuery, sizeof(equipQuery))) return;
    // The previous state and replacement commit together, rather than as two tasks.
    Transaction transaction = new Transaction();
    transaction.AddQuery(clearQuery);
    transaction.AddQuery(equipQuery);
    g_WeaponsStatsDb.Execute(transaction, WeaponsStats_OnTransitionCommitted,
        WeaponsStats_OnTransitionFailed, g_WeaponsStatsConnectionGeneration);
}

void WeaponsStats_RecordUnequip(int client, int playerClass, int slot, const char[] uid,
    bool clearState = true)
{
    if (!WeaponsStats_IsEnabled()) return;
    char weaponName[MAX_ITEM_NAME_LENGTH];
    WeaponsStats_GetWeaponName(uid, weaponName, sizeof(weaponName));
    WeaponsStats_LogTransition("weapon_unequip", client, playerClass, slot, uid, weaponName);
    if (!clearState) return;
    char steamId[KOGASA_STEAMID_MAX], playerName[MAX_NAME_LENGTH];
    if (WeaponsStats_GetClientStateIdentity(client, steamId, sizeof(steamId), playerName, sizeof(playerName)))
    {
        WeaponsStats_ClearSlotState(steamId, playerClass, slot, true);
    }
}

void WeaponsStats_MirrorLoadedClients()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientConnected(client) && g_bRetrievedLoadout[client]) WeaponsStats_MirrorClientSavedLoadout(client);
    }
}

void WeaponsStats_MirrorClientSavedLoadout(int client)
{
    char steamId[KOGASA_STEAMID_MAX], playerName[MAX_NAME_LENGTH];
    if (!WeaponsStats_GetClientStateIdentity(client, steamId, sizeof(steamId), playerName, sizeof(playerName))) return;
    for (int playerClass = 1; playerClass < NUM_PLAYER_CLASSES; playerClass++)
    {
        for (int slot = 0; slot < NUM_ITEMS; slot++)
        {
            char uid[MAX_ITEM_IDENTIFIER_LENGTH], weaponName[MAX_ITEM_NAME_LENGTH];
            strcopy(uid, sizeof(uid), g_CurrentLoadout[client][playerClass][slot].uid);
            if (!uid[0]) continue;
            WeaponsStats_GetWeaponName(uid, weaponName, sizeof(weaponName));
            WeaponsStats_UpsertEquipState(steamId, playerName, playerClass, slot, uid, weaponName, false);
        }
    }
}

bool WeaponsStats_GetClientStateIdentity(int client, char[] steamId, int steamLen, char[] playerName, int nameLen)
{
    if (!WeaponsStats_CanWriteState() || !Kogasa_GetClientSteamId64(client, steamId, steamLen, true)) return false;
    if (!GetClientName(client, playerName, nameLen) || !playerName[0]) strcopy(playerName, nameLen, steamId);
    return true;
}

bool WeaponsStats_BuildClearSlotQuery(const char[] steamId, int playerClass, int slot,
    bool increment, char[] query, int queryLen)
{
    if (!WeaponsStats_CanWriteState()) return false;
    char escapedSteam[(KOGASA_STEAMID_MAX * 2) + 1];
    if (!Db_Escape(g_WeaponsStatsDb, steamId, escapedSteam, sizeof(escapedSteam), "weapons")) return false;
    int now = GetTime();
    int written;
    if (increment)
    {
        // MySQL evaluates assignments left-to-right. Clear equipped AFTER reading it.
        written = FormatEx(query, queryLen,
            "UPDATE %s SET last_unequipped_at = %d, unequip_count = unequip_count + 1, "
            ... "equipped = 0, updated_at = %d WHERE steamid64 = '%s' AND class_index = %d "
            ... "AND loadout_slot = %d AND equipped != 0",
            WEAPONS_STATS_STATE_TABLE, now, now, escapedSteam, playerClass, slot);
    }
    else
    {
        written = FormatEx(query, queryLen,
            "UPDATE %s SET equipped = 0, updated_at = %d WHERE steamid64 = '%s' "
            ... "AND class_index = %d AND loadout_slot = %d AND equipped != 0",
            WEAPONS_STATS_STATE_TABLE, now, escapedSteam, playerClass, slot);
    }
    return written < queryLen - 1;
}

void WeaponsStats_ClearSlotState(const char[] steamId, int playerClass, int slot, bool increment)
{
    char query[1024];
    if (WeaponsStats_BuildClearSlotQuery(steamId, playerClass, slot, increment, query, sizeof(query)))
    {
        g_WeaponsStatsDb.Query(WeaponsStats_OnQueryComplete, query, g_WeaponsStatsConnectionGeneration);
    }
}

bool WeaponsStats_BuildEquipQuery(const char[] steamId, const char[] playerName,
    int playerClass, int slot, const char[] uid, const char[] weaponName, bool increment,
    char[] query, int queryLen)
{
    if (!WeaponsStats_CanWriteState()) return false;
    char className[16];
    WeaponsStats_GetClassName(playerClass, className, sizeof(className));
    char escapedSteam[(KOGASA_STEAMID_MAX * 2) + 1], escapedName[257], escapedClass[33];
    char escapedUid[(MAX_ITEM_IDENTIFIER_LENGTH * 2) + 1], escapedWeapon[(MAX_ITEM_NAME_LENGTH * 2) + 1];
    if (!Db_Escape(g_WeaponsStatsDb, steamId, escapedSteam, sizeof(escapedSteam), "weapons")
        || !Db_Escape(g_WeaponsStatsDb, playerName, escapedName, sizeof(escapedName), "weapons")
        || !Db_Escape(g_WeaponsStatsDb, className, escapedClass, sizeof(escapedClass), "weapons")
        || !Db_Escape(g_WeaponsStatsDb, uid, escapedUid, sizeof(escapedUid), "weapons")
        || !Db_Escape(g_WeaponsStatsDb, weaponName, escapedWeapon, sizeof(escapedWeapon), "weapons")) return false;
    int now = GetTime();
    int count = increment ? 1 : 0;
    int written = FormatEx(query, queryLen,
        "INSERT INTO %s (steamid64, player_name, class_index, class_name, loadout_slot, "
        ... "weapon_uid, weapon_name, equipped, first_equipped_at, last_equipped_at, "
        ... "last_unequipped_at, equip_count, unequip_count, updated_at) "
        ... "VALUES ('%s', '%s', %d, '%s', %d, '%s', '%s', 1, %d, %d, 0, 1, 0, %d) ",
        WEAPONS_STATS_STATE_TABLE, escapedSteam, escapedName, playerClass, escapedClass,
        slot, escapedUid, escapedWeapon, now, now, now);
    if (written >= queryLen - 1) return false;
    char update[768];
    if (g_WeaponsStatsIsMySql)
    {
        FormatEx(update, sizeof(update),
            "ON DUPLICATE KEY UPDATE player_name = VALUES(player_name), class_name = VALUES(class_name), "
            ... "weapon_name = VALUES(weapon_name), equipped = 1, last_equipped_at = VALUES(last_equipped_at), "
            ... "equip_count = equip_count + %d, updated_at = VALUES(updated_at)", count);
    }
    else
    {
        FormatEx(update, sizeof(update),
            "ON CONFLICT(steamid64, class_index, loadout_slot, weapon_uid) DO UPDATE SET "
            ... "player_name = excluded.player_name, class_name = excluded.class_name, weapon_name = excluded.weapon_name, "
            ... "equipped = 1, last_equipped_at = excluded.last_equipped_at, equip_count = %s.equip_count + %d, "
            ... "updated_at = excluded.updated_at", WEAPONS_STATS_STATE_TABLE, count);
    }
    if (written + strlen(update) >= queryLen) return false;
    StrCat(query, queryLen, update);
    return true;
}

void WeaponsStats_UpsertEquipState(const char[] steamId, const char[] playerName,
    int playerClass, int slot, const char[] uid, const char[] weaponName, bool increment)
{
    char query[2048];
    if (WeaponsStats_BuildEquipQuery(steamId, playerName, playerClass, slot, uid, weaponName, increment, query, sizeof(query)))
    {
        g_WeaponsStatsDb.Query(WeaponsStats_OnQueryComplete, query, g_WeaponsStatsConnectionGeneration);
    }
}

void WeaponsStats_GetWeaponName(const char[] uid, char[] buffer, int maxlen)
{
    CustomItemDefinition item;
    if (GetCustomItemDefinition(uid, item) && item.displayName[0]) strcopy(buffer, maxlen, item.displayName);
    else strcopy(buffer, maxlen, uid);
}

void WeaponsStats_GetClassName(int playerClass, char[] buffer, int maxlen)
{
    TF2Classes_GetKey(view_as<TFClassType>(playerClass), buffer, maxlen, "unknown");
}

void WeaponsStats_SanitizeField(char[] value, int maxlen)
{
    ReplaceString(value, maxlen, "|", "/", false);
    ReplaceString(value, maxlen, "\r", " ", false);
    ReplaceString(value, maxlen, "\n", " ", false);
    ReplaceString(value, maxlen, "\t", " ", false);
    ReplaceString(value, maxlen, "\"", "'", false);
    TrimString(value);
}

void WeaponsStats_LogTransition(const char[] eventName, int client, int playerClass, int slot,
    const char[] uid, const char[] weaponName)
{
    char steamId[KOGASA_STEAMID_MAX] = "unknown", playerName[MAX_NAME_LENGTH] = "unknown";
    char className[16], safeEvent[64], safeUid[MAX_ITEM_IDENTIFIER_LENGTH], safeWeapon[MAX_ITEM_NAME_LENGTH];
    int userId;
    if (client > 0 && client <= MaxClients && IsClientConnected(client))
    {
        Kogasa_GetClientSteamId64(client, steamId, sizeof(steamId), true);
        GetClientName(client, playerName, sizeof(playerName));
        userId = GetClientUserId(client);
    }
    WeaponsStats_GetClassName(playerClass, className, sizeof(className));
    strcopy(safeEvent, sizeof(safeEvent), eventName);
    strcopy(safeUid, sizeof(safeUid), uid);
    strcopy(safeWeapon, sizeof(safeWeapon), weaponName);
    WeaponsStats_SanitizeField(steamId, sizeof(steamId));
    WeaponsStats_SanitizeField(playerName, sizeof(playerName));
    WeaponsStats_SanitizeField(className, sizeof(className));
    WeaponsStats_SanitizeField(safeEvent, sizeof(safeEvent));
    WeaponsStats_SanitizeField(safeUid, sizeof(safeUid));
    WeaponsStats_SanitizeField(safeWeapon, sizeof(safeWeapon));
    char message[512];
    FormatEx(message, sizeof(message),
        "event=%s|client=%d|userid=%d|steamid64=%s|name=%s|class=%s|class_index=%d|slot=%d|weapon_uid=%s|weapon_name=%s",
        safeEvent, client, userId, steamId, playerName, className, playerClass, slot, safeUid, safeWeapon);
    PluginStats_Record(safeEvent, message);
}
