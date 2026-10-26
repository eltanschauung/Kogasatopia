#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>

// Only this plugin-owned SQLite database is opened. No configured connection,
// player balance, real client identity, or production lottery is ever used.
#define LOTTO_TICKET_TABLE "test_equal_tickets"
#define BP_BALANCE_TABLE "test_equal_balances"
#define BP_IDEMPOTENT_AWARDS_TABLE "test_equal_receipts"
#define BP_CURRENCY_COLOR_MAX 32

Database testDb;
int checks, failures, testCase, reloads, refundEvents, refunded, retryRequests;
int g_CurrentLotteryId = 17, testRequiredValue = 100;
bool g_CurrentLotteryEqual = true, g_LotteryEqualRefundInProgress, g_IsMySql;
bool g_ClientBonusPointsLoaded[MAXPLAYERS + 1];
bool g_ClientLotteryTicketLoaded[MAXPLAYERS + 1];
int g_ClientBonusPoints[MAXPLAYERS + 1];
int cachedTicketValue[4];
char cachedTicket[4][64];

methodmap TestDatabase < Handle
{
    public void Execute(Transaction txn, Function success, Function failure, any data)
    {
        #pragma unused success
        #pragma unused failure
        testDb.Execute(txn, Test_Commit, Test_Failure, data);
    }
}
TestDatabase g_Database;

stock int GetLotteryEqualTicketValue() { return testRequiredValue; }
stock void BeginEqualLotteryRefunds() { retryRequests++; }
stock bool IsClientAuthorizedHuman(int client) { return client > 0 && client <= 3; }
stock int Kogasa_FindClientBySteamId64(const char[] identity)
{
    if (StrEqual(identity, "test-low")) return 1;
    if (StrEqual(identity, "test-high")) return 2;
    if (StrEqual(identity, "test-exact")) return 3;
    return 0;
}
stock void GetCurrencyColorTag(char[] value, int maxlen) { strcopy(value, maxlen, "{cyan}"); }
stock void LoadClientBonusPoints(int client)
{
    char query[256], identity[32];
    strcopy(identity, sizeof(identity), client == 1 ? "test-low" : (client == 2 ? "test-high" : "test-exact"));
    FormatEx(query, sizeof(query), "SELECT balance FROM test_equal_balances WHERE steamid64='%s'", identity);
    g_ClientBonusPoints[client] = Scalar(query);
}
stock void ClearClientLotteryTicketCache(int client)
{
    cachedTicketValue[client] = 0;
    cachedTicket[client][0] = '\0';
}
stock void TestChat(int client, const char[] format, any ...)
{
    #pragma unused format
    if (client != 1 && client != 2) failures++;
}
stock void LogLotteryCreditEvent(const char[] reason, const char[] identity,
    int amount, int lotteryId, int client, int balanceAfter)
{
    #pragma unused identity
    #pragma unused client
    if ((!StrEqual(reason, "lottery_equal_refund") && !StrEqual(reason, "lottery_equal_excess_refund"))
        || lotteryId != 17 || balanceAfter != -1 || amount <= 0) failures++;
    refundEvents++;
    refunded += amount;
}
stock void ReloadAllClientLotteryTickets()
{
    reloads++;
    for (int client = 1; client <= 3; client++) ClearClientLotteryTicketCache(client);
    DBResultSet rows = SQL_Query(testDb,
        "SELECT steamid64, ticket_value, ticket FROM test_equal_tickets WHERE lottery_id = 17");
    if (rows == null) { failures++; return; }
    while (rows.FetchRow())
    {
        char identity[32];
        rows.FetchString(0, identity, sizeof(identity));
        int client = Kogasa_FindClientBySteamId64(identity);
        if (!client) continue;
        cachedTicketValue[client] = rows.FetchInt(1);
        rows.FetchString(2, cachedTicket[client], sizeof(cachedTicket[]));
    }
    delete rows;
}
public Action Timer_RetryEqualLotteryRefunds(Handle timer, any lotteryId)
{
    #pragma unused timer
    #pragma unused lotteryId
    failures++;
    return Plugin_Stop;
}
public void SQLTxn_OnEqualLotteryTicketsRefundFailure(Database db, any data,
    int numQueries, const char[] error, int failIndex, any[] queryData)
{
    #pragma unused db
    #pragma unused data
    #pragma unused numQueries
    #pragma unused error
    #pragma unused failIndex
    #pragma unused queryData
    failures++;
}

#define Database TestDatabase
#define CPrintToChat TestChat
#include "equal_under_test.inc"
#undef Database
#undef CPrintToChat

void Check(bool result, const char[] label)
{
    checks++;
    if (!result) { failures++; PrintToServer("[LotteryEqualProbe] Failed: %s (case %d)", label, testCase); }
}
void Query(const char[] query)
{
    if (!SQL_FastQuery(testDb, query)) SetFailState("Test fixture query failed");
}
int Scalar(const char[] query)
{
    DBResultSet rows = SQL_Query(testDb, query);
    if (rows == null || !rows.FetchRow()) SetFailState("Test assertion query failed");
    int result = rows.FetchInt(0);
    delete rows;
    return result;
}
void Seed()
{
    Query("DELETE FROM test_equal_tickets");
    Query("DELETE FROM test_equal_balances");
    Query("DELETE FROM test_equal_receipts");
    Query("INSERT INTO test_equal_balances (steamid64, balance) VALUES ('test-low', 50), ('test-high', 50), ('test-exact', 50)");
    char query[1024];
    FormatEx(query, sizeof(query),
        "INSERT INTO test_equal_tickets (lottery_id,steamid64,display_name,ticket,ticket_value,created_at) VALUES (17, 'test-low', 'low', 'LOW', 10, 123), "
        ... "(17, 'test-high', 'high', 'SAME-CHARACTERS-紅', 1000, 123), "
        ... "(17, 'test-exact', 'exact', 'EXACT', %d, 123), "
        ... "(17, 'test-offline', 'offline', 'OFFLINE', 2000, 123), "
        ... "(18, 'test-high', 'other', 'OTHER-LOTTERY', 2000, 123)", testRequiredValue);
    Query(query);
    if (testCase == 1) Query("DELETE FROM test_equal_tickets WHERE lottery_id = 17 AND steamid64 = 'test-low'");
    if (testCase == 2) Query("DELETE FROM test_equal_tickets WHERE lottery_id = 17 AND steamid64 != 'test-exact'");
    if (testCase == 3) Query("DELETE FROM test_equal_tickets WHERE lottery_id = 17");
    for (int client = 1; client <= 3; client++)
    {
        g_ClientBonusPointsLoaded[client] = true;
        g_ClientBonusPoints[client] = 50;
    }
}
void StartCase()
{
    if (testCase == 7)
    {
        g_CurrentLotteryEqual = false;
        DataPack stale = new DataPack();
        stale.WriteCell(17);
        stale.WriteCell(testRequiredValue);
        int before = reloads;
        g_LotteryEqualRefundInProgress = true;
        SQL_OnEqualLotteryInvalidTicketsLoaded(g_Database, null, "", stale);
        Check(!g_LotteryEqualRefundInProgress && reloads == before, "stale Equal callback makes no transaction");
        Check(Scalar("SELECT ticket_value FROM test_equal_tickets WHERE lottery_id=18") == 2000, "other lottery unchanged");
        PrintToServer("[LotteryEqualProbe] %d checks; %d failures", checks, failures);
        return;
    }
    testRequiredValue = testCase == 4 ? 340 : (testCase >= 5 ? 680 : 100);
    // Case 6 repeats case 5 without resetting balances or ticket rows.
    if (testCase != 6) Seed();
    refundEvents = refunded = 0;
    g_LotteryEqualRefundInProgress = true;
    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT steamid64, ticket_value FROM test_equal_tickets WHERE lottery_id = 17 AND ticket_value <> %d", testRequiredValue);
    DBResultSet rows = SQL_Query(testDb, query);
    if (rows == null) SetFailState("Test selection failed");
    DataPack pack = new DataPack();
    pack.WriteCell(17);
    pack.WriteCell(testRequiredValue);
    SQL_OnEqualLotteryInvalidTicketsLoaded(g_Database, rows, "", pack);
    delete rows;
    Check(g_LotteryEqualRefundInProgress, "normalization remains guarded until SQL commits");
}
public void Test_Commit(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    Check(numQueries == 4, "receipt, refund, delete, normalization share one transaction");
    int before = reloads;
    SQLTxn_OnEqualLotteryTicketsRefunded(view_as<TestDatabase>(db), data, numQueries, results, queryData);
    Check(!g_LotteryEqualRefundInProgress && reloads == before + 1, "commit releases guard and reloads client tickets");
    Check(retryRequests == 0, "unchanged required value does not requeue");
    char query[256];
    FormatEx(query, sizeof(query), "SELECT COUNT(*) FROM test_equal_tickets WHERE lottery_id=17 AND ticket_value != %d", testRequiredValue);
    Check(Scalar(query) == 0, "all retained stakes equal required value");
    Check(Scalar("SELECT COUNT(*) FROM test_equal_tickets WHERE lottery_id=17 AND steamid64='test-low'") == 0, "undersized ticket removed");
    int participants = testCase == 2 ? 1 : (testCase == 3 ? 0 : 3);
    // This is the exact aggregation used by sm_pool and the draw.
    FormatEx(query, sizeof(query), "SELECT COALESCE(SUM(ticket_value), 0) FROM test_equal_tickets WHERE lottery_id=17");
    Check(Scalar(query) == participants * testRequiredValue, "sm_pool sum reflects normalized stakes");
    Check(Scalar("SELECT COUNT(*) FROM test_equal_tickets WHERE lottery_id=17") == participants, "participant count preserved except refunded tickets");
    int highBalance = participants == 3 ? 50 + 1000 - testRequiredValue : 50;
    Check(Scalar("SELECT balance FROM test_equal_balances WHERE steamid64='test-high'") == highBalance, "oversized excess refunded exactly once");
    Check(Scalar("SELECT COALESCE(SUM(balance),0) FROM test_equal_balances WHERE steamid64='test-offline'")
        == (participants == 3 ? 2000 - testRequiredValue : 0), "offline excess refunded");
    Check(Scalar("SELECT balance FROM test_equal_balances WHERE steamid64='test-exact'") == 50, "exact stake balance unchanged");
    Check(Scalar("SELECT COUNT(*) FROM test_equal_tickets WHERE ticket_value != 2000 AND lottery_id=18") == 0, "other lottery not normalized");
    int expectedBalance = (testCase == 0 || testCase >= 4) ? 60 : 50;
    Check(Scalar("SELECT balance FROM test_equal_balances WHERE steamid64='test-low'") == expectedBalance, "undersized stake refunded exactly once");
    Check(g_ClientBonusPoints[1] == expectedBalance && g_ClientBonusPoints[2] == highBalance, "connected balance cache matches database");
    bool newRefund = testCase == 0 || testCase == 4 || testCase == 5;
    bool newExcess = participants == 3 && testCase != 6;
    Check(refundEvents == (newRefund ? 1 : 0) + (newExcess ? 2 : 0)
        && refunded == (newRefund ? 10 : 0) + (newExcess ? 3000 - 2 * testRequiredValue : 0),
        "only actual refunds credited and logged");
    int receiptCount = (testCase == 0 || testCase >= 4) ? 3 : (testCase == 1 ? 2 : 0);
    Check(Scalar("SELECT COUNT(*) FROM test_equal_receipts") == receiptCount, "durable receipts retained without duplicate retry credits");
    if (participants == 3)
    {
        Check(cachedTicketValue[2] == testRequiredValue && StrEqual(cachedTicket[2], "SAME-CHARACTERS-紅"), "connected ticket cache has original characters and normalized value");
        Check(Scalar("SELECT COUNT(*) FROM test_equal_tickets WHERE lottery_id=17 AND steamid64='test-high' AND ticket='SAME-CHARACTERS-紅' AND display_name='high' AND created_at=123") == 1, "characters, name and creation time unchanged");
        Check(Scalar("SELECT COUNT(*) FROM test_equal_tickets WHERE lottery_id=17 AND steamid64='test-offline' AND ticket='OFFLINE'") == 1, "offline ticket characters retained");
    }
    testCase++;
    StartCase();
}
public void Test_Failure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    #pragma unused db
    #pragma unused data
    #pragma unused numQueries
    #pragma unused error
    #pragma unused failIndex
    #pragma unused queryData
    SetFailState("Isolated Equal Lottery transaction failed");
}
public void OnPluginStart()
{
    char error[256];
    testDb = SQLite_UseDatabase("lottery_equal_refund_regression", error, sizeof(error));
    if (testDb == null) SetFailState("Could not open isolated test database");
    Query("CREATE TABLE IF NOT EXISTS test_equal_balances (steamid64 TEXT PRIMARY KEY, balance INTEGER, updated_at TEXT DEFAULT CURRENT_TIMESTAMP)");
    Query("CREATE TABLE IF NOT EXISTS test_equal_tickets (id INTEGER PRIMARY KEY, lottery_id INTEGER, steamid64 TEXT, display_name TEXT, ticket TEXT, ticket_value INTEGER, created_at INTEGER, UNIQUE(lottery_id, steamid64))");
    Query("CREATE TABLE IF NOT EXISTS test_equal_receipts (award_key TEXT PRIMARY KEY, steamid64 TEXT, amount INTEGER, reason TEXT, created_at INTEGER)");
    StartCase();
}
public void OnPluginEnd()
{
    delete testDb;
}
