public Action Command_Lottery(int client, int args)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Handled;
    }

    if (!IsLotteryReadyForClient(client))
    {
        return Plugin_Handled;
    }

    if (args >= 1)
    {
        char amountArg[32];
        GetCmdArg(1, amountArg, sizeof(amountArg));
        StripQuotes(amountArg);
        TrimString(amountArg);

        if (StrEqual(amountArg, "all", false))
        {
            AttemptLotteryAllTicketPurchase(client);
            return Plugin_Handled;
        }

        int amount = 0;
        if (ParsePositiveInteger(amountArg, amount))
        {
            AttemptLotteryTicketPurchase(client, amount);
            return Plugin_Handled;
        }
    }

    ShowLotteryMenu(client);
    return Plugin_Handled;
}

public Action Command_LotteryAll(int client, int args)
{
    if (!Client_IsHumanInGame(client) || !IsLotteryReadyForClient(client))
    {
        return Plugin_Handled;
    }

    AttemptLotteryAllTicketPurchase(client);
    return Plugin_Handled;
}

public Action CommandListener_LotteryAllAlias(int client, const char[] command, int argc)
{
    return Command_LotteryAll(client, 0);
}

public Action CommandListener_LotteryAllChatAlias(int client, const char[] command, int argc)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Continue;
    }

    char text[32];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);
    TrimString(text);
    if (!StrEqual(text, "allin", false))
    {
        return Plugin_Continue;
    }

    return Command_LotteryAll(client, 0);
}

public Action Command_LotteryRefund(int client, int args)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Handled;
    }

    if (!IsLotteryReadyForClient(client))
    {
        return Plugin_Handled;
    }

    RefundLotteryTicket(client);
    return Plugin_Handled;
}

public Action CommandListener_LotteryRefundAlias(int client, const char[] command, int argc)
{
    return Command_LotteryRefund(client, 0);
}

public Action Command_LotteryTime(int client, int args)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Handled;
    }

    PrintLotteryTime(client, true);
    return Plugin_Handled;
}

void PrintLotteryTime(int client, bool includePrefix)
{
    int secondsUntilLottery = SecondsUntilNextLotteryDraw(GetTime());
    int minutesUntilLottery = (secondsUntilLottery + 59) / 60;
    char minuteLabel[16];
    strcopy(minuteLabel, sizeof(minuteLabel), minutesUntilLottery == 1 ? "minute" : "minutes");

    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));

    if (includePrefix)
    {
        CPrintToChat(client, "%s[Lotto]{default} Time until the lottery: {gold}%d %s", colorTag, minutesUntilLottery, minuteLabel);
    }
    else
    {
        CPrintToChat(client, "{default}Time until the lottery: {gold}%d %s", minutesUntilLottery, minuteLabel);
    }

}

int SecondsUntilNextLotteryDraw(int timestamp)
{
    static int drawSeconds[] = {60, 960, 1860, 2760};
    int elapsedThisHour = timestamp % 3600;

    for (int i = 0; i < sizeof(drawSeconds); i++)
    {
        if (elapsedThisHour <= drawSeconds[i])
        {
            return drawSeconds[i] - elapsedThisHour;
        }
    }

    return 3660 - elapsedThisHour;
}

public Action Command_LotteryPrizePool(int client, int args)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Handled;
    }

    if (!IsLotteryReadyForClient(client, false))
    {
        return Plugin_Handled;
    }

    PrintLotteryPrizePool(client);
    return Plugin_Handled;
}

public Action CommandListener_LotteryPoolAlias(int client, const char[] command, int argc)
{
    return Command_LotteryPrizePool(client, 0);
}

public Action Command_LotteryHistory(int client, int args)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Handled;
    }

    if (!g_DatabaseReady || g_Database == null)
    {
        char colorTag[BP_CURRENCY_COLOR_MAX + 2];
        GetCurrencyColorTag(colorTag, sizeof(colorTag));
        CPrintToChat(client, "%s[Lotto]{default} The lottery database is not ready.", colorTag);
        ConnectDatabase();
        return Plugin_Handled;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));

    char query[512];
    Format(query, sizeof(query),
        "SELECT l.id, l.hash, l.finished_at, l.winner_name, l.prize_pool, COALESCE(t.ticket_value, 0) FROM %s l LEFT JOIN %s t ON t.lottery_id = l.id AND t.steamid64 = l.winner_steamid64 WHERE l.finished = 1 ORDER BY l.finished_at DESC, l.id DESC LIMIT 25",
        LOTTO_TABLE,
        LOTTO_TICKET_TABLE);
    g_Database.Query(SQL_OnLotteryHistoryLoaded, query, pack);
    return Plugin_Handled;
}

public void SQL_OnLotteryHistoryLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    if (!Client_IsHumanInGame(client))
    {
        return;
    }

    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));
    if (error[0] != '\0')
    {
        CPrintToChat(client, "%s[Lotto]{default} Could not load lottery history.", colorTag);
        LogError("[points_store] Failed to load lottery history: %s", error);
        return;
    }

    char currencyLong[BP_CURRENCY_LONG_MAX];
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));

    Menu menu = new Menu(MenuHandler_LotteryHistory);
    menu.SetTitle("Recent Lottos");

    int count = 0;
    if (results != null)
    {
        while (results.FetchRow())
        {
            int lotteryId = results.FetchInt(0);
            char hash[LOTTO_HASH_MAX];
            char shortHash[LOTTO_SHORT_HASH_MAX];
            char winnerName[LOTTO_NAME_MAX];
            char cleanWinnerName[LOTTO_NAME_MAX];
            char finishedAt[32];
            char info[16];
            char display[192];

            results.FetchString(1, hash, sizeof(hash));
            int finishedTimestamp = results.FetchInt(2);
            results.FetchString(3, winnerName, sizeof(winnerName));
            int prizePool = results.FetchInt(4);
            int investment = results.FetchInt(5);
            char profit[24];
            FormatLotteryHistoryProfit(profit, sizeof(profit), prizePool, investment);

            GetLotteryShortHash(hash, shortHash, sizeof(shortHash));
            StripMenuColorTags(winnerName, cleanWinnerName, sizeof(cleanWinnerName));
            if (cleanWinnerName[0] == '\0')
            {
                strcopy(cleanWinnerName, sizeof(cleanWinnerName), "Unknown");
            }
            FormatTime(finishedAt, sizeof(finishedAt), "%m/%d %H:%M", finishedTimestamp);
            IntToString(lotteryId, info, sizeof(info));
            Format(display, sizeof(display), "#%d %s %s - %s - %d %s%s", lotteryId, shortHash, finishedAt, cleanWinnerName, prizePool, currencyLong, profit);
            menu.AddItem(info, display, ITEMDRAW_DISABLED);
            count++;
        }
    }

    if (count == 0)
    {
        menu.AddItem("none", "No finished lottos found.", ITEMDRAW_DISABLED);
    }

    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

void FormatLotteryHistoryProfit(char[] buffer, int maxlen, int payout, int investment)
{
    buffer[0] = '\0';
    if (investment <= 0)
    {
        return;
    }

    int percent = RoundToNearest((float(payout - investment) / float(investment)) * 100.0);
    Format(buffer, maxlen, percent >= 0 ? " +%d%%" : " %d%%", percent);
}

public int MenuHandler_LotteryHistory(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    return 0;
}

void StripMenuColorTags(const char[] input, char[] output, int maxlen)
{
    if (maxlen <= 0)
    {
        return;
    }

    int out = 0;
    bool inTag = false;
    int len = strlen(input);
    for (int i = 0; i < len && out < maxlen - 1; i++)
    {
        int colorCodeLength = 0;
        if (input[i] == '\x07')
        {
            colorCodeLength = 6;
        }
        else if (input[i] == '\x08')
        {
            colorCodeLength = 8;
        }

        if (colorCodeLength > 0)
        {
            bool hasCompleteColor = i + colorCodeLength < len;
            for (int offset = 1; hasCompleteColor && offset <= colorCodeLength; offset++)
            {
                char character = input[i + offset];
                hasCompleteColor = (character >= '0' && character <= '9')
                    || (character >= 'A' && character <= 'F')
                    || (character >= 'a' && character <= 'f');
            }

            if (hasCompleteColor)
            {
                i += colorCodeLength;
            }
            continue;
        }

        if (input[i] >= '\x01' && input[i] <= '\x06')
        {
            continue;
        }

        if (input[i] == '{')
        {
            inTag = true;
            continue;
        }
        if (inTag)
        {
            if (input[i] == '}')
            {
                inTag = false;
            }
            continue;
        }

        output[out++] = input[i];
    }
    output[out] = '\0';
    TrimString(output);
}

public Action Command_ViewLotteryTicket(int client, int args)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Handled;
    }

    if (!IsLotteryReadyForClient(client))
    {
        return Plugin_Handled;
    }

    PrintClientLotteryTicket(client);
    return Plugin_Handled;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
    if (client <= 0 || client > MaxClients || !g_LotteryWaitingCustom[client])
    {
        return Plugin_Continue;
    }

    g_LotteryWaitingCustom[client] = false;

    char text[32];
    strcopy(text, sizeof(text), sArgs);
    StripQuotes(text);
    TrimString(text);

    int amount = 0;
    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));
    if (!IsLotteryReadyForClient(client))
    {
        return Plugin_Handled;
    }

    if (StrEqual(text, "all", false))
    {
        AttemptLotteryAllTicketPurchase(client);
        return Plugin_Handled;
    }

    if (!ParsePositiveInteger(text, amount))
    {
        CPrintToChat(client, "%s[Lottery]{default} Ticket value must be a positive integer or {gold}all{default}.", colorTag);
        return Plugin_Handled;
    }

    AttemptLotteryTicketPurchase(client, amount);
    return Plugin_Handled;
}

