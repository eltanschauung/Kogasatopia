void LoadClientPurchases(int client)
{
    if (!g_DatabaseReady || g_Database == null || !IsClientAuthorizedHuman(client))
    {
        return;
    }

    char steamId[32];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId)))
    {
        return;
    }

    char escapedSteamId[65];
    if (!EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId)))
    {
        LogError("[bonuspoints_transactions] Failed to escape SteamID64 for client %d.", client);
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(steamId);

    char query[384];
    Format(query, sizeof(query),
        "SELECT item_key, price_paid, expires_at, uses_remaining FROM %s WHERE steamid64 = '%s' AND (expires_at = 0 OR expires_at > %d) AND uses_remaining != 0",
        BP_TRANS_TABLE,
        escapedSteamId,
        GetTime());
    g_Database.Query(SQL_OnClientPurchasesLoaded, query, pack);
}

void LoadClientBonusPoints(int client)
{
    if (!g_DatabaseReady || g_Database == null || !IsClientAuthorizedHuman(client) || g_ClientBonusPointsPending[client])
    {
        return;
    }

    char steamId[32];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId)))
    {
        return;
    }

    char escapedSteamId[65];
    if (!EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId)))
    {
        LogError("[points_store] Failed to escape SteamID64 for bonus-point load for client %d.", client);
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(steamId);

    g_ClientBonusPointsPending[client] = true;

    char query[256];
    Format(query, sizeof(query),
        "SELECT balance FROM %s WHERE steamid64 = '%s'",
        BP_BALANCE_TABLE,
        escapedSteamId);
    g_Database.Query(SQL_OnClientBonusPointsLoaded, query, pack);
}

public void SQL_OnClientPurchasesLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    char expectedSteamId[32];
    pack.ReadString(expectedSteamId, sizeof(expectedSteamId));
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

    g_ClientPurchases[client].Clear();
    g_ClientPurchaseExpiresAt[client].Clear();
    g_ClientPurchaseUsesRemaining[client].Clear();

    if (error[0] != '\0')
    {
        LogError("[bonuspoints_transactions] Failed to load purchases for %s: %s", expectedSteamId, error);
        g_ClientPurchasesLoaded[client] = false;
        return;
    }

    if (results != null)
    {
        char itemKey[BP_TRANS_ITEM_KEY_MAX];
        while (results.FetchRow())
        {
            results.FetchString(0, itemKey, sizeof(itemKey));
            int pricePaid = results.FetchInt(1);
            int expiresAt = results.FetchInt(2);
            int usesRemaining = results.FetchInt(3);
            int configuredUses = GetConfiguredItemUses(itemKey);
            if (configuredUses > 0 && usesRemaining == BP_PURCHASE_UNLIMITED_USES)
            {
                usesRemaining = configuredUses;
                SavePurchaseUsesRemaining(client, itemKey, usesRemaining);
            }
            if (pricePaid > 0 && usesRemaining != 0 && (expiresAt == BP_PURCHASE_PERMANENT || expiresAt > GetTime()))
            {
                g_ClientPurchases[client].SetValue(itemKey, pricePaid);
                g_ClientPurchaseExpiresAt[client].SetValue(itemKey, expiresAt);
                g_ClientPurchaseUsesRemaining[client].SetValue(itemKey, usesRemaining);
            }
        }
    }

    g_ClientPurchasesLoaded[client] = true;
}

public void SQL_OnClientBonusPointsLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    char expectedSteamId[32];
    pack.ReadString(expectedSteamId, sizeof(expectedSteamId));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (!IsClientAuthorizedHuman(client))
    {
        return;
    }

    g_ClientBonusPointsPending[client] = false;

    char currentSteamId[32];
    if (!GetClientSteamId64(client, currentSteamId, sizeof(currentSteamId)) || !StrEqual(currentSteamId, expectedSteamId, false))
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[points_store] Failed to load bonus points for %s: %s", expectedSteamId, error);
        g_ClientBonusPointsLoaded[client] = false;
        return;
    }

    g_ClientBonusPoints[client] = 0;
    if (results != null && results.FetchRow())
    {
        g_ClientBonusPoints[client] = results.FetchInt(0);
        if (g_ClientBonusPoints[client] < 0)
        {
            g_ClientBonusPoints[client] = 0;
        }
    }

    g_ClientBonusPointsLoaded[client] = true;
}

int GetCachedPurchasePrice(int client, const char[] itemKey)
{
    if (client <= 0 || client > MaxClients || g_ClientPurchases[client] == null || g_ClientPurchaseExpiresAt[client] == null || g_ClientPurchaseUsesRemaining[client] == null)
    {
        return 0;
    }

    int pricePaid = 0;
    if (!g_ClientPurchases[client].GetValue(itemKey, pricePaid))
    {
        return 0;
    }

    int expiresAt = BP_PURCHASE_PERMANENT;
    g_ClientPurchaseExpiresAt[client].GetValue(itemKey, expiresAt);
    if (expiresAt != BP_PURCHASE_PERMANENT && expiresAt <= GetTime())
    {
        RemoveCachedPurchase(client, itemKey);
        return 0;
    }

    int usesRemaining = BP_PURCHASE_UNLIMITED_USES;
    g_ClientPurchaseUsesRemaining[client].GetValue(itemKey, usesRemaining);
    if (usesRemaining == 0)
    {
        RemoveCachedPurchase(client, itemKey);
        return 0;
    }

    return pricePaid > 0 ? pricePaid : 0;
}

int GetConfiguredItemUses(const char[] itemKey)
{
    int itemIndex = FindStoreItem(itemKey);
    if (itemIndex == -1)
    {
        return BP_PURCHASE_UNLIMITED_USES;
    }

    return g_ItemUses.Get(itemIndex);
}

int GetCachedPurchaseExpiresAt(int client, const char[] itemKey)
{
    if (GetCachedPurchasePrice(client, itemKey) <= 0)
    {
        return -1;
    }

    int expiresAt = BP_PURCHASE_PERMANENT;
    if (g_ClientPurchaseExpiresAt[client] != null)
    {
        g_ClientPurchaseExpiresAt[client].GetValue(itemKey, expiresAt);
    }

    return expiresAt;
}

int GetCachedPurchaseUsesRemaining(int client, const char[] itemKey)
{
    if (GetCachedPurchasePrice(client, itemKey) <= 0)
    {
        return 0;
    }

    int usesRemaining = BP_PURCHASE_UNLIMITED_USES;
    if (g_ClientPurchaseUsesRemaining[client] != null)
    {
        g_ClientPurchaseUsesRemaining[client].GetValue(itemKey, usesRemaining);
    }

    return usesRemaining;
}

int ConsumeCachedPurchaseUse(int client, const char[] itemKey)
{
    if (GetCachedPurchasePrice(client, itemKey) <= 0)
    {
        return -1;
    }

    int usesRemaining = BP_PURCHASE_UNLIMITED_USES;
    g_ClientPurchaseUsesRemaining[client].GetValue(itemKey, usesRemaining);
    if (usesRemaining <= 0)
    {
        return -1;
    }

    usesRemaining--;
    if (usesRemaining > 0)
    {
        g_ClientPurchaseUsesRemaining[client].SetValue(itemKey, usesRemaining);
    }
    else
    {
        RemoveCachedPurchase(client, itemKey);
        BroadcastPurchaseRanOut(client, itemKey);
    }

    SavePurchaseUsesRemaining(client, itemKey, usesRemaining);
    return usesRemaining;
}

void BroadcastPurchaseRanOut(int client, const char[] itemKey)
{
    if (!Client_IsHumanInGame(client))
    {
        return;
    }

    char itemName[BP_TRANS_ITEM_NAME_MAX];
    if (!GetStoreItemName(itemKey, itemName, sizeof(itemName)))
    {
        strcopy(itemName, sizeof(itemName), itemKey);
    }

    char prefix[96];
    GetCurrencyPrefix(prefix, sizeof(prefix));

    char displayName[256];
    BuildPurchaseDisplayName(client, displayName, sizeof(displayName));
    CPrintToChatAllEx(client, "%s %s's {gold}%s{default} ran out!", prefix, displayName, itemName);
}

bool GetStoreItemName(const char[] itemKey, char[] itemName, int maxlen)
{
    itemName[0] = '\0';

    int itemIndex = FindStoreItem(itemKey);
    if (itemIndex == -1)
    {
        return false;
    }

    g_ItemNames.GetString(itemIndex, itemName, maxlen);
    return itemName[0] != '\0';
}

void RemoveCachedPurchase(int client, const char[] itemKey)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    if (g_ClientPurchases[client] != null)
    {
        g_ClientPurchases[client].Remove(itemKey);
    }
    if (g_ClientPurchaseExpiresAt[client] != null)
    {
        g_ClientPurchaseExpiresAt[client].Remove(itemKey);
    }
    if (g_ClientPurchaseUsesRemaining[client] != null)
    {
        g_ClientPurchaseUsesRemaining[client].Remove(itemKey);
    }
}

void SavePurchaseUsesRemaining(int client, const char[] itemKey, int usesRemaining)
{
    if (g_Database == null || client <= 0 || client > MaxClients)
    {
        return;
    }

    char steamId[32];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId)))
    {
        return;
    }

    char escapedSteamId[65];
    char escapedItemKey[(BP_TRANS_ITEM_KEY_MAX * 2) + 1];
    if (!EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId)) || !EscapeSql(itemKey, escapedItemKey, sizeof(escapedItemKey)))
    {
        LogError("[points_store] Failed to escape purchase-use update for client %d.", client);
        return;
    }

    char query[384];
    Format(query, sizeof(query),
        "UPDATE %s SET uses_remaining = %d WHERE steamid64 = '%s' AND item_key = '%s'",
        BP_TRANS_TABLE,
        usesRemaining,
        escapedSteamId,
        escapedItemKey);
    g_Database.Query(SQL_OnPurchaseUsesUpdated, query);
}

public void SQL_OnPurchaseUsesUpdated(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[points_store] Failed to update purchase uses: %s", error);
    }
}

