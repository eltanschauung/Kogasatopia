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
    if (!Client_IsHumanInGame(client))
        return Plugin_Handled;
    if (!g_CurrencyLeaderboardReady)
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
    for (int row = 0; row < g_CurrencyLeaderboardRows; row++)
        if (Oblivion_SteamMessageVisible(client, g_CurrencyLeaderboardSteamIds[row])) visible[count++] = row;
    int pages = (count + BP_LEADERBOARD_PAGE_SIZE - 1) / BP_LEADERBOARD_PAGE_SIZE;
    if (pages < 1) pages = 1;
    if (page < 1 || page > pages)
    {
        CPrintToChat(client, "%s Use !gl <1-%d>; only the top 50 are listed.", g_CurrencyPrefix, pages);
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
        CPrintToChat(client, "#%d {%s}%s{default} %s%d", index + 1,
            g_CurrencyLeaderboardColors[row], g_CurrencyLeaderboardNames[row], currencyColor, g_CurrencyLeaderboardBalances[row]);
    }
    if (start >= end)
        CPrintToChat(client, "%s No cached leaderboard entries on page %d.", g_CurrencyPrefix, page);
    else if (end < count && page < pages)
        CPrintToChat(client, "{default}Use {gold}!gl %d{default} for the next page (top 50).", page + 1);
    return Plugin_Handled;
}
