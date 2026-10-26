#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>

#define LOTTO_TICKET_TABLE "points_store_lottery_tickets"
#define LOTTO_TABLE "points_store_lotteries"
#define BP_BALANCE_TABLE "points_store_balances"
Database g_Database;
bool g_IsMySql;
int g_CurrencySnapshotGeneration, checks, failures, initializations;
#include "history.inc"

void Check(bool ok, const char[] label)
{
    checks++;
    if (!ok) { failures++; PrintToServer("[TicketHistoryProbe] FAIL: %s", label); }
}
void Query(const char[] sql)
{
    if (!SQL_FastQuery(g_Database, sql)) SetFailState("Ticket-history fixture SQL failed");
}
int Scalar(const char[] sql)
{
    DBResultSet rows = SQL_Query(g_Database, sql);
    if (rows == null || !rows.FetchRow()) SetFailState("Ticket-history fixture assertion failed");
    int value = rows.FetchInt(0);
    delete rows;
    return value;
}

public void OnPluginStart()
{
    char error[256];
    // Dedicated test database only. No configured/production connection is opened.
    g_Database = SQLite_UseDatabase("lottery_ticket_history_regression", error, sizeof(error));
    if (g_Database == null) SetFailState("Could not open ticket-history fixture");
    Query("DROP TABLE IF EXISTS points_store_lottery_tickets");
    Query("DROP TABLE IF EXISTS points_store_lottery_ticket_history");
    Query("DROP TABLE IF EXISTS points_store_balances");
    Query("DROP TABLE IF EXISTS points_store_lotteries");
    Query("CREATE TABLE points_store_lottery_tickets(id INTEGER PRIMARY KEY,lottery_id INTEGER,steamid64 TEXT,display_name TEXT,ticket TEXT,ticket_value INTEGER,created_at INTEGER)");
    Query("CREATE TABLE points_store_balances(steamid64 TEXT PRIMARY KEY,balance INTEGER)");
    Query("CREATE TABLE points_store_lotteries(id INTEGER PRIMARY KEY,equal_lottery INTEGER,equal_ticket_value INTEGER)");
    Query("INSERT INTO points_store_lotteries VALUES(17,0,0)");
    Query("INSERT INTO points_store_balances VALUES('00000000000000001',900)");

    char path[PLATFORM_MAX_PATH], sql[4096];
    BuildPath(Path_SM, path, sizeof(path), "data/lottery_ticket_history_mysql.sql");
    File export = OpenFile(path, "w");
    if (export == null) SetFailState("Could not export trigger SQL fixture");
    LotteryHistory_BuildCreate(sql, sizeof(sql), true); export.WriteLine("%s;", sql);
    for (int kind = 0; kind < 3; kind++)
    {
        LotteryHistory_BuildTrigger(sql, sizeof(sql), true, kind);
        export.WriteLine("%s;", sql);
    }
    delete export;
    LotteryHistory_EnsureSchema();
}

// The production bootstrap continues to economy schema here. This fixture only
// runs assertions on its private SQLite tables after the actual chain completes.
void EnsureEconomySchema()
{
    initializations++;
    if (initializations > 1)
    {
        Check(Scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history") == 4, "repeat schema initialization preserves journal");
        PrintToServer("[TicketHistoryProbe] %d checks, %d failures", checks, failures);
        return;
    }
    Check(Scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='trigger'") == 3, "all mutation triggers installed");
    Check(Scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name LIKE 'idx_lotto_history_%'") == 3, "lookup indexes installed");
    Query("INSERT INTO points_store_lottery_tickets VALUES(1,17,'00000000000000001','Synthetic','FIRST',100,123)");
    Check(Scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history WHERE operation='purchase' AND old_ticket_value=0 AND ticket_value=100 AND stake_delta=100 AND balance_snapshot=900") == 1, "purchase recorded with observed balance");
    Check(Scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history WHERE length(recorded_date)=10 AND recorded_at>0 AND steamid64='00000000000000001'") == 1, "date and account recorded");
    Query("BEGIN");
    Query("UPDATE points_store_lottery_tickets SET ticket='SECOND',ticket_value=340,created_at=124 WHERE id=1");
    Query("UPDATE points_store_balances SET balance=660");
    Query("COMMIT");
    Check(Scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history WHERE operation='replace' AND old_ticket_value=100 AND ticket_value=340 AND stake_delta=240 AND old_created_at=123 AND ticket_created_at=124") == 1, "replacement preserves original and new stakes");
    Query("BEGIN");
    Query("UPDATE points_store_lottery_tickets SET ticket='ROLLBACK',ticket_value=680,created_at=125 WHERE id=1");
    Query("UPDATE points_store_balances SET balance=320");
    Query("ROLLBACK");
    Check(Scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history") == 2, "rolled-back replacement has no false audit row");
    Check(Scalar("SELECT ticket_value FROM points_store_lottery_tickets WHERE id=1") == 340, "rollback preserves ticket");
    Check(Scalar("SELECT balance FROM points_store_balances") == 660, "rollback preserves wallet");
    Query("CREATE TRIGGER fail_journal BEFORE INSERT ON points_store_lottery_ticket_history BEGIN SELECT RAISE(ABORT,'injected fixture journal failure'); END");
    Check(!SQL_FastQuery(g_Database,"INSERT INTO points_store_lottery_tickets VALUES(2,17,'00000000000000002','Synthetic','FAIL',100,126)"), "journal failure rejects ticket insertion atomically");
    Check(Scalar("SELECT COUNT(*) FROM points_store_lottery_tickets WHERE id=2") == 0, "failed journal leaves no unaudited ticket");
    Query("DROP TRIGGER fail_journal");
    Query("UPDATE points_store_lotteries SET equal_lottery=1,equal_ticket_value=100");
    Query("BEGIN");
    Query("UPDATE points_store_balances SET balance=900");
    Query("UPDATE points_store_lottery_tickets SET ticket_value=100 WHERE id=1");
    Query("COMMIT");
    Check(Scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history WHERE operation='equal_conversion' AND old_ticket_value=340 AND ticket_value=100 AND stake_delta=-240 AND balance_snapshot=900 AND equal_lottery=1 AND equal_ticket_value=100") == 1, "equal conversion retains pre-normalization stake");
    Query("UPDATE points_store_lottery_tickets SET ticket_value=ticket_value,display_name='Renamed' WHERE id=1");
    Check(Scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history") == 3, "no-op and name-only updates do not invent purchases");
    Query("DELETE FROM points_store_lottery_tickets WHERE id=1");
    Check(Scalar("SELECT COUNT(*) FROM points_store_lottery_ticket_history WHERE operation='remove' AND old_ticket_value=100 AND ticket_value=0 AND stake_delta=-100") == 1, "removal remains traceable after live ticket deletion");
    Check(Scalar("SELECT ticket_value FROM points_store_lottery_ticket_history WHERE record_id=1") == 100, "older purchase record is immutable");
    LotteryHistory_EnsureSchema();
}
public void OnPluginEnd() { delete g_Database; }
