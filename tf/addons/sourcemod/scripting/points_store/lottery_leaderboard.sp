static char g_LotteryLeaderboardSteamIds[CURRENCY_LEADERBOARD_LIMIT][32];
static char g_LotteryLeaderboardNames[CURRENCY_LEADERBOARD_LIMIT][128];
static char g_LotteryLeaderboardColors[CURRENCY_LEADERBOARD_LIMIT][32];
static char g_LotteryLeaderboardCounts[CURRENCY_LEADERBOARD_LIMIT][32];
static char g_LotteryLeaderboardPercentages[CURRENCY_LEADERBOARD_LIMIT][32];
static char g_LotteryLeaderboardProfits[CURRENCY_LEADERBOARD_LIMIT][32];
static int g_LotteryLeaderboardRows;
static bool g_LotteryLeaderboardReady;
static bool g_LotteryLeaderboardRequested;
static bool g_LotteryLeaderboardInFlight;
static Handle g_LotteryLeaderboardRetry;

int LotteryLeaderboard_GetRows(bool &ready)
{
    ready = g_LotteryLeaderboardReady;
    return g_LotteryLeaderboardRows;
}

void LotteryLeaderboard_GetSteamId(int row, char[] steamId, int maxlen)
{
    strcopy(steamId, maxlen, g_LotteryLeaderboardSteamIds[row]);
}

void LotteryLeaderboard_PrintRow(int client, int rank, int row, const char[] currencyColor)
{
    CPrintToChat(client, "%d. {%s}%s{default} - %s lottos - %s%s%% (%s%s{default})", rank,
        g_LotteryLeaderboardColors[row], g_LotteryLeaderboardNames[row], g_LotteryLeaderboardCounts[row],
        g_LotteryLeaderboardPercentages[row][0] == '-' ? "" : "+", g_LotteryLeaderboardPercentages[row],
        currencyColor, g_LotteryLeaderboardProfits[row]);
}

void LotteryLeaderboard_OnPluginStart()
{
    RegConsoleCmd("sm_ll", Command_ShowLotteryLeaderboard, "Show the lottery participation and profit leaderboard.");
    RegConsoleCmd("sm_lotteryleaderboard", Command_ShowLotteryLeaderboard, "Show the lottery participation and profit leaderboard.");
    g_LotteryLeaderboardRequested = true;
}

void LotteryLeaderboard_OnPluginEnd()
{
    delete g_LotteryLeaderboardRetry;
    g_LotteryLeaderboardRetry = null;
}

static void LotteryLeaderboard_BuildQuery(char[] query, int maxlen, bool mysql)
{
    char steamId[512], lotteryId[512], amount[512];
    Leaderboard_LogField("steamid64", steamId, sizeof(steamId), mysql);
    Leaderboard_LogField("lottery_id", lotteryId, sizeof(lotteryId), mysql);
    Leaderboard_LogField("amount", amount, sizeof(amount), mysql);
    char validFields[512], cacheJoin[128], nameJoin[128], ruleJoin[128], payoutJoin[128];
    strcopy(validFields, sizeof(validFields), mysql
        ? "steamid64 REGEXP '^[0-9]{17}$' AND lottery_id REGEXP '^[0-9]+$' AND amount REGEXP '^[0-9]+$'"
        : "length(steamid64)=17 AND steamid64 NOT GLOB '*[^0-9]*' "
        ... "AND length(lottery_id)>0 AND lottery_id NOT GLOB '*[^0-9]*' "
        ... "AND length(amount)>0 AND amount NOT GLOB '*[^0-9]*'");
    strcopy(cacheJoin, sizeof(cacheJoin), mysql
        ? "BINARY pc.steamid = BINARY totals.steamid64" : "pc.steamid = totals.steamid64");
    strcopy(nameJoin, sizeof(nameJoin), mysql
        ? "BINARY fs.steamid64 = BINARY totals.steamid64" : "fs.steamid64 = totals.steamid64");
    strcopy(ruleJoin, sizeof(ruleJoin), mysql
        ? "BINARY pr.pattern = BINARY totals.steamid64" : "pr.pattern = totals.steamid64");
    strcopy(payoutJoin, sizeof(payoutJoin), mysql
        ? "BINARY p.steamid64 = BINARY t.steamid64" : "p.steamid64 = t.steamid64");

    // Count each completed ticket once. Refunds remove tickets, and unfinished
    // draws contribute neither stakes nor payouts. Credit events contain actual
    // main/bonus prizes after tax; historical draws without them paid the pool
    // to their saved winner. Aggregate payouts before joining to avoid fan-out.
    FormatEx(query, maxlen,
        "SELECT totals.steamid64,CAST(totals.lottos AS %s),"
        ... "CAST(CAST(ROUND(100.0*(totals.payouts-totals.stakes)/totals.stakes) AS %s) AS %s),"
        ... "CAST(totals.payouts-totals.stakes AS %s),"
        ... "COALESCE(NULLIF(pr.newname,''),NULLIF(fs.last_name,''),totals.steamid64),"
        ... "COALESCE(NULLIF(pc.name_color,''),'gold') FROM ("
        ... "SELECT t.steamid64,COUNT(*) AS lottos,SUM(t.ticket_value) AS stakes,"
        ... "SUM(COALESCE(p.payout,CASE WHEN l.winner_steamid64=t.steamid64 THEN l.prize_pool ELSE 0 END)) AS payouts "
        ... "FROM %s t JOIN %s l ON l.id=t.lottery_id LEFT JOIN ("
        ... "SELECT steamid64,CAST(lottery_id AS %s) AS lottery_id,SUM(CAST(amount AS %s)) AS payout FROM ("
        ... "SELECT %s AS steamid64,%s AS lottery_id,%s AS amount FROM plugin_statistics_events "
        ... "WHERE source_plugin='points_store' AND event_name='lottery_credit' "
        ... "AND (message LIKE '%%|reason=lottery_main_payout|%%' OR message LIKE '%%|reason=lottery_extra_payout|%%')"
        ... ") fields WHERE %s GROUP BY steamid64,CAST(lottery_id AS %s)"
        ... ") p ON %s AND p.lottery_id=t.lottery_id "
        ... "WHERE l.finished=1 AND t.ticket_value>0 GROUP BY t.steamid64"
        ... ") totals LEFT JOIN whaletracker_points_cache pc ON %s "
        ... "LEFT JOIN prename_rules pr ON %s LEFT JOIN filters_steam_names fs ON %s "
        ... "ORDER BY totals.lottos DESC,(totals.payouts-totals.stakes) DESC,totals.steamid64 ASC LIMIT %d",
        mysql ? "CHAR" : "TEXT", mysql ? "SIGNED" : "INTEGER", mysql ? "CHAR" : "TEXT", mysql ? "CHAR" : "TEXT",
        LOTTO_TICKET_TABLE, LOTTO_TABLE, mysql ? "SIGNED" : "INTEGER", mysql ? "SIGNED" : "INTEGER",
        steamId, lotteryId, amount, validFields, mysql ? "SIGNED" : "INTEGER",
        payoutJoin, cacheJoin, ruleJoin, nameJoin, CURRENCY_LEADERBOARD_LIMIT);
}

void LotteryLeaderboard_LoadStartupCache()
{
    if (!g_LotteryLeaderboardRequested || g_LotteryLeaderboardInFlight
        || g_LotteryLeaderboardRetry != null || !g_DatabaseReady || g_Database == null)
        return;
    char query[6144];
    LotteryLeaderboard_BuildQuery(query, sizeof(query), g_IsMySql);
    g_LotteryLeaderboardInFlight = true;
    g_Database.Query(PointsStore_CacheLotteryLeaderboard, query);
}

public void PointsStore_CacheLotteryLeaderboard(Database db, DBResultSet results, const char[] error, any data)
{
    g_LotteryLeaderboardInFlight = false;
    if (error[0] != '\0' || results == null)
    {
        LogError("[points_store] Lottery leaderboard startup load failed: %s", error);
        g_LotteryLeaderboardRetry = CreateTimer(30.0, LotteryLeaderboard_Retry);
        return;
    }
    g_LotteryLeaderboardRows = 0;
    while (g_LotteryLeaderboardRows < CURRENCY_LEADERBOARD_LIMIT && results.FetchRow())
    {
        int row = g_LotteryLeaderboardRows++;
        results.FetchString(0, g_LotteryLeaderboardSteamIds[row], sizeof(g_LotteryLeaderboardSteamIds[]));
        results.FetchString(1, g_LotteryLeaderboardCounts[row], sizeof(g_LotteryLeaderboardCounts[]));
        results.FetchString(2, g_LotteryLeaderboardPercentages[row], sizeof(g_LotteryLeaderboardPercentages[]));
        results.FetchString(3, g_LotteryLeaderboardProfits[row], sizeof(g_LotteryLeaderboardProfits[]));
        results.FetchString(4, g_LotteryLeaderboardNames[row], sizeof(g_LotteryLeaderboardNames[]));
        results.FetchString(5, g_LotteryLeaderboardColors[row], sizeof(g_LotteryLeaderboardColors[]));
        TrimString(g_LotteryLeaderboardNames[row]);
        NormalizeLeaderboardColorTag(g_LotteryLeaderboardColors[row], sizeof(g_LotteryLeaderboardColors[]));
        if (!g_LotteryLeaderboardNames[row][0])
            strcopy(g_LotteryLeaderboardNames[row], sizeof(g_LotteryLeaderboardNames[]), g_LotteryLeaderboardSteamIds[row]);
    }
    g_LotteryLeaderboardRequested = false;
    g_LotteryLeaderboardReady = true;
    LogMessage("[points_store] Lottery leaderboard startup cache ready: %d rows.", g_LotteryLeaderboardRows);
}

public Action LotteryLeaderboard_Retry(Handle timer)
{
    g_LotteryLeaderboardRetry = null;
    LotteryLeaderboard_LoadStartupCache();
    return Plugin_Stop;
}
