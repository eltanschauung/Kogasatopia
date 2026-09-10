float GetSendBonusPointsCooldown()
{
    if (g_CvarSendCooldown == null)
    {
        return 0.0;
    }

    float cooldown = g_CvarSendCooldown.FloatValue;
    return cooldown > 0.0 ? cooldown : 0.0;
}

void StartSendBonusPointsCooldown(int client)
{
    float cooldown = GetSendBonusPointsCooldown();
    if (cooldown <= 0.0 || client <= 0 || client > MaxClients)
    {
        return;
    }

    g_NextSendAllowedAt[client] = GetEngineTime() + cooldown;
}

void ShowShopMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Shop);
    char currencyShort[BP_CURRENCY_SHORT_MAX];
    char currencyLong[BP_CURRENCY_LONG_MAX];
    GetCurrencyShortLabel(currencyShort, sizeof(currencyShort));
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));

    char title[BP_CURRENCY_LONG_MAX + 16];
    Format(title, sizeof(title), "%s Shop", currencyLong);
    menu.SetTitle(title);

    char itemKey[BP_TRANS_ITEM_KEY_MAX];
    char itemName[BP_TRANS_ITEM_NAME_MAX];
    char display[BP_TRANS_ITEM_NAME_MAX + 32];

    for (int ownershipGroup = 0; ownershipGroup < 2; ownershipGroup++)
    {
        bool showPurchased = ownershipGroup == 1;
        for (int i = 0; i < g_ItemPrices.Length; i++)
        {
            g_ItemKeys.GetString(i, itemKey, sizeof(itemKey));
            bool purchased = GetCachedPurchasePrice(client, itemKey) > 0;
            if (purchased != showPurchased)
            {
                continue;
            }

            g_ItemNames.GetString(i, itemName, sizeof(itemName));
            int price = g_ItemPrices.Get(i);
            if (purchased)
            {
                Format(display, sizeof(display), "%s BOUGHT", itemName);
            }
            else
            {
                GetCurrencyShortLabelForAmount(price, currencyShort, sizeof(currencyShort));
                Format(display, sizeof(display), "%s %d %s", itemName, price, currencyShort);
            }
            menu.AddItem(itemKey, display);
        }
    }

    if (g_ItemPrices.Length == 0)
    {
        menu.AddItem("", "No shop items configured", ITEMDRAW_DISABLED);
    }

    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Shop(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }

    if (action != MenuAction_Select)
    {
        return 0;
    }

    if (!Client_IsHumanInGame(client))
    {
        return 0;
    }

    char itemKey[BP_TRANS_ITEM_KEY_MAX];
    menu.GetItem(item, itemKey, sizeof(itemKey));
    ShowShopItemMenu(client, itemKey);
    return 0;
}

void ShowShopItemMenu(int client, const char[] itemKey)
{
    if (!Client_IsHumanInGame(client))
    {
        return;
    }

    int itemIndex = FindStoreItem(itemKey);
    if (itemIndex == -1)
    {
        PrintToChat(client, "[Shop] That item is no longer available.");
        ShowShopMenu(client);
        return;
    }

    strcopy(g_ClientShopDetailItem[client], sizeof(g_ClientShopDetailItem[]), itemKey);

    char itemName[BP_TRANS_ITEM_NAME_MAX];
    g_ItemNames.GetString(itemIndex, itemName, sizeof(itemName));

    Menu menu = new Menu(MenuHandler_ShopItem);
    menu.SetTitle(itemName);
    menu.AddItem("description", "Description");

    if (GetCachedPurchasePrice(client, itemKey) > 0)
    {
        menu.AddItem("purchased", "Purchased", ITEMDRAW_DISABLED);
    }
    else
    {
        char currencyShort[BP_CURRENCY_SHORT_MAX];
        char purchaseDisplay[96];
        int price = g_ItemPrices.Get(itemIndex);
        GetCurrencyShortLabelForAmount(price, currencyShort, sizeof(currencyShort));
        Format(purchaseDisplay, sizeof(purchaseDisplay), "Purchase (%d %s)", price, currencyShort);
        menu.AddItem("purchase", purchaseDisplay);
    }
    menu.AddItem("back", "Back");
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ShopItem(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }

    if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
    {
        if (Client_IsHumanInGame(client))
        {
            ShowShopMenu(client);
        }
        return 0;
    }

    if (action != MenuAction_Select || !Client_IsHumanInGame(client))
    {
        return 0;
    }

    char actionName[32];
    menu.GetItem(item, actionName, sizeof(actionName));

    char itemKey[BP_TRANS_ITEM_KEY_MAX];
    strcopy(itemKey, sizeof(itemKey), g_ClientShopDetailItem[client]);
    if (!itemKey[0] || FindStoreItem(itemKey) == -1)
    {
        PrintToChat(client, "[Shop] That item is no longer available.");
        ShowShopMenu(client);
        return 0;
    }

    if (StrEqual(actionName, "description", false))
    {
        PrintStoreItemDescription(client, itemKey);
        ShowShopItemMenu(client, itemKey);
    }
    else if (StrEqual(actionName, "purchase", false))
    {
        AttemptPurchase(client, itemKey);
    }
    else if (StrEqual(actionName, "back", false))
    {
        ShowShopMenu(client);
    }

    return 0;
}

void PrintStoreItemDescription(int client, const char[] itemKey)
{
    int itemIndex = FindStoreItem(itemKey);
    if (itemIndex == -1)
    {
        return;
    }

    char itemName[BP_TRANS_ITEM_NAME_MAX];
    char description[BP_TRANS_ITEM_DESCRIPTION_MAX];
    char color[BP_CURRENCY_COLOR_MAX];
    g_ItemNames.GetString(itemIndex, itemName, sizeof(itemName));
    g_ItemDescriptions.GetString(itemIndex, description, sizeof(description));
    g_ItemColors.GetString(itemIndex, color, sizeof(color));
    TrimString(description);
    if (!description[0])
    {
        strcopy(description, sizeof(description), "No description configured.");
    }

    CPrintToChat(client, "{%s}%s{default}: %s", color, itemName, description);
}

void AttemptPurchase(int client, const char[] itemKey)
{
    char prefix[96];
    char currencyShort[BP_CURRENCY_SHORT_MAX];
    char currencyLong[BP_CURRENCY_LONG_MAX];
    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyPrefix(prefix, sizeof(prefix));
    GetCurrencyShortLabel(currencyShort, sizeof(currencyShort));
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
    GetCurrencyColorTag(colorTag, sizeof(colorTag));

    if (!g_DatabaseReady || g_Database == null)
    {
        LogPurchaseEvent("purchase_rejected", "database_not_ready", client, itemKey, "", 0, GetCachedBonusPoints(client));
        PrintToChat(client, "[Shop] The shop database is not ready.");
        return;
    }

    if (!g_ClientPurchasesLoaded[client])
    {
        LogPurchaseEvent("purchase_rejected", "purchases_not_loaded", client, itemKey, "", 0, GetCachedBonusPoints(client));
        PrintToChat(client, "[Shop] Your purchases are loading. Try again in a moment.");
        return;
    }

    if (!AreBonusPointsReady(client))
    {
        LoadClientBonusPoints(client);
        LogPurchaseEvent("purchase_rejected", "balance_not_loaded", client, itemKey, "", 0, GetCachedBonusPoints(client));
        PrintToChat(client, "[Shop] Your %s are loading. Try again in a moment.", currencyLong);
        return;
    }

    int itemIndex = FindStoreItem(itemKey);
    if (itemIndex == -1)
    {
        LogPurchaseEvent("purchase_rejected", "item_not_found", client, itemKey, "", 0, GetCachedBonusPoints(client));
        PrintToChat(client, "[Shop] That item is no longer available.");
        return;
    }

    char itemName[BP_TRANS_ITEM_NAME_MAX];
    g_ItemNames.GetString(itemIndex, itemName, sizeof(itemName));
    int price = g_ItemPrices.Get(itemIndex);
    int durationSeconds = g_ItemDurations.Get(itemIndex);
    int useCount = g_ItemUses.Get(itemIndex);
    int expiresAt = (durationSeconds > 0) ? (GetTime() + durationSeconds) : BP_PURCHASE_PERMANENT;

    if (GetCachedPurchasePrice(client, itemKey) > 0)
    {
        LogPurchaseEvent("purchase_rejected", "already_owned", client, itemKey, itemName, price, GetCachedBonusPoints(client));
        PrintToChat(client, "[Shop] You already own this item.");
        return;
    }

    char steamId[32];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId)))
    {
        PrintToChat(client, "[Shop] Could not read your SteamID64.");
        return;
    }

    char escapedSteamId[65];
    char escapedItemKey[(BP_TRANS_ITEM_KEY_MAX * 2) + 1];
    if (!EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId)) || !EscapeSql(itemKey, escapedItemKey, sizeof(escapedItemKey)))
    {
        LogPurchaseEvent("purchase_rejected", "sql_escape_failed", client, itemKey, itemName, price, GetCachedBonusPoints(client));
        PrintToChat(client, "[Shop] Could not prepare your purchase.");
        return;
    }

    if (!SpendBonusPointsWithContext(client, price, "shop_purchase", 0))
    {
        LogPurchaseEvent("purchase_rejected", "insufficient_points", client, itemKey, itemName, price, GetCachedBonusPoints(client));
        CPrintToChat(client, "%s You can't afford {gold}%s;", prefix, itemName);
        CPrintToChat(client, "{default}Your balance: {lightgreen}%d%s", GetCachedBonusPoints(client), currencyShort);
        CPrintToChat(client, "{default}Earn %s through gameplay; see %s!bp", currencyLong, colorTag);
        return;
    }

    g_ClientPurchases[client].SetValue(itemKey, price);
    g_ClientPurchaseExpiresAt[client].SetValue(itemKey, expiresAt);
    g_ClientPurchaseUsesRemaining[client].SetValue(itemKey, useCount);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(steamId);
    pack.WriteString(itemKey);
    pack.WriteString(itemName);
    pack.WriteCell(price);
    pack.WriteCell(expiresAt);
    pack.WriteCell(useCount);

    char query[896];
    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "INSERT INTO %s (steamid64, item_key, price_paid, expires_at, uses_remaining) "
            ... "VALUES ('%s', '%s', %d, %d, %d) "
            ... "ON DUPLICATE KEY UPDATE price_paid = VALUES(price_paid), expires_at = VALUES(expires_at), uses_remaining = VALUES(uses_remaining), purchased_at = CURRENT_TIMESTAMP",
            BP_TRANS_TABLE,
            escapedSteamId,
            escapedItemKey,
            price,
            expiresAt,
            useCount);
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO %s (steamid64, item_key, price_paid, expires_at, uses_remaining) "
            ... "VALUES ('%s', '%s', %d, %d, %d) "
            ... "ON CONFLICT(steamid64, item_key) DO UPDATE SET price_paid = excluded.price_paid, expires_at = excluded.expires_at, uses_remaining = excluded.uses_remaining, purchased_at = CURRENT_TIMESTAMP",
            BP_TRANS_TABLE,
            escapedSteamId,
            escapedItemKey,
            price,
            expiresAt,
            useCount);
    }

    g_Database.Query(SQL_OnPurchaseInserted, query, pack);
}

public void SQL_OnPurchaseInserted(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    char expectedSteamId[32];
    char itemKey[BP_TRANS_ITEM_KEY_MAX];
    char itemName[BP_TRANS_ITEM_NAME_MAX];
    pack.ReadString(expectedSteamId, sizeof(expectedSteamId));
    pack.ReadString(itemKey, sizeof(itemKey));
    pack.ReadString(itemName, sizeof(itemName));
    int price = pack.ReadCell();
    int expiresAt = pack.ReadCell();
    int useCount = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    if (!IsClientAuthorizedHuman(client))
    {
        return;
    }

    char currentSteamId[32];
    if (!GetClientSteamId64(client, currentSteamId, sizeof(currentSteamId)) || !StrEqual(currentSteamId, expectedSteamId, false))
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[bonuspoints_transactions] Failed to insert purchase for %s/%s: %s", expectedSteamId, itemKey, error);
        LogPurchaseEvent("purchase_save_failed", error, client, itemKey, itemName, price, GetCachedBonusPoints(client));
        RemoveCachedPurchase(client, itemKey);
        if (Client_IsHumanInGame(client))
        {
            PrintToChat(client, "[Shop] Your purchase could not be saved. Contact an admin.");
        }
        return;
    }

    g_ClientPurchases[client].SetValue(itemKey, price);
    g_ClientPurchaseExpiresAt[client].SetValue(itemKey, expiresAt);
    g_ClientPurchaseUsesRemaining[client].SetValue(itemKey, useCount);
    LogPurchaseEvent("purchase_success", "ok", client, itemKey, itemName, price, GetCachedBonusPoints(client));
    if (Client_IsHumanInGame(client))
    {
        char colorTag[BP_CURRENCY_COLOR_MAX + 2];
        char currencyShort[BP_CURRENCY_SHORT_MAX];
        GetCurrencyColorTag(colorTag, sizeof(colorTag));
        GetCurrencyShortLabelForAmount(price, currencyShort, sizeof(currencyShort));

        char displayName[256];
        BuildPurchaseDisplayName(client, displayName, sizeof(displayName));
        CPrintToChatAllEx(client, "%s[!shop]{default} %s bought {gold}%s{default} for %d %s%s{default}", colorTag, displayName, itemName, price, colorTag, currencyShort);
        PlayPurchaseSound();
    }
}

static void PlayPurchaseSound()
{
    SaySounds_TryPlayCommand(0, "xp_gain");
}

void BuildPurchaseDisplayName(int client, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (GetFeatureStatus(FeatureType_Native, "Filters_GetChatName") == FeatureStatus_Available
        && Filters_GetChatName(client, buffer, maxlen)
        && buffer[0] != '\0')
    {
        ChatColors_ResolveTeamTag(client, buffer, maxlen);
        return;
    }

    char colorTag[16];
    ChatColors_GetTeamTag(client, colorTag, sizeof(colorTag));
    Format(buffer, maxlen, "%s%N{default}", colorTag, client);
}

