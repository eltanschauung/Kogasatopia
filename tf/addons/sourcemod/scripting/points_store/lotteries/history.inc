// Unconditional, database-side ticket journal. Triggers commit/roll back with
// the ticket mutation, including changes from other servers and offline clients.
#define LOTTO_TICKET_HISTORY_TABLE "points_store_lottery_ticket_history"

void LotteryHistory_BuildCreate(char[] query, int maxlen, bool mysql)
{
    FormatEx(query, maxlen,
        "CREATE TABLE IF NOT EXISTS %s ("
        ... "record_id %s,recorded_at INTEGER NOT NULL,recorded_date VARCHAR(10) NOT NULL,"
        ... "lottery_id INTEGER NOT NULL,ticket_id INTEGER NOT NULL,steamid64 VARCHAR(32) NOT NULL,"
        ... "operation VARCHAR(24) NOT NULL,old_ticket_value INTEGER NOT NULL,ticket_value INTEGER NOT NULL,"
        ... "stake_delta INTEGER NOT NULL,balance_snapshot INTEGER NULL,old_created_at INTEGER NOT NULL,"
        ... "ticket_created_at INTEGER NOT NULL,equal_lottery INTEGER NOT NULL,equal_ticket_value INTEGER NOT NULL%s)%s",
        LOTTO_TICKET_HISTORY_TABLE,
        mysql ? "BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY" : "INTEGER PRIMARY KEY AUTOINCREMENT",
        mysql ? ",KEY idx_lotto_history_client(steamid64,recorded_at),KEY idx_lotto_history_date(recorded_date,recorded_at),KEY idx_lotto_history_lottery(lottery_id,record_id)" : "",
        mysql ? " ENGINE=InnoDB" : "");
}

void LotteryHistory_BuildTrigger(char[] query, int maxlen, bool mysql, int kind)
{
    char row[4], name[64], event[8], oldValue[32], newValue[32], oldCreated[32], newCreated[32];
    strcopy(row, sizeof(row), kind == 2 ? "OLD" : "NEW");
    strcopy(event, sizeof(event), kind == 0 ? "INSERT" : (kind == 1 ? "UPDATE" : "DELETE"));
    FormatEx(name, sizeof(name), "points_store_lotto_history_%s_v1", event);
    strcopy(oldValue, sizeof(oldValue), kind == 0 ? "0" : "OLD.ticket_value");
    strcopy(newValue, sizeof(newValue), kind == 2 ? "0" : "NEW.ticket_value");
    strcopy(oldCreated, sizeof(oldCreated), kind == 0 ? "0" : "OLD.created_at");
    strcopy(newCreated, sizeof(newCreated), kind == 2 ? "0" : "NEW.created_at");

    char balance[256], equal[256], required[256], operation[768], condition[256];
    FormatEx(balance, sizeof(balance), "(SELECT balance FROM %s WHERE steamid64=%s.steamid64)", BP_BALANCE_TABLE, row);
    FormatEx(equal, sizeof(equal), "COALESCE((SELECT equal_lottery FROM %s WHERE id=%s.lottery_id),0)", LOTTO_TABLE, row);
    FormatEx(required, sizeof(required), "COALESCE((SELECT equal_ticket_value FROM %s WHERE id=%s.lottery_id),0)", LOTTO_TABLE, row);
    if (kind == 1)
    {
        FormatEx(operation, sizeof(operation),
            "CASE WHEN OLD.ticket<>NEW.ticket OR OLD.created_at<>NEW.created_at THEN 'replace' "
            ... "WHEN %s=1 AND NEW.ticket_value<OLD.ticket_value THEN 'equal_conversion' ELSE 'adjust' END", equal);
        strcopy(condition, sizeof(condition),
            " WHERE OLD.ticket_value<>NEW.ticket_value OR OLD.ticket<>NEW.ticket OR OLD.created_at<>NEW.created_at"
            ... " OR OLD.steamid64<>NEW.steamid64 OR OLD.lottery_id<>NEW.lottery_id");
    }
    else strcopy(operation, sizeof(operation), kind == 0 ? "'purchase'" : "'remove'");
    char insert[3072];
    FormatEx(insert, sizeof(insert),
        "INSERT INTO %s (recorded_at,recorded_date,lottery_id,ticket_id,steamid64,operation,old_ticket_value,"
        ... "ticket_value,stake_delta,balance_snapshot,old_created_at,ticket_created_at,equal_lottery,equal_ticket_value) "
        ... "SELECT %s,%s,%s.lottery_id,%s.id,%s.steamid64,%s,%s,%s,(%s-%s),%s,%s,%s,%s,%s%s",
        LOTTO_TICKET_HISTORY_TABLE,
        mysql ? "UNIX_TIMESTAMP()" : "CAST(strftime('%s','now') AS INTEGER)",
        mysql ? "CURRENT_DATE()" : "date('now','localtime')",
        row, row, row, operation, oldValue, newValue, newValue, oldValue,
        balance, oldCreated, newCreated, equal, required, condition);
    if (mysql)
        FormatEx(query, maxlen, "CREATE TRIGGER %s AFTER %s ON %s FOR EACH ROW %s", name, event, LOTTO_TICKET_TABLE, insert);
    else
        FormatEx(query, maxlen, "CREATE TRIGGER IF NOT EXISTS %s AFTER %s ON %s BEGIN %s; END", name, event, LOTTO_TICKET_TABLE, insert);
}

void LotteryHistory_EnsureSchema()
{
    LotteryHistory_QueueSchemaStage(0);
}

void LotteryHistory_QueueSchemaStage(int stage)
{
    if (g_Database == null) return;
    char query[4096];
    if (stage == 0) LotteryHistory_BuildCreate(query, sizeof(query), g_IsMySql);
    else if (stage <= 3) LotteryHistory_BuildTrigger(query, sizeof(query), g_IsMySql, stage - 1);
    else if (g_IsMySql || stage > 6)
    {
        // Only mark the rest of Points Store ready once journaling is installed.
        EnsureEconomySchema();
        return;
    }
    else
    {
        static const char indexes[][] = {
            "CREATE INDEX IF NOT EXISTS idx_lotto_history_client ON points_store_lottery_ticket_history(steamid64,recorded_at)",
            "CREATE INDEX IF NOT EXISTS idx_lotto_history_date ON points_store_lottery_ticket_history(recorded_date,recorded_at)",
            "CREATE INDEX IF NOT EXISTS idx_lotto_history_lottery ON points_store_lottery_ticket_history(lottery_id,record_id)"
        };
        strcopy(query, sizeof(query), indexes[stage - 4]);
    }
    g_Database.Query(LotteryHistory_SchemaStageReady, query, stage);
}

public void LotteryHistory_SchemaStageReady(Database db, DBResultSet results, const char[] error, any stage)
{
    // Bootstrap precedes g_DatabaseReady; verify the connection without that flag.
    if (db == null || g_Database == null || !g_Database.IsSameConnection(db)) return;
    bool alreadyInstalled = stage >= 1 && stage <= 3 && g_IsMySql
        && StrContains(error, "already exists", false) != -1;
    if (error[0] && !alreadyInstalled)
    {
        LogError("[points_store] Lottery ticket journal schema failed at stage %d: %s", stage, error);
        CreateTimer(30.0, LotteryHistory_RetrySchema, g_CurrencySnapshotGeneration);
        return;
    }
    LotteryHistory_QueueSchemaStage(stage + 1);
}

public Action LotteryHistory_RetrySchema(Handle timer, any generation)
{
    if (generation == g_CurrencySnapshotGeneration) LotteryHistory_EnsureSchema();
    return Plugin_Stop;
}
