void Lotteries_OnPluginStart()
{
    g_LotteryPendingSteamIds = new StringMap();
    g_LotteryWords = new ArrayList(ByteCountToCells(LOTTO_WORD_MAX));
    g_LotteryRarities = new ArrayList();
    g_LotteryDrawTokens = new ArrayList(ByteCountToCells(LOTTO_TOKEN_MAX));

    for (int client = 1; client <= MaxClients; client++)
    {
        ClearClientLotteryTicketCache(client);
        g_NextLotteryTicketMutationAt[client] = 0.0;
    }

    g_CvarLotteryDisabled = CreateConVar("sm_points_store_lottery_disabled", "0", "Disable lottery ticket commands and lottery draws on this server.", _, true, 0.0, true, 1.0);
    g_CvarLotteryMaxTicketValue = CreateConVar("sm_points_store_lottery_max_ticket_value", "1000", "Maximum lottery ticket value. Bets above this are capped. 0 disables the cap.", _, true, 0.0);
    g_CvarLotteryEqualTicketValue = CreateConVar("sm_points_store_lottery_equal_ticket_value", "100", "Required ticket value during an Equal Lottery.", _, true, 1.0);
    g_CvarLotteryDisabled.AddChangeHook(OnLotteryDisabledConVarChanged);
    g_CvarLotteryEqualTicketValue.AddChangeHook(OnLotteryEqualTicketValueChanged);

    RegConsoleCmd("sm_lottery", Command_Lottery, "Open the currency lottery.");
    RegConsoleCmd("sm_gamble", Command_Lottery, "Open the currency lottery.");
    RegConsoleCmd("sm_bet", Command_Lottery, "Open the currency lottery.");
    RegConsoleCmd("sm_lotto", Command_Lottery, "Open the currency lottery.");
    RegConsoleCmd("sm_allin", Command_LotteryAll, "Bet all available currency on the lottery.");
    AddCommandListener(CommandListener_LotteryAllAlias, "allin");
    AddCommandListener(CommandListener_LotteryAllChatAlias, "say");
    AddCommandListener(CommandListener_LotteryAllChatAlias, "say_team");
    RegConsoleCmd("sm_lottos", Command_LotteryHistory, "Show recent lottery history.");
    RegConsoleCmd("sm_lottohistory", Command_LotteryHistory, "Show recent lottery history.");
    RegConsoleCmd("sm_lottowhen", Command_LotteryTime, "Show time until the next lottery draw.");
    RegConsoleCmd("sm_when", Command_LotteryTime, "Show time until the next lottery draw.");
    RegConsoleCmd("sm_lottotime", Command_LotteryTime, "Show time until the next lottery draw.");
    RegConsoleCmd("sm_time", Command_LotteryTime, "Show time until the next lottery draw.");
    RegConsoleCmd("sm_pool", Command_LotteryPrizePool, "Show the lottery prize pool.");
    RegConsoleCmd("sm_prizepool", Command_LotteryPrizePool, "Show the lottery prize pool.");
    AddCommandListener(CommandListener_LotteryPoolAlias, "pool");
    RegConsoleCmd("sm_ticket", Command_ViewLotteryTicket, "View your current lottery ticket.");
    RegConsoleCmd("sm_viewticket", Command_ViewLotteryTicket, "View your current lottery ticket.");
    RegConsoleCmd("sm_lottorefund", Command_LotteryRefund, "Refund your current lottery ticket.");
    RegConsoleCmd("sm_lotteryrefund", Command_LotteryRefund, "Refund your current lottery ticket.");
    RegConsoleCmd("sm_refund", Command_LotteryRefund, "Refund your current lottery ticket.");
    AddCommandListener(CommandListener_LotteryRefundAlias, "refund");
    RegAdminCmd("sm_dolottery", Command_DoLottery, ADMFLAG_GENERIC, "Draw the current currency lottery.");
    RegAdminCmd("sm_dolotto", Command_DoLottery, ADMFLAG_GENERIC, "Draw the current currency lottery.");

    LoadLotteryWords();
}

void Lotteries_OnPluginEnd()
{
    delete g_LotteryPendingSteamIds;
    delete g_LotteryWords;
    delete g_LotteryRarities;
    delete g_LotteryDrawTokens;

    if (g_LotteryDrawTimer != null)
    {
        KillTimer(g_LotteryDrawTimer);
        g_LotteryDrawTimer = null;
    }
    CancelPendingLotteryCall();
}

void Lotteries_OnMapEnd()
{
    int interruptedLotteryId = 0;
    if (g_LotteryCallTimer != null)
    {
        interruptedLotteryId = g_LotteryCallLotteryId;
    }

    CancelPendingLotteryCall();

    if (interruptedLotteryId > 0)
    {
        g_LotteryMapChangeLotteryId = interruptedLotteryId;
    }
}

void Lotteries_OnMapStart()
{
    if (g_LotteryMapChangeLotteryId <= 0 || g_LotteryCallTimer != null
        || g_LotteryDrawInProgress)
    {
        return;
    }

    g_LotteryCallRequesterUserId = 0;
    g_LotteryCallLotteryId = g_LotteryMapChangeLotteryId;
    g_LotteryMapChangeLotteryId = 0;
    g_LotteryCallTimer = CreateTimer(
        LOTTO_MAP_CHANGE_DELAY,
        Timer_LotteryCall,
        _,
        TIMER_FLAG_NO_MAPCHANGE);

    if (g_LotteryCallTimer == null)
    {
        LogError("[points_store] Could not reschedule lottery %d after a map change.", g_LotteryCallLotteryId);
        g_LotteryCallLotteryId = 0;
    }
}

void Lotteries_OnClientAuthorized(int client)
{
    g_NextLotteryTicketMutationAt[client] = 0.0;
    LoadClientLotteryTicket(client);
}

void Lotteries_OnClientDisconnect(int client)
{
    g_LotteryWaitingCustom[client] = false;
    g_NextLotteryTicketMutationAt[client] = 0.0;
    ClearClientLotteryTicketCache(client);
}

void Lotteries_OnDatabaseDisconnected()
{
    g_LotteryReady = false;
    g_LotteryCreating = false;
    g_CurrentLotteryId = 0;
    g_CurrentLotteryHash[0] = '\0';
    g_CurrentLotteryHashColor[0] = '\0';
    g_CurrentLotterySuper = false;
    g_CurrentLotteryEqual = false;
    g_LotteryEqualRefundInProgress = false;
    CancelPendingLotteryCall();
}

void Lotteries_OnDatabaseReady()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientAuthorizedHuman(client))
        {
            LoadClientLotteryTicket(client);
        }
    }
    EnsureActiveLottery();
}

void EnsureLotterySchema()
{
    if (g_Database == null)
    {
        return;
    }

    char query[2048];
    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "id INT NOT NULL AUTO_INCREMENT, "
            ... "hash VARCHAR(32) NOT NULL, "
            ... "hash_color VARCHAR(32) NOT NULL, "
            ... "created_at INT NOT NULL, "
            ... "super_lottery TINYINT NOT NULL DEFAULT 0, "
            ... "equal_lottery TINYINT NOT NULL DEFAULT 0, "
            ... "finished TINYINT NOT NULL DEFAULT 0, "
            ... "finished_at INT NOT NULL DEFAULT 0, "
            ... "winner_steamid64 VARCHAR(32) NOT NULL DEFAULT '', "
            ... "winner_name VARCHAR(255) NOT NULL DEFAULT '', "
            ... "prize_pool INT NOT NULL DEFAULT 0, "
            ... "PRIMARY KEY (id), "
            ... "UNIQUE KEY unique_points_store_lottery_hash (hash), "
            ... "KEY idx_points_store_lottery_finished (finished))",
            LOTTO_TABLE);
    }
    else
    {
        Format(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "id INTEGER PRIMARY KEY AUTOINCREMENT, "
            ... "hash VARCHAR(32) NOT NULL UNIQUE, "
            ... "hash_color VARCHAR(32) NOT NULL, "
            ... "created_at INTEGER NOT NULL, "
            ... "super_lottery INTEGER NOT NULL DEFAULT 0, "
            ... "equal_lottery INTEGER NOT NULL DEFAULT 0, "
            ... "finished INTEGER NOT NULL DEFAULT 0, "
            ... "finished_at INTEGER NOT NULL DEFAULT 0, "
            ... "winner_steamid64 VARCHAR(32) NOT NULL DEFAULT '', "
            ... "winner_name VARCHAR(255) NOT NULL DEFAULT '', "
            ... "prize_pool INTEGER NOT NULL DEFAULT 0)",
            LOTTO_TABLE);
    }

    g_Database.Query(SQL_OnLotterySchemaReady, query);
}

public void SQL_OnLotterySchemaReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[points_store] Lottery schema creation failed: %s", error);
        return;
    }

    char query[256];
    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "ALTER TABLE %s ADD COLUMN IF NOT EXISTS super_lottery TINYINT NOT NULL DEFAULT 0 AFTER created_at",
            LOTTO_TABLE);
    }
    else
    {
        Format(query, sizeof(query),
            "ALTER TABLE %s ADD COLUMN super_lottery INTEGER NOT NULL DEFAULT 0",
            LOTTO_TABLE);
    }

    g_Database.Query(SQL_OnLotterySuperColumnReady, query);
}

public void SQL_OnLotterySuperColumnReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0'
        && StrContains(error, "Duplicate column", false) == -1
        && StrContains(error, "duplicate column", false) == -1)
    {
        LogError("[points_store] Lottery super_lottery migration failed: %s", error);
    }

    char query[256];
    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "ALTER TABLE %s ADD COLUMN IF NOT EXISTS equal_lottery TINYINT NOT NULL DEFAULT 0 AFTER super_lottery",
            LOTTO_TABLE);
    }
    else
    {
        Format(query, sizeof(query),
            "ALTER TABLE %s ADD COLUMN equal_lottery INTEGER NOT NULL DEFAULT 0",
            LOTTO_TABLE);
    }

    g_Database.Query(SQL_OnLotteryEqualColumnReady, query);
}

public void SQL_OnLotteryEqualColumnReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0'
        && StrContains(error, "Duplicate column", false) == -1
        && StrContains(error, "duplicate column", false) == -1
        && StrContains(error, "already exists", false) == -1)
    {
        LogError("[points_store] Lottery equal_lottery migration failed: %s", error);
    }

    EnsureLotteryTicketsSchema();
}

void EnsureLotteryTicketsSchema()
{
    if (g_Database == null)
    {
        return;
    }

    char query[4096];
    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "id INT NOT NULL AUTO_INCREMENT, "
            ... "lottery_id INT NOT NULL, "
            ... "steamid64 VARCHAR(32) NOT NULL, "
            ... "display_name VARCHAR(255) NOT NULL DEFAULT '', "
            ... "ticket TEXT NOT NULL, "
            ... "ticket_value INT NOT NULL, "
            ... "created_at INT NOT NULL, "
            ... "PRIMARY KEY (id), "
            ... "UNIQUE KEY unique_points_store_lottery_ticket (lottery_id, steamid64), "
            ... "KEY idx_points_store_lottery_ticket_lottery (lottery_id), "
            ... "KEY idx_points_store_lottery_ticket_steamid64 (steamid64))",
            LOTTO_TICKET_TABLE);
    }
    else
    {
        Format(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "id INTEGER PRIMARY KEY AUTOINCREMENT, "
            ... "lottery_id INTEGER NOT NULL, "
            ... "steamid64 VARCHAR(32) NOT NULL, "
            ... "display_name VARCHAR(255) NOT NULL DEFAULT '', "
            ... "ticket TEXT NOT NULL, "
            ... "ticket_value INTEGER NOT NULL, "
            ... "created_at INTEGER NOT NULL, "
            ... "UNIQUE (lottery_id, steamid64))",
            LOTTO_TICKET_TABLE);
    }

    g_Database.Query(SQL_OnLotteryTicketsSchemaReady, query);
}

public void SQL_OnLotteryTicketsSchemaReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[points_store] Lottery ticket schema creation failed: %s", error);
        return;
    }

    if (!g_IsMySql)
    {
        g_Database.Query(SQL_OnIgnoredResult, "CREATE INDEX IF NOT EXISTS idx_points_store_lottery_finished ON points_store_lotteries (finished)");
        g_Database.Query(SQL_OnIgnoredResult, "CREATE INDEX IF NOT EXISTS idx_points_store_lottery_ticket_lottery ON points_store_lottery_tickets (lottery_id)");
        g_Database.Query(SQL_OnIgnoredResult, "CREATE INDEX IF NOT EXISTS idx_points_store_lottery_ticket_steamid64 ON points_store_lottery_tickets (steamid64)");
    }

    EnsureEconomySchema();
}

