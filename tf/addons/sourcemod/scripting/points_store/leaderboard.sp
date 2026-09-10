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

public Action Command_ShowCurrencyLeaderboard(int client, int args)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Handled;
    }

    char prefix[96];
    GetCurrencyPrefix(prefix, sizeof(prefix));

    if (!g_DatabaseReady || g_Database == null)
    {
        CPrintToChat(client, "%s Database is not ready.", prefix);
        return Plugin_Handled;
    }

    int page = 1;
    if (args >= 1)
    {
        char arg[16];
        GetCmdArg(1, arg, sizeof(arg));
        int parsed = StringToInt(arg);
        if (parsed > 0)
        {
            page = parsed;
        }
    }

    int offset = (page - 1) * BP_LEADERBOARD_PAGE_SIZE;

    char currencyLong[BP_CURRENCY_LONG_MAX];
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
    CPrintToChat(client, "{green}[Store]{default} %s leaderboard will print momentarily...", currencyLong);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(page);

    char joinCondition[128];
    if (g_IsMySql)
    {
        strcopy(joinCondition, sizeof(joinCondition), "BINARY pc.steamid = BINARY b.steamid64");
    }
    else
    {
        strcopy(joinCondition, sizeof(joinCondition), "pc.steamid = b.steamid64");
    }

    char query[1400];
    Format(query, sizeof(query),
        "SELECT b.steamid64, b.balance, COALESCE(NULLIF(pr.newname,''), NULLIF(fs.last_name,''), b.steamid64), COALESCE(NULLIF(pc.name_color,''), 'gold') "
        ... "FROM %s b "
        ... "LEFT JOIN whaletracker_points_cache pc ON %s "
        ... "LEFT JOIN prename_rules pr ON pr.pattern = b.steamid64 "
        ... "LEFT JOIN filters_steam_names fs ON fs.steamid64 = b.steamid64 COLLATE utf8mb4_uca1400_ai_ci "
        ... "WHERE b.balance > 0 "
        ... "ORDER BY b.balance DESC, b.steamid64 ASC "
        ... "LIMIT %d OFFSET %d",
        BP_BALANCE_TABLE,
        joinCondition,
        BP_LEADERBOARD_PAGE_SIZE,
        offset);
    g_Database.Query(PointsStore_ShowCurrencyLeaderboardCallback, query, pack);
    return Plugin_Handled;
}

public void PointsStore_ShowCurrencyLeaderboardCallback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    int page = pack.ReadCell();
    delete pack;

    if (!Client_IsHumanInGame(client))
    {
        return;
    }

    char prefix[96];
    GetCurrencyPrefix(prefix, sizeof(prefix));

    if (error[0] != '\0')
    {
        CPrintToChat(client, "%s Failed to load currency leaderboard.", prefix);
        LogError("[points_store] Failed to load currency leaderboard: %s", error);
        return;
    }

    char currencyColor[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(currencyColor, sizeof(currencyColor));

    int rows = 0;
    while (results != null && results.FetchRow())
    {
        int rank = ((page - 1) * BP_LEADERBOARD_PAGE_SIZE) + rows + 1;
        int balance = results.FetchInt(1);

        char displayName[128];
        char colorTag[32];
        results.FetchString(2, displayName, sizeof(displayName));
        results.FetchString(3, colorTag, sizeof(colorTag));
        TrimString(displayName);
        NormalizeLeaderboardColorTag(colorTag, sizeof(colorTag));

        if (displayName[0] == '\0')
        {
            results.FetchString(0, displayName, sizeof(displayName));
            TrimString(displayName);
        }
        if (displayName[0] == '\0')
        {
            strcopy(displayName, sizeof(displayName), "Unknown");
        }

        rows++;
        CPrintToChat(client, "#%d {%s}%s{default} %s%d", rank, colorTag, displayName, currencyColor, balance);
    }

    if (rows == 0)
    {
        CPrintToChat(client, "%s No currency leaderboard entries on page %d.", prefix, page);
        return;
    }

    CPrintToChat(client, "Use !%scurrencyranks %d{default} to view the next 10 ranks!", currencyColor, page + 1);
}

