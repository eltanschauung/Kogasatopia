// Pending writes are keyed by item and owned by a SQL callback, not by a menu.
StringMap g_StorePendingPurchaseReceipts[MAXPLAYERS + 1];
bool g_StorePurchaseAttempt[MAXPLAYERS + 1];

void Store_ClearPendingPurchaseReceipts(int client)
{
    delete g_StorePendingPurchaseReceipts[client];
    g_StorePendingPurchaseReceipts[client] = null;
    g_StorePurchaseAttempt[client] = false;
}

float GetSendBonusPointsCooldown()
{
    if (g_CvarSendCooldown == null) return 0.0;
    float cooldown = g_CvarSendCooldown.FloatValue;
    return cooldown > 0.0 ? cooldown : 0.0;
}

void StartSendBonusPointsCooldown(int client)
{
    float cooldown = GetSendBonusPointsCooldown();
    if (cooldown > 0.0 && client > 0 && client <= MaxClients)
    {
        g_NextSendAllowedAt[client] = GetEngineTime() + cooldown;
    }
}

void ShowShopMenu(int client)
{
    if (!Client_IsHumanInGame(client)) return;
    Menu menu = new Menu(MenuHandler_Shop);
    char currencyShort[BP_CURRENCY_SHORT_MAX], currencyLong[BP_CURRENCY_LONG_MAX];
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
    char title[BP_CURRENCY_LONG_MAX + 16];
    FormatEx(title, sizeof(title), "%s Shop", currencyLong);
    menu.SetTitle(title);

    int count = g_ItemPrices.Length;
    bool[] purchased = new bool[count > 0 ? count : 1];
    char itemKey[BP_TRANS_ITEM_KEY_MAX], itemName[BP_TRANS_ITEM_NAME_MAX];
    char display[BP_TRANS_ITEM_NAME_MAX + BP_CURRENCY_SHORT_MAX + 32];
    for (int i = 0; i < count; i++)
    {
        g_ItemKeys.GetString(i, itemKey, sizeof(itemKey));
        purchased[i] = GetCachedPurchasePrice(client, itemKey) > 0;
    }
    for (int ownershipGroup = 0; ownershipGroup < 2; ownershipGroup++)
    {
        bool showPurchased = ownershipGroup == 1;
        for (int i = 0; i < count; i++)
        {
            if (purchased[i] != showPurchased) continue;
            g_ItemKeys.GetString(i, itemKey, sizeof(itemKey));
            g_ItemNames.GetString(i, itemName, sizeof(itemName));
            int price = g_ItemPrices.Get(i);
            if (purchased[i]) FormatEx(display, sizeof(display), "%s BOUGHT", itemName);
            else
            {
                GetCurrencyShortLabelForAmount(price, currencyShort, sizeof(currencyShort));
                FormatEx(display, sizeof(display), "%s %d %s", itemName, price, currencyShort);
            }
            menu.AddItem(itemKey, display);
        }
    }
    if (count == 0) menu.AddItem("", "No shop items configured", ITEMDRAW_DISABLED);
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Shop(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }
    if (action == MenuAction_Select && Client_IsHumanInGame(client))
    {
        char itemKey[BP_TRANS_ITEM_KEY_MAX];
        menu.GetItem(item, itemKey, sizeof(itemKey));
        ShowShopItemMenu(client, itemKey);
    }
    return 0;
}

void ShowShopItemMenu(int client, const char[] itemKey)
{
    if (!Client_IsHumanInGame(client)) return;
    int itemIndex = FindStoreItem(itemKey);
    if (itemIndex == -1)
    {
        PrintToChat(client, "[Shop] That item is no longer available.");
        ShowShopMenu(client);
        return;
    }
    strcopy(g_ClientShopDetailItem[client], sizeof(g_ClientShopDetailItem[]), itemKey);
    char itemName[BP_TRANS_ITEM_NAME_MAX], info[BP_TRANS_ITEM_KEY_MAX + 16];
    g_ItemNames.GetString(itemIndex, itemName, sizeof(itemName));
    Menu menu = new Menu(MenuHandler_ShopItem);
    menu.SetTitle(itemName);
    // Bind actions to this menu's item, not a mutable per-client "current item".
    FormatEx(info, sizeof(info), "description:%s", itemKey);
    menu.AddItem(info, "Description");
    if (GetCachedPurchasePrice(client, itemKey) > 0)
    {
        menu.AddItem("purchased", "Purchased", ITEMDRAW_DISABLED);
    }
    else
    {
        char currencyShort[BP_CURRENCY_SHORT_MAX], purchaseDisplay[96];
        int price = g_ItemPrices.Get(itemIndex);
        GetCurrencyShortLabelForAmount(price, currencyShort, sizeof(currencyShort));
        FormatEx(purchaseDisplay, sizeof(purchaseDisplay), "Purchase (%d %s)", price, currencyShort);
        FormatEx(info, sizeof(info), "purchase:%s", itemKey);
        menu.AddItem(info, purchaseDisplay);
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
        if (Client_IsHumanInGame(client)) ShowShopMenu(client);
        return 0;
    }
    if (action != MenuAction_Select || !Client_IsHumanInGame(client)) return 0;
    char info[BP_TRANS_ITEM_KEY_MAX + 16];
    menu.GetItem(item, info, sizeof(info));
    if (StrEqual(info, "back"))
    {
        ShowShopMenu(client);
        return 0;
    }
    int separator = FindCharInString(info, ':');
    if (separator < 0) return 0;
    info[separator] = '\0';
    char itemKey[BP_TRANS_ITEM_KEY_MAX];
    strcopy(itemKey, sizeof(itemKey), info[separator + 1]);
    if (FindStoreItem(itemKey) == -1)
    {
        PrintToChat(client, "[Shop] That item is no longer available.");
        ShowShopMenu(client);
        return 0;
    }
    if (StrEqual(info, "description"))
    {
        PrintStoreItemDescription(client, itemKey);
        ShowShopItemMenu(client, itemKey);
    }
    else if (StrEqual(info, "purchase")) AttemptPurchase(client, itemKey);
    return 0;
}

void PrintStoreItemDescription(int client, const char[] itemKey)
{
    if (!Client_IsHumanInGame(client)) return;
    int itemIndex = FindStoreItem(itemKey);
    if (itemIndex == -1) return;
    char itemName[BP_TRANS_ITEM_NAME_MAX], description[BP_TRANS_ITEM_DESCRIPTION_MAX];
    char color[BP_CURRENCY_COLOR_MAX];
    g_ItemNames.GetString(itemIndex, itemName, sizeof(itemName));
    g_ItemDescriptions.GetString(itemIndex, description, sizeof(description));
    g_ItemColors.GetString(itemIndex, color, sizeof(color));
    TrimString(description);
    if (!description[0]) strcopy(description, sizeof(description), "No description configured.");
    CPrintToChat(client, "{%s}%s{default}: %s", color, itemName, description);
}

void AttemptPurchase(int client, const char[] itemKey)
{
    if (!Client_IsHumanInGame(client) || g_StorePurchaseAttempt[client]) return;
    if (!g_DatabaseReady || g_Database == null)
    {
        LogPurchaseEvent("purchase_rejected", "database_not_ready", client, itemKey, "", 0, GetCachedBonusPoints(client));
        PrintToChat(client, "[Shop] The shop database is not ready.");
        return;
    }
    if (!g_ClientPurchasesLoaded[client])
    {
        LoadClientPurchases(client);
        PrintToChat(client, "[Shop] Your purchases are loading. Try again in a moment.");
        return;
    }
    if (!AreBonusPointsReady(client))
    {
        LoadClientBonusPoints(client);
        PrintToChat(client, "[Shop] Your balance is loading. Try again in a moment.");
        return;
    }
    int itemIndex = FindStoreItem(itemKey);
    if (itemIndex == -1)
    {
        PrintToChat(client, "[Shop] That item is no longer available.");
        return;
    }
    // Even an exhausted one-use item may still have an INSERT outstanding.
    if (g_StorePendingPurchaseReceipts[client] != null
        && g_StorePendingPurchaseReceipts[client].ContainsKey(itemKey))
    {
        PrintToChat(client, "[Shop] Your previous purchase of this item is still saving.");
        return;
    }
    char itemName[BP_TRANS_ITEM_NAME_MAX];
    g_ItemNames.GetString(itemIndex, itemName, sizeof(itemName));
    int price = g_ItemPrices.Get(itemIndex);
    int durationSeconds = g_ItemDurations.Get(itemIndex);
    int useCount = g_ItemUses.Get(itemIndex);
    int now = GetTime();
    if (durationSeconds > 0 && durationSeconds > 2147483647 - now)
    {
        LogError("[points_store] Expiry overflows for item '%s'.", itemKey);
        PrintToChat(client, "[Shop] This item's duration is not valid. Contact an admin.");
        return;
    }
    int expiresAt = durationSeconds > 0 ? now + durationSeconds : BP_PURCHASE_PERMANENT;
    if (GetCachedPurchasePrice(client, itemKey) > 0)
    {
        PrintToChat(client, "[Shop] You already own this item.");
        return;
    }
    char steamId[32], escapedSteamId[65], escapedItemKey[(BP_TRANS_ITEM_KEY_MAX * 2) + 1];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId))) return;
    if (!EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId))
        || !EscapeSql(itemKey, escapedItemKey, sizeof(escapedItemKey)))
    {
        PrintToChat(client, "[Shop] Could not prepare your purchase.");
        return;
    }
    char query[896];
    if (g_IsMySql)
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO %s (steamid64, item_key, price_paid, expires_at, uses_remaining) VALUES ('%s', '%s', %d, %d, %d) "
            ... "ON DUPLICATE KEY UPDATE price_paid = VALUES(price_paid), expires_at = VALUES(expires_at), uses_remaining = VALUES(uses_remaining), purchased_at = CURRENT_TIMESTAMP",
            BP_TRANS_TABLE, escapedSteamId, escapedItemKey, price, expiresAt, useCount);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO %s (steamid64, item_key, price_paid, expires_at, uses_remaining) VALUES ('%s', '%s', %d, %d, %d) "
            ... "ON CONFLICT(steamid64, item_key) DO UPDATE SET price_paid = excluded.price_paid, expires_at = excluded.expires_at, uses_remaining = excluded.uses_remaining, purchased_at = CURRENT_TIMESTAMP",
            BP_TRANS_TABLE, escapedSteamId, escapedItemKey, price, expiresAt, useCount);
    }

    int serial = GetClientSerial(client);
    Database purchaseDb = view_as<Database>(CloneHandle(g_Database));
    g_StorePurchaseAttempt[client] = true;
    bool spent = SpendBonusPointsWithContext(client, price, "shop_purchase", 0);
    int currentClient = GetClientFromSerial(serial);
    if (currentClient > 0) g_StorePurchaseAttempt[currentClient] = false;
    if (!spent)
    {
        delete purchaseDb;
        if (Client_IsHumanInGame(currentClient))
        {
            LogPurchaseEvent("purchase_rejected", "insufficient_points", currentClient, itemKey, itemName, price, GetCachedBonusPoints(currentClient));
            char prefix[96], currencyShort[BP_CURRENCY_SHORT_MAX], currencyLong[BP_CURRENCY_LONG_MAX];
            char colorTag[BP_CURRENCY_COLOR_MAX + 2];
            GetCurrencyPrefix(prefix, sizeof(prefix));
            GetCurrencyShortLabel(currencyShort, sizeof(currencyShort));
            GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
            GetCurrencyColorTag(colorTag, sizeof(colorTag));
            CPrintToChat(currentClient, "%s You can't afford {gold}%s;", prefix, itemName);
            CPrintToChat(currentClient, "{default}Your balance: {lightgreen}%d%s", GetCachedBonusPoints(currentClient), currencyShort);
            CPrintToChat(currentClient, "{default}Earn %s through gameplay; see %s!bp", currencyLong, colorTag);
        }
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(serial);
    pack.WriteString(steamId);
    pack.WriteString(itemKey);
    pack.WriteString(itemName);
    pack.WriteCell(price);
    if (IsClientAuthorizedHuman(currentClient) && Store_IsCurrentConnection(purchaseDb))
    {
        g_ClientPurchases[currentClient].SetValue(itemKey, price);
        g_ClientPurchaseExpiresAt[currentClient].SetValue(itemKey, expiresAt);
        g_ClientPurchaseUsesRemaining[currentClient].SetValue(itemKey, useCount);
        Store_MarkPurchasesChanged(currentClient);
        if (g_StorePendingPurchaseReceipts[currentClient] == null)
            g_StorePendingPurchaseReceipts[currentClient] = new StringMap();
        g_StorePendingPurchaseReceipts[currentClient].SetValue(itemKey, pack);
    }
    // Persist to the captured account even if a synchronous hook disconnected it.
    purchaseDb.Query(SQL_OnPurchaseInserted, query, pack);
    delete purchaseDb;
}

public void SQL_OnPurchaseInserted(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int serial = pack.ReadCell();
    char expectedSteamId[32], itemKey[BP_TRANS_ITEM_KEY_MAX], itemName[BP_TRANS_ITEM_NAME_MAX];
    pack.ReadString(expectedSteamId, sizeof(expectedSteamId));
    pack.ReadString(itemKey, sizeof(itemKey));
    pack.ReadString(itemName, sizeof(itemName));
    int price = pack.ReadCell();
    int client = GetClientFromSerial(serial);
    int token;
    bool ownsReceipt = client > 0 && g_StorePendingPurchaseReceipts[client] != null
        && g_StorePendingPurchaseReceipts[client].GetValue(itemKey, token)
        && token == view_as<int>(pack);
    delete pack;
    if (ownsReceipt) g_StorePendingPurchaseReceipts[client].Remove(itemKey);

    if (error[0] != '\0' || results == null)
    {
        // Account-level audit must survive disconnects. Do not blindly refund an
        // ambiguous SQL outcome: the existing spend and receipt are separate writes.
        LogError("[points_store] Purchase save failed for %s/%s: %s", expectedSteamId, itemKey,
            error[0] != '\0' ? error : "missing result set");
        if (ownsReceipt && Store_IsCurrentConnection(db) && IsClientAuthorizedHuman(client))
        {
            LogPurchaseEvent("purchase_save_failed", error, client, itemKey, itemName, price, GetCachedBonusPoints(client));
            RemoveCachedPurchase(client, itemKey);
            LoadClientPurchases(client);
            if (Client_IsHumanInGame(client)) PrintToChat(client, "[Shop] Your purchase could not be confirmed. Contact an admin.");
        }
        return;
    }
    if (!ownsReceipt || !IsClientAuthorizedHuman(client) || !Store_IsCurrentConnection(db)) return;
    char currentSteamId[32];
    if (!GetClientSteamId64(client, currentSteamId, sizeof(currentSteamId))
        || !StrEqual(currentSteamId, expectedSteamId)) return;

    // Confirmation is not a new grant. Reapplying price/expiry/uses here would
    // resurrect an expired/consumed item, or restore uses consumed while INSERT ran.
    LogPurchaseEvent("purchase_success", "ok", client, itemKey, itemName, price, GetCachedBonusPoints(client));
    if (Client_IsHumanInGame(client))
    {
        char colorTag[BP_CURRENCY_COLOR_MAX + 2], currencyShort[BP_CURRENCY_SHORT_MAX], displayName[256];
        GetCurrencyColorTag(colorTag, sizeof(colorTag));
        GetCurrencyShortLabelForAmount(price, currencyShort, sizeof(currencyShort));
        BuildPurchaseDisplayName(client, displayName, sizeof(displayName));
        client = GetClientFromSerial(serial);
        if (Client_IsHumanInGame(client))
        {
            CPrintToChatAllEx(client, "%s[!shop]{default} %s bought {gold}%s{default} for %d %s%s{default}",
                colorTag, displayName, itemName, price, colorTag, currencyShort);
            PlayPurchaseSound();
        }
    }
}

static void PlayPurchaseSound()
{
    SaySounds_TryPlayCommand(0, "xp_gain");
}

void BuildPurchaseDisplayName(int client, char[] buffer, int maxlen)
{
    if (maxlen <= 0) return;
    buffer[0] = '\0';
    if (!Client_IsHumanInGame(client)) return;
    int serial = GetClientSerial(client);
    if (GetFeatureStatus(FeatureType_Native, "Filters_GetChatName") == FeatureStatus_Available
        && Filters_GetChatName(client, buffer, maxlen) && buffer[0] != '\0')
    {
        if (GetClientFromSerial(serial) == client) ChatColors_ResolveTeamTag(client, buffer, maxlen);
        return;
    }
    if (GetClientFromSerial(serial) != client || !IsClientInGame(client)) return;
    char colorTag[16];
    ChatColors_GetTeamTag(client, colorTag, sizeof(colorTag));
    FormatEx(buffer, maxlen, "%s%N{default}", colorTag, client);
}
