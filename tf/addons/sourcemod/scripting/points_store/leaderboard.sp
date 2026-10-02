void NormalizeLeaderboardColorTag(char[] colorTag, int maxlen)
{
    TrimString(colorTag);

    if (colorTag[0] == '\0'
        || StrEqual(colorTag, "teamcolor", false)
        || StrEqual(colorTag, "{teamcolor}", false))
    {
        strcopy(colorTag, maxlen, "gold");
        return;
    }

    int len = strlen(colorTag);
    if (len >= 2 && colorTag[0] == '{' && colorTag[len - 1] == '}')
    {
        int out = 0;
        for (int i = 1; i < len - 1 && out < maxlen - 1; i++)
        {
            colorTag[out++] = colorTag[i];
        }
        colorTag[out] = '\0';
    }

    if (colorTag[0] == '\0')
    {
        strcopy(colorTag, maxlen, "gold");
    }
}

#define CURRENCY_LEADERBOARD_LIMIT 50
enum CurrencyLeaderboardKind
{
    CurrencyLeaderboard_Balance,
    CurrencyLeaderboard_GemsSent,
    CurrencyLeaderboard_Lottery
};
static char g_CurrencyLeaderboardSteamIds[CURRENCY_LEADERBOARD_LIMIT][32];
static char g_CurrencyLeaderboardNames[CURRENCY_LEADERBOARD_LIMIT][128];
static char g_CurrencyLeaderboardColors[CURRENCY_LEADERBOARD_LIMIT][32];
static int g_CurrencyLeaderboardBalances[CURRENCY_LEADERBOARD_LIMIT];
static int g_CurrencyLeaderboardRows;
static int g_CurrencyLeaderboardGeneration;
static bool g_CurrencyLeaderboardReady;
static bool g_CurrencyLeaderboardRefreshRequested;
static bool g_CurrencyLeaderboardInFlight;
static int g_CurrencyLeaderboardPreviousPopulation;
static int g_CurrencyLeaderboardLivePopulation;
static bool g_CurrencyLeaderboardSamplePopulation;

static char g_GemsSentLeaderboardSteamIds[CURRENCY_LEADERBOARD_LIMIT][32];
static char g_GemsSentLeaderboardNames[CURRENCY_LEADERBOARD_LIMIT][128];
static char g_GemsSentLeaderboardColors[CURRENCY_LEADERBOARD_LIMIT][32];
static char g_GemsSentLeaderboardTotals[CURRENCY_LEADERBOARD_LIMIT][32];
static int g_GemsSentLeaderboardRows;
static bool g_GemsSentLeaderboardReady;
static bool g_GemsSentLeaderboardRequested;
static bool g_GemsSentLeaderboardInFlight;
static Handle g_GemsSentLeaderboardRetry;

void GemsSentLeaderboard_OnPluginStart()
{
    RegConsoleCmd("sm_gsl", Command_ShowGemsSentLeaderboard, "Show the gems sent leaderboard.");
    RegConsoleCmd("sm_gemssentleaderboard", Command_ShowGemsSentLeaderboard, "Show the gems sent leaderboard.");
    // The startup request waits for FinishSchemaReady; maps never request it again.
    g_GemsSentLeaderboardRequested = true;
}

void GemsSentLeaderboard_OnPluginEnd()
{
    delete g_GemsSentLeaderboardRetry;
    g_GemsSentLeaderboardRetry = null;
}

void Leaderboard_LogField(const char[] field, char[] expression, int maxlen, bool mysql)
{
    // Points-store events use a pipe-delimited key=value protocol. Match the full key
    // boundary so amount cannot match sender_balance or text in a player's name.
    if (mysql)
    {
        FormatEx(expression, maxlen,
            "SUBSTRING_INDEX(SUBSTRING_INDEX(CONCAT('|',message),'|%s=',-1),'|',1)", field);
    }
    else
    {
        int markerLength = strlen(field) + 2;
        FormatEx(expression, maxlen,
            "substr(message,instr(message,'|%s=')+%d,"
            ... "instr(substr(message||'|',instr(message,'|%s=')+%d),'|')-1)",
            field, markerLength, field, markerLength);
    }
}

static void GemsSentLeaderboard_BuildQuery(char[] query, int maxlen, bool mysql)
{
    char sender[512], target[512], amount[512];
    Leaderboard_LogField("sender_steamid64", sender, sizeof(sender), mysql);
    Leaderboard_LogField("target_steamid64", target, sizeof(target), mysql);
    Leaderboard_LogField("amount", amount, sizeof(amount), mysql);
    char validFields[512], cacheJoin[128], nameJoin[128], ruleJoin[128];
    strcopy(validFields, sizeof(validFields), mysql
        ? "sender_id REGEXP '^[0-9]{17}$' AND target_id REGEXP '^[0-9]{17}$' AND amount REGEXP '^[0-9]+$'"
        : "length(sender_id)=17 AND sender_id NOT GLOB '*[^0-9]*' "
        ... "AND length(target_id)=17 AND target_id NOT GLOB '*[^0-9]*' "
        ... "AND length(amount)>0 AND amount NOT GLOB '*[^0-9]*'");
    strcopy(cacheJoin, sizeof(cacheJoin), mysql
        ? "BINARY pc.steamid = BINARY totals.steamid64" : "pc.steamid = totals.steamid64");
    strcopy(nameJoin, sizeof(nameJoin), mysql
        ? "BINARY fs.steamid64 = BINARY totals.steamid64" : "fs.steamid64 = totals.steamid64");
    strcopy(ruleJoin, sizeof(ruleJoin), mysql
        ? "BINARY pr.pattern = BINARY totals.steamid64" : "pr.pattern = totals.steamid64");
    FormatEx(query, maxlen,
        "SELECT totals.steamid64,CAST(totals.gems_sent AS %s),"
        ... "COALESCE(NULLIF(pr.newname,''),NULLIF(fs.last_name,''),totals.steamid64),"
        ... "COALESCE(NULLIF(pc.name_color,''),'gold') FROM ("
        ... "SELECT sender_id AS steamid64,SUM(CAST(amount AS %s)) AS gems_sent FROM ("
        ... "SELECT %s AS sender_id,%s AS target_id,%s AS amount "
        ... "FROM plugin_statistics_events WHERE source_plugin='points_store' AND event_name='transfer_success'"
        ... ") fields WHERE %s AND sender_id<>target_id AND CAST(amount AS %s)>0 GROUP BY sender_id"
        ... ") totals LEFT JOIN whaletracker_points_cache pc ON %s "
        ... "LEFT JOIN prename_rules pr ON %s "
        ... "LEFT JOIN filters_steam_names fs ON %s "
        ... "ORDER BY totals.gems_sent DESC,totals.steamid64 ASC LIMIT %d",
        mysql ? "CHAR" : "TEXT", mysql ? "UNSIGNED" : "INTEGER", sender, target, amount, validFields,
        mysql ? "UNSIGNED" : "INTEGER", cacheJoin, ruleJoin, nameJoin, CURRENCY_LEADERBOARD_LIMIT);
}

void GemsSentLeaderboard_LoadStartupCache()
{
    if (!g_GemsSentLeaderboardRequested || g_GemsSentLeaderboardInFlight
        || g_GemsSentLeaderboardRetry != null || !g_DatabaseReady || g_Database == null)
        return;
    char query[4096];
    GemsSentLeaderboard_BuildQuery(query, sizeof(query), g_IsMySql);
    g_GemsSentLeaderboardInFlight = true;
    g_Database.Query(PointsStore_CacheGemsSentLeaderboard, query);
}

public void PointsStore_CacheGemsSentLeaderboard(Database db, DBResultSet results, const char[] error, any data)
{
    g_GemsSentLeaderboardInFlight = false;
    if (error[0] != '\0' || results == null)
    {
        LogError("[points_store] Gems sent leaderboard startup load failed: %s", error);
        // Survive map changes while retrying the original startup request.
        g_GemsSentLeaderboardRetry = CreateTimer(30.0, GemsSentLeaderboard_Retry);
        return;
    }
    g_GemsSentLeaderboardRows = 0;
    while (g_GemsSentLeaderboardRows < CURRENCY_LEADERBOARD_LIMIT && results.FetchRow())
    {
        int row = g_GemsSentLeaderboardRows++;
        results.FetchString(0, g_GemsSentLeaderboardSteamIds[row], sizeof(g_GemsSentLeaderboardSteamIds[]));
        results.FetchString(1, g_GemsSentLeaderboardTotals[row], sizeof(g_GemsSentLeaderboardTotals[]));
        results.FetchString(2, g_GemsSentLeaderboardNames[row], sizeof(g_GemsSentLeaderboardNames[]));
        results.FetchString(3, g_GemsSentLeaderboardColors[row], sizeof(g_GemsSentLeaderboardColors[]));
        TrimString(g_GemsSentLeaderboardNames[row]);
        NormalizeLeaderboardColorTag(g_GemsSentLeaderboardColors[row], sizeof(g_GemsSentLeaderboardColors[]));
        if (!g_GemsSentLeaderboardNames[row][0])
            strcopy(g_GemsSentLeaderboardNames[row], sizeof(g_GemsSentLeaderboardNames[]), g_GemsSentLeaderboardSteamIds[row]);
    }
    g_GemsSentLeaderboardRequested = false;
    g_GemsSentLeaderboardReady = true;
    LogMessage("[points_store] Gems sent leaderboard startup cache ready: %d rows.", g_GemsSentLeaderboardRows);
}

public Action GemsSentLeaderboard_Retry(Handle timer)
{
    g_GemsSentLeaderboardRetry = null;
    GemsSentLeaderboard_LoadStartupCache();
    return Plugin_Stop;
}

public void OnGameFrame()
{
    if (g_CurrencyLeaderboardSamplePopulation) g_CurrencyLeaderboardLivePopulation = GetClientCount(false);
}

void CurrencyLeaderboard_OnMapEnd()
{
    // OnMapEnd itself can follow client teardown; use the last live frame.
    g_CurrencyLeaderboardPreviousPopulation = g_CurrencyLeaderboardLivePopulation;
    g_CurrencyLeaderboardSamplePopulation = false;
}

void CurrencyLeaderboard_OnMapStart()
{
    g_CurrencyLeaderboardGeneration++;
    g_CurrencyLeaderboardLivePopulation = GetClientCount(false);
    g_CurrencyLeaderboardSamplePopulation = true;
    // Initialize once even after a quiet server start. Later map refreshes use
    // the outgoing map's population; new-map signon can report zero clients.
    g_CurrencyLeaderboardInFlight = false;
    g_CurrencyLeaderboardRefreshRequested = !g_CurrencyLeaderboardReady
        || g_CurrencyLeaderboardPreviousPopulation > 2 || GetClientCount(false) > 2;
    CurrencyLeaderboard_RefreshIfRequested();
}

void CurrencyLeaderboard_RefreshIfRequested()
{
    if (!g_CurrencyLeaderboardReady) g_CurrencyLeaderboardRefreshRequested = true;
    if (!g_CurrencyLeaderboardRefreshRequested || g_CurrencyLeaderboardInFlight
        || !g_DatabaseReady || g_Database == null) return;
    g_CurrencyLeaderboardRefreshRequested = false;
    g_CurrencyLeaderboardInFlight = true;
    char cacheJoin[128], nameJoin[128];
    strcopy(cacheJoin, sizeof(cacheJoin), g_IsMySql
        ? "BINARY pc.steamid = BINARY b.steamid64" : "pc.steamid = b.steamid64");
    strcopy(nameJoin, sizeof(nameJoin), g_IsMySql
        ? "BINARY fs.steamid64 = BINARY b.steamid64" : "fs.steamid64 = b.steamid64");
    char query[1400];
    FormatEx(query, sizeof(query),
        "SELECT b.steamid64, b.balance, COALESCE(NULLIF(pr.newname,''), NULLIF(fs.last_name,''), b.steamid64), COALESCE(NULLIF(pc.name_color,''), 'gold') "
        ... "FROM %s b LEFT JOIN whaletracker_points_cache pc ON %s "
        ... "LEFT JOIN prename_rules pr ON pr.pattern = b.steamid64 "
        ... "LEFT JOIN filters_steam_names fs ON %s "
        ... "WHERE b.balance > 0 ORDER BY b.balance DESC, b.steamid64 ASC LIMIT %d",
        BP_BALANCE_TABLE, cacheJoin, nameJoin, CURRENCY_LEADERBOARD_LIMIT);
    g_Database.Query(PointsStore_CacheCurrencyLeaderboard, query, g_CurrencyLeaderboardGeneration);
}

public void PointsStore_CacheCurrencyLeaderboard(Database db, DBResultSet results, const char[] error, any generation)
{
    if (generation != g_CurrencyLeaderboardGeneration)
        return;
    g_CurrencyLeaderboardInFlight = false;
    if (error[0] != '\0' || results == null)
    {
        LogError("[points_store] Currency leaderboard refresh failed: %s", error);
        g_CurrencyLeaderboardRefreshRequested = true;
        CreateTimer(30.0, CurrencyLeaderboard_Retry, generation, TIMER_FLAG_NO_MAPCHANGE);
        return; // Retain a successful older cache while dependencies reconnect.
    }
    g_CurrencyLeaderboardRows = 0;
    while (g_CurrencyLeaderboardRows < CURRENCY_LEADERBOARD_LIMIT && results.FetchRow())
    {
        int row = g_CurrencyLeaderboardRows++;
        results.FetchString(0, g_CurrencyLeaderboardSteamIds[row], sizeof(g_CurrencyLeaderboardSteamIds[]));
        g_CurrencyLeaderboardBalances[row] = results.FetchInt(1);
        results.FetchString(2, g_CurrencyLeaderboardNames[row], sizeof(g_CurrencyLeaderboardNames[]));
        results.FetchString(3, g_CurrencyLeaderboardColors[row], sizeof(g_CurrencyLeaderboardColors[]));
        TrimString(g_CurrencyLeaderboardNames[row]);
        NormalizeLeaderboardColorTag(g_CurrencyLeaderboardColors[row], sizeof(g_CurrencyLeaderboardColors[]));
        if (!g_CurrencyLeaderboardNames[row][0])
            results.FetchString(0, g_CurrencyLeaderboardNames[row], sizeof(g_CurrencyLeaderboardNames[]));
    }
    g_CurrencyLeaderboardReady = true;
    LogMessage("[points_store] Currency leaderboard cache ready: %d rows.", g_CurrencyLeaderboardRows);
}

public Action CurrencyLeaderboard_Retry(Handle timer, any generation)
{
    if (generation == g_CurrencyLeaderboardGeneration) CurrencyLeaderboard_RefreshIfRequested();
    return Plugin_Stop;
}

public Action Command_ShowCurrencyLeaderboard(int client, int args)
{
    return CurrencyLeaderboard_ShowCached(client, args, CurrencyLeaderboard_Balance);
}

public Action Command_ShowGemsSentLeaderboard(int client, int args)
{
    return CurrencyLeaderboard_ShowCached(client, args, CurrencyLeaderboard_GemsSent);
}

public Action Command_ShowLotteryLeaderboard(int client, int args)
{
    return CurrencyLeaderboard_ShowCached(client, args, CurrencyLeaderboard_Lottery);
}

static Action CurrencyLeaderboard_ShowCached(int client, int args, CurrencyLeaderboardKind kind)
{
    if (!Client_IsHumanInGame(client))
        return Plugin_Handled;
    bool ready;
    int rows;
    char command[4];
    switch (kind)
    {
        case CurrencyLeaderboard_Balance:
        {
            ready = g_CurrencyLeaderboardReady;
            rows = g_CurrencyLeaderboardRows;
            strcopy(command, sizeof(command), "gl");
        }
        case CurrencyLeaderboard_GemsSent:
        {
            ready = g_GemsSentLeaderboardReady;
            rows = g_GemsSentLeaderboardRows;
            strcopy(command, sizeof(command), "gsl");
        }
        case CurrencyLeaderboard_Lottery:
        {
            rows = LotteryLeaderboard_GetRows(ready);
            strcopy(command, sizeof(command), "ll");
        }
    }
    if (!ready)
    {
        CPrintToChat(client, "%s Leaderboard is loading; please try again shortly.", g_CurrencyPrefix);
        return Plugin_Handled;
    }
    int page = 1;
    if (args >= 1)
    {
        char argument[16];
        GetCmdArg(1, argument, sizeof(argument));
        page = StringToInt(argument);
    }
    int visible[CURRENCY_LEADERBOARD_LIMIT], count;
    char steamId[32];
    for (int row = 0; row < rows; row++)
    {
        switch (kind)
        {
            case CurrencyLeaderboard_Balance: strcopy(steamId, sizeof(steamId), g_CurrencyLeaderboardSteamIds[row]);
            case CurrencyLeaderboard_GemsSent: strcopy(steamId, sizeof(steamId), g_GemsSentLeaderboardSteamIds[row]);
            case CurrencyLeaderboard_Lottery: LotteryLeaderboard_GetSteamId(row, steamId, sizeof(steamId));
        }
        if (Oblivion_SteamMessageVisible(client, steamId)) visible[count++] = row;
    }
    int pages = (count + BP_LEADERBOARD_PAGE_SIZE - 1) / BP_LEADERBOARD_PAGE_SIZE;
    if (pages < 1) pages = 1;
    if (page < 1 || page > pages)
    {
        CPrintToChat(client, "%s Use !%s <1-%d>; only the top 50 are listed.", g_CurrencyPrefix, command, pages);
        return Plugin_Handled;
    }
    int start = (page - 1) * BP_LEADERBOARD_PAGE_SIZE;
    int end = start + BP_LEADERBOARD_PAGE_SIZE;
    if (end > count) end = count;
    char currencyColor[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(currencyColor, sizeof(currencyColor));
    for (int index = start; index < end; index++)
    {
        int row = visible[index];
        switch (kind)
        {
            case CurrencyLeaderboard_Balance:
                CPrintToChat(client, "#%d {%s}%s{default} %s%d", index + 1,
                    g_CurrencyLeaderboardColors[row], g_CurrencyLeaderboardNames[row], currencyColor, g_CurrencyLeaderboardBalances[row]);
            case CurrencyLeaderboard_GemsSent:
                CPrintToChat(client, "#%d {%s}%s{default} %s%s", index + 1,
                    g_GemsSentLeaderboardColors[row], g_GemsSentLeaderboardNames[row], currencyColor, g_GemsSentLeaderboardTotals[row]);
            case CurrencyLeaderboard_Lottery:
                LotteryLeaderboard_PrintRow(client, index + 1, row, currencyColor);
        }
    }
    if (start >= end)
        CPrintToChat(client, "%s No cached leaderboard entries on page %d.", g_CurrencyPrefix, page);
    else if (end < count && page < pages)
        CPrintToChat(client, "{default}Use {gold}!%s %d{default} for the next page (top 50).", command, page + 1);
    return Plugin_Handled;
}
