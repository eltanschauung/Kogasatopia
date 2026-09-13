/** Short-lived authenticated sessions for the interactive weapons MOTD. */

#define WEAPONS_WEB_SESSIONS_TABLE "weapons_web_sessions"
#define WEAPONS_WEB_ACTIONS_TABLE "weapons_web_actions"
#define WEAPONS_WEB_SESSION_LIFETIME 900
#define WEAPONS_WEB_POLL_INTERVAL 0.25
#define WEAPONS_WEB_ACTION_LIMIT 8

static Database g_WeaponsWebDb = null;
static bool g_WeaponsWebDbReady;
static bool g_WeaponsWebIsMySql;
static bool g_WeaponsWebPollPending;
static int g_WeaponsWebConnectionGeneration;
static int g_WeaponsWebActiveUntil;
static int g_WeaponsWebLastPrune;
static Handle g_WeaponsWebReconnectTimer = null;
static Handle g_WeaponsWebPollTimer = null;
static ConVar g_WeaponsWebDatabaseCvar;
static StringMap g_WeaponsWebActionsInFlight;
static char g_WeaponsWebServerStamp[33];

void WeaponsWeb_OnPluginStart()
{
	g_WeaponsWebDatabaseCvar = CreateConVar("sm_weapons_web_database", "default",
		"Database config used by interactive weapon MOTD sessions.");
	g_WeaponsWebDatabaseCvar.AddChangeHook(WeaponsWeb_OnDatabaseChanged);
	g_WeaponsWebActionsInFlight = new StringMap();
	WeaponsWeb_GenerateToken(g_WeaponsWebServerStamp, sizeof(g_WeaponsWebServerStamp));
	g_WeaponsWebPollTimer = CreateTimer(WEAPONS_WEB_POLL_INTERVAL, WeaponsWeb_PollTimer,
		_, TIMER_REPEAT);
	WeaponsWeb_ConnectDatabase();
}

void WeaponsWeb_OnPluginEnd()
{
	delete g_WeaponsWebPollTimer;
	g_WeaponsWebPollTimer = null;
	WeaponsWeb_StopConnection();
	delete g_WeaponsWebActionsInFlight;
	g_WeaponsWebActionsInFlight = null;
}

public void WeaponsWeb_OnDatabaseChanged(ConVar convar, const char[] oldValue,
	const char[] newValue)
{
	WeaponsWeb_ConnectDatabase();
}

static void WeaponsWeb_StopConnection()
{
	g_WeaponsWebConnectionGeneration++;
	Db_CancelTimer(g_WeaponsWebReconnectTimer);
	Db_Close(g_WeaponsWebDb, g_WeaponsWebDbReady);
	g_WeaponsWebPollPending = false;
	if (g_WeaponsWebActionsInFlight != null) g_WeaponsWebActionsInFlight.Clear();
}

static bool WeaponsWeb_IsCurrentConnection(Database db, int generation)
{
	return generation == g_WeaponsWebConnectionGeneration && db != null
		&& g_WeaponsWebDb != null && db.IsSameConnection(g_WeaponsWebDb);
}

static void WeaponsWeb_ConnectDatabase()
{
	WeaponsWeb_StopConnection();
	char config[64];
	g_WeaponsWebDatabaseCvar.GetString(config, sizeof(config));
	TrimString(config);
	if (!config[0]) strcopy(config, sizeof(config), "default");
	if (!Db_CheckConfigOrLog("weapons web", config)) return;
	SQL_TConnect(WeaponsWeb_OnDatabaseConnected, config, g_WeaponsWebConnectionGeneration);
}

public void WeaponsWeb_OnDatabaseConnected(Handle owner, Handle hndl, const char[] error,
	any generation)
{
	if (generation != g_WeaponsWebConnectionGeneration)
	{
		delete hndl;
		return;
	}
	if (hndl == null)
	{
		LogError("[Weapons] Web loadout database connection failed: %s",
			error[0] ? error : "unknown error");
		WeaponsWeb_ScheduleReconnect();
		return;
	}
	Db_Close(g_WeaponsWebDb, g_WeaponsWebDbReady);
	g_WeaponsWebDb = view_as<Database>(hndl);
	char driverName[32];
	DBDriver driver = g_WeaponsWebDb.Driver;
	driver.GetIdentifier(driverName, sizeof(driverName));
	g_WeaponsWebIsMySql = StrEqual(driverName, "mysql", false);
	if (g_WeaponsWebIsMySql && !g_WeaponsWebDb.SetCharset("utf8mb4"))
	{
		LogError("[Weapons] Failed to set web loadout database charset to utf8mb4.");
	}
	WeaponsWeb_EnsureSessionSchema();
}

static void WeaponsWeb_ScheduleReconnect(float delay = DB_RECONNECT_DELAY)
{
	g_WeaponsWebDbReady = false;
	if (g_WeaponsWebReconnectTimer != null) return;
	g_WeaponsWebReconnectTimer = CreateTimer(delay, WeaponsWeb_ReconnectTimer,
		g_WeaponsWebConnectionGeneration);
}

public Action WeaponsWeb_ReconnectTimer(Handle timer, any generation)
{
	if (timer != g_WeaponsWebReconnectTimer) return Plugin_Stop;
	g_WeaponsWebReconnectTimer = null;
	if (generation == g_WeaponsWebConnectionGeneration) WeaponsWeb_ConnectDatabase();
	return Plugin_Stop;
}

static void WeaponsWeb_EnsureSessionSchema()
{
	char query[2048], suffix[512];
	if (g_WeaponsWebIsMySql)
	{
		strcopy(suffix, sizeof(suffix),
			", KEY idx_weapons_web_sessions_expiry (expires_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
	}
	else
	{
		strcopy(suffix, sizeof(suffix), ")");
	}
	FormatEx(query, sizeof(query),
		"CREATE TABLE IF NOT EXISTS %s (token VARCHAR(32) NOT NULL, "
		... "steamid64 VARCHAR(32) NOT NULL, server_stamp VARCHAR(32) NOT NULL, "
		... "class_index INTEGER NOT NULL, equipped_uids VARCHAR(512) NOT NULL DEFAULT '', "
		... "created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, PRIMARY KEY (token)%s",
		WEAPONS_WEB_SESSIONS_TABLE, suffix);
	g_WeaponsWebDb.Query(WeaponsWeb_OnSessionSchemaReady, query,
		g_WeaponsWebConnectionGeneration);
}

public void WeaponsWeb_OnSessionSchemaReady(Database db, DBResultSet results,
	const char[] error, any generation)
{
	if (!WeaponsWeb_IsCurrentConnection(db, generation)) return;
	if (error[0])
	{
		LogError("[Weapons] Failed to create web session schema: %s", error);
		if (Db_IsTransientError(error)) WeaponsWeb_ScheduleReconnect(DB_RECONNECT_FAST_DELAY);
		return;
	}
	char query[3072], suffix[768], booleanType[16];
	strcopy(booleanType, sizeof(booleanType), g_WeaponsWebIsMySql ? "TINYINT(1)" : "INTEGER");
	if (g_WeaponsWebIsMySql)
	{
		strcopy(suffix, sizeof(suffix),
			", KEY idx_weapons_web_actions_pending (status, created_at), "
			... "KEY idx_weapons_web_actions_session (session_token)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
	}
	else
	{
		strcopy(suffix, sizeof(suffix), ")");
	}
	FormatEx(query, sizeof(query),
		"CREATE TABLE IF NOT EXISTS %s (action_id VARCHAR(36) NOT NULL, "
		... "session_token VARCHAR(32) NOT NULL, weapon_uid VARCHAR(64) NOT NULL, "
		... "desired_equipped %s NOT NULL, status VARCHAR(16) NOT NULL DEFAULT 'pending', "
		... "result_loadout VARCHAR(512) NOT NULL DEFAULT '', error_code VARCHAR(64) NOT NULL DEFAULT '', "
		... "created_at INTEGER NOT NULL, processed_at INTEGER NOT NULL DEFAULT 0, "
		... "PRIMARY KEY (action_id)%s",
		WEAPONS_WEB_ACTIONS_TABLE, booleanType, suffix);
	g_WeaponsWebDb.Query(WeaponsWeb_OnActionSchemaReady, query, generation);
}

public void WeaponsWeb_OnActionSchemaReady(Database db, DBResultSet results,
	const char[] error, any generation)
{
	if (!WeaponsWeb_IsCurrentConnection(db, generation)) return;
	if (error[0])
	{
		LogError("[Weapons] Failed to create web action schema: %s", error);
		if (Db_IsTransientError(error)) WeaponsWeb_ScheduleReconnect(DB_RECONNECT_FAST_DELAY);
		return;
	}
	g_WeaponsWebDbReady = true;
	Db_CancelTimer(g_WeaponsWebReconnectTimer);
	if (!g_WeaponsWebIsMySql)
	{
		g_WeaponsWebDb.Query(WeaponsWeb_OnMaintenanceQuery,
			"CREATE INDEX IF NOT EXISTS idx_weapons_web_sessions_expiry ON weapons_web_sessions (expires_at)", generation);
		g_WeaponsWebDb.Query(WeaponsWeb_OnMaintenanceQuery,
			"CREATE INDEX IF NOT EXISTS idx_weapons_web_actions_pending ON weapons_web_actions (status, created_at)", generation);
		g_WeaponsWebDb.Query(WeaponsWeb_OnMaintenanceQuery,
			"CREATE INDEX IF NOT EXISTS idx_weapons_web_actions_session ON weapons_web_actions (session_token)", generation);
	}
	WeaponsWeb_PruneExpired(true);
}

public void WeaponsWeb_OnMaintenanceQuery(Database db, DBResultSet results,
	const char[] error, any generation)
{
	if (!error[0]) return;
	LogError("[Weapons] Web loadout maintenance query failed: %s", error);
	if (WeaponsWeb_IsCurrentConnection(db, generation) && Db_IsTransientError(error))
	{
		WeaponsWeb_ScheduleReconnect(DB_RECONNECT_FAST_DELAY);
	}
}

bool WeaponsWeb_TryOpenPanel(int client, int playerClass, const char[] classKey)
{
	if (!g_WeaponsWebDbReady || !Weapons_LoadoutClientValid(client) || !IsClientInGame(client)
		|| IsFakeClient(client) || !Weapons_LoadoutClassValid(playerClass)
		|| !AreClientCookiesCached(client)) return false;
	char steamId[KOGASA_STEAMID_MAX];
	if (!Kogasa_GetClientSteamId64(client, steamId, sizeof(steamId), true)) return false;
	char token[33], loadout[512];
	WeaponsWeb_GenerateToken(token, sizeof(token));
	WeaponsWeb_BuildLoadout(client, playerClass, loadout, sizeof(loadout));
	char escapedToken[65], escapedSteam[(KOGASA_STEAMID_MAX * 2) + 1];
	char escapedStamp[65], escapedLoadout[1025];
	if (!Db_Escape(g_WeaponsWebDb, token, escapedToken, sizeof(escapedToken), "weapons web")
		|| !Db_Escape(g_WeaponsWebDb, steamId, escapedSteam, sizeof(escapedSteam), "weapons web")
		|| !Db_Escape(g_WeaponsWebDb, g_WeaponsWebServerStamp, escapedStamp, sizeof(escapedStamp), "weapons web")
		|| !Db_Escape(g_WeaponsWebDb, loadout, escapedLoadout, sizeof(escapedLoadout), "weapons web")) return false;
	int now = GetTime();
	char query[2048];
	FormatEx(query, sizeof(query),
		"INSERT INTO %s (token, steamid64, server_stamp, class_index, equipped_uids, created_at, expires_at) "
		... "VALUES ('%s', '%s', '%s', %d, '%s', %d, %d)",
		WEAPONS_WEB_SESSIONS_TABLE, escapedToken, escapedSteam, escapedStamp,
		playerClass, escapedLoadout, now, now + WEAPONS_WEB_SESSION_LIFETIME);
	DataPack pack = new DataPack();
	pack.WriteCell(g_WeaponsWebConnectionGeneration);
	pack.WriteCell(GetClientSerial(client));
	pack.WriteString(classKey);
	pack.WriteString(token);
	g_WeaponsWebDb.Query(WeaponsWeb_OnSessionCreated, query, pack);
	g_WeaponsWebActiveUntil = now + WEAPONS_WEB_SESSION_LIFETIME;
	return true;
}

public void WeaponsWeb_OnSessionCreated(Database db, DBResultSet results,
	const char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int generation = pack.ReadCell();
	int serial = pack.ReadCell();
	char classKey[16], token[33];
	pack.ReadString(classKey, sizeof(classKey));
	pack.ReadString(token, sizeof(token));
	delete pack;
	int client = GetClientFromSerial(serial);
	if (!Weapons_LoadoutClientValid(client) || !IsClientInGame(client)) return;
	if (!WeaponsWeb_IsCurrentConnection(db, generation) || error[0])
	{
		if (error[0]) LogError("[Weapons] Failed to create web loadout session: %s", error);
		WeaponsCommands_ShowClassPage(client, true, classKey, "");
		return;
	}
	WeaponsCommands_ShowClassPage(client, true, classKey, token);
}

static void WeaponsWeb_GenerateToken(char[] token, int maxlen)
{
	FormatEx(token, maxlen, "%08x%08x%08x%08x", GetURandomInt(), GetURandomInt(),
		GetURandomInt(), GetURandomInt());
}

static void WeaponsWeb_BuildLoadout(int client, int playerClass, char[] buffer, int maxlen)
{
	buffer[0] = '\0';
	for (int slot; slot < NUM_ITEMS; slot++)
	{
		char uid[MAX_ITEM_IDENTIFIER_LENGTH];
		strcopy(uid, sizeof(uid), g_CurrentLoadout[client][playerClass][slot].uid);
		if (!uid[0]) continue;
		if (buffer[0]) StrCat(buffer, maxlen, "|");
		StrCat(buffer, maxlen, uid);
	}
}

public Action WeaponsWeb_PollTimer(Handle timer)
{
	if (!g_WeaponsWebDbReady || g_WeaponsWebPollPending
		|| GetTime() > g_WeaponsWebActiveUntil) return Plugin_Continue;
	g_WeaponsWebPollPending = true;
	char escapedStamp[65], query[2048];
	if (!Db_Escape(g_WeaponsWebDb, g_WeaponsWebServerStamp, escapedStamp,
		sizeof(escapedStamp), "weapons web"))
	{
		g_WeaponsWebPollPending = false;
		return Plugin_Continue;
	}
	FormatEx(query, sizeof(query),
		"SELECT a.action_id, a.session_token, a.weapon_uid, a.desired_equipped, "
		... "s.steamid64, s.class_index FROM %s a INNER JOIN %s s ON s.token = a.session_token "
		... "WHERE a.status = 'pending' AND s.server_stamp = '%s' AND s.expires_at >= %d "
		... "ORDER BY a.created_at ASC, a.action_id ASC LIMIT %d",
		WEAPONS_WEB_ACTIONS_TABLE, WEAPONS_WEB_SESSIONS_TABLE, escapedStamp,
		GetTime(), WEAPONS_WEB_ACTION_LIMIT);
	g_WeaponsWebDb.Query(WeaponsWeb_OnActionsFetched, query,
		g_WeaponsWebConnectionGeneration);
	WeaponsWeb_PruneExpired(false);
	return Plugin_Continue;
}

public void WeaponsWeb_OnActionsFetched(Database db, DBResultSet results,
	const char[] error, any generation)
{
	if (generation == g_WeaponsWebConnectionGeneration) g_WeaponsWebPollPending = false;
	if (!WeaponsWeb_IsCurrentConnection(db, generation)) return;
	if (error[0])
	{
		LogError("[Weapons] Failed to poll web loadout actions: %s", error);
		if (Db_IsTransientError(error)) WeaponsWeb_ScheduleReconnect(DB_RECONNECT_FAST_DELAY);
		return;
	}
	if (results == null) return;
	while (results.FetchRow())
	{
		char actionId[37], sessionToken[33], uid[MAX_ITEM_IDENTIFIER_LENGTH];
		char steamId[KOGASA_STEAMID_MAX];
		results.FetchString(0, actionId, sizeof(actionId));
		int ignored;
		if (g_WeaponsWebActionsInFlight.GetValue(actionId, ignored)) continue;
		results.FetchString(1, sessionToken, sizeof(sessionToken));
		results.FetchString(2, uid, sizeof(uid));
		bool desiredEquipped = results.FetchInt(3) != 0;
		results.FetchString(4, steamId, sizeof(steamId));
		int playerClass = results.FetchInt(5);
		g_WeaponsWebActionsInFlight.SetValue(actionId, 1);
		WeaponsWeb_ProcessAction(actionId, sessionToken, steamId, playerClass,
			uid, desiredEquipped);
	}
}

static void WeaponsWeb_ProcessAction(const char[] actionId, const char[] sessionToken,
	const char[] steamId, int playerClass, const char[] uid, bool desiredEquipped)
{
	int client = WeaponsWeb_FindClient(steamId);
	char errorCode[64];
	errorCode[0] = '\0';
	bool success;
	CustomItemDefinition item;
	if (!Weapons_LoadoutClassValid(playerClass))
	{
		strcopy(errorCode, sizeof(errorCode), "invalid_class");
	}
	else if (client == 0)
	{
		strcopy(errorCode, sizeof(errorCode), "client_offline");
	}
	else if (!AreClientCookiesCached(client))
	{
		strcopy(errorCode, sizeof(errorCode), "cookies_unavailable");
	}
	else if (!GetCustomItemDefinition(uid, item)
		|| item.loadoutPosition[playerClass] < 0 || item.loadoutPosition[playerClass] >= NUM_ITEMS)
	{
		strcopy(errorCode, sizeof(errorCode), "invalid_item");
	}
	else if (desiredEquipped)
	{
		if (!CanPlayerViewItem(client, item))
		{
			strcopy(errorCode, sizeof(errorCode), "access_denied");
		}
		else if (ItemRequiresPointsStorePurchase(client, item))
		{
			WeaponsLoadout_PrintShopPurchaseRequired(client);
			strcopy(errorCode, sizeof(errorCode), "purchase_required");
		}
		else if (!SetClientCustomLoadoutItem(client, playerClass, uid,
			LOADOUT_FLAG_UPDATE_BACKEND | LOADOUT_FLAG_ATTEMPT_REGEN))
		{
			strcopy(errorCode, sizeof(errorCode), "equip_failed");
		}
		else
		{
			WeaponsLoadout_QueueEquippedItemDescription(client, uid);
			success = true;
		}
	}
	else
	{
		int slot = item.loadoutPosition[playerClass];
		if (StrEqual(g_CurrentLoadout[client][playerClass][slot].uid, uid, false))
		{
			UnsetClientCustomLoadoutItem(client, playerClass, slot,
				LOADOUT_FLAG_UPDATE_BACKEND | LOADOUT_FLAG_ATTEMPT_REGEN);
		}
		success = true;
	}
	if (success && client > 0) EmitSoundToClient(client, SOUND_MENU_BUTTON_EQUIP);
	char loadout[512];
	loadout[0] = '\0';
	if (client > 0 && Weapons_LoadoutClassValid(playerClass))
	{
		WeaponsWeb_BuildLoadout(client, playerClass, loadout, sizeof(loadout));
	}
	WeaponsWeb_CompleteAction(actionId, sessionToken, loadout, success, errorCode);
}

static int WeaponsWeb_FindClient(const char[] steamId)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client)) continue;
		char candidate[KOGASA_STEAMID_MAX];
		if (Kogasa_GetClientSteamId64(client, candidate, sizeof(candidate), true)
			&& StrEqual(candidate, steamId, false)) return client;
	}
	return 0;
}

static void WeaponsWeb_CompleteAction(const char[] actionId, const char[] sessionToken,
	const char[] loadout, bool success, const char[] errorCode)
{
	char escapedAction[73], escapedSession[65], escapedLoadout[1025], escapedError[129];
	if (!Db_Escape(g_WeaponsWebDb, actionId, escapedAction, sizeof(escapedAction), "weapons web")
		|| !Db_Escape(g_WeaponsWebDb, sessionToken, escapedSession, sizeof(escapedSession), "weapons web")
		|| !Db_Escape(g_WeaponsWebDb, loadout, escapedLoadout, sizeof(escapedLoadout), "weapons web")
		|| !Db_Escape(g_WeaponsWebDb, errorCode, escapedError, sizeof(escapedError), "weapons web"))
	{
		g_WeaponsWebActionsInFlight.Remove(actionId);
		return;
	}
	char sessionQuery[1536], actionQuery[2048];
	FormatEx(sessionQuery, sizeof(sessionQuery),
		"UPDATE %s SET equipped_uids = '%s' WHERE token = '%s'",
		WEAPONS_WEB_SESSIONS_TABLE, escapedLoadout, escapedSession);
	FormatEx(actionQuery, sizeof(actionQuery),
		"UPDATE %s SET status = '%s', result_loadout = '%s', error_code = '%s', processed_at = %d "
		... "WHERE action_id = '%s' AND session_token = '%s' AND status = 'pending'",
		WEAPONS_WEB_ACTIONS_TABLE, success ? "success" : "error", escapedLoadout,
		escapedError, GetTime(), escapedAction, escapedSession);
	Transaction transaction = new Transaction();
	transaction.AddQuery(sessionQuery);
	transaction.AddQuery(actionQuery);
	DataPack pack = new DataPack();
	pack.WriteCell(g_WeaponsWebConnectionGeneration);
	pack.WriteString(actionId);
	g_WeaponsWebDb.Execute(transaction, WeaponsWeb_OnActionCompleted,
		WeaponsWeb_OnActionCompletionFailed, pack);
}

public void WeaponsWeb_OnActionCompleted(Database db, any data, int numQueries,
	DBResultSet[] results, any[] queryData)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	pack.ReadCell();
	char actionId[37];
	pack.ReadString(actionId, sizeof(actionId));
	delete pack;
	if (g_WeaponsWebActionsInFlight != null) g_WeaponsWebActionsInFlight.Remove(actionId);

}

public void WeaponsWeb_OnActionCompletionFailed(Database db, any data, int numQueries,
	const char[] error, int failIndex, any[] queryData)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int generation = pack.ReadCell();
	char actionId[37];
	pack.ReadString(actionId, sizeof(actionId));
	delete pack;
	if (g_WeaponsWebActionsInFlight != null) g_WeaponsWebActionsInFlight.Remove(actionId);
	LogError("[Weapons] Failed to finish web loadout action at query %d: %s",
		failIndex, error);
	if (WeaponsWeb_IsCurrentConnection(db, generation) && Db_IsTransientError(error))
	{
		WeaponsWeb_ScheduleReconnect(DB_RECONNECT_FAST_DELAY);
	}
}

static void WeaponsWeb_PruneExpired(bool force)
{
	int now = GetTime();
	if (!force && now - g_WeaponsWebLastPrune < 600) return;
	g_WeaponsWebLastPrune = now;
	char query[256];
	FormatEx(query, sizeof(query), "DELETE FROM %s WHERE created_at < %d",
		WEAPONS_WEB_ACTIONS_TABLE, now - 3600);
	g_WeaponsWebDb.Query(WeaponsWeb_OnMaintenanceQuery, query,
		g_WeaponsWebConnectionGeneration);
	FormatEx(query, sizeof(query), "DELETE FROM %s WHERE expires_at < %d",
		WEAPONS_WEB_SESSIONS_TABLE, now);
	g_WeaponsWebDb.Query(WeaponsWeb_OnMaintenanceQuery, query,
		g_WeaponsWebConnectionGeneration);
}
