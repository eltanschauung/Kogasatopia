// The catalogue is published only after parsing and sorting have succeeded.
// Keep the legacy parallel arrays/API, but index item keys once rather than
// doing a linear, case-insensitive scan for every ownership/menu lookup.
StringMap g_StoreItemIndex = null;

enum struct StoreCatalogEntry
{
    char key[BP_TRANS_ITEM_KEY_MAX];
    char name[BP_TRANS_ITEM_NAME_MAX];
    char description[BP_TRANS_ITEM_DESCRIPTION_MAX];
    char color[BP_CURRENCY_COLOR_MAX];
    int price;
    int duration;
    int uses;
    int order;
}

void Store_NormalizeItemKey(const char[] input, char[] output, int maxlen)
{
    strcopy(output, maxlen, input);
    for (int i = 0; output[i] != '\0'; i++)
    {
        output[i] = CharToLower(output[i]);
    }
}

public int Store_CompareCatalogEntries(int first, int second, Handle array, Handle data)
{
    ArrayList entries = view_as<ArrayList>(array);
    StoreCatalogEntry a, b;
    entries.GetArray(first, a, sizeof(a));
    entries.GetArray(second, b, sizeof(b));
    if (a.price != b.price)
    {
        return a.price > b.price ? -1 : 1;
    }
    // Preserve config order for equal prices; do not depend on sort stability.
    return a.order < b.order ? -1 : (a.order > b.order ? 1 : 0);
}

void LoadStoreItems()
{
    char configPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configPath, sizeof(configPath), "configs/points_store.cfg");
    KeyValues kv = new KeyValues("points_store");
    if (!kv.ImportFromFile(configPath) || !kv.GotoFirstSubKey())
    {
        LogError("[points_store] Could not read items from %s; retaining the current catalogue.", configPath);
        delete kv;
        return;
    }

    ArrayList entries = new ArrayList(sizeof(StoreCatalogEntry));
    StringMap seen = new StringMap();
    int order = 0;
    do
    {
        StoreCatalogEntry entry;
        char priceText[32], durationText[32], usesText[32];
        kv.GetSectionName(entry.key, sizeof(entry.key));
        kv.GetString("price", priceText, sizeof(priceText));
        kv.GetString("long_name", entry.name, sizeof(entry.name));
        kv.GetString("description", entry.description, sizeof(entry.description), "No description configured.");
        kv.GetString("color", entry.color, sizeof(entry.color), "gold");
        kv.GetString("duration", durationText, sizeof(durationText));
        kv.GetString("uses", usesText, sizeof(usesText));
        TrimString(entry.key);
        TrimString(entry.name);
        TrimString(entry.description);
        TrimString(entry.color);
        TrimString(priceText);
        TrimString(durationText);
        TrimString(usesText);

        if (entry.key[0] == '\0' || entry.name[0] == '\0'
            || !Store_ParseNonnegativeInt(priceText, entry.price) || entry.price <= 0)
        {
            continue;
        }
        entry.duration = ParseDurationSeconds(durationText);
        if (entry.duration < 0)
        {
            LogError("[points_store] Invalid or overflowing duration for '%s'; item ignored.", entry.key);
            continue;
        }
        if (entry.color[0] == '\0')
        {
            strcopy(entry.color, sizeof(entry.color), "gold");
        }
        entry.uses = BP_PURCHASE_UNLIMITED_USES;
        if (usesText[0] != '\0' && !StrEqual(usesText, "-1")
            && !Store_ParseNonnegativeInt(usesText, entry.uses))
        {
            LogError("[points_store] Invalid or overflowing uses for '%s'; item ignored.", entry.key);
            continue;
        }
        if (entry.uses <= 0)
        {
            entry.uses = BP_PURCHASE_UNLIMITED_USES;
        }

        char normalized[BP_TRANS_ITEM_KEY_MAX];
        Store_NormalizeItemKey(entry.key, normalized, sizeof(normalized));
        if (seen.ContainsKey(normalized))
        {
            LogError("[points_store] Duplicate item_key '%s' ignored.", entry.key);
            continue;
        }
        seen.SetValue(normalized, 1);
        entry.order = order++;
        entries.PushArray(entry, sizeof(entry));
    }
    while (kv.GotoNextKey());
    delete kv;
    delete seen;

    if (entries.Length == 0)
    {
        LogError("[points_store] No valid items in %s; retaining the current catalogue.", configPath);
        delete entries;
        return;
    }
    entries.SortCustom(Store_CompareCatalogEntries);

    ArrayList keys = new ArrayList(ByteCountToCells(BP_TRANS_ITEM_KEY_MAX));
    ArrayList names = new ArrayList(ByteCountToCells(BP_TRANS_ITEM_NAME_MAX));
    ArrayList descriptions = new ArrayList(ByteCountToCells(BP_TRANS_ITEM_DESCRIPTION_MAX));
    ArrayList colors = new ArrayList(ByteCountToCells(BP_CURRENCY_COLOR_MAX));
    ArrayList prices = new ArrayList();
    ArrayList durations = new ArrayList();
    ArrayList uses = new ArrayList();
    StringMap index = new StringMap();
    for (int i = 0, count = entries.Length; i < count; i++)
    {
        StoreCatalogEntry entry;
        entries.GetArray(i, entry, sizeof(entry));
        keys.PushString(entry.key);
        names.PushString(entry.name);
        descriptions.PushString(entry.description);
        colors.PushString(entry.color);
        prices.Push(entry.price);
        durations.Push(entry.duration);
        uses.Push(entry.uses);
        char normalized[BP_TRANS_ITEM_KEY_MAX];
        Store_NormalizeItemKey(entry.key, normalized, sizeof(normalized));
        index.SetValue(normalized, i);
    }
    delete entries;

    // No engine calls or forwards between deleting the old snapshot and publishing.
    delete g_ItemKeys;
    delete g_ItemNames;
    delete g_ItemDescriptions;
    delete g_ItemColors;
    delete g_ItemPrices;
    delete g_ItemDurations;
    delete g_ItemUses;
    delete g_StoreItemIndex;
    g_ItemKeys = keys;
    g_ItemNames = names;
    g_ItemDescriptions = descriptions;
    g_ItemColors = colors;
    g_ItemPrices = prices;
    g_ItemDurations = durations;
    g_ItemUses = uses;
    g_StoreItemIndex = index;
    LogMessage("[points_store] Loaded %d shop item(s).", prices.Length);
}

// Check before multiplying or adding: StringToIntEx does not expose overflow.
bool Store_ParseNonnegativeInt(const char[] text, int &value)
{
    value = 0;
    int i = text[0] == '+' ? 1 : 0;
    if (text[i] == '\0')
    {
        return false;
    }
    for (; text[i] != '\0'; i++)
    {
        int digit = text[i] - '0';
        if (digit < 0 || digit > 9 || value > (2147483647 - digit) / 10)
        {
            return false;
        }
        value = value * 10 + digit;
    }
    return true;
}

int ParseDurationSeconds(const char[] input)
{
    char text[32];
    if (strlen(input) >= sizeof(text))
    {
        return -1;
    }
    strcopy(text, sizeof(text), input);
    TrimString(text);
    int len = strlen(text);
    if (len == 0)
    {
        return BP_PURCHASE_PERMANENT;
    }

    int multiplier = 1;
    char suffix = CharToLower(text[len - 1]);
    if (suffix == 'd' || suffix == 'h' || suffix == 'm' || suffix == 's')
    {
        if (suffix == 'd') multiplier = 86400;
        else if (suffix == 'h') multiplier = 3600;
        else if (suffix == 'm') multiplier = 60;
        text[len - 1] = '\0';
    }
    TrimString(text);
    int amount;
    if (!Store_ParseNonnegativeInt(text, amount))
    {
        return -1;
    }
    if (amount <= 0)
    {
        return BP_PURCHASE_PERMANENT;
    }
    if (amount > 2147483647 / multiplier)
    {
        return -1;
    }
    return amount * multiplier;
}

// Retained for callers in future local modules. Configuration loading uses one
// O(n log n) sort instead of seven array shifts for every inserted item.
stock void AddStoreItemSorted(const char[] itemKey, const char[] itemName,
    const char[] description, const char[] color, int price, int durationSeconds, int useCount)
{
    if (FindStoreItem(itemKey) != -1)
    {
        LogError("[points_store] Duplicate item_key '%s' ignored.", itemKey);
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
    }
    else
    {
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
    Store_RebuildItemIndex();
}

void Store_RebuildItemIndex()
{
    if (g_StoreItemIndex == null) g_StoreItemIndex = new StringMap();
    else g_StoreItemIndex.Clear();
    for (int i = 0, count = g_ItemKeys.Length; i < count; i++)
    {
        char key[BP_TRANS_ITEM_KEY_MAX], normalized[BP_TRANS_ITEM_KEY_MAX];
        g_ItemKeys.GetString(i, key, sizeof(key));
        Store_NormalizeItemKey(key, normalized, sizeof(normalized));
        g_StoreItemIndex.SetValue(normalized, i);
    }
}

int FindStoreItem(const char[] itemKey)
{
    // Reject a too-long key instead of silently aliasing its truncated prefix.
    if (g_ItemKeys == null || itemKey[0] == '\0' || strlen(itemKey) >= BP_TRANS_ITEM_KEY_MAX)
    {
        return -1;
    }
    if (g_StoreItemIndex == null) Store_RebuildItemIndex();
    char normalized[BP_TRANS_ITEM_KEY_MAX];
    Store_NormalizeItemKey(itemKey, normalized, sizeof(normalized));
    int index;
    return g_StoreItemIndex.GetValue(normalized, index) ? index : -1;
}

bool IsClientAuthorizedHuman(int client)
{
    return client > 0 && client <= MaxClients && IsClientConnected(client)
        && IsClientAuthorized(client) && !IsFakeClient(client);
}

void ClearClientPurchaseCache(int client)
{
    if (client <= 0 || client > MaxClients) return;
    Store_InvalidatePurchaseLoad(client);
    if (g_ClientPurchases[client] == null) g_ClientPurchases[client] = new StringMap();
    else g_ClientPurchases[client].Clear();
    if (g_ClientPurchaseExpiresAt[client] == null) g_ClientPurchaseExpiresAt[client] = new StringMap();
    else g_ClientPurchaseExpiresAt[client].Clear();
    if (g_ClientPurchaseUsesRemaining[client] == null) g_ClientPurchaseUsesRemaining[client] = new StringMap();
    else g_ClientPurchaseUsesRemaining[client].Clear();
    g_ClientPurchasesLoaded[client] = false;
}

void ClearClientBonusPointsCache(int client)
{
    if (client <= 0 || client > MaxClients) return;
    Store_InvalidateBalanceLoad(client);
    g_ClientBonusPoints[client] = 0;
    g_ClientBonusPointsLoaded[client] = false;
    g_ClientBonusPointsPending[client] = false;
}

void ClearClientStoreCache(int client)
{
    if (client > 0 && client <= MaxClients) g_ClientShopDetailItem[client][0] = '\0';
    ClearClientPurchaseCache(client);
    ClearClientBonusPointsCache(client);
}

bool GetClientSteamId64(int client, char[] steamId, int maxlen)
{
    if (maxlen <= 0) return false;
    steamId[0] = '\0';
    return IsClientAuthorizedHuman(client) && Kogasa_GetClientSteamId64(client, steamId, maxlen, true);
}

bool EscapeSql(const char[] input, char[] output, int maxlen)
{
    if (maxlen <= 0) return false;
    output[0] = '\0';
    if (g_Database == null) return false;
    int written;
    return g_Database.Escape(input, output, maxlen, written);
}
