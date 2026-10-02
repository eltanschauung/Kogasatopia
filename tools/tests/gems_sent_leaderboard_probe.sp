#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>

#define BP_BALANCE_TABLE "points_store_balances"
#define BP_CURRENCY_COLOR_MAX 32
#define BP_LEADERBOARD_PAGE_SIZE 10

public Plugin myinfo = {
    name = "Gems sent leaderboard regression probe",
    author = "Kogasatopia",
    description = "Tests the production cache and commands using isolated temporary tables.",
    version = "1.0"
};

Database g_Database;
bool g_DatabaseReady, g_IsMySql;
char g_CurrencyPrefix[32] = "[Gems]";
ArrayList g_Messages;
int g_Assertions, g_Failures, g_Commands, g_Errors;
char g_Page[16];
bool g_HideFirst;

bool Client_IsHumanInGame(int client) { return client == 1; }
bool Oblivion_SteamMessageVisible(int client, const char[] steamId) {
    return client == 1 && (!g_HideFirst || !StrEqual(steamId, "76561198000000001"));
}
void GetCurrencyColorTag(char[] output, int maxlen) { strcopy(output, maxlen, "{cyan}"); }
void ProbeChat(int client, const char[] format, any ...) {
    char text[256];
    VFormat(text, sizeof(text), format, 3);
    if (client == 1) g_Messages.PushString(text);
}
int ProbeArg(int argument, char[] output, int maxlen) {
    return argument == 1 ? strcopy(output, maxlen, g_Page) : 0;
}
void ProbeRegister(const char[] command, ConCmd callback, const char[] description) {
    #pragma unused callback, description
    if (StrEqual(command, "sm_gsl") || StrEqual(command, "sm_gemssentleaderboard")) g_Commands++;
}
void ProbeError(const char[] format, any ...) {
    #pragma unused format
    g_Errors++;
}

#define CPrintToChat ProbeChat
#define GetCmdArg ProbeArg
#define RegConsoleCmd ProbeRegister
#define LogError ProbeError
#include "gems_sent_under_test.inc"

void Check(bool result, const char[] description) {
    g_Assertions++;
    if (!result) {
        g_Failures++;
        PrintToServer("[GemsSentProbe] FAIL: %s", description);
    }
}
void Execute(const char[] sql) {
    char error[256];
    if (!SQL_FastQuery(g_Database, sql)) {
        SQL_GetError(g_Database, error, sizeof(error));
        SetFailState("Fixture SQL failed: %s", error);
    }
}
void Transfer(const char[] sender, const char[] target, const char[] amount,
    const char[] event = "transfer_success", const char[] plugin = "points_store") {
    char sql[1024];
    FormatEx(sql, sizeof(sql),
        "INSERT INTO plugin_statistics_events VALUES('%s','%s',"
        ... "'event=%s|sender_steamid64=%s|target_steamid64=%s|amount=%s|sender_balance=1')",
        plugin, event, event, sender, target, amount);
    Execute(sql);
}

public void OnPluginStart() {
    g_Messages = new ArrayList(ByteCountToCells(256));
    char error[256], sql[4096];
    g_Database = SQLite_UseDatabase("gems_sent_probe", error, sizeof(error));
    if (g_Database == null) SetFailState("SQLite fixture failed: %s", error);
    Execute("CREATE TEMP TABLE plugin_statistics_events(source_plugin TEXT,event_name TEXT,message TEXT)");
    Execute("CREATE TEMP TABLE whaletracker_points_cache(steamid TEXT,name_color TEXT)");
    Execute("CREATE TEMP TABLE prename_rules(pattern TEXT,newname TEXT)");
    Execute("CREATE TEMP TABLE filters_steam_names(steamid64 TEXT,last_name TEXT)");
    Execute("INSERT INTO filters_steam_names VALUES('76561198000000001','Old Name'),('76561198000000002','Second')");
    Execute("INSERT INTO prename_rules VALUES('76561198000000001','Preferred Name')");
    Execute("INSERT INTO whaletracker_points_cache VALUES('76561198000000001','{green}')");
    Transfer("76561198000000001", "76561198000000099", "2147483647");
    Transfer("76561198000000001", "76561198000000098", "10");
    Transfer("76561198000000002", "76561198000000099", "200");
    Transfer("76561198000000001", "76561198000000001", "9000");
    Transfer("76561198000000002", "76561198000000099", "9000", "transfer_failed");
    Transfer("76561198000000002", "76561198000000099", "9000", "transfer_success", "other");
    Transfer("76561198000000002", "76561198000000099", "-10");
    Transfer("76561198000000002", "76561198000000099", "100oops");
    Transfer("unknown", "76561198000000099", "9000");
    Transfer("76561198000000002", "unknown", "9000");
    Execute("INSERT INTO plugin_statistics_events VALUES('points_store','transfer_success','amount=9000')");
    for (int i = 3; i <= 15; i++) {
        char steamId[32];
        FormatEx(steamId, sizeof(steamId), "765611980000000%02d", i);
        Transfer(steamId, "76561198000000099", "100");
    }

    char queryPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, queryPath, sizeof(queryPath), "data/gems_sent_queries.txt");
    File queries = OpenFile(queryPath, "w");
    if (queries == null) SetFailState("Could not export regression queries.");
    GemsSentLeaderboard_BuildQuery(sql, sizeof(sql), false);
    queries.WriteLine("%s", sql);
    DBResultSet results = SQL_Query(g_Database, sql);
    if (results == null) {
        SQL_GetError(g_Database, error, sizeof(error));
        SetFailState("Production SQLite query failed: %s", error);
    }
    GemsSentLeaderboard_BuildQuery(sql, sizeof(sql), true);
    queries.WriteLine("%s", sql);
    delete queries;

    GemsSentLeaderboard_OnPluginStart();
    Check(g_Commands == 2 && g_GemsSentLeaderboardRequested, "both aliases request a startup cache");
    GemsSentLeaderboard_LoadStartupCache();
    Check(!g_GemsSentLeaderboardInFlight, "startup waits for the database");
    PointsStore_CacheGemsSentLeaderboard(g_Database, results, "", 0);
    delete results;
    Check(g_GemsSentLeaderboardReady && !g_GemsSentLeaderboardRequested, "successful load completes startup request");
    Check(g_GemsSentLeaderboardRows == 15, "only valid other-player transfers are aggregated");
    Check(StrEqual(g_GemsSentLeaderboardTotals[0], "2147483657"), "totals above 32 bits remain exact");
    Check(StrEqual(g_GemsSentLeaderboardTotals[1], "200"), "failed/self/malformed transfers do not count");
    Check(StrEqual(g_GemsSentLeaderboardNames[0], "Preferred Name"), "configured name overrides historical name");
    Check(StrEqual(g_GemsSentLeaderboardColors[0], "green") && StrEqual(g_GemsSentLeaderboardColors[1], "gold"),
        "name colors and default color match gl");
    Check(StrEqual(g_GemsSentLeaderboardSteamIds[2], "76561198000000003"), "ties sort by steamid");

    g_DatabaseReady = true;
    GemsSentLeaderboard_LoadStartupCache();
    Check(!g_GemsSentLeaderboardInFlight, "database reconnect cannot refresh a completed cache");
    g_DatabaseReady = false;
    Transfer("76561198000000002", "76561198000000099", "1000");
    CurrencyLeaderboard_OnMapStart();
    Check(g_GemsSentLeaderboardReady && !g_GemsSentLeaderboardRequested
        && StrEqual(g_GemsSentLeaderboardTotals[1], "200"), "map change retains startup snapshot");

    Command_ShowGemsSentLeaderboard(1, 0);
    Check(g_Messages.Length == 11, "first page contains ten entries and next-page hint");
    char text[256];
    g_Messages.GetString(0, text, sizeof(text));
    Check(StrContains(text, "{green}Preferred Name") != -1 && StrContains(text, "2147483657") != -1,
        "sent command prints cached name and total");
    g_Messages.GetString(10, text, sizeof(text));
    Check(StrContains(text, "!gsl 2") != -1, "sent pagination uses correct alias");
    g_Messages.Clear();
    strcopy(g_Page, sizeof(g_Page), "2");
    Command_ShowGemsSentLeaderboard(1, 1);
    Check(g_Messages.Length == 5, "second page contains remaining entries");
    g_Messages.Clear();
    strcopy(g_Page, sizeof(g_Page), "99");
    Command_ShowGemsSentLeaderboard(1, 1);
    g_Messages.GetString(0, text, sizeof(text));
    Check(StrContains(text, "!gsl <1-2>") != -1, "invalid page points to gsl");
    g_Messages.Clear();
    g_HideFirst = true;
    Command_ShowGemsSentLeaderboard(1, 0);
    g_Messages.GetString(0, text, sizeof(text));
    Check(StrContains(text, "Second") != -1, "Oblivion filtering remains in effect");
    g_HideFirst = false;
    g_Messages.Clear();
    g_CurrencyLeaderboardReady = true;
    g_CurrencyLeaderboardRows = 1;
    strcopy(g_CurrencyLeaderboardNames[0], sizeof(g_CurrencyLeaderboardNames[]), "Balance User");
    strcopy(g_CurrencyLeaderboardColors[0], sizeof(g_CurrencyLeaderboardColors[]), "gold");
    g_CurrencyLeaderboardBalances[0] = 42;
    Command_ShowCurrencyLeaderboard(1, 0);
    g_Messages.GetString(0, text, sizeof(text));
    Check(StrContains(text, "Balance User") != -1 && StrContains(text, "42") != -1, "gl still prints balances");

    g_GemsSentLeaderboardReady = false;
    g_GemsSentLeaderboardRequested = true;
    PointsStore_CacheGemsSentLeaderboard(g_Database, null, "injected failure", 0);
    CurrencyLeaderboard_OnMapStart();
    Check(g_Errors == 1 && g_GemsSentLeaderboardRetry != null && g_GemsSentLeaderboardRequested,
        "failed startup request keeps its retry across maps");
    GemsSentLeaderboard_OnPluginEnd();
    GemsSentLeaderboard_Retry(null);
    Check(g_GemsSentLeaderboardRequested && !g_GemsSentLeaderboardInFlight, "retry still waits if database unavailable");
    PrintToServer("[GemsSentProbe] %d assertions, %d failures", g_Assertions, g_Failures);
}

public void OnPluginEnd() {
    GemsSentLeaderboard_OnPluginEnd();
    delete g_Database;
    delete g_Messages;
}
