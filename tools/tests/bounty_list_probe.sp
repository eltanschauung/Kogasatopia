#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>

public Plugin myinfo = {
    name = "Bounty list regression probe",
    author = "Kogasatopia",
    description = "Tests the production bounty cache with isolated temporary tables.",
    version = "1.0"
};

#define BP_CURRENCY_LONG_MAX 64
Database g_Database;
char g_Query[1024];
int g_QueryGeneration, g_Queries, g_Lookups, g_Errors, g_Assertions, g_Failures;
int g_Now = 1800000000;
int g_PlaytimeLimit = 3000;
float g_EngineTime = 100.0;
bool g_Async;

bool Client_IsHumanInGame(int client) {
    #pragma unused client
    return false;
}
bool IsClientActiveBountyTarget(int client) {
    #pragma unused client
    return false;
}
int Kogasa_FindClientBySteamId64(const char[] steamId) {
    #pragma unused steamId
    g_Lookups++;
    return 0;
}
int GetBountyPlaytimeLimitSeconds() { return g_PlaytimeLimit; }
void GetCurrencyLongLabel(char[] buffer, int maxlen) { strcopy(buffer, maxlen, "Gems"); }
void ProbeChat(int client, const char[] format, any ...) {
    #pragma unused client, format
}
void ProbeError(const char[] format, any ...) {
    #pragma unused format
    g_Errors++;
}
int ProbeTime() { return g_Now; }
float ProbeEngineTime() { return g_EngineTime; }
float RealClock() { return GetEngineTime(); }
void ProbeQuery(SQLQueryCallback callback, const char[] query, any data) {
    #pragma unused callback
    g_Queries++;
    strcopy(g_Query, sizeof(g_Query), query);
    g_QueryGeneration = data;
    if (g_Async) g_Database.Query(Probe_AsyncComplete, query, data);
}

#define CPrintToChat ProbeChat
#define LogError ProbeError
#define GetTime ProbeTime
#define GetEngineTime ProbeEngineTime
#include "bounty_state.inc"
#include "bounty_list_under_test.inc"

void Check(bool result, const char[] description) {
    g_Assertions++;
    if (!result) {
        g_Failures++;
        PrintToServer("[BountyListProbe] FAIL: %s", description);
    }
}
void Execute(const char[] sql) {
    char error[256];
    if (!SQL_FastQuery(g_Database, sql)) {
        SQL_GetError(g_Database, error, sizeof(error));
        SetFailState("Fixture SQL failed: %s", error);
    }
}
DBResultSet LoadRows() {
    char error[256];
    DBResultSet rows = SQL_Query(g_Database, g_Query);
    if (rows == null) {
        SQL_GetError(g_Database, error, sizeof(error));
        SetFailState("Production query failed: %s", error);
    }
    return rows;
}
void CompleteRefresh() {
    DBResultSet rows = LoadRows();
    SQL_OnActiveBountyTargetsLoaded(g_Database, rows, "", g_QueryGeneration);
    delete rows;
}
void FireRefreshTimer(float time) {
    delete g_BountyTargetCacheRefreshTimer;
    g_BountyTargetCacheRefreshTimer = null;
    g_EngineTime = time;
    Timer_RefreshBountyCache(null);
}
bool ItemContains(Menu menu, int item, const char[] expected) {
    char info[32], display[256];
    menu.GetItem(item, info, sizeof(info), _, display, sizeof(display));
    return StrContains(display, expected) != -1;
}

public void OnPluginStart() {
    char error[256];
    g_Database = SQLite_UseDatabase("bounty_list_probe", error, sizeof(error));
    if (g_Database == null) SetFailState("SQLite fixture failed: %s", error);
    Execute("CREATE TEMP TABLE points_store_bounties(target_steamid64 TEXT, target_name TEXT, amount INTEGER, bonus_amount INTEGER, qualifying_playtime_seconds INTEGER, expires_at INTEGER, status TEXT)");
    Execute("INSERT INTO points_store_bounties VALUES('alice','Alice',100,20,1800,1800604800,'active'),('alice','Alice',50,25,600,1800604700,'active'),('bob','Bob',500,0,0,1800604800,'active'),('charlie','Charlie',195,0,0,1800604800,'active'),('expired','Expired',10000,0,0,1799999999,'active'),('claimed','Claimed',10000,0,0,1800604800,'claimed'),('survived','Survived',10000,0,0,1800604800,'survived')");

    RefreshActiveBountyTargets();
    Check(g_Queries == 0, "database-not-ready cannot dispatch queries");
    g_BountyDatabaseReady = true;
    RefreshActiveBountyTargets();
    Check(g_Queries == 1 && g_BountyTargetCachePending, "first refresh dispatches one shared query");
    for (int i = 0; i < 100; i++) RefreshActiveBountyTargets();
    Check(g_Queries == 1 && g_BountyTargetCacheRefreshQueued, "in-flight requests coalesce");
    MarkActiveBountyTarget("new-target");
    CompleteRefresh();
    Check(!g_BountyListCacheReady && g_BountyTargetCacheRefreshTimer != null, "stale generation waits for one follow-up refresh");
    FireRefreshTimer(105.0);
    Check(g_Queries == 2, "queued burst needs only one follow-up query");
    CompleteRefresh();
    Check(g_BountyListCacheReady && g_BountyListCache.Length == 3, "only live active targets are cached");
    Check(g_ActiveBountyCount == 3 && IsSteamIdActiveBountyTarget("alice") && !IsSteamIdActiveBountyTarget("expired"), "target and menu caches use the same snapshot");
    char queryPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, queryPath, sizeof(queryPath), "data/bounty_list_probe_query.txt");
    File queryFile = OpenFile(queryPath, "w");
    if (queryFile == null) SetFailState("Could not export production cache query.");
    queryFile.WriteLine("%s", g_Query);
    delete queryFile;

    BountyListEntry entry;
    g_BountyListCache.GetArray(1, entry, sizeof(entry));
    Check(StrEqual(entry.steamId, "alice") && entry.amount == 195, "stacked base and bonus amounts are combined");
    Check(entry.qualifyingPlaytime == 1800, "stack uses its next qualifying-playtime expiry");
    Check(GetBountyListRemainingMinutes(entry, g_Now) == 20, "30 minutes elapsed of 50 displays 20m, not one week");
    entry.qualifyingPlaytime = 0;
    Check(GetBountyListRemainingMinutes(entry, g_Now) == 50, "fresh 50-minute bounty displays 50m");
    g_PlaytimeLimit = 1200;
    Check(GetBountyListRemainingMinutes(entry, g_Now) == 20, "configured 20-minute bounty displays 20m");
    entry.qualifyingPlaytime = 1;
    Check(GetBountyListRemainingMinutes(entry, g_Now) == 20, "fractional remaining minutes round up");
    entry.qualifyingPlaytime = 1200;
    Check(GetBountyListRemainingMinutes(entry, g_Now) == 0, "completed qualifying playtime is hidden");
    entry.qualifyingPlaytime = 0;
    entry.expiresAt = g_Now + 61;
    Check(GetBountyListRemainingMinutes(entry, g_Now) == 2, "near wall expiry remains a backstop");
    entry.expiresAt = g_Now;
    Check(GetBountyListRemainingMinutes(entry, g_Now) == 0, "expired wall clock is hidden");
    g_PlaytimeLimit = 3000;

    Menu menu = BuildBountyListMenu();
    Check(menu.ItemCount == 3 && ItemContains(menu, 0, "Bob (Gems 500) (50m)"), "menu sorts larger bounty first and formats 50m");
    Check(ItemContains(menu, 1, "Alice (Gems 195) (20m)"), "menu displays stacked qualifying time as 20m");
    Check(ItemContains(menu, 2, "Charlie"), "equal amounts retain alphabetical order");
    delete menu;
    int queriesBefore = g_Queries;
    int lookupsBefore = g_Lookups;
    float started = RealClock();
    for (int i = 0; i < 500; i++) {
        menu = BuildBountyListMenu();
        delete menu;
    }
    PrintToServer("[BountyListProbe] 500 cached menu builds: %.3f ms", (RealClock() - started) * 1000.0);
    Check(g_Queries == queriesBefore && g_Lookups == lookupsBefore, "500 menu requests require no SQL or Steam-id scans");

    Execute("UPDATE points_store_bounties SET bonus_amount = 100, qualifying_playtime_seconds = 2400 WHERE target_steamid64 = 'alice'");
    for (int i = 0; i < 100; i++) RefreshActiveBountyTargets();
    Check(g_Queries == queriesBefore && g_BountyTargetCacheRefreshTimer != null, "fresh-cache mutations share one bounded timer");
    FireRefreshTimer(110.0);
    CompleteRefresh();
    menu = BuildBountyListMenu();
    Check(ItemContains(menu, 1, "Alice (Gems 350) (10m)"), "committed growth and progress replace the menu snapshot");
    delete menu;

    g_EngineTime = 115.0;
    RefreshActiveBountyTargets();
    queriesBefore = g_Queries;
    for (int i = 0; i < 100; i++) RefreshActiveBountyTargets();
    CompleteRefresh();
    Check(g_BountyListCacheReady && !g_BountyTargetCachePending && g_Queries == queriesBefore
        && g_BountyTargetCacheRefreshTimer != null, "busy mutation traffic still publishes a snapshot before the coalesced follow-up");
    FireRefreshTimer(120.0);
    CompleteRefresh();

    g_EngineTime = 125.0;
    RefreshActiveBountyTargets();
    SQL_OnActiveBountyTargetsLoaded(g_Database, null, "injected failure", g_QueryGeneration);
    Check(g_Errors == 1 && g_BountyListCacheReady && g_BountyTargetCacheRefreshTimer != null, "query failures retain the snapshot and queue a bounded retry");
    FireRefreshTimer(130.0);
    CompleteRefresh();
    Check(!g_BountyTargetCachePending, "successful retry clears in-flight state");

    Bounties_OnDatabaseDisconnected();
    Check(!g_BountyListCacheReady && !g_BountyTargetCachePending && g_BountyTargetCacheRefreshTimer == null, "disconnect clears readiness, pending query, and retry timer");
    g_BountyDatabaseReady = false;
    SQL_OnActiveBountyTargetsLoaded(g_Database, null, "", g_QueryGeneration);
    Check(!g_BountyListCacheReady, "old callbacks cannot publish while disconnected");
    g_BountyDatabaseReady = true;
    Database other = SQLite_UseDatabase("bounty_other_probe", error, sizeof(error));
    g_BountyTargetCachePending = true;
    SQL_OnActiveBountyTargetsLoaded(other, null, "", g_BountyTargetCacheGeneration);
    Check(g_BountyTargetCachePending, "callbacks from an old connection cannot clear a new pending query");
    delete other;
    g_BountyTargetCachePending = false;

    Execute("DELETE FROM points_store_bounties");
    g_EngineTime = 135.0;
    RefreshActiveBountyTargets();
    CompleteRefresh();
    menu = BuildBountyListMenu();
    Check(g_ActiveBountyCount == 0 && menu.ItemCount == 1 && ItemContains(menu, 0, "No active bounties"), "empty snapshot replaces old targets and has an empty-state menu");
    delete menu;

    for (int i = 0; i < 105; i++) {
        entry.amount = 100;
        entry.qualifyingPlaytime = 0;
        entry.expiresAt = g_Now + 604800;
        FormatEx(entry.steamId, sizeof(entry.steamId), "target%d", i);
        FormatEx(entry.name, sizeof(entry.name), "Target %d", i);
        g_BountyListCache.PushArray(entry, sizeof(entry));
    }
    menu = BuildBountyListMenu();
    Check(menu.ItemCount == 100, "menu retains the 100-target display cap");
    delete menu;
    g_BountyListCache.Clear();

    // Exercise the real threaded API, whose callback database is a cloned handle.
    g_Async = true;
    g_EngineTime = 140.0;
    RefreshActiveBountyTargets();
}

public void Probe_AsyncComplete(Database db, DBResultSet rows, const char[] error, any generation) {
    Check(error[0] == '\0' && db.IsSameConnection(g_Database), "real threaded query returns the expected connection");
    SQL_OnActiveBountyTargetsLoaded(db, rows, error, generation);
    Check(g_BountyListCacheReady && !g_BountyTargetCachePending && g_ActiveBountyCount == 0, "real threaded callback publishes its cloned database handle");
    PrintToServer("[BountyListProbe] %d assertions, %d failures", g_Assertions, g_Failures);
}

public void OnPluginEnd() {
    delete g_BountyTargetCacheRefreshTimer;
    delete g_BountyListCache;
    delete g_ActiveBountyTargets;
    delete g_Database;
}

