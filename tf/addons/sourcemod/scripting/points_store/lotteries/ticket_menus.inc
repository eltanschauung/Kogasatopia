bool ParsePositiveInteger(const char[] text, int &value)
{
    value = 0;

    char trimmed[32];
    strcopy(trimmed, sizeof(trimmed), text);
    TrimString(trimmed);

    int len = strlen(trimmed);
    if (len <= 0)
    {
        return false;
    }

    for (int i = 0; i < len; i++)
    {
        if (trimmed[i] < '0' || trimmed[i] > '9')
        {
            return false;
        }
    }

    value = StringToInt(trimmed);
    return value > 0;
}

int RoundLotteryTicketValue(int amount)
{
    if (amount <= 0)
    {
        return 0;
    }

    return (amount / LOTTO_TICKET_UNIT) * LOTTO_TICKET_UNIT;
}

int GetLotteryChanceCount(int amount)
{
    if (g_CurrentLotteryEqual)
    {
        return amount == GetLotteryEqualTicketValue() ? 1 : 0;
    }

    int roundedAmount = RoundLotteryTicketValue(amount);
    if (roundedAmount <= 0)
    {
        return 0;
    }

    return roundedAmount / LOTTO_TICKET_UNIT;
}

void ShowLotteryMenu(int client)
{
    if (!IsLotteryReadyForClient(client))
    {
        return;
    }

    if (g_ClientLotteryHasTicket[client])
    {
        ShowOwnedLotteryTicketMenu(client);
        return;
    }

    Menu menu = new Menu(MenuHandler_LotteryBuy);
    char currencyLong[BP_CURRENCY_LONG_MAX];
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));

    char title[BP_CURRENCY_LONG_MAX + 16];
    Format(title, sizeof(title), "%s Lottery", currencyLong);
    menu.SetTitle(title);

    char display[128];
    if (g_CurrentLotteryEqual)
    {
        int requiredValue = GetLotteryEqualTicketValue();
        char info[16];
        IntToString(requiredValue, info, sizeof(info));
        Format(display, sizeof(display), "%d %s", requiredValue, currencyLong);
        menu.AddItem(info, display);
        menu.AddItem("pool", "Prize pool");
        menu.Display(client, MENU_TIME_FOREVER);
        return;
    }

    Format(display, sizeof(display), "10 %s", currencyLong);
    menu.AddItem("10", display);
    Format(display, sizeof(display), "25 %s", currencyLong);
    menu.AddItem("25", display);
    Format(display, sizeof(display), "50 %s", currencyLong);
    menu.AddItem("50", display);
    Format(display, sizeof(display), "100 %s", currencyLong);
    menu.AddItem("100", display);
    menu.AddItem("custom", "Custom (type in chat)");
    menu.AddItem("pool", "Prize pool");
    menu.Display(client, MENU_TIME_FOREVER);
}

void ShowOwnedLotteryTicketMenu(int client)
{
    Menu menu = new Menu(MenuHandler_LotteryOwned);
    char currencyLong[BP_CURRENCY_LONG_MAX];
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));

    char title[BP_CURRENCY_LONG_MAX + 16];
    Format(title, sizeof(title), "%s Lotto", currencyLong);
    menu.SetTitle(title);
    menu.AddItem("view", "View ticket");
    menu.AddItem("refund", "Refund ticket");
    menu.AddItem("pool", "Prize pool");
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_LotteryBuy(Menu menu, MenuAction action, int client, int item)
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

    char info[32];
    menu.GetItem(item, info, sizeof(info));
    if (StrEqual(info, "custom", false))
    {
        PromptLotteryCustomAmount(client);
        return 0;
    }

    if (StrEqual(info, "pool", false))
    {
        PrintLotteryPrizePool(client);
        return 0;
    }

    int amount = StringToInt(info);
    if (amount > 0)
    {
        AttemptLotteryTicketPurchase(client, amount);
    }
    return 0;
}

public int MenuHandler_LotteryOwned(Menu menu, MenuAction action, int client, int item)
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

    char info[32];
    menu.GetItem(item, info, sizeof(info));
    if (StrEqual(info, "view", false))
    {
        PrintClientLotteryTicket(client);
    }
    else if (StrEqual(info, "refund", false))
    {
        RefundLotteryTicket(client);
    }
    else if (StrEqual(info, "pool", false))
    {
        PrintLotteryPrizePool(client);
        return 0;
    }
    return 0;
}

void PromptLotteryCustomAmount(int client)
{
    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));
    if (g_CurrentLotteryEqual)
    {
        CPrintToChat(client,
            "%s[Lottery]{default} Equal Lottery tickets must have a value of {gold}%d{default}.",
            colorTag,
            GetLotteryEqualTicketValue());
        return;
    }

    g_LotteryWaitingCustom[client] = true;
    CPrintToChat(client, "%s[Lottery]{default} Type your ticket value, or {gold}all{default}. Values are rounded down to the nearest %s%d{default}.", colorTag, colorTag, LOTTO_TICKET_UNIT);
}

void PrintClientLotteryTicket(int client)
{
    if (!IsLotteryReadyForClient(client))
    {
        return;
    }

    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));
    if (!g_ClientLotteryHasTicket[client])
    {
        CPrintToChat(client, "%s[Lottery]{default} You do not have a ticket in the current lottery.", colorTag);
        return;
    }

    char display[LOTTO_TICKET_PRINT_MAX];
    char currencyLong[BP_CURRENCY_LONG_MAX];
    int ticketValue = g_CurrentLotteryEqual
        ? GetLotteryEqualTicketValue()
        : g_ClientLotteryTicketValue[client];
    BuildLotteryTicketDisplay(g_ClientLotteryTicket[client], display, sizeof(display));
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
    CPrintToChat(client, "%s[Lottery]{default} Your ticket: %s\n{gold}Value:{default} %s%d %s{default}", colorTag, display, colorTag, ticketValue, currencyLong);
}

