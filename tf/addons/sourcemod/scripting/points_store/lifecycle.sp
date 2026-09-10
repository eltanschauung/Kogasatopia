public void OnPluginStart()
{
    LoadTranslations("common.phrases");

    g_ItemKeys = new ArrayList(ByteCountToCells(BP_TRANS_ITEM_KEY_MAX));
    g_ItemNames = new ArrayList(ByteCountToCells(BP_TRANS_ITEM_NAME_MAX));
    g_ItemDescriptions = new ArrayList(ByteCountToCells(BP_TRANS_ITEM_DESCRIPTION_MAX));
    g_ItemColors = new ArrayList(ByteCountToCells(BP_CURRENCY_COLOR_MAX));
    g_ItemPrices = new ArrayList();
    g_ItemDurations = new ArrayList();
    g_ItemUses = new ArrayList();
    g_PerMapAwardCounts = new StringMap();
    g_PerMapIgnoreInitialMapStart = g_PerMapLateLoad;
    g_PerMapStateAction = g_PerMapLateLoad ? BP_PER_MAP_ACTION_RESTORE : BP_PER_MAP_ACTION_RESET;
    RefreshPerMapAwardScope();
    Rewards_OnPluginStart();

    for (int i = 1; i <= MaxClients; i++)
    {
        g_ClientPurchases[i] = new StringMap();
        g_ClientPurchaseExpiresAt[i] = new StringMap();
        g_ClientPurchaseUsesRemaining[i] = new StringMap();
        g_ClientPurchasesLoaded[i] = false;
        g_ClientBonusPoints[i] = 0;
        g_ClientBonusPointsLoaded[i] = false;
        g_ClientBonusPointsPending[i] = false;
        g_ClientShopDetailItem[i][0] = '\0';
    }

    g_CvarDatabase = CreateConVar("sm_bonuspoints_transactions_database", BP_TRANS_DB_CONFIG_DEFAULT, "Databases.cfg entry for bonuspoints_transactions.");
    g_CvarEventLogging = CreateConVar("sm_points_store_event_logging", "1", "Write structured currency economy events through plugin statistics.", _, true, 0.0, true, 1.0);
    g_CvarLogRandomMisses = CreateConVar("sm_points_store_log_random_misses", "0", "Log failed random-chance currency rolls when event logging is enabled.", _, true, 0.0, true, 1.0);
    g_CvarCurrencyShort = CreateConVar("sm_points_store_currency_short", "Gems", "Short currency label used in compact messages, e.g. BP or Gem.");
    g_CvarCurrencyLong = CreateConVar("sm_points_store_currency_long", "Gems", "Long currency label used in menus and prose, e.g. Bonus Points or Gems.");
    g_CvarCurrencyColor = CreateConVar("sm_points_store_currency_color", "cyan", "Multicolors tag name used for the currency prefix, without braces.");
    g_CvarSendCooldown = CreateConVar("sm_points_store_send_cooldown", "15.0", "Seconds a client must wait between successful !send currency transfers.", _, true, 0.0);
    g_CvarEnableWelfare = CreateConVar("sm_points_store_welfare", "1", "Enable welfare?", _, true, 0.0, true, 1.0);
    g_CvarWelfareMinPlayers = CreateConVar("sm_points_store_welfare_min_players", "3", "Minimum number of human clients in game required to collect welfare. 0 disables the requirement.", _, true, 0.0, true, 64.0);
    g_CvarBountyMinPlayers = CreateConVar("sm_points_store_bounty_min_players", "6", "Minimum GetClientCount(false) required to place bounties and advance bounty playtime.", _, true, 0.0, true, 64.0);
    g_CvarBountyMinAmount = CreateConVar("sm_points_store_bounty_min_amount", "50", "Minimum Gem value of an individual bounty.", _, true, 1.0);
    g_CvarBountyMaxAmount = CreateConVar("sm_points_store_bounty_max_amount", "1000", "Maximum Gem value of an individual bounty, including kill growth.", _, true, 1.0);
    g_CvarBountyTimeLimitMinutes = CreateConVar("sm_points_store_bounty_time_limit_minutes", "20.0", "Qualifying playtime required to survive a bounty, in minutes.", _, true, 1.0, true, 1440.0);
    g_CvarAutoBountyMinDeaths = CreateConVar("sm_points_store_auto_bounty_min_deaths", "2", "Minimum live scoreboard deaths required for automatic bounty selection.", _, true, 0.0);
    g_CvarCurrencyShort.AddChangeHook(OnCurrencyConVarChanged);
    g_CvarCurrencyLong.AddChangeHook(OnCurrencyConVarChanged);
    g_CvarCurrencyColor.AddChangeHook(OnCurrencyConVarChanged);
    RefreshCurrencyLabels();

    RegConsoleCmd("sm_shop", Command_Shop, "Open the points store.");
    RegConsoleCmd("sm_store", Command_Shop, "Open the points store.");
    RegConsoleCmd("sm_buy", Command_Shop, "Open the points store.");
    RegConsoleCmd("sm_bonus", Command_ShowBonusPoints, "Show your currency balance.");
    RegConsoleCmd("sm_bonuspoints", Command_ShowBonusPoints, "Show your currency balance.");
    RegConsoleCmd("sm_bp", Command_ShowBonusPoints, "Show your currency balance.");
    RegConsoleCmd("sm_currencyranks", Command_ShowCurrencyLeaderboard, "Show the currency leaderboard.");
    RegConsoleCmd("sm_bonuspointsranks", Command_ShowCurrencyLeaderboard, "Show the currency leaderboard.");
    RegConsoleCmd("sm_bpranks", Command_ShowCurrencyLeaderboard, "Show the currency leaderboard.");
    RegConsoleCmd("sm_gl", Command_ShowCurrencyLeaderboard, "Show the currency leaderboard.");
    RegConsoleCmd("sm_send", Command_SendBonusPoints, "Send currency to another player.");
    RegConsoleCmd("sm_sendbp", Command_SendBonusPoints, "Send currency to another player.");
    RegConsoleCmd("sm_bpsend", Command_SendBonusPoints, "Send currency to another player.");
    RegConsoleCmd("sm_gem", Command_ShowBonusPoints, "Show your currency balance.");
    RegConsoleCmd("sm_gems", Command_ShowBonusPoints, "Show your currency balance.");
    RegConsoleCmd("sm_wallet", Command_ShowBonusPoints, "Show your currency balance.");
    AddCommandListener(CommandListener_ShowBonusPointsAlias, "gem");
    AddCommandListener(CommandListener_ShowBonusPointsAlias, "gems");
    AddCommandListener(CommandListener_ShowBonusPointsAlias, "wallet");
    RegConsoleCmd("sm_gemranks", Command_ShowCurrencyLeaderboard, "Show the currency leaderboard.");
    RegConsoleCmd("sm_gemsranks", Command_ShowCurrencyLeaderboard, "Show the currency leaderboard.");
    RegConsoleCmd("sm_gemsleaderboard", Command_ShowCurrencyLeaderboard, "Show the currency leaderboard.");
    RegConsoleCmd("sm_sendgem", Command_SendBonusPoints, "Send currency to another player.");
    RegConsoleCmd("sm_gemsend", Command_SendBonusPoints, "Send currency to another player.");
    RegConsoleCmd("sm_welfare", Command_Welfare, "Collect once-per-map welfare currency.");
    RegConsoleCmd("sm_collectwelfare", Command_Welfare, "Collect once-per-map welfare currency.");
    RegConsoleCmd("sm_handout", Command_Welfare, "Collect once-per-map welfare currency.");
    RegConsoleCmd("sm_gibs", Command_Welfare, "Collect once-per-map welfare currency.");
    RegConsoleCmd("sm_ebt", Command_Welfare, "Collect once-per-map welfare currency.");
    RegConsoleCmd("sm_welfarecheck", Command_Welfare, "Collect once-per-map welfare currency.");
    AddCommandListener(CommandListener_WelfareAlias, "gibs");
    AddCommandListener(CommandListener_WelfareAlias, "welfare");
    AddCommandListener(CommandListener_WelfareAlias, "ebt");
    AddCommandListener(CommandListener_WelfareChatAlias, "say");
    AddCommandListener(CommandListener_WelfareChatAlias, "say_team");
    AddCommandListener(CommandListener_PointsStoreChatAlias, "say");
    AddCommandListener(CommandListener_PointsStoreChatAlias, "say_team");

    Lotteries_OnPluginStart();
    Bounties_OnPluginStart();
    Dailies_OnPluginStart();
    MemomanEvent_OnPluginStart();
    GameplayRewards_OnPluginStart();

    LoadStoreItems();
    ConnectDatabase();
}

public void OnPluginEnd()
{
    Lotteries_OnPluginEnd();
    Bounties_OnPluginEnd();
    MemomanEvent_OnPluginEnd();
    delete g_IdempotentAwardForward;

    delete g_ItemKeys;
    delete g_ItemNames;
    delete g_ItemDescriptions;
    delete g_ItemColors;
    delete g_ItemPrices;
    delete g_ItemDurations;
    delete g_ItemUses;
    delete g_PerMapAwardCounts;
    Rewards_OnPluginEnd();

    for (int i = 1; i <= MaxClients; i++)
    {
        delete g_ClientPurchases[i];
        g_ClientPurchases[i] = null;
        delete g_ClientPurchaseExpiresAt[i];
        g_ClientPurchaseExpiresAt[i] = null;
        delete g_ClientPurchaseUsesRemaining[i];
        g_ClientPurchaseUsesRemaining[i] = null;
    }

    Db_CancelTimer(g_hDatabaseReconnectTimer);
    Db_Close(g_Database, g_DatabaseReady);
}

public void OnMapStart()
{
    Lotteries_OnMapStart();
    Bounties_OnMapStart();
    RefreshPerMapAwardScope();
    if (g_PerMapIgnoreInitialMapStart)
    {
        g_PerMapIgnoreInitialMapStart = false;
        return;
    }

    ResetPerMapAwardState();
}

public void OnMapEnd()
{
    Lotteries_OnMapEnd();
}

public void OnClientAuthorized(int client, const char[] auth)
{
    Bounties_OnClientAuthorized(client);
    g_NextSendAllowedAt[client] = 0.0;
    ClearClientStoreCache(client);
    LoadClientPurchases(client);
    LoadClientBonusPoints(client);
    Lotteries_OnClientAuthorized(client);
}

public void OnClientPutInServer(int client)
{
    GameplayRewards_OnClientPutInServer(client);
}

public void OnClientDisconnect(int client)
{
    GameplayRewards_OnClientDisconnect(client);
    Bounties_OnClientDisconnect(client);
    g_NextSendAllowedAt[client] = 0.0;
    ClearClientStoreCache(client);
    Lotteries_OnClientDisconnect(client);
}

