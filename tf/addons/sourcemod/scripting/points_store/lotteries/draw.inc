public Action Command_DoLottery(int client, int args)
{
    if (!IsLotteryEnabled())
    {
        ReplyToCommand(client, "[Lotto] The lottery is disabled on this server.");
        return Plugin_Handled;
    }

    if (!g_DatabaseReady || g_Database == null || !g_LotteryReady || g_CurrentLotteryId <= 0)
    {
        ReplyToCommand(client, "[Lotto] The lottery database is not ready.");
        EnsureActiveLottery();
        return Plugin_Handled;
    }

    if (g_LotteryCallTimer != null)
    {
        ReplyToCommand(client, "[Lotto] A lottery draw is already scheduled.");
        return Plugin_Handled;
    }

    if (g_LotteryDrawInProgress)
    {
        ReplyToCommand(client, "[Lotto] A lottery draw is already in progress.");
        return Plugin_Handled;
    }

    g_LotteryCallRequesterUserId = client > 0 ? GetClientUserId(client) : 0;
    g_LotteryCallLotteryId = g_CurrentLotteryId;

    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));
    int callDelay = GetRandomInt(20, 80);

    g_LotteryCallTimer = CreateTimer(float(callDelay), Timer_LotteryCall, _, TIMER_FLAG_NO_MAPCHANGE);
    if (g_LotteryCallTimer == null)
    {
        g_LotteryCallRequesterUserId = 0;
        g_LotteryCallLotteryId = 0;
        ReplyToCommand(client, "[Lotto] Could not schedule the lottery draw.");
        return Plugin_Handled;
    }

    int specialLotteryRoll = GetRandomInt(1, 100);
    if (g_CurrentLotterySuper || (!g_CurrentLotteryEqual && specialLotteryRoll <= 35))
    {
        SetCurrentLotterySuper(true);
        CPrintToChatAll("%s[Lotto]{default} A {gold}SUPER LOTTERY{default} is being called soon, {gold}!bet{default} no longer has a size limit!", colorTag);
    }
    else if (g_CurrentLotteryEqual || specialLotteryRoll <= 70)
    {
        SetCurrentLotteryEqual(true);
        CPrintToChatAll(
            "%s[Lotto]{default} An {gold}Equal Lottery{default} is being called soon, {gold}only tickets with a value of %d are accepted!",
            colorTag,
            GetLotteryEqualTicketValue());
    }
    else
    {
        CPrintToChatAll("%s[Lotto]{default} A lottery is being called soon, {gold}!bet{default} now!", colorTag);
    }
    return Plugin_Handled;
}

public Action Timer_LotteryCall(Handle timer, any data)
{
    if (g_LotteryCallTimer != timer)
    {
        return Plugin_Stop;
    }

    int requesterUserId = g_LotteryCallRequesterUserId;
    int lotteryId = g_LotteryCallLotteryId;
    g_LotteryCallTimer = null;
    g_LotteryCallRequesterUserId = 0;
    g_LotteryCallLotteryId = 0;

    if (!IsLotteryEnabled())
    {
        ReplyToLotteryRequester(requesterUserId, "[Lotto] The lottery is disabled on this server.");
        return Plugin_Stop;
    }

    StartLotteryDraw(requesterUserId, lotteryId);
    return Plugin_Stop;
}

public Action Timer_RetryStartLotteryDraw(Handle timer, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int requesterUserId = pack.ReadCell();
    int lotteryId = pack.ReadCell();

    if (!IsLotteryEnabled())
    {
        ReplyToLotteryRequester(requesterUserId, "[Lotto] The lottery is disabled on this server.");
        return Plugin_Stop;
    }

    StartLotteryDraw(requesterUserId, lotteryId, true);
    return Plugin_Stop;
}

void StartLotteryDraw(int requesterUserId, int lotteryId, bool retry = false)
{
    if (!IsLotteryEnabled())
    {
        g_LotteryDrawInProgress = false;
        ReplyToLotteryRequester(requesterUserId, "[Lotto] The lottery is disabled on this server.");
        return;
    }

    if (!g_DatabaseReady || g_Database == null || !g_LotteryReady || g_CurrentLotteryId <= 0)
    {
        ReplyToLotteryRequester(requesterUserId, "[Lotto] The lottery database is not ready.");
        EnsureActiveLottery();
        return;
    }

    if (lotteryId != g_CurrentLotteryId)
    {
        ReplyToLotteryRequester(requesterUserId, "[Lotto] The scheduled lottery is no longer active.");
        return;
    }

    if (g_LotteryDrawInProgress && !retry)
    {
        ReplyToLotteryRequester(requesterUserId, "[Lotto] A lottery draw is already in progress.");
        return;
    }

    if (!g_LotteryDrawInProgress)
    {
        g_LotteryDrawInProgress = true;
    }

    if (g_LotteryPendingTicketWrites > 0 || g_LotteryEqualRefundInProgress)
    {
        DataPack retryPack = new DataPack();
        retryPack.WriteCell(requesterUserId);
        retryPack.WriteCell(lotteryId);
        CreateTimer(1.0, Timer_RetryStartLotteryDraw, retryPack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(requesterUserId);
    pack.WriteCell(lotteryId);

    char query[256];
    Format(query, sizeof(query),
        "SELECT COUNT(*), COALESCE(SUM(ticket_value), 0) FROM %s WHERE lottery_id = %d",
        LOTTO_TICKET_TABLE,
        lotteryId);
    g_Database.Query(SQL_OnLotteryDrawStatsLoaded, query, pack);
}

public void SQL_OnLotteryDrawStatsLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int requesterUserId = pack.ReadCell();
    int lotteryId = pack.ReadCell();
    delete pack;

    if (!IsLotteryEnabled())
    {
        g_LotteryDrawInProgress = false;
        ReplyToLotteryRequester(requesterUserId, "[Lotto] The lottery is disabled on this server.");
        return;
    }

    if (lotteryId != g_CurrentLotteryId)
    {
        g_LotteryDrawInProgress = false;
        return;
    }

    if (error[0] != '\0')
    {
        g_LotteryDrawInProgress = false;
        ReplyToLotteryRequester(requesterUserId, "[Lotto] Could not load lottery tickets.");
        LogError("[points_store] Failed to load lottery draw stats: %s", error);
        return;
    }

    int ticketCount = 0;
    int prizePool = 0;
    if (results != null && results.FetchRow())
    {
        ticketCount = results.FetchInt(0);
        prizePool = results.FetchInt(1);
    }

    if (ticketCount <= 0 || prizePool <= 0)
    {
        g_LotteryDrawInProgress = false;
        ReplyToLotteryRequester(requesterUserId, "[Lotto] There are no tickets in the current lottery.");
        return;
    }

    DataPack winnerPack = new DataPack();
    winnerPack.WriteCell(requesterUserId);
    winnerPack.WriteCell(lotteryId);
    winnerPack.WriteCell(prizePool);

    char query[512];
    Format(query, sizeof(query),
        "SELECT steamid64, display_name, ticket, ticket_value FROM %s WHERE lottery_id = %d ORDER BY id",
        LOTTO_TICKET_TABLE,
        lotteryId);
    g_Database.Query(SQL_OnLotteryWinnerSelected, query, winnerPack);
}

public void SQL_OnLotteryWinnerSelected(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int requesterUserId = pack.ReadCell();
    int lotteryId = pack.ReadCell();
    int prizePool = pack.ReadCell();
    delete pack;

    if (!IsLotteryEnabled())
    {
        g_LotteryDrawInProgress = false;
        ReplyToLotteryRequester(requesterUserId, "[Lotto] The lottery is disabled on this server.");
        return;
    }

    if (lotteryId != g_CurrentLotteryId)
    {
        g_LotteryDrawInProgress = false;
        return;
    }

    if (error[0] != '\0' || results == null)
    {
        g_LotteryDrawInProgress = false;
        ReplyToLotteryRequester(requesterUserId, "[Lotto] Could not select a winner.");
        LogError("[points_store] Failed to select lottery winner: %s", error[0] ? error : "no row returned");
        return;
    }

    ArrayList steamIds = new ArrayList(ByteCountToCells(32));
    ArrayList storedNames = new ArrayList(ByteCountToCells(LOTTO_NAME_MAX));
    ArrayList tickets = new ArrayList(ByteCountToCells(LOTTO_TICKET_MAX));
    ArrayList ticketValues = new ArrayList();
    ArrayList ticketChances = new ArrayList();
    ArrayList selectedWinners = new ArrayList();
    int totalChances = 0;

    while (results.FetchRow())
    {
        int ticketValue = results.FetchInt(3);
        int chanceCount = GetLotteryChanceCount(ticketValue);
        if (chanceCount <= 0)
        {
            continue;
        }

        char steamId[32];
        char storedName[LOTTO_NAME_MAX];
        char ticket[LOTTO_TICKET_MAX];
        results.FetchString(0, steamId, sizeof(steamId));
        results.FetchString(1, storedName, sizeof(storedName));
        results.FetchString(2, ticket, sizeof(ticket));

        steamIds.PushString(steamId);
        storedNames.PushString(storedName);
        tickets.PushString(ticket);
        ticketValues.Push(ticketValue);
        ticketChances.Push(chanceCount);
        selectedWinners.Push(0);
        totalChances += chanceCount;
    }

    int validTicketCount = steamIds.Length;
    if (validTicketCount <= 0 || totalChances <= 0)
    {
        g_LotteryDrawInProgress = false;
        ReplyToLotteryRequester(requesterUserId, "[Lotto] Could not select a winner.");
        LogError("[points_store] Failed to select lottery winner: no valid ticket values for prize pool %d.", prizePool);
        delete steamIds;
        delete storedNames;
        delete tickets;
        delete ticketValues;
        delete ticketChances;
        delete selectedWinners;
        return;
    }

    int mainWinnerIndex = PickLotteryWinnerIndex(ticketChances, selectedWinners);
    if (mainWinnerIndex < 0)
    {
        g_LotteryDrawInProgress = false;
        ReplyToLotteryRequester(requesterUserId, "[Lotto] Could not select a winner.");
        LogError("[points_store] Failed to select lottery winner: no weighted index for %d tickets and %d chances.", validTicketCount, totalChances);
        delete steamIds;
        delete storedNames;
        delete tickets;
        delete ticketValues;
        delete ticketChances;
        delete selectedWinners;
        return;
    }

    selectedWinners.Set(mainWinnerIndex, 1);

    g_LotteryDrawExtraWinnerCount = validTicketCount / LOTTO_EXTRA_WINNER_PARTICIPANTS;
    if (g_LotteryDrawExtraWinnerCount > validTicketCount - 1)
    {
        g_LotteryDrawExtraWinnerCount = validTicketCount - 1;
    }
    if (g_LotteryDrawExtraWinnerCount > sizeof(g_LotteryDrawExtraWinnerPrizes))
    {
        g_LotteryDrawExtraWinnerCount = sizeof(g_LotteryDrawExtraWinnerPrizes);
    }

    int extraPrize = (prizePool * LOTTO_EXTRA_WINNER_PERCENT) / 100;
    if (extraPrize <= 0)
    {
        g_LotteryDrawExtraWinnerCount = 0;
    }

    int welfarePoolPrize = 0;

    char mainSteamId[32];
    char mainStoredName[LOTTO_NAME_MAX];
    char mainTicket[LOTTO_TICKET_MAX];
    steamIds.GetString(mainWinnerIndex, mainSteamId, sizeof(mainSteamId));
    storedNames.GetString(mainWinnerIndex, mainStoredName, sizeof(mainStoredName));
    tickets.GetString(mainWinnerIndex, mainTicket, sizeof(mainTicket));

    strcopy(g_LotteryDrawWinnerSteamId, sizeof(g_LotteryDrawWinnerSteamId), mainSteamId);
    g_LotteryDrawWinnerTicketValue = ticketValues.Get(mainWinnerIndex);
    ResolveLotteryWinnerName(mainSteamId, mainStoredName, g_LotteryDrawWinnerName, sizeof(g_LotteryDrawWinnerName));

    for (int i = 0; i < g_LotteryDrawExtraWinnerCount; i++)
    {
        int extraWinnerIndex = PickLotteryWinnerIndex(ticketChances, selectedWinners);
        if (extraWinnerIndex < 0)
        {
            g_LotteryDrawExtraWinnerCount = i;
            break;
        }

        selectedWinners.Set(extraWinnerIndex, 1);
        g_LotteryDrawExtraWinnerPrizes[i] = extraPrize;
        g_LotteryDrawExtraWinnerTicketValues[i] = ticketValues.Get(extraWinnerIndex);
        char extraSteamId[32];
        char extraStoredName[LOTTO_NAME_MAX];
        steamIds.GetString(extraWinnerIndex, extraSteamId, sizeof(extraSteamId));
        storedNames.GetString(extraWinnerIndex, extraStoredName, sizeof(extraStoredName));

        strcopy(g_LotteryDrawExtraWinnerSteamIds[i], sizeof(g_LotteryDrawExtraWinnerSteamIds[]), extraSteamId);
        ResolveLotteryWinnerName(extraSteamId, extraStoredName, g_LotteryDrawExtraWinnerNames[i], sizeof(g_LotteryDrawExtraWinnerNames[]));
    }

    g_LotteryDrawWelfarePoolPrize = welfarePoolPrize * g_LotteryDrawExtraWinnerCount;
    g_LotteryDrawWinnerPrize = prizePool - ((extraPrize * g_LotteryDrawExtraWinnerCount) + g_LotteryDrawWelfarePoolPrize);
    if (g_LotteryDrawWinnerPrize <= 0)
    {
        g_LotteryDrawWinnerPrize = prizePool;
        g_LotteryDrawExtraWinnerCount = 0;
        g_LotteryDrawWelfarePoolPrize = 0;
    }

    g_LotteryDrawLotteryId = lotteryId;
    g_LotteryDrawPrizePool = prizePool;
    g_LotteryDrawIndex = 0;
    strcopy(g_LotteryDrawHash, sizeof(g_LotteryDrawHash), g_CurrentLotteryHash);
    strcopy(g_LotteryDrawHashColor, sizeof(g_LotteryDrawHashColor), g_CurrentLotteryHashColor);
    BuildLotteryDrawTokens(mainTicket);

    delete steamIds;
    delete storedNames;
    delete tickets;
    delete ticketValues;
    delete ticketChances;
    delete selectedWinners;

    if (g_LotteryDrawTokens.Length <= 0)
    {
        g_LotteryDrawInProgress = false;
        ReplyToLotteryRequester(requesterUserId, "[Lotto] The selected ticket had no printable words.");
        return;
    }

    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));
    char shortHash[LOTTO_SHORT_HASH_MAX];
    GetLotteryShortHash(g_LotteryDrawHash, shortHash, sizeof(shortHash));
    CPrintToChatAll("%s[Lotto]{default} Drawing lottery %s%s{default}...", colorTag, g_LotteryDrawHashColor, shortHash);

    // Reveals survive map changes so the already-selected winner is still paid.
    g_LotteryDrawTimer = CreateTimer(LOTTO_REVEAL_INTERVAL, Timer_LotteryReveal, _, TIMER_REPEAT);
}

int PickLotteryWinnerIndex(ArrayList ticketChances, ArrayList selectedWinners)
{
    int totalChances = 0;
    int ticketCount = ticketChances.Length;
    for (int i = 0; i < ticketCount; i++)
    {
        if (selectedWinners.Get(i) == 0)
        {
            totalChances += ticketChances.Get(i);
        }
    }

    if (totalChances <= 0)
    {
        return -1;
    }

    int roll = GetRandomInt(1, totalChances);
    int running = 0;
    for (int i = 0; i < ticketCount; i++)
    {
        if (selectedWinners.Get(i) != 0)
        {
            continue;
        }

        running += ticketChances.Get(i);
        if (roll <= running)
        {
            return i;
        }
    }

    return -1;
}

public Action Timer_LotteryReveal(Handle timer, any data)
{
    if (g_LotteryDrawTimer != timer)
    {
        return Plugin_Stop;
    }

    if (!IsLotteryEnabled())
    {
        g_LotteryDrawTimer = null;
        g_LotteryDrawInProgress = false;
        ResetLotteryDrawState();
        return Plugin_Stop;
    }

    if (g_LotteryDrawIndex < g_LotteryDrawTokens.Length)
    {
        char token[LOTTO_TOKEN_MAX];
        g_LotteryDrawTokens.GetString(g_LotteryDrawIndex, token, sizeof(token));
        CPrintToChatAll("%s", token);
        g_LotteryDrawIndex++;
        return Plugin_Continue;
    }

    g_LotteryDrawTimer = null;
    FinalizeLotteryDraw();
    return Plugin_Stop;
}

void FinalizeLotteryDraw()
{
    if (!IsLotteryEnabled())
    {
        g_LotteryDrawInProgress = false;
        ResetLotteryDrawState();
        return;
    }

    char winnerName[LOTTO_NAME_MAX];
    ResolveLotteryWinnerName(g_LotteryDrawWinnerSteamId, g_LotteryDrawWinnerName, winnerName, sizeof(winnerName));

    char escapedSteamId[65];
    char escapedWinnerName[(LOTTO_NAME_MAX * 2) + 1];
    if (!EscapeSql(g_LotteryDrawWinnerSteamId, escapedSteamId, sizeof(escapedSteamId))
        || !EscapeSql(winnerName, escapedWinnerName, sizeof(escapedWinnerName)))
    {
        LogError("[points_store] Failed to escape lottery winner data.");
        g_LotteryDrawInProgress = false;
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(g_LotteryDrawLotteryId);
    pack.WriteCell(g_LotteryDrawWinnerPrize);
    pack.WriteString(g_LotteryDrawWinnerSteamId);
    pack.WriteString(winnerName);
    pack.WriteString(g_LotteryDrawHash);
    pack.WriteString(g_LotteryDrawHashColor);

    char query[768];
    Format(query, sizeof(query),
        "UPDATE %s SET finished = 1, finished_at = %d, winner_steamid64 = '%s', winner_name = '%s', prize_pool = %d WHERE id = %d AND finished = 0",
        LOTTO_TABLE,
        GetTime(),
        escapedSteamId,
        escapedWinnerName,
        g_LotteryDrawPrizePool,
        g_LotteryDrawLotteryId);
    g_Database.Query(SQL_OnLotteryFinished, query, pack);
}

void FormatLotteryPayoutDelta(char[] buffer, int maxlen, int payout, int investment)
{
    int delta = payout - investment;
    float percent = 0.0;
    if (investment > 0)
    {
        percent = (float(delta) / float(investment)) * 100.0;
    }

    if (delta >= 0)
    {
        Format(buffer, maxlen, "{green}(+%.2f%%)", percent);
    }
    else
    {
        Format(buffer, maxlen, "{red}(-%.2f%%)", -percent);
    }
}

public void SQL_OnLotteryFinished(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int lotteryId = pack.ReadCell();
    int winnerPrize = pack.ReadCell();
    char winnerSteamId[32];
    char winnerName[LOTTO_NAME_MAX];
    char hash[LOTTO_HASH_MAX];
    char hashColor[BP_CURRENCY_COLOR_MAX + 2];
    pack.ReadString(winnerSteamId, sizeof(winnerSteamId));
    pack.ReadString(winnerName, sizeof(winnerName));
    pack.ReadString(hash, sizeof(hash));
    pack.ReadString(hashColor, sizeof(hashColor));
    delete pack;

    if (error[0] != '\0')
    {
        LogError("[points_store] Failed to mark lottery %d finished: %s", lotteryId, error);
        char colorTag[BP_CURRENCY_COLOR_MAX + 2];
        GetCurrencyColorTag(colorTag, sizeof(colorTag));
        CPrintToChatAll("%s[Lotto]{default} The lottery could not be finalized. Prize was not paid; check logs.", colorTag);
        g_LotteryDrawInProgress = false;
        return;
    }

    if (results == null || results.AffectedRows <= 0)
    {
        LogError("[points_store] Lottery %d was already finalized; skipping duplicate payout.", lotteryId);
        g_LotteryDrawInProgress = false;
        g_LotteryReady = false;
        g_CurrentLotteryId = 0;
        g_CurrentLotteryHash[0] = '\0';
        g_CurrentLotteryHashColor[0] = '\0';
        g_CurrentLotterySuper = false;
        g_CurrentLotteryEqual = false;
        g_LotteryEqualRefundInProgress = false;
        ClearAllClientLotteryCaches();
        ResetLotteryDrawState();
        EnsureActiveLottery();
        return;
    }

    CreditSteamId64BonusPoints(winnerSteamId, winnerPrize, "lottery_main_payout", lotteryId);
    for (int i = 0; i < g_LotteryDrawExtraWinnerCount; i++)
    {
        CreditSteamId64BonusPoints(g_LotteryDrawExtraWinnerSteamIds[i], g_LotteryDrawExtraWinnerPrizes[i], "lottery_extra_payout", lotteryId);
    }
    RecordLotteryWelfarePoolCredit(g_LotteryDrawWelfarePoolPrize, lotteryId);

    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    char currencyLong[BP_CURRENCY_LONG_MAX];
    char shortHash[LOTTO_SHORT_HASH_MAX];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
    GetLotteryShortHash(hash, shortHash, sizeof(shortHash));
    char winnerDelta[32];
    FormatLotteryPayoutDelta(winnerDelta, sizeof(winnerDelta), winnerPrize, g_LotteryDrawWinnerTicketValue);
    CPrintToChatAll("%s[Lotto]{default} %s won lottery %s%s{default} for %s%d %s{default} %s{default}!", colorTag, winnerName, hashColor, shortHash, colorTag, winnerPrize, currencyLong, winnerDelta);

    for (int i = 0; i < g_LotteryDrawExtraWinnerCount; i++)
    {
        char extraDelta[32];
        FormatLotteryPayoutDelta(extraDelta, sizeof(extraDelta), g_LotteryDrawExtraWinnerPrizes[i], g_LotteryDrawExtraWinnerTicketValues[i]);
        CPrintToChatAll("{default}%s won %s%d %s{default} %s{default}!", g_LotteryDrawExtraWinnerNames[i], colorTag, g_LotteryDrawExtraWinnerPrizes[i], currencyLong, extraDelta);
    }

    g_LotteryDrawInProgress = false;
    g_LotteryReady = false;
    g_CurrentLotteryId = 0;
    g_CurrentLotteryHash[0] = '\0';
    g_CurrentLotteryHashColor[0] = '\0';
    g_CurrentLotterySuper = false;
    g_CurrentLotteryEqual = false;
    g_LotteryEqualRefundInProgress = false;
    ClearAllClientLotteryCaches();
    ResetLotteryDrawState();
    EnsureActiveLottery();
}

