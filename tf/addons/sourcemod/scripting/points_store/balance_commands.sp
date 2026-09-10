public Action Command_Shop(int client, int args)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Handled;
    }

    if (!g_DatabaseReady || g_Database == null)
    {
        PrintToChat(client, "[Shop] The shop database is not ready.");
        return Plugin_Handled;
    }

    if (!g_ClientPurchasesLoaded[client])
    {
        PrintToChat(client, "[Shop] Your purchases are loading. Try again in a moment.");
        LoadClientPurchases(client);
        return Plugin_Handled;
    }

    ShowShopMenu(client);
    return Plugin_Handled;
}

public Action Command_ShowBonusPoints(int client, int args)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Handled;
    }

    int target = client;
    if (args >= 1)
    {
        char targetArg[64];
        GetCmdArgString(targetArg, sizeof(targetArg));
        TrimString(targetArg);
        if (targetArg[0])
        {
            int targets[MAXPLAYERS];
            char targetName[MAX_TARGET_LENGTH];
            bool targetNameIsMl;
            int count = ProcessTargetString(
                targetArg,
                client,
                targets,
                sizeof(targets),
                COMMAND_FILTER_NO_BOTS,
                targetName,
                sizeof(targetName),
                targetNameIsMl);
            if (count == 1 && Client_IsHumanInGame(targets[0]))
            {
                target = targets[0];
            }
            else
            {
                RequestOfflineBalanceSearch(client, targetArg);
                return Plugin_Handled;
            }
        }
    }

    if (!AreBonusPointsReady(target))
    {
        char prefix[96];
        char currencyLong[BP_CURRENCY_LONG_MAX];
        GetCurrencyPrefix(prefix, sizeof(prefix));
        GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
        LoadClientBonusPoints(target);
        CPrintToChat(client, "%s %N's %s are loading. Try again in a moment.", prefix, target, currencyLong);
        return Plugin_Handled;
    }

    char displayName[256];
    BuildPurchaseDisplayName(target, displayName, sizeof(displayName));
    PrintBonusPointsSummary(client, displayName, GetCachedBonusPoints(target));
    return Plugin_Handled;
}

void PrintBonusPointsSummary(int client, const char[] displayName, int balance)
{
    char currencyLong[BP_CURRENCY_LONG_MAX];
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
    char msg1[384];
    FormatEx(msg1, sizeof(msg1),
        "%s{default}'s %s: {lightgreen}%i{default}\n"
        ... "{lightgreen}+3{default}: Medic drops, penta-kills, ending 20+ killstreaks\n"
        ... "{lightgreen}+2{default}: Triple-kills, quadra-kills, ending 10+ killstreaks",
        displayName,
        currencyLong,
        balance);

    char msg2[256];
    FormatEx(msg2, sizeof(msg2),
        "{lightgreen}+1:{default} Airshot kills, market garden kills, ubers, killstreaks, dominations, revenge, meatshot kills, Sandman-Cleaver combos, medic assist lives");

    CPrintToChat(client, "%s", msg1);
    CPrintToChat(client, "%s", msg2);
}

void RequestOfflineBalanceSearch(int client, const char[] search)
{
    if (!g_DatabaseReady || g_Database == null)
    {
        CPrintToChat(client, "%s Player search is temporarily unavailable.", g_CurrencyPrefix);
        return;
    }

    char escapedSearch[(BP_BALANCE_SEARCH_NAME_MAX * 2) + 1];
    if (!EscapeSql(search, escapedSearch, sizeof(escapedSearch)))
    {
        CPrintToChat(client, "%s Could not search for that player.", g_CurrencyPrefix);
        return;
    }

    ConVar minKdConVar = FindConVar("sm_whaletracker_rank_min_kd_sum");
    ConVar minPlaytimeConVar = FindConVar("sm_whaletracker_rank_min_playtime_seconds");
    int minKd = minKdConVar != null ? minKdConVar.IntValue : 200;
    int minPlaytime = minPlaytimeConVar != null ? minPlaytimeConVar.IntValue : 10800;
    int generation = ++g_BalanceSearchGeneration[client];

    char query[2304];
    FormatEx(query, sizeof(query),
        "SELECT w.steamid, "
        ... "COALESCE(NULLIF(pr.newname COLLATE utf8mb4_uca1400_ai_ci, ''), NULLIF(fs.last_name, ''), NULLIF(w.cached_personaname, ''), w.steamid), "
        ... "COALESCE(b.balance, 0), GREATEST(COALESCE(w.playtime, 0), 0) "
        ... "FROM whaletracker w "
        ... "LEFT JOIN filters_steam_names fs ON fs.steamid64 = w.steamid "
        ... "LEFT JOIN prename_rules pr ON pr.pattern COLLATE utf8mb4_uca1400_ai_ci = w.steamid "
        ... "LEFT JOIN %s b ON BINARY b.steamid64 = BINARY w.steamid "
        ... "WHERE (GREATEST(COALESCE(w.kills, 0), 0) + GREATEST(COALESCE(w.deaths, 0), 0)) >= %d "
        ... "AND GREATEST(COALESCE(w.playtime, 0), 0) >= %d "
        ... "AND (COALESCE(pr.newname, '') LIKE '%%%s%%' "
        ... "OR COALESCE(fs.last_name, '') LIKE '%%%s%%' "
        ... "OR COALESCE(w.cached_personaname, '') LIKE '%%%s%%') "
        ... "ORDER BY GREATEST(COALESCE(w.playtime, 0), 0) DESC LIMIT %d",
        BP_BALANCE_TABLE,
        minKd,
        minPlaytime,
        escapedSearch,
        escapedSearch,
        escapedSearch,
        BP_BALANCE_SEARCH_MAX);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(generation);
    pack.WriteString(search);
    g_Database.Query(SQL_OnOfflineBalanceSearch, query, pack);
}

public void SQL_OnOfflineBalanceSearch(Database db, DBResultSet rows, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    int generation = pack.ReadCell();
    char search[BP_BALANCE_SEARCH_NAME_MAX];
    pack.ReadString(search, sizeof(search));
    delete pack;

    if (!Client_IsHumanInGame(client) || generation != g_BalanceSearchGeneration[client])
    {
        return;
    }
    if (error[0])
    {
        LogError("[points_store] Offline balance search failed: %s", error);
        CPrintToChat(client, "%s Player search failed.", g_CurrencyPrefix);
        return;
    }

    Menu menu = new Menu(MenuHandler_OfflineBalanceSearch);
    menu.SetTitle("Select player balance:");
    int count = 0;
    while (rows != null && rows.FetchRow())
    {
        char steamId[32];
        char name[BP_BALANCE_SEARCH_NAME_MAX];
        char display[192];
        rows.FetchString(0, steamId, sizeof(steamId));
        rows.FetchString(1, name, sizeof(name));
        int balance = rows.FetchInt(2);
        FormatEx(display, sizeof(display), "%s (%d %s)", name, balance, g_CurrencyLongLabel);
        menu.AddItem(steamId, display);
        count++;
    }

    if (count == 0)
    {
        delete menu;
        CPrintToChat(client, "%s No ranked player matched {gold}%s{default}.", g_CurrencyPrefix, search);
        return;
    }

    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_OfflineBalanceSearch(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }
    if (action != MenuAction_Select || !Client_IsHumanInGame(client))
    {
        return 0;
    }

    char steamId[32];
    char escapedSteamId[65];
    menu.GetItem(item, steamId, sizeof(steamId));
    if (!EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId)))
    {
        return 0;
    }

    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT COALESCE(b.balance, 0), "
        ... "COALESCE(NULLIF(pr.newname COLLATE utf8mb4_uca1400_ai_ci, ''), NULLIF(fs.last_name, ''), NULLIF(w.cached_personaname, ''), w.steamid) "
        ... "FROM whaletracker w "
        ... "LEFT JOIN filters_steam_names fs ON fs.steamid64 = w.steamid "
        ... "LEFT JOIN prename_rules pr ON pr.pattern COLLATE utf8mb4_uca1400_ai_ci = w.steamid "
        ... "LEFT JOIN %s b ON BINARY b.steamid64 = BINARY w.steamid "
        ... "WHERE BINARY w.steamid = BINARY '%s' LIMIT 1",
        BP_BALANCE_TABLE,
        escapedSteamId);
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(steamId);
    g_Database.Query(SQL_OnOfflineBalanceSelected, query, pack);
    return 0;
}

public void SQL_OnOfflineBalanceSelected(Database db, DBResultSet rows, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    char steamId[32];
    pack.ReadString(steamId, sizeof(steamId));
    delete pack;

    if (!Client_IsHumanInGame(client))
    {
        return;
    }
    if (error[0] || rows == null || !rows.FetchRow())
    {
        if (error[0])
        {
            LogError("[points_store] Offline balance selection failed: %s", error);
        }
        CPrintToChat(client, "%s That player's balance could not be loaded.", g_CurrencyPrefix);
        return;
    }

    int balance = rows.FetchInt(0);
    char name[BP_BALANCE_SEARCH_NAME_MAX];
    char displayName[256];
    char colorTag[32];
    rows.FetchString(1, name, sizeof(name));
    colorTag[0] = '\0';
    if (GetFeatureStatus(FeatureType_Native, "Filters_GetSteamIdColorTag") == FeatureStatus_Available)
    {
        Filters_GetSteamIdColorTag(steamId, colorTag, sizeof(colorTag));
    }
    if (!colorTag[0])
    {
        strcopy(colorTag, sizeof(colorTag), "{default}");
    }
    FormatEx(displayName, sizeof(displayName), "%s%s", colorTag, name);
    PrintBonusPointsSummary(client, displayName, balance);
}

