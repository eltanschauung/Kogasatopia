bool IsLotteryEnabled()
{
    return g_CvarLotteryDisabled == null || !g_CvarLotteryDisabled.BoolValue;
}

int GetLotteryMaxTicketValue()
{
    if (g_CvarLotteryMaxTicketValue == null)
    {
        return 1000;
    }

    return g_CvarLotteryMaxTicketValue.IntValue;
}

int GetLotteryEqualTicketValue()
{
    if (g_CurrentLotteryEqualTicketValue > 0)
    {
        return g_CurrentLotteryEqualTicketValue;
    }
    if (g_CvarLotteryEqualTicketValue == null)
    {
        return 100;
    }

    return g_CvarLotteryEqualTicketValue.IntValue;
}

int ClampLotteryTicketValue(int client, int amount)
{
    if (g_CurrentLotterySuper || g_CurrentLotteryEqual)
    {
        return amount;
    }

    int maxTicketValue = GetLotteryMaxTicketValue();
    if (maxTicketValue <= 0 || amount <= maxTicketValue)
    {
        return amount;
    }

    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    char currencyLong[BP_CURRENCY_LONG_MAX];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
    CPrintToChat(client, "%s[Lottery]{default} Ticket value capped at %s%d %s{default}.", colorTag, colorTag, maxTicketValue, currencyLong);
    return maxTicketValue;
}

void ClearLocalLotteryState()
{
    CancelPendingLotteryCall();

    if (g_LotteryDrawTimer != null)
    {
        KillTimer(g_LotteryDrawTimer);
        g_LotteryDrawTimer = null;
    }

    g_LotteryReady = false;
    g_LotteryCreating = false;
    g_LotteryDrawInProgress = false;
    g_CurrentLotteryId = 0;
    g_CurrentLotteryHash[0] = '\0';
    g_CurrentLotteryHashColor[0] = '\0';
    g_CurrentLotterySuper = false;
    g_CurrentLotteryEqual = false;
    g_CurrentLotteryEqualTicketValue = 0;
    g_LotteryCallDeadline = 0;
    g_LotteryEqualRefundInProgress = false;
    ClearAllClientLotteryCaches();
    ResetLotteryDrawState();
}

void EnsureActiveLottery()
{
    if (!IsLotteryEnabled())
    {
        ClearLocalLotteryState();
        return;
    }

    if (!g_DatabaseReady || g_Database == null || g_LotteryCreating)
    {
        return;
    }

    if (g_LotteryReady && g_CurrentLotteryId > 0)
    {
        return;
    }

    char query[320];
    Format(query, sizeof(query),
        "SELECT id, hash, hash_color, super_lottery, equal_lottery, equal_ticket_value, call_deadline FROM %s WHERE finished = 0 ORDER BY id DESC LIMIT 1",
        LOTTO_TABLE);
    g_Database.Query(SQL_OnActiveLotterySelected, query);
}

public void SQL_OnActiveLotterySelected(Database db, DBResultSet results, const char[] error, any data)
{
    if (!IsLotteryEnabled())
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[points_store] Failed to load active lottery: %s", error);
        return;
    }

    if (results != null && results.FetchRow())
    {
        int lotteryId = results.FetchInt(0);
        char hash[LOTTO_HASH_MAX];
        char hashColor[BP_CURRENCY_COLOR_MAX + 2];
        results.FetchString(1, hash, sizeof(hash));
        results.FetchString(2, hashColor, sizeof(hashColor));
        bool superLottery = results.FetchInt(3) != 0;
        bool equalLottery = results.FetchInt(4) != 0;
        SetActiveLottery(lotteryId, hash, hashColor, superLottery, equalLottery, results.FetchInt(5), results.FetchInt(6));
        return;
    }

    CreateActiveLottery();
}

void CreateActiveLottery()
{
    if (!IsLotteryEnabled() || !g_DatabaseReady || g_Database == null || g_LotteryCreating)
    {
        return;
    }

    g_LotteryCreating = true;

    int createdAt = GetTime();
    char hash[LOTTO_HASH_MAX];
    char colorName[BP_CURRENCY_COLOR_MAX];
    char hashColor[BP_CURRENCY_COLOR_MAX + 2];
    BuildLotteryHash(createdAt, hash, sizeof(hash));
    GetRandomLotteryColorName(colorName, sizeof(colorName));
    Format(hashColor, sizeof(hashColor), "{%s}", colorName);

    char escapedHash[(LOTTO_HASH_MAX * 2) + 1];
    char escapedHashColor[((BP_CURRENCY_COLOR_MAX + 2) * 2) + 1];
    if (!EscapeSql(hash, escapedHash, sizeof(escapedHash)) || !EscapeSql(hashColor, escapedHashColor, sizeof(escapedHashColor)))
    {
        g_LotteryCreating = false;
        LogError("[points_store] Failed to escape new lottery hash.");
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteString(hash);
    pack.WriteString(hashColor);

    char query[512];
    Format(query, sizeof(query),
        "INSERT INTO %s (hash, hash_color, created_at, finished) VALUES ('%s', '%s', %d, 0)",
        LOTTO_TABLE,
        escapedHash,
        escapedHashColor,
        createdAt);
    g_Database.Query(SQL_OnActiveLotteryInserted, query, pack);
}

public void SQL_OnActiveLotteryInserted(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    char hash[LOTTO_HASH_MAX];
    char hashColor[BP_CURRENCY_COLOR_MAX + 2];
    pack.ReadString(hash, sizeof(hash));
    pack.ReadString(hashColor, sizeof(hashColor));
    delete pack;

    g_LotteryCreating = false;

    if (!IsLotteryEnabled())
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[points_store] Failed to create active lottery: %s", error);
        return;
    }

    char escapedHash[(LOTTO_HASH_MAX * 2) + 1];
    if (!EscapeSql(hash, escapedHash, sizeof(escapedHash)))
    {
        LogError("[points_store] Failed to escape created lottery hash.");
        return;
    }

    DataPack selectPack = new DataPack();
    selectPack.WriteString(hash);
    selectPack.WriteString(hashColor);

    char query[256];
    Format(query, sizeof(query),
        "SELECT id FROM %s WHERE hash = '%s' LIMIT 1",
        LOTTO_TABLE,
        escapedHash);
    g_Database.Query(SQL_OnActiveLotteryInsertedSelected, query, selectPack);
}

public void SQL_OnActiveLotteryInsertedSelected(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    char hash[LOTTO_HASH_MAX];
    char hashColor[BP_CURRENCY_COLOR_MAX + 2];
    pack.ReadString(hash, sizeof(hash));
    pack.ReadString(hashColor, sizeof(hashColor));
    delete pack;

    if (!IsLotteryEnabled())
    {
        return;
    }

    if (error[0] != '\0' || results == null || !results.FetchRow())
    {
        LogError("[points_store] Failed to select newly created lottery: %s", error[0] ? error : "no row returned");
        return;
    }

    SetActiveLottery(results.FetchInt(0), hash, hashColor, false, false);
}

void SetActiveLottery(
    int lotteryId,
    const char[] hash,
    const char[] hashColor,
    bool superLottery,
    bool equalLottery,
    int equalTicketValue = 0,
    int callDeadline = 0)
{
    g_CurrentLotteryId = lotteryId;
    strcopy(g_CurrentLotteryHash, sizeof(g_CurrentLotteryHash), hash);
    strcopy(g_CurrentLotteryHashColor, sizeof(g_CurrentLotteryHashColor), hashColor);
    g_CurrentLotterySuper = superLottery;
    g_CurrentLotteryEqual = equalLottery && !superLottery;
    g_CurrentLotteryEqualTicketValue = g_CurrentLotteryEqual ? equalTicketValue : 0;
    g_LotteryCallDeadline = callDeadline;
    g_LotteryReady = true;

    // Special modes require a final-minute call; ordinary calls can also be
    // five-minute empty retries. Discard stale special modes before refunds.
    if ((g_CurrentLotteryEqual || g_CurrentLotterySuper || callDeadline > 0)
        && !IsLotteryCallScheduleCurrent(callDeadline, GetTime(), g_CurrentLotteryEqual || g_CurrentLotterySuper))
    {
        ResetLotteryCallState();
    }
    ResumePendingLotteryCall();

    if (g_CurrentLotteryEqual)
    {
        BeginEqualLotteryRefunds();
        return;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientAuthorizedHuman(i))
        {
            LoadClientLotteryTicket(i);
        }
    }
}

bool IsLotteryCallWindowCurrent(int deadline, int now)
{
    return deadline > 0 && deadline >= now && deadline - now <= LOTTO_CALL_WARNING_SECONDS;
}

bool IsLotteryCallScheduleCurrent(int deadline, int now, bool specialLottery)
{
    if (specialLottery)
    {
        return IsLotteryCallWindowCurrent(deadline, now);
    }

    // Resume overdue ordinary retries after a map change/reload, rather than
    // silently losing the draw while the server was unavailable.
    return deadline > 0 && deadline - now <= LOTTO_EMPTY_RETRY_SECONDS;
}

void PersistLotteryCallState()
{
    if (!g_DatabaseReady || g_Database == null || g_CurrentLotteryId <= 0) return;
    char query[384];
    FormatEx(query, sizeof(query),
        "UPDATE %s SET super_lottery=%d, equal_lottery=%d, equal_ticket_value = %d, call_deadline=%d WHERE id=%d AND finished=0",
        LOTTO_TABLE, g_CurrentLotterySuper ? 1 : 0, g_CurrentLotteryEqual ? 1 : 0,
        g_CurrentLotteryEqual ? GetLotteryEqualTicketValue() : 0, g_LotteryCallDeadline, g_CurrentLotteryId);
    g_Database.Query(SQL_OnIgnoredResult, query);
}

void ResetLotteryCallState(int nextDeadline = 0)
{
    CancelPendingLotteryCall();
    g_CurrentLotteryEqual = false;
    g_CurrentLotterySuper = false;
    g_CurrentLotteryEqualTicketValue = 0;
    g_LotteryCallDeadline = nextDeadline;
    PersistLotteryCallState();
}

void ResumePendingLotteryCall()
{
    if (!IsLotteryEnabled() || !g_LotteryReady || g_CurrentLotteryId <= 0 || g_LotteryCallTimer != null
        || g_LotteryDrawInProgress || g_LotteryCallDeadline <= 0) return;
    int remaining = g_LotteryCallDeadline - GetTime();
    if (!IsLotteryCallScheduleCurrent(g_LotteryCallDeadline, GetTime(), g_CurrentLotteryEqual || g_CurrentLotterySuper))
    {
        ResetLotteryCallState();
        return;
    }
    g_LotteryCallRequesterUserId = 0;
    g_LotteryCallLotteryId = g_CurrentLotteryId;
    g_LotteryCallTimer = CreateTimer(float(remaining > 0 ? remaining : 1), Timer_LotteryCall, _, TIMER_FLAG_NO_MAPCHANGE);
}

void SetCurrentLotterySuper(bool superLottery)
{
    g_CurrentLotterySuper = superLottery;
    if (superLottery)
    {
        g_CurrentLotteryEqual = false;
    }

    if (!superLottery || !g_DatabaseReady || g_Database == null || g_CurrentLotteryId <= 0)
    {
        return;
    }

    PersistLotteryCallState();
}

void SetCurrentLotteryEqual(bool equalLottery)
{
    // Choose only on the transition into Equal mode, not when a pending draw
    // is restored or called again. Store the amount with the lottery itself.
    if (equalLottery && !g_CurrentLotteryEqual)
    {
        int standardValue = g_CvarLotteryEqualTicketValue == null ? 100 : g_CvarLotteryEqualTicketValue.IntValue;
        g_CurrentLotteryEqualTicketValue = GetRandomInt(0, 1) == 0 ? standardValue : GetRandomInt(20, 140) * 5;
    }
    g_CurrentLotteryEqual = equalLottery;
    if (equalLottery)
    {
        g_CurrentLotterySuper = false;
    }

    if (!equalLottery || !g_DatabaseReady || g_Database == null || g_CurrentLotteryId <= 0)
    {
        return;
    }

    PersistLotteryCallState();
    BeginEqualLotteryRefunds();
}

void BeginEqualLotteryRefunds()
{
    if (!g_CurrentLotteryEqual || g_LotteryEqualRefundInProgress
        || !g_DatabaseReady || g_Database == null || g_CurrentLotteryId <= 0)
    {
        return;
    }

    g_LotteryEqualRefundInProgress = true;
    ContinueEqualLotteryRefunds(g_CurrentLotteryId);
}

void ContinueEqualLotteryRefunds(int lotteryId)
{
    if (!g_CurrentLotteryEqual || lotteryId != g_CurrentLotteryId
        || !g_DatabaseReady || g_Database == null)
    {
        g_LotteryEqualRefundInProgress = false;
        return;
    }

    if (g_LotteryPendingTicketWrites > 0)
    {
        CreateTimer(0.5, Timer_RetryEqualLotteryRefunds, lotteryId, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }

    int requiredValue = GetLotteryEqualTicketValue();
    DataPack pack = new DataPack();
    pack.WriteCell(lotteryId);
    pack.WriteCell(requiredValue);

    char query[384];
    FormatEx(query, sizeof(query),
        "SELECT steamid64, ticket_value FROM %s "
        ... "WHERE lottery_id = %d AND ticket_value < %d",
        LOTTO_TICKET_TABLE,
        lotteryId,
        requiredValue);
    g_Database.Query(SQL_OnEqualLotteryInvalidTicketsLoaded, query, pack);
}

public Action Timer_RetryEqualLotteryRefunds(Handle timer, any lotteryId)
{
    if (!g_CurrentLotteryEqual || lotteryId != g_CurrentLotteryId)
    {
        return Plugin_Stop;
    }

    g_LotteryEqualRefundInProgress = true;
    ContinueEqualLotteryRefunds(lotteryId);
    return Plugin_Stop;
}

public void SQL_OnEqualLotteryInvalidTicketsLoaded(
    Database db,
    DBResultSet rows,
    const char[] error,
    any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int lotteryId = pack.ReadCell();
    int requiredValue = pack.ReadCell();
    delete pack;

    if (!g_CurrentLotteryEqual || lotteryId != g_CurrentLotteryId)
    {
        g_LotteryEqualRefundInProgress = false;
        return;
    }
    if (error[0] != '\0')
    {
        g_LotteryEqualRefundInProgress = false;
        LogError("[points_store] Failed to load invalid Equal Lottery tickets: %s", error);
        CreateTimer(1.0, Timer_RetryEqualLotteryRefunds, lotteryId, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }

    ArrayList steamIds = new ArrayList(ByteCountToCells(32));
    ArrayList amounts = new ArrayList();
    char steamId[32];
    while (rows != null && rows.FetchRow())
    {
        rows.FetchString(0, steamId, sizeof(steamId));
        steamIds.PushString(steamId);
        amounts.Push(rows.FetchInt(1));
    }

    if (steamIds.Length == 0)
    {
        delete steamIds;
        delete amounts;
        g_LotteryEqualRefundInProgress = false;
        ReloadAllClientLotteryTickets();
        if (requiredValue != GetLotteryEqualTicketValue())
        {
            BeginEqualLotteryRefunds();
        }
        return;
    }

    Transaction txn = new Transaction();
    char query[1024];
    if (g_IsMySql)
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO %s (steamid64, balance) "
            ... "SELECT steamid64, ticket_value FROM %s WHERE lottery_id = %d AND ticket_value < %d "
            ... "ON DUPLICATE KEY UPDATE balance = GREATEST(0, balance + VALUES(balance))",
            BP_BALANCE_TABLE,
            LOTTO_TICKET_TABLE,
            lotteryId,
            requiredValue);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO %s (steamid64, balance) "
            ... "SELECT steamid64, ticket_value FROM %s WHERE lottery_id = %d AND ticket_value < %d "
            ... "ON CONFLICT(steamid64) DO UPDATE SET balance = MAX(0, balance + excluded.balance), updated_at = CURRENT_TIMESTAMP",
            BP_BALANCE_TABLE,
            LOTTO_TICKET_TABLE,
            lotteryId,
            requiredValue);
    }
    txn.AddQuery(query);

    FormatEx(query, sizeof(query),
        "DELETE FROM %s WHERE lottery_id = %d AND ticket_value < %d",
        LOTTO_TICKET_TABLE,
        lotteryId,
        requiredValue);
    txn.AddQuery(query);

    DataPack txnPack = new DataPack();
    txnPack.WriteCell(lotteryId);
    txnPack.WriteCell(requiredValue);
    txnPack.WriteCell(view_as<int>(steamIds));
    txnPack.WriteCell(view_as<int>(amounts));
    g_Database.Execute(
        txn,
        SQLTxn_OnEqualLotteryTicketsRefunded,
        SQLTxn_OnEqualLotteryTicketsRefundFailure,
        txnPack);
}

public void SQLTxn_OnEqualLotteryTicketsRefunded(
    Database db,
    any data,
    int numQueries,
    DBResultSet[] results,
    any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int lotteryId = pack.ReadCell();
    int requiredValue = pack.ReadCell();
    ArrayList steamIds = view_as<ArrayList>(pack.ReadCell());
    ArrayList amounts = view_as<ArrayList>(pack.ReadCell());
    delete pack;

    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));
    char steamId[32];
    for (int i = 0; i < steamIds.Length; i++)
    {
        steamIds.GetString(i, steamId, sizeof(steamId));
        int amount = amounts.Get(i);
        int client = Kogasa_FindClientBySteamId64(steamId);
        int balanceAfter = -1;
        if (IsClientAuthorizedHuman(client))
        {
            if (g_ClientBonusPointsLoaded[client])
            {
                g_ClientBonusPoints[client] += amount;
                balanceAfter = g_ClientBonusPoints[client];
            }
            else
            {
                LoadClientBonusPoints(client);
            }

            ClearClientLotteryTicketCache(client);
            g_ClientLotteryTicketLoaded[client] = true;

            CPrintToChat(client,
                "%s[Lottery]{default} An {gold}Equal Value Lottery{default} is coming; your ticket has been refunded! Bet again with a value of {gold}%d{default} to get a ticket.",
                colorTag,
                requiredValue);
        }
        LogLotteryCreditEvent("lottery_equal_refund", steamId, amount, lotteryId, client, balanceAfter);
    }

    delete steamIds;
    delete amounts;
    g_LotteryEqualRefundInProgress = false;
    ReloadAllClientLotteryTickets();
    if (g_CurrentLotteryEqual && lotteryId == g_CurrentLotteryId
        && requiredValue != GetLotteryEqualTicketValue())
    {
        BeginEqualLotteryRefunds();
    }
}

public void SQLTxn_OnEqualLotteryTicketsRefundFailure(
    Database db,
    any data,
    int numQueries,
    const char[] error,
    int failIndex,
    any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int lotteryId = pack.ReadCell();
    pack.ReadCell();
    ArrayList steamIds = view_as<ArrayList>(pack.ReadCell());
    ArrayList amounts = view_as<ArrayList>(pack.ReadCell());
    delete pack;
    delete steamIds;
    delete amounts;

    g_LotteryEqualRefundInProgress = false;
    LogError("[points_store] Equal Lottery refund transaction failed at query %d: %s", failIndex, error);
    if (g_CurrentLotteryEqual && lotteryId == g_CurrentLotteryId)
    {
        CreateTimer(1.0, Timer_RetryEqualLotteryRefunds, lotteryId, TIMER_FLAG_NO_MAPCHANGE);
    }
}

