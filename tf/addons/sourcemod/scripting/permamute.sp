/**
 * vim: set filetype=c :
 *
 * =============================================================================
 * PermaMute
 *
 * Copyright 2008 Ryan Mannion. All Rights Reserved.
 * =============================================================================
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <sourcemod>
#include <clientprefs>
#include <basecomm>
#include <morecolors>

#undef REQUIRE_PLUGIN
#include <adminmenu>
#include <adminsdb_api>
#include <points_store_api>
#include <filters_api>
#define REQUIRE_PLUGIN

#include "include/database.inc"

#pragma semicolon 1

#define PERMAMUTE_VERSION   "0.2"
#define VOTEMUTE_COST       50
#define VOTEMUTE_DURATION   3600
#define VOTEMUTE_PERCENT    65
#define VOTEMUTE_TIME       20
#define VOTEMUTE_DB_CONFIG  "default"
#define VOTEMUTE_HISTORY_TABLE "permamute_votemute_history"
#define VOTEMUTE_LOCK_TABLE "permamute_votemute_targets"
#define VOTEMUTE_HISTORY_SECONDS (30 * 24 * 60 * 60)
#define VOTEMUTE_PRUNE_INTERVAL 21600.0
#define VOTEMUTE_RETRY_INTERVAL 5.0

#define CVAR_VERSION	    0
#define CVAR_NUM_CVARS	    1

#define COOKIE_PMUTE	    0
#define COOKIE_PGAG	    1
#define COOKIE_VOTESILENCE  2
#define COOKIE_NUM_COOKIES  3

#define ACCESS_FLAG	    ADMFLAG_CHAT

new Handle:g_cvars[CVAR_NUM_CVARS];
new Handle:g_cookies[COOKIE_NUM_COOKIES];
new g_gagged = 0;
new Handle:g_adminMenu = INVALID_HANDLE;
new g_PMuteTarget[33];
new Handle:g_VoteSilenceTimers[MAXPLAYERS + 1];
new bool:g_VoteSilenceOwnsMute[MAXPLAYERS + 1];
new bool:g_VoteSilenceOwnsGag[MAXPLAYERS + 1];
new g_VoteMuteTargetUserId;
new g_VoteMuteChoice[MAXPLAYERS + 1];
new g_VoteMuteWeight[MAXPLAYERS + 1];
new String:g_VoteMuteTargetAuth[32];
new String:g_VoteMuteTargetSteamId64[32];
new String:g_VoteMuteTargetName[MAX_NAME_LENGTH];
new String:g_VoteMuteTargetChatName[256];
Database g_VoteMuteDatabase = null;
bool g_VoteMuteDatabaseReady = false;
Handle g_VoteMuteDatabaseReconnectTimer = null;
Handle g_VoteMutePruneTimer = null;
int g_VoteMuteDatabaseGeneration = 0;

enum PCommType {
    PCommType_PMute = 0,
    PCommType_PUnMute,
    PCommType_PGag,
    PCommType_PUnGag,
    PCommType_PSilence,
    PCommType_PUnSilence,
    PCommType_NumTypes
};

public Plugin:myinfo = {
    name = "PermaMute",
    author = "Ryan \"FLOOR_MASTER\" Mannion, Kogasatopia",
    description = "Enable permanently muting or gagging a player.",
    version = PERMAMUTE_VERSION,
    url = "http://www.2fort2furious.com"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], errMax) {
    MarkNativeAsOptional("AdminsDB_GetClientWhitelistLevel");
    MarkNativeAsOptional("PointsStore_AreBonusPointsLoaded");
    MarkNativeAsOptional("PointsStore_GetBonusPoints");
    MarkNativeAsOptional("PointsStore_SpendBonusPoints");
    MarkNativeAsOptional("PointsStore_RefundBonusPoints");
    MarkNativeAsOptional("Filters_GetChatName");
    return APLRes_Success;
}

public OnPluginStart() {
    LoadTranslations("common.phrases");

    g_cvars[CVAR_VERSION] = CreateConVar(
	"sm_permamute_version",
	PERMAMUTE_VERSION,
	"PermaMute Version",
	FCVAR_PLUGIN|FCVAR_REPLICATED|FCVAR_NOTIFY);

    g_cookies[COOKIE_PMUTE] = RegClientCookie(
	"permamute-mute",
	"PermaMute mute status",
	CookieAccess_Protected);

    g_cookies[COOKIE_PGAG] = RegClientCookie(
	"permamute-gag",
	"PermaMute gag status",
	CookieAccess_Protected);

    g_cookies[COOKIE_VOTESILENCE] = RegClientCookie(
        "permamute-votesilence-until",
        "Vote silence expiry timestamp",
        CookieAccess_Protected);

    SetCookieMenuItem(Menu_Status, 0, "Display PermaMute Status");

    RegConsoleCmd("say", Command_Say);
    RegConsoleCmd("say_team", Command_Say);
    RegConsoleCmd("sm_votemute", Command_VoteMute,
        "sm_votemute <player> - Spend 50 Gems to start a one-hour silence vote.");

    RegAdminCmd("sm_pmute",
	Command_PMute,
	ACCESS_FLAG,
	"sm_pmute <player> - Permanently removes a player's ability to use voice.");
    RegAdminCmd("sm_punmute",
	Command_PUnMute,
	ACCESS_FLAG,
	"sm_punmute <player> - Permamently restores a player's ability to use voice.");
    RegAdminCmd("sm_pgag",
	Command_PGag,
	ACCESS_FLAG,
	"sm_pgag <player> - Permanently removes a player's ability to use chat.");
    RegAdminCmd("sm_pungag",
	Command_PUnGag,
	ACCESS_FLAG,
	"sm_pungag <player> - Permanently restores a player's ability to use chat.");
    RegAdminCmd("sm_psilence",
	Command_PSilence,
	ACCESS_FLAG,
	"sm_psilence <player> - Permanently removes a player's ability to use voice and chat.");
    RegAdminCmd("sm_punsilence",
	Command_PUnSilence,
	ACCESS_FLAG,
	"sm_punsilence <player> - Permanently restores a player's ability to use voice and chat.");

    CreateTimer(1.0, Timer_ProcessConnectedCookies);
    ConnectVoteMuteDatabase();

    new Handle:topmenu;
    if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE)) {
	OnAdminMenuReady(topmenu);
    }
}

public OnPluginEnd() {
    Db_CancelTimer(g_VoteMuteDatabaseReconnectTimer);
    Db_CancelTimer(g_VoteMutePruneTimer);
    Db_Close(g_VoteMuteDatabase, g_VoteMuteDatabaseReady);
}

stock bool:PluginExists(const String:plugin_name[]) {
    new Handle:iter = GetPluginIterator();
    new Handle:plugin = INVALID_HANDLE;
    decl String:name[64];

    while (MorePlugins(iter)) {
	plugin = ReadPlugin(iter);
	GetPluginFilename(plugin, name, sizeof(name));
	if (StrEqual(name, plugin_name)) {
	    CloseHandle(iter);
	    return true;
	}
    }

    CloseHandle(iter);
    return false;
}

public OnLibraryRemoved(const String:name[]) {
    if (StrEqual(name, "adminmenu")) {
	g_adminMenu = INVALID_HANDLE;
    }
}

public OnAdminMenuReady(Handle:topmenu) {
    if (topmenu == g_adminMenu) {
	return;
    }

    g_adminMenu = topmenu;

    new TopMenuObject:player_commands = FindTopMenuCategory(g_adminMenu, ADMINMENU_PLAYERCOMMANDS);

    if (player_commands == INVALID_TOPMENUOBJECT) {
	return;
    }

    AddToTopMenu(g_adminMenu, "sm_pmute", TopMenuObject_Item, AdminMenu_PMute,
	player_commands, "sm_pmute", ACCESS_FLAG);
}

public AdminMenu_PMute(Handle:topmenu, TopMenuAction:action,
    TopMenuObject:object_id, param, String:buffer[], maxlength) {
    switch (action) {
	case TopMenuAction_DisplayOption: {
	    Format(buffer, maxlength, "Permanently Gag/Mute player");
	}
	case TopMenuAction_SelectOption: {
	    DisplayPMutePlayerMenu(param);
	}
    }
}

stock DisplayPMutePlayerMenu(client) {
    new Handle:menu = CreateMenu(MenuHandler_PMutePlayer);

    decl String:title[100];
    Format(title, sizeof(title), "Permanently Gag/Mute player:");
    SetMenuTitle(menu, title);
    SetMenuExitBackButton(menu, true);
    AddTargetsToMenu(menu, client, true, false);
    DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuHandler_PMutePlayer(Handle:menu, MenuAction:action, param1, param2) {
    new client = param1;

    switch (action) {
	case MenuAction_End: {
	    CloseHandle(menu);
	}
	case MenuAction_Cancel: {
	    if (param2 == MenuCancel_ExitBack && g_adminMenu != INVALID_HANDLE) {
		DisplayTopMenu(g_adminMenu, client, TopMenuPosition_LastCategory);
	    }
	}
	case MenuAction_Select: {
	    decl String:info[32];

	    GetMenuItem(menu, param2, info, sizeof(info));
	    new userid = StringToInt(info);
	    new target = GetClientOfUserId(userid);

	    if (!target) {
		PrintToChat(client, "[PERMAMUTE] %t", "Player no longer available");
	    }
	    else if (!CanUserTarget(client, target)) {
		PrintToChat(client, "[PERMAMUTE] %t", "Unable to target");
	    }
	    else {
		g_PMuteTarget[client] = target;
		DisplayPMuteTypesMenu(client, target);
    }
	}
    }
}

stock DisplayPMuteTypesMenu(client, target) {
    new Handle:menu = CreateMenu(MenuHandler_PMuteTypes);

    decl String:title[100];
    Format(title, sizeof(title), "Choose Type:");
    SetMenuTitle(menu, title);
    SetMenuExitBackButton(menu, true);

    decl String:cookie[8];
    new bool:silenced = true;

    GetClientCookie(target, g_cookies[COOKIE_PMUTE], cookie, sizeof(cookie));
    if (!strcmp(cookie, "1")) {
	AddMenuItem(menu, "1", "UnPermaMute Player");
    }
    else {
	AddMenuItem(menu, "0", "PermaMute Player");
	silenced = false;
    }

    GetClientCookie(target, g_cookies[COOKIE_PGAG], cookie, sizeof(cookie));
    if (!strcmp(cookie, "1")) {
	AddMenuItem(menu, "3", "UnPermaGag Player");
    }
    else {
	AddMenuItem(menu, "2", "PermaGag Player");
	silenced = false;
    }

    if (silenced) {
	AddMenuItem(menu, "5", "UnPermaSilence Player");
    }
    else {
	AddMenuItem(menu, "4", "PermaSilence Player");
    }

    DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public Menu_Status(client, CookieMenuAction:action, any:info, String:buffer[], maxlen) {
    if (action == CookieMenuAction_DisplayOption) {
	Format(buffer, maxlen, "Display PermaMute Status");
    }
    else if (action == CookieMenuAction_SelectOption) {
	CreateMenuStatus(client);
    }
}

public MenuHandler_PMuteTypes(Handle:menu, MenuAction:action, param1, param2) {
    new client = param1;

    switch (action) {
	case MenuAction_End: {
	    CloseHandle(menu);
	}
	case MenuAction_Cancel: {
	    if (param1 == MenuCancel_ExitBack && g_adminMenu != INVALID_HANDLE) {
		DisplayTopMenu(g_adminMenu, client, TopMenuPosition_LastCategory);
	    }
	}
	case MenuAction_Select: {
	    decl String:info[32];

	    GetMenuItem(menu, param2, info, sizeof(info));
	    new PCommType:type = PCommType:StringToInt(info);

	    PerformPMute(client, g_PMuteTarget[client], type);
	}
    }
}

stock PerformPMute(client, target, PCommType:type) {
    decl String:cmd[32];
    new target_userid = GetClientUserId(target);
    decl String:target_name[MAX_NAME_LENGTH];
    GetClientName(target, target_name, sizeof(target_name));

    switch (type) {
	case PCommType_PMute: {
	    Format(cmd, sizeof(cmd), "sm_mute #%d", target_userid);
	    ServerCommand(cmd);
	    SetClientCookie(target, g_cookies[COOKIE_PMUTE], "1");
	    if (client) {
		ShowActivity2(client, "[PERMAMUTE] ", "Permanently Muted %N", target);
	    }
	}
	case PCommType_PUnMute: {
	    Format(cmd, sizeof(cmd), "sm_unmute #%d", target_userid);
	    ServerCommand(cmd);
	    SetClientCookie(target, g_cookies[COOKIE_PMUTE], "0");
	    if (client) {
		ShowActivity2(client, "[PERMAMUTE] ", "Permanently UnMuted %N", target);
	    }
	}
	case PCommType_PGag: {
	    Format(cmd, sizeof(cmd), "sm_gag #%d", target_userid);
	    ServerCommand(cmd);
	    SetClientCookie(target, g_cookies[COOKIE_PGAG], "1");
	    if (client) {
		ShowActivity2(client, "[PERMAMUTE] ", "Permanently Gagged %N", target);
	    }
	}
	case PCommType_PUnGag: {
	    Format(cmd, sizeof(cmd), "sm_ungag #%d", target_userid);
	    ServerCommand(cmd);
	    SetClientCookie(target, g_cookies[COOKIE_PGAG], "0");
	    if (client) {
		ShowActivity2(client, "[PERMAMUTE] ", "Permanently UnGagged %N", target);
	    }
	}
	case PCommType_PSilence: {
	    PerformPMute(client, target, PCommType_PMute);
	    PerformPMute(client, target, PCommType_PGag);
	}
	case PCommType_PUnSilence: {
	    PerformPMute(client, target, PCommType_PUnMute);
	    PerformPMute(client, target, PCommType_PUnGag);
	}
    }

}

stock CreateMenuStatus(client) {
    new Handle:menu = CreateMenu(Menu_StatusDisplay);
    decl String:text[64];
    decl String:cookie[8];

    Format(text, sizeof(text), "PermaMute Status");
    SetMenuTitle(menu, text);

    GetClientCookie(client, g_cookies[COOKIE_PMUTE], cookie, sizeof(cookie));
    if (!strcmp(cookie, "1")) {
	AddMenuItem(menu, "permamute-mute", "You are permanently muted", ITEMDRAW_DISABLED);
    }
    else {
	AddMenuItem(menu, "permamute-mute", "You are not permanently muted", ITEMDRAW_DISABLED);
    }

    GetClientCookie(client, g_cookies[COOKIE_PGAG], cookie, sizeof(cookie));
    if (!strcmp(cookie, "1")) {
	AddMenuItem(menu, "permamute-gag", "You are permanently gagged", ITEMDRAW_DISABLED);
    }
    else {
	AddMenuItem(menu, "permamute-gag", "You are not permanently gagged", ITEMDRAW_DISABLED);
    }

    SetMenuExitBackButton(menu, true);
    SetMenuExitButton(menu, true);
    DisplayMenu(menu, client, 15);
}

public Menu_StatusDisplay(Handle:menu, MenuAction:action, param1, param2) {
    new client = param1;

    switch (action) {
	case MenuAction_Cancel: {
	    switch (param2) {
		case MenuCancel_ExitBack: {
		    ShowCookieMenu(client);
		}
	    }
	}
	case MenuAction_End: {
	    CloseHandle(menu);
	}
    }
}

public Action:Command_Say(client, args) {
    if (g_gagged & (1 << (client - 1))) {
	return Plugin_Handled;
    }
    return Plugin_Continue;
}

public OnClientCookiesCached(client) {
    if (IsClientInGame(client)) {
        ProcessCookies(client);
    }
}

public OnClientPostAdminCheck(client) {
    if (AreClientCookiesCached(client)) {
	ProcessCookies(client);
    }
}

stock ProcessCookies(client) {
    decl String:cookie[32];

    GetClientCookie(client, g_cookies[COOKIE_PMUTE], cookie, sizeof(cookie));
    if (StrEqual(cookie, "1")) {
	PrintToServer("[PERMAMUTE] %N is permanently muted", client);
	PerformPMute(0, client, PCommType_PMute);
    }

    GetClientCookie(client, g_cookies[COOKIE_PGAG], cookie, sizeof(cookie));
    if (StrEqual(cookie, "1")) {
	PrintToServer("[PERMAMUTE] %N is permanently gagged", client);
	PerformPMute(0, client, PCommType_PGag);
    }
    GetClientCookie(client, g_cookies[COOKIE_VOTESILENCE], cookie, sizeof(cookie));
    new expiresAt = StringToInt(cookie);
    if (expiresAt > GetTime()) {
        ApplyVoteSilence(client, expiresAt);
    }
    else if (expiresAt > 0) {
        SetClientCookie(client, g_cookies[COOKIE_VOTESILENCE], "0");
    }
}

public OnClientDisconnect(client) {
    if (g_VoteSilenceTimers[client] != INVALID_HANDLE) {
        KillTimer(g_VoteSilenceTimers[client]);
        g_VoteSilenceTimers[client] = INVALID_HANDLE;
    }

    g_VoteSilenceOwnsMute[client] = false;
    g_VoteSilenceOwnsGag[client] = false;
    g_VoteMuteChoice[client] = 0;
    g_VoteMuteWeight[client] = 0;
}

public Action:Timer_ProcessConnectedCookies(Handle:timer) {
    for (new client = 1; client <= MaxClients; client++) {
        if (IsClientInGame(client) && !IsFakeClient(client) && AreClientCookiesCached(client)) {
            ProcessCookies(client);
        }
    }

    return Plugin_Stop;
}

stock ConnectVoteMuteDatabase() {
    Db_CancelTimer(g_VoteMuteDatabaseReconnectTimer);
    Db_Close(g_VoteMuteDatabase, g_VoteMuteDatabaseReady);

    if (!Db_CheckConfigOrLog("permamute", VOTEMUTE_DB_CONFIG)) {
        return;
    }

    g_VoteMuteDatabaseGeneration++;
    Database.Connect(SQL_OnVoteMuteDatabaseConnected, VOTEMUTE_DB_CONFIG, g_VoteMuteDatabaseGeneration);
}

stock ScheduleVoteMuteDatabaseReconnect(Float:delay = DB_RECONNECT_DELAY) {
    g_VoteMuteDatabaseReady = false;
    if (g_VoteMuteDatabaseReconnectTimer == null) {
        g_VoteMuteDatabaseReconnectTimer = CreateTimer(delay, Timer_ReconnectVoteMuteDatabase);
    }
}

public Action:Timer_ReconnectVoteMuteDatabase(Handle:timer) {
    g_VoteMuteDatabaseReconnectTimer = null;
    ConnectVoteMuteDatabase();
    return Plugin_Stop;
}

public void SQL_OnVoteMuteDatabaseConnected(Database db, const char[] error, any data) {
    if (data != g_VoteMuteDatabaseGeneration) {
        if (db != null) {
            delete db;
        }
        return;
    }

    if (db == null) {
        LogError("[PermaMute] Votemute history database connection failed: %s", error[0] ? error : "unknown error");
        ScheduleVoteMuteDatabaseReconnect();
        return;
    }

    g_VoteMuteDatabase = db;
    g_VoteMuteDatabaseReady = false;
    Db_CancelTimer(g_VoteMuteDatabaseReconnectTimer);

    if (!g_VoteMuteDatabase.SetCharset("utf8mb4")) {
        LogError("[PermaMute] Could not set the votemute database charset to utf8mb4.");
    }

    char query[768];
    Format(query, sizeof(query),
        "CREATE TABLE IF NOT EXISTS %s ("
        ... "steamid64 VARCHAR(20) NOT NULL PRIMARY KEY, "
        ... "updated_at BIGINT NOT NULL"
        ... ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        VOTEMUTE_LOCK_TABLE);
    g_VoteMuteDatabase.Query(
        SQL_OnVoteMuteLockSchemaReady,
        query,
        g_VoteMuteDatabaseGeneration);
}

public void SQL_OnVoteMuteLockSchemaReady(Database db, DBResultSet results, const char[] error, any data) {
    if (data != g_VoteMuteDatabaseGeneration) {
        return;
    }

    if (error[0]) {
        LogError("[PermaMute] Could not create the votemute target table: %s", error);
        if (Db_IsTransientError(error)) {
            ScheduleVoteMuteDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
        }
        return;
    }

    char query[1024];
    Format(query, sizeof(query),
        "CREATE TABLE IF NOT EXISTS %s ("
        ... "id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, "
        ... "event_key VARCHAR(64) NOT NULL, "
        ... "steamid64 VARCHAR(20) NOT NULL, "
        ... "voted_at BIGINT NOT NULL, "
        ... "PRIMARY KEY (id), "
        ... "UNIQUE KEY uq_permavote_event (event_key), "
        ... "KEY idx_permavote_target_time (steamid64, voted_at), "
        ... "KEY idx_permavote_time (voted_at)"
        ... ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
        VOTEMUTE_HISTORY_TABLE);
    g_VoteMuteDatabase.Query(SQL_OnVoteMuteHistorySchemaReady, query, data);
}

public void SQL_OnVoteMuteHistorySchemaReady(Database db, DBResultSet results, const char[] error, any data) {
    if (data != g_VoteMuteDatabaseGeneration) {
        return;
    }

    if (error[0]) {
        LogError("[PermaMute] Could not create the votemute history table: %s", error);
        if (Db_IsTransientError(error)) {
            ScheduleVoteMuteDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
        }
        return;
    }

    g_VoteMuteDatabaseReady = true;
    LogMessage("[PermaMute] Votemute history database is ready.");
    PruneVoteMuteHistory();
    if (g_VoteMutePruneTimer == null) {
        g_VoteMutePruneTimer = CreateTimer(
            VOTEMUTE_PRUNE_INTERVAL,
            Timer_PruneVoteMuteHistory,
            _,
            TIMER_REPEAT);
    }
}

public Action:Timer_PruneVoteMuteHistory(Handle:timer) {
    PruneVoteMuteHistory();
    return Plugin_Continue;
}

stock PruneVoteMuteHistory() {
    if (!Db_IsReady(g_VoteMuteDatabase, g_VoteMuteDatabaseReady)) {
        return;
    }

    char query[256];
    Format(query, sizeof(query),
        "DELETE FROM %s WHERE voted_at < %d",
        VOTEMUTE_HISTORY_TABLE,
        GetTime() - VOTEMUTE_HISTORY_SECONDS);
    g_VoteMuteDatabase.Query(
        SQL_OnVoteMuteHistoryPruned,
        query,
        g_VoteMuteDatabaseGeneration);
}

public void SQL_OnVoteMuteHistoryPruned(Database db, DBResultSet results, const char[] error, any data) {
    if (data != g_VoteMuteDatabaseGeneration) {
        return;
    }

    if (error[0]) {
        LogError("[PermaMute] Could not prune expired votemute history: %s", error);
        if (Db_IsTransientError(error)) {
            ScheduleVoteMuteDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
        }
        return;
    }

    char query[512];
    Format(query, sizeof(query),
        "DELETE targets FROM %s AS targets "
        ... "LEFT JOIN %s AS history ON history.steamid64 = targets.steamid64 "
        ... "WHERE targets.updated_at < %d AND history.id IS NULL",
        VOTEMUTE_LOCK_TABLE,
        VOTEMUTE_HISTORY_TABLE,
        GetTime() - VOTEMUTE_HISTORY_SECONDS);
    g_VoteMuteDatabase.Query(SQL_OnVoteMuteLocksPruned, query, data);
}

public void SQL_OnVoteMuteLocksPruned(Database db, DBResultSet results, const char[] error, any data) {
    if (data != g_VoteMuteDatabaseGeneration) {
        return;
    }

    if (error[0]) {
        LogError("[PermaMute] Could not prune expired votemute targets: %s", error);
        if (Db_IsTransientError(error)) {
            ScheduleVoteMuteDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
        }
    }
}

stock RecordSuccessfulVoteMute() {
    decl String:eventKey[64];
    Format(eventKey, sizeof(eventKey), "%s-%d-%08x",
        g_VoteMuteTargetSteamId64,
        GetTime(),
        GetURandomInt());

    DataPack pack = new DataPack();
    pack.WriteString(eventKey);
    pack.WriteString(g_VoteMuteTargetSteamId64);
    pack.WriteString(g_VoteMuteTargetAuth);
    pack.WriteCell(g_VoteMuteTargetUserId);
    pack.WriteString(g_VoteMuteTargetChatName);
    SubmitVoteMuteRecord(pack);
}

stock SubmitVoteMuteRecord(DataPack pack) {
    if (!Db_IsReady(g_VoteMuteDatabase, g_VoteMuteDatabaseReady)) {
        CreateTimer(VOTEMUTE_RETRY_INTERVAL, Timer_RetryVoteMuteRecord, pack);
        return;
    }

    pack.Reset();

    decl String:eventKey[64];
    decl String:steamId64[32];
    pack.ReadString(eventKey, sizeof(eventKey));
    pack.ReadString(steamId64, sizeof(steamId64));

    char escapedEventKey[129];
    char escapedSteamId64[65];
    if (!Db_Escape(g_VoteMuteDatabase, eventKey, escapedEventKey, sizeof(escapedEventKey), "PermaMute")
        || !Db_Escape(g_VoteMuteDatabase, steamId64, escapedSteamId64, sizeof(escapedSteamId64), "PermaMute")) {
        CreateTimer(VOTEMUTE_RETRY_INTERVAL, Timer_RetryVoteMuteRecord, pack);
        return;
    }

    new now = GetTime();
    new cutoff = now - VOTEMUTE_HISTORY_SECONDS;
    Transaction transaction = new Transaction();
    char query[768];

    Format(query, sizeof(query),
        "INSERT INTO %s (steamid64, updated_at) VALUES ('%s', %d) "
        ... "ON DUPLICATE KEY UPDATE updated_at = VALUES(updated_at)",
        VOTEMUTE_LOCK_TABLE,
        escapedSteamId64,
        now);
    transaction.AddQuery(query);

    Format(query, sizeof(query),
        "DELETE FROM %s WHERE steamid64 = '%s' AND voted_at < %d",
        VOTEMUTE_HISTORY_TABLE,
        escapedSteamId64,
        cutoff);
    transaction.AddQuery(query);

    Format(query, sizeof(query),
        "INSERT IGNORE INTO %s (event_key, steamid64, voted_at) "
        ... "VALUES ('%s', '%s', %d)",
        VOTEMUTE_HISTORY_TABLE,
        escapedEventKey,
        escapedSteamId64,
        now);
    transaction.AddQuery(query);

    Format(query, sizeof(query),
        "SELECT COUNT(*) FROM %s WHERE steamid64 = '%s' AND voted_at >= %d",
        VOTEMUTE_HISTORY_TABLE,
        escapedSteamId64,
        cutoff);
    transaction.AddQuery(query);

    g_VoteMuteDatabase.Execute(
        transaction,
        SQLTxn_OnVoteMuteRecordSuccess,
        SQLTxn_OnVoteMuteRecordFailure,
        pack);
}

public Action:Timer_RetryVoteMuteRecord(Handle:timer, any data) {
    SubmitVoteMuteRecord(view_as<DataPack>(data));
    return Plugin_Stop;
}

public void SQLTxn_OnVoteMuteRecordSuccess(
    Database db,
    any data,
    int numQueries,
    DBResultSet[] results,
    any[] queryData
) {
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    decl String:eventKey[64];
    decl String:steamId64[32];
    decl String:steamId2[32];
    decl String:chatName[256];
    pack.ReadString(eventKey, sizeof(eventKey));
    pack.ReadString(steamId64, sizeof(steamId64));
    pack.ReadString(steamId2, sizeof(steamId2));
    new targetUserId = pack.ReadCell();
    pack.ReadString(chatName, sizeof(chatName));
    delete pack;

    if (numQueries < 4 || results[3] == null || !results[3].FetchRow()) {
        LogError("[PermaMute] Votemute history transaction '%s' returned no count.", eventKey);
        return;
    }

    new recentVoteMutes = results[3].FetchInt(0);
    if (recentVoteMutes >= 3) {
        PermanentlySilenceVoteMuteTarget(steamId64, steamId2, targetUserId, chatName);
    }
}

public void SQLTxn_OnVoteMuteRecordFailure(
    Database db,
    any data,
    int numQueries,
    const char[] error,
    int failIndex,
    any[] queryData
) {
    DataPack pack = view_as<DataPack>(data);
    LogError("[PermaMute] Could not record successful votemute at query %d: %s", failIndex, error);

    if (Db_IsTransientError(error)) {
        ScheduleVoteMuteDatabaseReconnect(DB_RECONNECT_FAST_DELAY);
    }

    CreateTimer(VOTEMUTE_RETRY_INTERVAL, Timer_RetryVoteMuteRecord, pack);
}

stock PermanentlySilenceVoteMuteTarget(
    const String:steamId64[],
    const String:steamId2[],
    targetUserId,
    const String:savedChatName[]
) {
    SetAuthIdCookie(steamId2, g_cookies[COOKIE_PMUTE], "1");
    SetAuthIdCookie(steamId2, g_cookies[COOKIE_PGAG], "1");

    new target = GetClientOfUserId(targetUserId);
    if (target > 0 && IsClientInGame(target) && !IsFakeClient(target)) {
        decl String:currentSteamId64[32];
        if (GetClientAuthId(target, AuthId_SteamID64, currentSteamId64, sizeof(currentSteamId64), true)
            && StrEqual(currentSteamId64, steamId64)) {
            PerformPMute(0, target, PCommType_PSilence);

            decl String:chatName[256];
            BuildVoteMuteChatName(target, chatName, sizeof(chatName));
            CPrintToChatAllEx(target,
                "{gold}[PermaMute]%s{default} reached three successful votemutes within 30 days and is now permanently silenced!",
                chatName);
            return;
        }
    }

    decl String:chatName[256];
    strcopy(chatName, sizeof(chatName), savedChatName);
    ReplaceString(chatName, sizeof(chatName), "{teamcolor}", "{default}", false);
    CPrintToChatAll(
        "{gold}[PermaMute]%s{default} reached three successful votemutes within 30 days and is now permanently silenced!",
        chatName);
}

stock bool:VoteMutePointsStoreReady() {
    return GetFeatureStatus(FeatureType_Native, "PointsStore_GetBonusPoints") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "PointsStore_SpendBonusPoints") == FeatureStatus_Available;
}

stock GetVoteSilenceExpiry(client) {
    if (!AreClientCookiesCached(client)) {
        return 0;
    }

    decl String:value[32];
    GetClientCookie(client, g_cookies[COOKIE_VOTESILENCE], value, sizeof(value));
    return StringToInt(value);
}

stock bool:IsClientPermanentlySilenced(client) {
    if (client <= 0 || !IsClientInGame(client) || !AreClientCookiesCached(client)) {
        return false;
    }

    decl String:muteValue[8];
    decl String:gagValue[8];
    GetClientCookie(client, g_cookies[COOKIE_PMUTE], muteValue, sizeof(muteValue));
    GetClientCookie(client, g_cookies[COOKIE_PGAG], gagValue, sizeof(gagValue));
    return StrEqual(muteValue, "1") && StrEqual(gagValue, "1");
}

public Action:Command_VoteMute(client, args) {
    if (client <= 0 || !IsClientInGame(client)) {
        return Plugin_Handled;
    }

    if (args < 1) {
        ReplyToCommand(client, "[PermaMute] Usage: sm_votemute <player>");
        return Plugin_Handled;
    }

    if (IsVoteInProgress() || g_VoteMuteTargetUserId != 0) {
        CPrintToChat(client, "{gold}[PermaMute]{default} Another vote is already in progress.");
        return Plugin_Handled;
    }

    if (!Db_IsReady(g_VoteMuteDatabase, g_VoteMuteDatabaseReady)) {
        CPrintToChat(client, "{gold}[PermaMute]{default} Votemute history is not ready yet.");
        return Plugin_Handled;
    }

    decl String:argument[MAX_TARGET_LENGTH];
    GetCmdArg(1, argument, sizeof(argument));
    new target = FindTarget(client, argument, true, true);
    if (target <= 0) {
        return Plugin_Handled;
    }

    if (target == client) {
        CPrintToChat(client, "{gold}[PermaMute]{default} You cannot start a vote against yourself.");
        return Plugin_Handled;
    }

    if (!AreClientCookiesCached(target)) {
        CPrintToChat(client, "{gold}[PermaMute]{default} %N's moderation data is still loading.", target);
        return Plugin_Handled;
    }

    if (GetVoteSilenceExpiry(target) > GetTime()) {
        CPrintToChat(client, "{gold}[PermaMute]{default} %N is already vote-silenced.", target);
        return Plugin_Handled;
    }

    if (IsClientPermanentlySilenced(target)) {
        CPrintToChat(client, "{gold}[PermaMute]{default} %N is already permanently silenced.", target);
        return Plugin_Handled;
    }

    if (!VoteMutePointsStoreReady()) {
        CPrintToChat(client, "{gold}[PermaMute]{default} Gem payments are not ready.");
        return Plugin_Handled;
    }

    if (GetFeatureStatus(FeatureType_Native, "PointsStore_AreBonusPointsLoaded") == FeatureStatus_Available
        && !PointsStore_AreBonusPointsLoaded(client)) {
        CPrintToChat(client, "{gold}[PermaMute]{default} Your Gem balance is still loading.");
        return Plugin_Handled;
    }

    if (PointsStore_GetBonusPoints(client) < VOTEMUTE_COST) {
        CPrintToChat(client, "{gold}[PermaMute]{default} You need {green}%d Gems{default} to start this vote.", VOTEMUTE_COST);
        return Plugin_Handled;
    }

    new Handle:menu = CreateMenu(MenuHandler_VoteMuteConfirmation);
    SetMenuTitle(menu, "Spend %d Gems to vote-silence %N for one hour?", VOTEMUTE_COST, target);

    decl String:info[16];
    IntToString(GetClientUserId(target), info, sizeof(info));
    AddMenuItem(menu, info, "Yes");
    AddMenuItem(menu, "no", "No");
    SetMenuExitButton(menu, true);
    DisplayMenu(menu, client, 15);
    return Plugin_Handled;
}

public MenuHandler_VoteMuteConfirmation(Handle:menu, MenuAction:action, client, item) {
    if (action == MenuAction_End) {
        CloseHandle(menu);
        return;
    }

    if (action != MenuAction_Select || client <= 0 || !IsClientInGame(client)) {
        return;
    }

    decl String:info[16];
    GetMenuItem(menu, item, info, sizeof(info));
    if (StrEqual(info, "no")) {
        return;
    }

    new target = GetClientOfUserId(StringToInt(info));
    if (target <= 0 || !IsClientInGame(target) || IsFakeClient(target)) {
        CPrintToChat(client, "{gold}[PermaMute]{default} Target is no longer available.");
        return;
    }

    StartVoteMute(client, target);
}

stock bool:StartVoteMute(client, target) {
    if (IsVoteInProgress() || g_VoteMuteTargetUserId != 0) {
        CPrintToChat(client, "{gold}[PermaMute]{default} Another vote is already in progress.");
        return false;
    }

    if (!AreClientCookiesCached(target) || GetVoteSilenceExpiry(target) > GetTime()) {
        CPrintToChat(client, "{gold}[PermaMute]{default} The target is unavailable or already vote-silenced.");
        return false;
    }

    if (IsClientPermanentlySilenced(target)) {
        CPrintToChat(client, "{gold}[PermaMute]{default} The target is already permanently silenced.");
        return false;
    }

    if (!Db_IsReady(g_VoteMuteDatabase, g_VoteMuteDatabaseReady)) {
        CPrintToChat(client, "{gold}[PermaMute]{default} Votemute history is no longer ready.");
        return false;
    }

    if (!VoteMutePointsStoreReady()
        || (GetFeatureStatus(FeatureType_Native, "PointsStore_AreBonusPointsLoaded") == FeatureStatus_Available
            && !PointsStore_AreBonusPointsLoaded(client))
        || PointsStore_GetBonusPoints(client) < VOTEMUTE_COST) {
        CPrintToChat(client, "{gold}[PermaMute]{default} You no longer have enough loaded Gems for this vote.");
        return false;
    }

    decl String:targetAuth[32];
    if (!GetClientAuthId(target, AuthId_Steam2, targetAuth, sizeof(targetAuth), true)) {
        CPrintToChat(client, "{gold}[PermaMute]{default} Target authentication is not ready.");
        return false;
    }

    decl String:targetSteamId64[32];
    if (!GetClientAuthId(target, AuthId_SteamID64, targetSteamId64, sizeof(targetSteamId64), true)) {
        CPrintToChat(client, "{gold}[PermaMute]{default} Target SteamID64 is not ready.");
        return false;
    }

    new recipients[MAXPLAYERS];
    new recipientCount;
    for (new voter = 1; voter <= MaxClients; voter++) {
        if (IsClientInGame(voter) && !IsFakeClient(voter)) {
            recipients[recipientCount++] = voter;
        }
    }

    if (recipientCount <= 0) {
        return false;
    }

    new Handle:vote = CreateMenu(MenuHandler_VoteMute, MENU_ACTIONS_ALL);
    SetMenuTitle(vote, "Silence %N for one hour? (%d%% required)", target, VOTEMUTE_PERCENT);
    AddMenuItem(vote, "yes", "Yes");
    AddMenuItem(vote, "no", "No");
    SetMenuExitButton(vote, false);

    if (!PointsStore_SpendBonusPoints(client, VOTEMUTE_COST)) {
        CloseHandle(vote);
        CPrintToChat(client, "{gold}[PermaMute]{default} Gem payment failed.");
        return false;
    }

    g_VoteMuteTargetUserId = GetClientUserId(target);
    ResetVoteMuteWeightedState();
    strcopy(g_VoteMuteTargetAuth, sizeof(g_VoteMuteTargetAuth), targetAuth);
    strcopy(g_VoteMuteTargetSteamId64, sizeof(g_VoteMuteTargetSteamId64), targetSteamId64);
    GetClientName(target, g_VoteMuteTargetName, sizeof(g_VoteMuteTargetName));
    BuildVoteMuteChatName(target, g_VoteMuteTargetChatName, sizeof(g_VoteMuteTargetChatName));

    if (!VoteMenu(vote, recipients, recipientCount, VOTEMUTE_TIME)) {
        ResetVoteMuteState();
        CloseHandle(vote);
        if (GetFeatureStatus(FeatureType_Native, "PointsStore_RefundBonusPoints") == FeatureStatus_Available) {
            PointsStore_RefundBonusPoints(client, VOTEMUTE_COST, "votemute_failed_start");
        }
        CPrintToChat(client, "{gold}[PermaMute]{default} The vote could not be started.");
        return false;
    }

    CPrintToChatAll("{gold}[PermaMute]{default} %N started a vote to silence %N for one hour.", client, target);
    return true;
}

public MenuHandler_VoteMute(Handle:menu, MenuAction:action, param1, param2) {
    if (action == MenuAction_Select) {
        TrackVoteMuteSelection(menu, param1, param2);
    }
    else if (action == MenuAction_VoteEnd) {
        ResolveWeightedVoteMute();
    }
    else if (action == MenuAction_VoteCancel) {
        CPrintToChatAll("{gold}[PermaMute]{default} Vote cancelled.");
    }
    else if (action == MenuAction_End) {
        ResetVoteMuteState();
        CloseHandle(menu);
    }
}

stock ApplySuccessfulVoteMute() {
    new expiresAt = GetTime() + VOTEMUTE_DURATION;
    decl String:value[32];
    IntToString(expiresAt, value, sizeof(value));
    SetAuthIdCookie(g_VoteMuteTargetAuth, g_cookies[COOKIE_VOTESILENCE], value);
    RecordSuccessfulVoteMute();

    new target = GetClientOfUserId(g_VoteMuteTargetUserId);
    if (target > 0 && IsClientInGame(target) && !IsFakeClient(target)) {
        SetClientCookie(target, g_cookies[COOKIE_VOTESILENCE], value);
        ApplyVoteSilence(target, expiresAt);
        BuildVoteMuteChatName(target, g_VoteMuteTargetChatName, sizeof(g_VoteMuteTargetChatName));
        CPrintToChatAllEx(target, "{gold}[PermaMute] %s{default} is now silenced for one hour!", g_VoteMuteTargetChatName);
        return;
    }

    ReplaceString(g_VoteMuteTargetChatName, sizeof(g_VoteMuteTargetChatName), "{teamcolor}", "{default}", false);
    CPrintToChatAll("{gold}[PermaMute]%s{default} is now silenced for one hour!", g_VoteMuteTargetChatName);
}

stock ApplyVoteSilence(client, expiresAt) {
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client)) {
        return;
    }

    if (g_VoteSilenceTimers[client] == INVALID_HANDLE) {
        g_VoteSilenceOwnsMute[client] = !BaseComm_IsClientMuted(client);
        g_VoteSilenceOwnsGag[client] = !BaseComm_IsClientGagged(client);
    }
    else {
        KillTimer(g_VoteSilenceTimers[client]);
        g_VoteSilenceTimers[client] = INVALID_HANDLE;
    }

    BaseComm_SetClientMute(client, true);
    BaseComm_SetClientGag(client, true);

    new remaining = expiresAt - GetTime();
    if (remaining < 1) {
        remaining = 1;
    }

    new Handle:pack;
    g_VoteSilenceTimers[client] = CreateDataTimer(float(remaining), Timer_VoteSilenceExpired, pack);
    WritePackCell(pack, GetClientUserId(client));
    WritePackCell(pack, expiresAt);
}

public Action:Timer_VoteSilenceExpired(Handle:timer, Handle:pack) {
    ResetPack(pack);
    new client = GetClientOfUserId(ReadPackCell(pack));
    new expectedExpiry = ReadPackCell(pack);
    if (client <= 0 || !IsClientInGame(client)) {
        return Plugin_Stop;
    }

    if (g_VoteSilenceTimers[client] == timer) {
        g_VoteSilenceTimers[client] = INVALID_HANDLE;
    }

    if (GetVoteSilenceExpiry(client) != expectedExpiry) {
        return Plugin_Stop;
    }

    SetClientCookie(client, g_cookies[COOKIE_VOTESILENCE], "0");
    ReleaseVoteSilence(client);
    return Plugin_Stop;
}

stock ReleaseVoteSilence(client) {
    decl String:cookie[8];

    GetClientCookie(client, g_cookies[COOKIE_PMUTE], cookie, sizeof(cookie));
    if (g_VoteSilenceOwnsMute[client] && !StrEqual(cookie, "1")) {
        BaseComm_SetClientMute(client, false);
    }

    GetClientCookie(client, g_cookies[COOKIE_PGAG], cookie, sizeof(cookie));
    if (g_VoteSilenceOwnsGag[client] && !StrEqual(cookie, "1")) {
        BaseComm_SetClientGag(client, false);
    }

    g_VoteSilenceOwnsMute[client] = false;
    g_VoteSilenceOwnsGag[client] = false;
}

stock BuildVoteMuteChatName(client, String:buffer[], maxlen) {
    buffer[0] = '\0';
    if (GetFeatureStatus(FeatureType_Native, "Filters_GetChatName") == FeatureStatus_Available
        && Filters_GetChatName(client, buffer, maxlen)
        && buffer[0] != '\0') {
        return;
    }

    Format(buffer, maxlen, "{teamcolor}%N{default}", client);
}

stock ResetVoteMuteState() {
    g_VoteMuteTargetUserId = 0;
    g_VoteMuteTargetAuth[0] = '\0';
    g_VoteMuteTargetSteamId64[0] = '\0';
    g_VoteMuteTargetName[0] = '\0';
    g_VoteMuteTargetChatName[0] = '\0';
    ResetVoteMuteWeightedState();
}

stock ResetVoteMuteWeightedState() {
    for (new client = 1; client <= MaxClients; client++) {
        g_VoteMuteChoice[client] = 0;
        g_VoteMuteWeight[client] = 0;
    }
}

stock GetVoteMuteClientVoteWeight(client) {
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client)) {
        return 0;
    }

    new level = 0;
    if (GetFeatureStatus(FeatureType_Native, "AdminsDB_GetClientWhitelistLevel") == FeatureStatus_Available) {
        level = AdminsDB_GetClientWhitelistLevel(client);
    }

    new weight = 1 + level;
    return weight > 0 ? weight : 0;
}

stock TrackVoteMuteSelection(Handle:menu, client, item) {
    if (client <= 0 || client > MaxClients) {
        return;
    }

    decl String:info[8];
    GetMenuItem(menu, item, info, sizeof(info));
    if (StrEqual(info, "yes")) {
        g_VoteMuteChoice[client] = 1;
    }
    else if (StrEqual(info, "no")) {
        g_VoteMuteChoice[client] = 2;
    }
    else {
        g_VoteMuteChoice[client] = 0;
    }

    g_VoteMuteWeight[client] = GetVoteMuteClientVoteWeight(client);
}

stock GetWeightedVoteMuteTotals(&yesVotes, &noVotes, &totalVotes) {
    yesVotes = 0;
    noVotes = 0;
    totalVotes = 0;

    for (new client = 1; client <= MaxClients; client++) {
        new weight = g_VoteMuteWeight[client];
        if (weight <= 0) {
            continue;
        }

        if (g_VoteMuteChoice[client] == 1) {
            yesVotes += weight;
            totalVotes += weight;
        }
        else if (g_VoteMuteChoice[client] == 2) {
            noVotes += weight;
            totalVotes += weight;
        }
    }
}

stock ResolveWeightedVoteMute() {
    new yesVotes;
    new noVotes;
    new totalVotes;
    GetWeightedVoteMuteTotals(yesVotes, noVotes, totalVotes);

    if (totalVotes > 0 && yesVotes * 100 >= totalVotes * VOTEMUTE_PERCENT) {
        ApplySuccessfulVoteMute();
        return;
    }

    CPrintToChatAll(
        "{gold}[PermaMute]{default} Vote failed: %d/%d weighted votes were yes; %d%% was required.",
        yesVotes,
        totalVotes,
        VOTEMUTE_PERCENT);
}

/* Commands {{{ */
public Action:Command_PMute(client, args) {
    if (args < 1) {
	ReplyToCommand(client, "[PERMAMUTE] Usage: sm_pmute <player>");
	return Plugin_Handled;
    }

    decl String:arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    TargetedAction(client, PCommType_PMute, arg);
    return Plugin_Handled;
}

public Action:Command_PUnMute(client, args) {
    if (args < 1) {
	ReplyToCommand(client, "[PERMAMUTE] Usage: sm_punmute <player>");
	return Plugin_Handled;
    }

    decl String:arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    TargetedAction(client, PCommType_PUnMute, arg);
    return Plugin_Handled;
}

public Action:Command_PGag(client, args) {
    if (args < 1) {
	ReplyToCommand(client, "[PERMAMUTE] Usage: sm_pgag <player>");
	return Plugin_Handled;
    }

    decl String:arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    TargetedAction(client, PCommType_PGag, arg);
    return Plugin_Handled;
}

public Action:Command_PUnGag(client, args) {
    if (args < 1) {
	ReplyToCommand(client, "[PERMAMUTE] Usage: sm_pungag <player>");
	return Plugin_Handled;
    }

    decl String:arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    TargetedAction(client, PCommType_PUnGag, arg);
    return Plugin_Handled;
}

public Action:Command_PSilence(client, args) {
    if (args < 1) {
	ReplyToCommand(client, "[PERMAMUTE] Usage: sm_psilence <player>");
	return Plugin_Handled;
    }

    decl String:arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    TargetedAction(client, PCommType_PSilence, arg);
    return Plugin_Handled;
}

public Action:Command_PUnSilence(client, args) {
    if (args < 1) {
	ReplyToCommand(client, "[PERMAMUTE] Usage: sm_punsilence <player>");
	return Plugin_Handled;
    }

    decl String:arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    TargetedAction(client, PCommType_PUnSilence, arg);
    return Plugin_Handled;
}
/* }}} Commands */

/* TargetAction {{{ */
stock TargetedAction(client, PCommType:type, const String:target_string[]) {
    decl String:target_name[MAX_TARGET_LENGTH];
    decl target_list[MAXPLAYERS];
    decl target_count;
    decl bool:tn_is_ml;

    if ((target_count = ProcessTargetString(
	target_string,
	client,
	target_list,
	MAXPLAYERS,
	0,
	target_name,
	sizeof(target_name),
	tn_is_ml)) <= 0) {
	ReplyToTargetError(client, target_count);
	return;
    }

    for (new i = 0; i < target_count; i++) {
	PerformPMute(client, target_list[i], type);
    }
}
/* }}} TargetAction */
