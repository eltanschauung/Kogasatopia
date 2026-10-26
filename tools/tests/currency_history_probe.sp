#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>

// All SQL uses this test plugin's dedicated SQLite fixture, never a configured DB.
Database g_Database;
bool g_DatabaseReady, g_IsMySql, expectError;
int checks, failures, errors, phase, g_CurrencyLeaderboardRows;
char g_CurrencyLeaderboardSteamIds[50][32];
int g_CurrencyLeaderboardBalances[50];
float deadline;

bool Store_IsCurrentConnection(Database db) { return g_Database.IsSameConnection(db); }
void TestLogError(const char[] format, any ...)
{
    #pragma unused format
    errors++;
    if (!expectError) failures++;
}
#define LogError TestLogError
#include "leaderboard_history.sp"
#undef LogError

void Check(bool result, const char[] label)
{
    checks++;
    if (!result) { failures++; PrintToServer("[CurrencyHistoryProbe] FAIL: %s", label); }
}
int Scalar(const char[] sql)
{
    DBResultSet rows = SQL_Query(g_Database, sql);
    if (rows == null || !rows.FetchRow()) SetFailState("Fixture assertion failed");
    int result = rows.FetchInt(0);
    delete rows;
    return result;
}
void Query(const char[] sql)
{
    if (!SQL_FastQuery(g_Database, sql)) SetFailState("Fixture setup failed");
}
void Archive()
{
    CurrencyHistory_RecordSnapshot(g_CurrencyLeaderboardRows, g_CurrencyLeaderboardSteamIds, g_CurrencyLeaderboardBalances);
}
public void OnPluginStart()
{
    char error[256];
    g_Database = SQLite_UseDatabase("currency_history_regression", error, sizeof(error));
    if (g_Database == null) SetFailState("Could not open dedicated history fixture");
    Query("DROP TABLE IF EXISTS points_store_balance_history");
    g_DatabaseReady = true;
    g_CurrencyLeaderboardRows = 2;
    strcopy(g_CurrencyLeaderboardSteamIds[0], 32, "00000000000000001");
    strcopy(g_CurrencyLeaderboardSteamIds[1], 32, "00000000000000002");
    g_CurrencyLeaderboardBalances[0] = 946;
    g_CurrencyLeaderboardBalances[1] = 1879;
    Archive();
    g_CurrencyLeaderboardBalances[0] = 12345; // Queued values must be immutable.
    deadline = GetEngineTime() + 20.0;
    CreateTimer(0.1, PollFixture, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}
public Action PollFixture(Handle timer)
{
    if (GetEngineTime() > deadline) SetFailState("History fixture timed out");
    if (g_CurrencyHistoryBusy) return Plugin_Continue;
    if (phase == 2)
    {
        if (g_CurrencyHistoryRetry == null) return Plugin_Continue;
        Check(errors == 1 && g_CurrencyHistoryJobs.Length == 1, "failed write keeps exact snapshot queued");
        Query("DROP TRIGGER fail_history");
        delete g_CurrencyHistoryRetry;
        expectError = false;
        g_CurrencyLeaderboardBalances[0] = 99999;
        CurrencyHistory_Drain();
        phase = 3;
        return Plugin_Continue;
    }
    if (g_CurrencyHistoryJobs.Length) return Plugin_Continue;
    if (phase == 0)
    {
        Check(Scalar("SELECT COUNT(*) FROM points_store_balance_history") == 2, "one complete snapshot");
        Check(Scalar("SELECT balance FROM points_store_balance_history WHERE steamid64='00000000000000001'") == 946, "exact original cache value, not later mutation");
        Check(Scalar("SELECT COUNT(*) FROM points_store_balance_history WHERE length(snapshot_date)=10 AND captured_at>0 AND host_port>0") == 2, "date, timestamp and port recorded");
        Check(Scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name LIKE 'idx_balance_history_%'") == 2, "date/client indexes created");
        Archive();
        // Simulate re-sending an already submitted SQL payload after a lost ack.
        DataPack original = view_as<DataPack>(g_CurrencyHistoryJobs.Get(0));
        char sql[CURRENCY_HISTORY_QUERY_MAX];
        original.Reset(); original.ReadString(sql, sizeof(sql));
        DataPack duplicate = new DataPack(); duplicate.WriteString(sql);
        g_CurrencyHistoryJobs.Push(duplicate);
        phase = 1;
        return Plugin_Continue;
    }
    if (phase == 1)
    {
        Check(Scalar("SELECT COUNT(*) FROM points_store_balance_history") == 4, "retry cannot duplicate archived rows");
        Check(Scalar("SELECT COUNT(DISTINCT snapshot_id) FROM points_store_balance_history") == 2, "multiple same-day refreshes retained");
        Check(Scalar("SELECT COUNT(*) FROM points_store_balance_history WHERE balance=946") == 1, "old snapshot not overwritten");
        Check(Scalar("SELECT COUNT(*) FROM points_store_balance_history WHERE balance=12345") == 1, "new snapshot has new value");
        Query("CREATE TRIGGER fail_history BEFORE INSERT ON points_store_balance_history BEGIN SELECT RAISE(ABORT,'injected fixture failure'); END");
        g_CurrencyLeaderboardBalances[0] = 10;
        expectError = true;
        Archive();
        phase = 2;
        return Plugin_Continue;
    }
    Check(Scalar("SELECT COUNT(*) FROM points_store_balance_history") == 6, "failed snapshot eventually committed");
    Check(Scalar("SELECT COUNT(*) FROM points_store_balance_history WHERE balance=10") == 1, "retry preserves values at capture time");
    Check(Scalar("SELECT COUNT(*) FROM points_store_balance_history WHERE balance=99999") == 0, "retry never re-queries changed balances");
    g_CurrencyLeaderboardRows = 0;
    Archive();
    Check(g_CurrencyHistoryJobs.Length == 0, "empty cache adds no fabricated balances");
    CurrencyHistory_Stop();
    PrintToServer("[CurrencyHistoryProbe] %d checks, %d failures", checks, failures);
    return Plugin_Stop;
}
public void OnPluginEnd()
{
    CurrencyHistory_Stop();
    delete g_Database;
}
