void LoadStoreItems()
{
    g_ItemKeys.Clear();
    g_ItemNames.Clear();
    g_ItemDescriptions.Clear();
    g_ItemColors.Clear();
    g_ItemPrices.Clear();
    g_ItemDurations.Clear();
    g_ItemUses.Clear();

    char configPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configPath, sizeof(configPath), "configs/points_store.cfg");

    KeyValues kv = new KeyValues("points_store");
    if (!FileToKeyValues(kv, configPath))
    {
        LogError("[bonuspoints_transactions] Could not load %s", configPath);
        delete kv;
        return;
    }

    if (!kv.GotoFirstSubKey())
    {
        LogError("[bonuspoints_transactions] No items found in %s", configPath);
        delete kv;
        return;
    }

    do
    {
        char itemKey[BP_TRANS_ITEM_KEY_MAX];
        char itemName[BP_TRANS_ITEM_NAME_MAX];
        char description[BP_TRANS_ITEM_DESCRIPTION_MAX];
        char color[BP_CURRENCY_COLOR_MAX];
        char priceText[32];
        char durationText[32];
        char usesText[32];
        kv.GetSectionName(itemKey, sizeof(itemKey));
        kv.GetString("price", priceText, sizeof(priceText));
        kv.GetString("long_name", itemName, sizeof(itemName));
        kv.GetString("description", description, sizeof(description), "No description configured.");
        kv.GetString("color", color, sizeof(color), "gold");
        kv.GetString("duration", durationText, sizeof(durationText));
        kv.GetString("uses", usesText, sizeof(usesText));
        TrimString(itemKey);
        TrimString(itemName);
        TrimString(description);
        TrimString(color);
        TrimString(priceText);
        TrimString(durationText);
        TrimString(usesText);

        int price = StringToInt(priceText);
        if (itemKey[0] == '\0' || itemName[0] == '\0' || price <= 0)
        {
            continue;
        }
        if (color[0] == '\0')
        {
            strcopy(color, sizeof(color), "gold");
        }

        int durationSeconds = ParseDurationSeconds(durationText);
        int useCount = BP_PURCHASE_UNLIMITED_USES;
        if (usesText[0] != '\0')
        {
            useCount = StringToInt(usesText);
            if (useCount <= 0)
            {
                useCount = BP_PURCHASE_UNLIMITED_USES;
            }
        }

        AddStoreItemSorted(itemKey, itemName, description, color, price, durationSeconds, useCount);
    }
    while (kv.GotoNextKey());

    delete kv;
    LogMessage("[bonuspoints_transactions] Loaded %d shop item(s).", g_ItemPrices.Length);
}

int ParseDurationSeconds(const char[] input)
{
    char text[32];
    strcopy(text, sizeof(text), input);
    TrimString(text);

    int len = strlen(text);
    if (len <= 0)
    {
        return BP_PURCHASE_PERMANENT;
    }

    int multiplier = 1;
    char suffix = text[len - 1];
    if (suffix == 'd' || suffix == 'D')
    {
        multiplier = 86400;
        text[len - 1] = '\0';
    }
    else if (suffix == 'h' || suffix == 'H')
    {
        multiplier = 3600;
        text[len - 1] = '\0';
    }
    else if (suffix == 'm' || suffix == 'M')
    {
        multiplier = 60;
        text[len - 1] = '\0';
    }
    else if (suffix == 's' || suffix == 'S')
    {
        text[len - 1] = '\0';
    }

    TrimString(text);
    int amount = StringToInt(text);
    if (amount <= 0)
    {
        return BP_PURCHASE_PERMANENT;
    }

    return amount * multiplier;
}

void AddStoreItemSorted(const char[] itemKey, const char[] itemName, const char[] description, const char[] color, int price, int durationSeconds, int useCount)
{
    if (FindStoreItem(itemKey) != -1)
    {
        LogError("[bonuspoints_transactions] Duplicate item_key '%s' ignored.", itemKey);
        return;
    }

    int insertAt = g_ItemPrices.Length;
    for (int i = 0; i < g_ItemPrices.Length; i++)
    {
        if (price > g_ItemPrices.Get(i))
        {
            insertAt = i;
            break;
        }
    }

    if (insertAt == g_ItemPrices.Length)
    {
        g_ItemKeys.PushString(itemKey);
        g_ItemNames.PushString(itemName);
        g_ItemDescriptions.PushString(description);
        g_ItemColors.PushString(color);
        g_ItemPrices.Push(price);
        g_ItemDurations.Push(durationSeconds);
        g_ItemUses.Push(useCount);
        return;
    }

    g_ItemKeys.ShiftUp(insertAt);
    g_ItemNames.ShiftUp(insertAt);
    g_ItemDescriptions.ShiftUp(insertAt);
    g_ItemColors.ShiftUp(insertAt);
    g_ItemPrices.ShiftUp(insertAt);
    g_ItemDurations.ShiftUp(insertAt);
    g_ItemUses.ShiftUp(insertAt);
    g_ItemKeys.SetString(insertAt, itemKey);
    g_ItemNames.SetString(insertAt, itemName);
    g_ItemDescriptions.SetString(insertAt, description);
    g_ItemColors.SetString(insertAt, color);
    g_ItemPrices.Set(insertAt, price);
    g_ItemDurations.Set(insertAt, durationSeconds);
    g_ItemUses.Set(insertAt, useCount);
}

int FindStoreItem(const char[] itemKey)
{
    char currentKey[BP_TRANS_ITEM_KEY_MAX];
    for (int i = 0; i < g_ItemKeys.Length; i++)
    {
        g_ItemKeys.GetString(i, currentKey, sizeof(currentKey));
        if (StrEqual(currentKey, itemKey, false))
        {
            return i;
        }
    }
    return -1;
}

bool IsClientAuthorizedHuman(int client)
{
    return client > 0
        && client <= MaxClients
        && IsClientConnected(client)
        && IsClientAuthorized(client)
        && !IsFakeClient(client);
}

void ClearClientPurchaseCache(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    if (g_ClientPurchases[client] == null)
    {
        g_ClientPurchases[client] = new StringMap();
    }
    else
    {
        g_ClientPurchases[client].Clear();
    }
    if (g_ClientPurchaseExpiresAt[client] == null)
    {
        g_ClientPurchaseExpiresAt[client] = new StringMap();
    }
    else
    {
        g_ClientPurchaseExpiresAt[client].Clear();
    }
    if (g_ClientPurchaseUsesRemaining[client] == null)
    {
        g_ClientPurchaseUsesRemaining[client] = new StringMap();
    }
    else
    {
        g_ClientPurchaseUsesRemaining[client].Clear();
    }
    g_ClientPurchasesLoaded[client] = false;
}

void ClearClientBonusPointsCache(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    g_ClientBonusPoints[client] = 0;
    g_ClientBonusPointsLoaded[client] = false;
    g_ClientBonusPointsPending[client] = false;
}

void ClearClientStoreCache(int client)
{
    if (client > 0 && client <= MaxClients)
    {
        g_ClientShopDetailItem[client][0] = '\0';
    }

    ClearClientPurchaseCache(client);
    ClearClientBonusPointsCache(client);
}

bool GetClientSteamId64(int client, char[] steamId, int maxlen)
{
    steamId[0] = '\0';
    if (!IsClientAuthorizedHuman(client))
    {
        return false;
    }

    return Kogasa_GetClientSteamId64(client, steamId, maxlen, true);
}

bool EscapeSql(const char[] input, char[] output, int maxlen)
{
    output[0] = '\0';
    if (g_Database == null)
    {
        return false;
    }

    int written = 0;
    return g_Database.Escape(input, output, maxlen, written);
}

