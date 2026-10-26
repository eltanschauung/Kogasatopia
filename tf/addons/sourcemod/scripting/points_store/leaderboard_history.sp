// Archive the exact successfully refreshed sm_gl top-50 cache, not a later
// re-query. Writes are asynchronous, immutable and idempotent on retry.
#define CURRENCY_HISTORY_TABLE "points_store_balance_history"
#define CURRENCY_HISTORY_QUERY_MAX 12288
#define CURRENCY_HISTORY_QUEUE_LIMIT 64

static ArrayList g_CurrencyHistoryJobs;
static bool g_CurrencyHistoryBusy;
static bool g_CurrencyHistorySchemaReady;
static Handle g_CurrencyHistoryRetry;

void CurrencyHistory_RecordSnapshot(int rowCount, const char[][] steamIds, const int[] balances)
{
    if (rowCount <= 0) return;
    if (g_CurrencyHistoryJobs == null) g_CurrencyHistoryJobs = new ArrayList();
    if (g_CurrencyHistoryJobs.Length >= CURRENCY_HISTORY_QUEUE_LIMIT)
    {
        LogError("[points_store] Balance history queue is full; snapshot not archived.");
        return;
    }
    int capturedAt = GetTime();
    ConVar port = FindConVar("hostport");
    int hostPort = port == null ? 0 : port.IntValue;
    char date[11], snapshotId[64];
    FormatTime(date, sizeof(date), "%Y-%m-%d", capturedAt);
    // Two random cells namespace refreshes/reloads/ports occurring in one second.
    FormatEx(snapshotId, sizeof(snapshotId), "%d:%d:%d:%d", capturedAt, hostPort, GetURandomInt(), GetURandomInt());
    char query[CURRENCY_HISTORY_QUERY_MAX], row[256];
    FormatEx(query, sizeof(query),
        "INSERT INTO %s (snapshot_id,snapshot_date,captured_at,host_port,steamid64,balance) VALUES ", CURRENCY_HISTORY_TABLE);
    int count;
    for (int i = 0; i < rowCount; i++)
    {
        int length = strlen(steamIds[i]);
        bool valid = length >= 16 && length < 32;
        for (int j = 0; j < length; j++) if (!IsCharNumeric(steamIds[i][j])) valid = false;
        if (!valid)
        {
            LogError("[points_store] Invalid account identity in balance cache; snapshot row skipped.");
            continue;
        }
        FormatEx(row, sizeof(row), "%s('%s','%s',%d,%d,'%s',%d)", count ? "," : "",
            snapshotId, date, capturedAt, hostPort, steamIds[i], balances[i]);
        StrCat(query, sizeof(query), row);
        count++;
    }
    if (!count) return;
    StrCat(query, sizeof(query), g_IsMySql
        ? " ON DUPLICATE KEY UPDATE balance=balance"
        : " ON CONFLICT(snapshot_id,steamid64) DO NOTHING");
    DataPack job = new DataPack();
    job.WriteString(query);
    g_CurrencyHistoryJobs.Push(job);
    CurrencyHistory_Drain();
}

void CurrencyHistory_Drain()
{
    if (g_CurrencyHistoryBusy || g_CurrencyHistoryRetry != null || !g_DatabaseReady || g_Database == null
        || g_CurrencyHistoryJobs == null || !g_CurrencyHistoryJobs.Length) return;
    g_CurrencyHistoryBusy = true;
    if (!g_CurrencyHistorySchemaReady)
    {
        Transaction schema = new Transaction();
        char query[1024];
        FormatEx(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s (snapshot_id VARCHAR(64) NOT NULL,snapshot_date VARCHAR(10) NOT NULL,"
            ... "captured_at INTEGER NOT NULL,host_port INTEGER NOT NULL,steamid64 VARCHAR(32) NOT NULL,balance INTEGER NOT NULL,"
            ... "PRIMARY KEY(snapshot_id,steamid64)%s)", CURRENCY_HISTORY_TABLE,
            g_IsMySql ? ",KEY idx_balance_history_date(snapshot_date,captured_at),KEY idx_balance_history_client(steamid64,captured_at)" : "");
        schema.AddQuery(query);
        if (!g_IsMySql)
        {
            schema.AddQuery("CREATE INDEX IF NOT EXISTS idx_balance_history_date ON points_store_balance_history(snapshot_date,captured_at)");
            schema.AddQuery("CREATE INDEX IF NOT EXISTS idx_balance_history_client ON points_store_balance_history(steamid64,captured_at)");
        }
        g_Database.Execute(schema, CurrencyHistory_SchemaReady, CurrencyHistory_SchemaFailed);
        return;
    }
    DataPack job = view_as<DataPack>(g_CurrencyHistoryJobs.Get(0));
    job.Reset();
    char query[CURRENCY_HISTORY_QUERY_MAX];
    job.ReadString(query, sizeof(query));
    g_Database.Query(CurrencyHistory_Written, query, job);
}

public void CurrencyHistory_SchemaReady(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    g_CurrencyHistoryBusy = false;
    g_CurrencyHistorySchemaReady = Store_IsCurrentConnection(db);
    if (g_CurrencyHistorySchemaReady) CurrencyHistory_Drain();
    else CurrencyHistory_ScheduleRetry();
}

public void CurrencyHistory_SchemaFailed(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    g_CurrencyHistoryBusy = false;
    g_CurrencyHistorySchemaReady = false;
    LogError("[points_store] Balance history schema failed; queued snapshots retained: %s", error);
    CurrencyHistory_ScheduleRetry();
}

public void CurrencyHistory_Written(Database db, DBResultSet results, const char[] error, any data)
{
    g_CurrencyHistoryBusy = false;
    if (error[0] || results == null)
    {
        g_CurrencyHistorySchemaReady = false;
        LogError("[points_store] Balance history write failed; snapshot retained for retry: %s", error);
        CurrencyHistory_ScheduleRetry();
        return;
    }
    DataPack job = view_as<DataPack>(data);
    g_CurrencyHistoryJobs.Erase(0);
    delete job;
    CurrencyHistory_Drain();
}

void CurrencyHistory_ScheduleRetry()
{
    if (g_CurrencyHistoryRetry == null) g_CurrencyHistoryRetry = CreateTimer(30.0, CurrencyHistory_Retry);
}

public Action CurrencyHistory_Retry(Handle timer)
{
    if (timer != g_CurrencyHistoryRetry) return Plugin_Stop;
    g_CurrencyHistoryRetry = null;
    CurrencyHistory_Drain();
    if (!g_CurrencyHistoryBusy && g_CurrencyHistoryJobs != null && g_CurrencyHistoryJobs.Length)
        CurrencyHistory_ScheduleRetry();
    return Plugin_Stop;
}

void CurrencyHistory_Stop()
{
    delete g_CurrencyHistoryRetry;
    if (g_CurrencyHistoryJobs != null)
    {
        if (g_CurrencyHistoryJobs.Length)
            LogError("[points_store] Unloading with %d unarchived balance snapshots.", g_CurrencyHistoryJobs.Length);
        for (int i = 0; i < g_CurrencyHistoryJobs.Length; i++)
        {
            DataPack job = view_as<DataPack>(g_CurrencyHistoryJobs.Get(i));
            delete job;
        }
    }
    delete g_CurrencyHistoryJobs;
}
