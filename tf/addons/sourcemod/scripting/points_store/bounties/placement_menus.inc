static const int g_BountyAmounts[] = {10, 25, 50, 100, 250, 1000};

public Action Timer_BountyMaintenance(Handle timer)
{
    if (g_BountyDatabaseReady)
    {
        ProcessExpiredBounties();
        RequestBountyProgress();
        RefreshActiveBountyTargets();
    }
    return Plugin_Continue;
}

public Action Command_PlaceBounty(int client, int args)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Handled;
    }
    if (!g_BountyDatabaseReady || g_Database == null)
    {
        CPrintToChat(client, "%s Bounties are temporarily unavailable.", g_BountyPrefix);
        return Plugin_Handled;
    }
    int cooldownRemaining = GetBountyPlacementCooldownRemaining(client);
    if (cooldownRemaining > 0)
    {
        CPrintToChat(client, "%s You can place another bounty in {gold}%d minutes{default}.",
            g_BountyPrefix,
            (cooldownRemaining + 59) / 60);
        return Plugin_Handled;
    }
    if (!IsBountyPopulationEligible())
    {
        CPrintToChat(client,
            "%s At least {gold}%d{default} connected players are required to place a bounty.",
            g_BountyPrefix,
            GetBountyMinPlayers());
        return Plugin_Handled;
    }
    if (args < 1)
    {
        CPrintToChat(client, "%s Usage: {gold}!bounty playername [amount]", g_BountyPrefix);
        return Plugin_Handled;
    }
    if (!AreBonusPointsReady(client))
    {
        LoadClientBonusPoints(client);
        CPrintToChat(client, "%s Your currency balance is still loading.", g_BountyPrefix);
        return Plugin_Handled;
    }
    if (g_BountyPlacementPending[client])
    {
        CPrintToChat(client, "%s Your bounty is still being saved. Try again shortly.", g_BountyPrefix);
        return Plugin_Handled;
    }

    g_BountyPendingSearch[client][0] = '\0';
    g_BountyPendingAmount[client] = 0;

    int searchArgCount = args;
    if (args >= 2)
    {
        char amountText[16];
        int amount;
        GetCmdArg(args, amountText, sizeof(amountText));
        int parsedLength = StringToIntEx(amountText, amount);
        if (parsedLength > 0 && amountText[parsedLength] == '\0')
        {
            if (!IsBountyAmountAllowed(amount))
            {
                CPrintToChat(client,
                    "%s Bounty amount must be between {gold}%d and %d{default}.",
                    g_BountyPrefix,
                    GetBountyMinAmount(),
                    GetBountyMaxAmount());
                return Plugin_Handled;
            }
            if (GetCachedBonusPoints(client) < amount)
            {
                CPrintToChat(client, "%s You do not have enough %s.", g_BountyPrefix, g_CurrencyLongLabel);
                return Plugin_Handled;
            }

            g_BountyPendingAmount[client] = amount;
            searchArgCount--;
        }
    }

    char searchPart[BOUNTY_NAME_MAX];
    for (int i = 1; i <= searchArgCount; i++)
    {
        GetCmdArg(i, searchPart, sizeof(searchPart));
        if (g_BountyPendingSearch[client][0] != '\0')
        {
            StrCat(g_BountyPendingSearch[client], sizeof(g_BountyPendingSearch[]), " ");
        }
        StrCat(g_BountyPendingSearch[client], sizeof(g_BountyPendingSearch[]), searchPart);
    }
    TrimString(g_BountyPendingSearch[client]);
    if (g_BountyPendingSearch[client][0] == '\0')
    {
        CPrintToChat(client, "%s Usage: {gold}!bounty playername [amount]", g_BountyPrefix);
        return Plugin_Handled;
    }

    RequestBountyPlayerSearch(client);
    return Plugin_Handled;
}

bool IsBountyAmountAllowed(int amount)
{
    return amount >= GetBountyMinAmount() && amount <= GetBountyMaxAmount();
}

void RequestBountyPlayerSearch(int client)
{
    delete g_BountySearchResults[client];
    g_BountySearchResults[client] = new ArrayList(sizeof(BountySearchResult));
    g_BountySearchGeneration[client]++;

    if (GetFeatureStatus(FeatureType_Native, "WhaleTracker_GetRankedPlaytimeHours") != FeatureStatus_Available)
    {
        CPrintToChat(client, "%s Ranked-player checks are temporarily unavailable.", g_BountyPrefix);
        return;
    }

    BountySearchResult entry;
    for (int target = 1; target <= MaxClients; target++)
    {
        if (!Client_IsHumanInGame(target) || target == client)
        {
            continue;
        }
        GetClientName(target, entry.name, sizeof(entry.name));
        if (StrContains(entry.name, g_BountyPendingSearch[client], false) == -1)
        {
            continue;
        }

        int rankedHours = WhaleTracker_GetRankedPlaytimeHours(target);
        if (rankedHours <= 0 || !GetClientSteamId64(target, entry.steamId, sizeof(entry.steamId)))
        {
            continue;
        }

        entry.playtime = rankedHours * 3600;
        entry.connected = true;
        g_BountySearchResults[client].PushArray(entry, sizeof(entry));
    }

    g_BountySearchResults[client].SortCustom(SortBountySearchResults);
    ShowBountySearchResults(client);
}

int FindBountySearchResult(ArrayList results, const char[] steamId)
{
    BountySearchResult entry;
    for (int i = 0; i < results.Length; i++)
    {
        results.GetArray(i, entry, sizeof(entry));
        if (StrEqual(entry.steamId, steamId, false))
        {
            return i;
        }
    }
    return -1;
}

public int SortBountySearchResults(int index1, int index2, Handle array, Handle data)
{
    ArrayList results = view_as<ArrayList>(array);
    BountySearchResult left;
    BountySearchResult right;
    results.GetArray(index1, left, sizeof(left));
    results.GetArray(index2, right, sizeof(right));

    if (left.connected != right.connected)
    {
        return left.connected ? -1 : 1;
    }
    if (left.playtime != right.playtime)
    {
        return left.playtime > right.playtime ? -1 : 1;
    }
    return strcmp(left.name, right.name, false);
}

void ShowBountySearchResults(int client)
{
    ArrayList results = g_BountySearchResults[client];
    if (results == null || results.Length == 0)
    {
        CPrintToChat(client, "%s No ranked player matched '{gold}%s{default}'.", g_BountyPrefix, g_BountyPendingSearch[client]);
        return;
    }

    Menu menu = new Menu(MenuHandler_BountySearchResults);
    menu.SetTitle("Place a bounty on:");
    BountySearchResult entry;
    char display[256];
    for (int i = 0; i < results.Length && i < BOUNTY_SEARCH_MAX; i++)
    {
        results.GetArray(i, entry, sizeof(entry));
        strcopy(display, sizeof(display), entry.name);
        menu.AddItem(entry.steamId, display);
    }
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_BountySearchResults(Menu menu, MenuAction action, int client, int item)
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

    char targetSteamId[BOUNTY_STEAMID_MAX];
    menu.GetItem(item, targetSteamId, sizeof(targetSteamId));
    if (!Client_IsHumanInGame(Kogasa_FindClientBySteamId64(targetSteamId)))
    {
        CPrintToChat(client, "%s That player is no longer online.", g_BountyPrefix);
        return 0;
    }
    char senderSteamId[BOUNTY_STEAMID_MAX];
    if (!GetClientSteamId64(client, senderSteamId, sizeof(senderSteamId)))
    {
        return 0;
    }
    if (StrEqual(senderSteamId, targetSteamId, false))
    {
        CPrintToChat(client, "%s You cannot place a bounty on yourself.", g_BountyPrefix);
        return 0;
    }
    if (g_ActiveBountyCount >= BOUNTY_MAX_ACTIVE && !IsSteamIdActiveBountyTarget(targetSteamId))
    {
        CPrintToChat(client, "%s The maximum of {gold}%d{default} active bounty targets has been reached.", g_BountyPrefix, BOUNTY_MAX_ACTIVE);
        return 0;
    }

    strcopy(g_BountyPendingTargetSteamId[client], sizeof(g_BountyPendingTargetSteamId[]), targetSteamId);
    strcopy(g_BountyPendingTargetName[client], sizeof(g_BountyPendingTargetName[]), targetSteamId);
    ArrayList results = g_BountySearchResults[client];
    int index = results != null ? FindBountySearchResult(results, targetSteamId) : -1;
    if (index != -1)
    {
        BountySearchResult entry;
        results.GetArray(index, entry, sizeof(entry));
        strcopy(g_BountyPendingTargetName[client], sizeof(g_BountyPendingTargetName[]), entry.name);
    }

    if (g_BountyPendingAmount[client] > 0)
    {
        ShowBountyConsentMenu(client);
    }
    else
    {
        ShowBountyAmountMenu(client);
    }
    return 0;
}

void ShowBountyAmountMenu(int client)
{
    Menu menu = new Menu(MenuHandler_BountyAmount);
    menu.SetTitle("Bounty on %s:", g_BountyPendingTargetName[client]);
    char info[16];
    char display[64];
    char currencyLong[BP_CURRENCY_LONG_MAX];
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
    for (int i = 0; i < sizeof(g_BountyAmounts); i++)
    {
        if (!IsBountyAmountAllowed(g_BountyAmounts[i]))
        {
            continue;
        }
        IntToString(g_BountyAmounts[i], info, sizeof(info));
        FormatEx(display, sizeof(display), "%d %s", g_BountyAmounts[i], currencyLong);
        menu.AddItem(info, display);
    }
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_BountyAmount(Menu menu, MenuAction action, int client, int item)
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

    char info[16];
    menu.GetItem(item, info, sizeof(info));
    int amount = StringToInt(info);
    if (!IsBountyAmountAllowed(amount) || !AreBonusPointsReady(client) || GetCachedBonusPoints(client) < amount)
    {
        CPrintToChat(client, "%s You do not have enough %s.", g_BountyPrefix, g_CurrencyLongLabel);
        return 0;
    }

    g_BountyPendingAmount[client] = amount;
    ShowBountyConsentMenu(client);
    return 0;
}

void ShowBountyConsentMenu(int client)
{
    char currencyLong[BP_CURRENCY_LONG_MAX];
    char currencyColor[BP_CURRENCY_COLOR_MAX + 2];
    char targetDisplay[256];
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
    GetCurrencyColorTag(currencyColor, sizeof(currencyColor));

    int target = Kogasa_FindClientBySteamId64(g_BountyPendingTargetSteamId[client]);
    if (!Client_IsHumanInGame(target))
    {
        CPrintToChat(client, "%s That player is no longer online.", g_BountyPrefix);
        return;
    }
    else
    {
        BuildPurchaseDisplayName(target, targetDisplay, sizeof(targetDisplay));
    }

    CPrintToChatEx(client,
        target > 0 ? target : client,
        "%s Spend %s%d %s{default} to place a bounty on %s?",
        g_BountyPrefix,
        currencyColor,
        g_BountyPendingAmount[client],
        currencyLong,
        targetDisplay);

    Menu menu = new Menu(MenuHandler_BountyConsent);
    menu.SetTitle("Spend %d %s to place a bounty on %s?",
        g_BountyPendingAmount[client],
        currencyLong,
        g_BountyPendingTargetName[client]);
    menu.AddItem("yes", "Yes");
    menu.AddItem("no", "No");
    menu.ExitButton = true;
    menu.Display(client, 20);
}

public int MenuHandler_BountyConsent(Menu menu, MenuAction action, int client, int item)
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

    char info[8];
    menu.GetItem(item, info, sizeof(info));
    if (!StrEqual(info, "yes"))
    {
        return 0;
    }
    if (g_BountyPlacementPending[client])
    {
        CPrintToChat(client, "%s Your bounty is still being saved. Try again shortly.", g_BountyPrefix);
        return 0;
    }
    if (!AreBonusPointsReady(client) || GetCachedBonusPoints(client) < g_BountyPendingAmount[client])
    {
        CPrintToChat(client, "%s You no longer have enough %s.", g_BountyPrefix, g_CurrencyLongLabel);
        return 0;
    }
    if (!IsBountyAmountAllowed(g_BountyPendingAmount[client]))
    {
        CPrintToChat(client,
            "%s Bounties must now be between {gold}%d and %d{default}. Choose another amount.",
            g_BountyPrefix,
            GetBountyMinAmount(),
            GetBountyMaxAmount());
        return 0;
    }
    if (!IsBountyPopulationEligible())
    {
        CPrintToChat(client,
            "%s At least {gold}%d{default} connected players are required to place a bounty.",
            g_BountyPrefix,
            GetBountyMinPlayers());
        return 0;
    }
    if (g_ActiveBountyCount >= BOUNTY_MAX_ACTIVE
        && !IsSteamIdActiveBountyTarget(g_BountyPendingTargetSteamId[client]))
    {
        CPrintToChat(client, "%s The maximum of {gold}%d{default} active bounty targets has been reached.", g_BountyPrefix, BOUNTY_MAX_ACTIVE);
        return 0;
    }
    int cooldownRemaining = GetBountyPlacementCooldownRemaining(client);
    if (cooldownRemaining > 0)
    {
        CPrintToChat(client, "%s You can place another bounty in {gold}%d minutes{default}.",
            g_BountyPrefix,
            (cooldownRemaining + 59) / 60);
        return 0;
    }
    if (!Client_IsHumanInGame(Kogasa_FindClientBySteamId64(g_BountyPendingTargetSteamId[client])))
    {
        CPrintToChat(client, "%s That player is no longer online.", g_BountyPrefix);
        return 0;
    }

    QueueBountyPlacement(client);
    return 0;
}

