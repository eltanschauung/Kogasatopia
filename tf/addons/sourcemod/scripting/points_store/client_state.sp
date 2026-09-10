// A query owns its DataPack until its callback, even after a cache is reset.
// The handle is also an unambiguous request token: invalidation forgets it;
// it must never delete a pack which an outstanding SQL callback still owns.
DataPack g_StorePurchaseLoad[MAXPLAYERS + 1];
DataPack g_StoreBalanceLoad[MAXPLAYERS + 1];
bool g_StorePurchaseReload[MAXPLAYERS + 1];
bool g_StoreBalanceReload[MAXPLAYERS + 1];
int g_StorePurchaseRevision[MAXPLAYERS + 1];

void Store_InvalidatePurchaseLoad(int client)
{
    g_StorePurchaseLoad[client] = null;
    g_StorePurchaseReload[client] = false;
    g_StorePurchaseRevision[client]++;
    Store_ClearPendingPurchaseReceipts(client);
}

void Store_InvalidateBalanceLoad(int client)
{
    g_StoreBalanceLoad[client] = null;
    g_StoreBalanceReload[client] = false;
    g_ClientBonusPointsPending[client] = false;
}

void Store_MarkPurchasesChanged(int client)
{
    g_StorePurchaseRevision[client]++;
}

bool Store_IsCurrentConnection(Database db)
{
    // Query callbacks receive a different Handle to the connection, not g_Database.
    return db != null && g_Database != null && g_DatabaseReady
        && g_Database.IsSameConnection(db);
}

void LoadClientPurchases(int client)
{
    if (!g_DatabaseReady || g_Database == null || !IsClientAuthorizedHuman(client)) return;
    if (g_StorePurchaseLoad[client] != null)
    {
        // Bound command/reconnect bursts to one outstanding read and one follow-up.
        g_StorePurchaseReload[client] = true;
        return;
    }
    char steamId[32], escapedSteamId[65];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId))) return;
    if (!EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId)))
    {
        LogError("[points_store] Failed to escape SteamID64 for client %d.", client);
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientSerial(client));
    pack.WriteCell(g_StorePurchaseRevision[client]);
    pack.WriteString(steamId);
    g_StorePurchaseLoad[client] = pack;
    g_StorePurchaseReload[client] = false;
    char query[384];
    FormatEx(query, sizeof(query),
        "SELECT item_key, price_paid, expires_at, uses_remaining FROM %s WHERE steamid64 = '%s' AND (expires_at = 0 OR expires_at > %d) AND uses_remaining != 0",
        BP_TRANS_TABLE, escapedSteamId, GetTime());
    g_Database.Query(SQL_OnClientPurchasesLoaded, query, pack);
}

void LoadClientBonusPoints(int client)
{
    if (!g_DatabaseReady || g_Database == null || !IsClientAuthorizedHuman(client)) return;
    if (g_StoreBalanceLoad[client] != null)
    {
        g_StoreBalanceReload[client] = true;
        return;
    }
    char steamId[32], escapedSteamId[65];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId))) return;
    if (!EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId)))
    {
        LogError("[points_store] Failed to escape SteamID64 for balance load for client %d.", client);
        return;
    }
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientSerial(client));
    pack.WriteCell(g_ClientBonusPoints[client]);
    pack.WriteCell(g_ClientBonusPointsLoaded[client]);
    pack.WriteString(steamId);
    g_StoreBalanceLoad[client] = pack;
    g_StoreBalanceReload[client] = false;
    g_ClientBonusPointsPending[client] = true;
    char query[256];
    FormatEx(query, sizeof(query), "SELECT balance FROM %s WHERE steamid64 = '%s'",
        BP_BALANCE_TABLE, escapedSteamId);
    g_Database.Query(SQL_OnClientBonusPointsLoaded, query, pack);
}

public void SQL_OnClientPurchasesLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int serial = pack.ReadCell();
    int revision = pack.ReadCell();
    char expectedSteamId[32];
    pack.ReadString(expectedSteamId, sizeof(expectedSteamId));
    int client = GetClientFromSerial(serial);
    bool ownsRequest = client > 0 && g_StorePurchaseLoad[client] == pack;
    delete pack;
    if (!ownsRequest) return;

    bool reload = g_StorePurchaseReload[client];
    g_StorePurchaseLoad[client] = null;
    g_StorePurchaseReload[client] = false;
    char currentSteamId[32];
    if (!GetClientSteamId64(client, currentSteamId, sizeof(currentSteamId))
        || !StrEqual(currentSteamId, expectedSteamId)) return;
    if (!Store_IsCurrentConnection(db))
    {
        LoadClientPurchases(client);
        return;
    }
    if (error[0] != '\0' || results == null)
    {
        // A failed refresh must not revoke existing ownership or publish an empty cache.
        LogError("[points_store] Failed to load purchases for %s: %s", expectedSteamId,
            error[0] != '\0' ? error : "missing result set");
        return;
    }
    if (revision != g_StorePurchaseRevision[client])
    {
        // A use was consumed or a purchase was made after SELECT was queued.
        // Read again behind those writes instead of restoring stale ownership/uses.
        LoadClientPurchases(client);
        return;
    }

    StringMap prices = new StringMap();
    StringMap expirations = new StringMap();
    StringMap uses = new StringMap();
    int now = GetTime();
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
        if (itemKey[0] != '\0' && pricePaid > 0 && usesRemaining != 0
            && (expiresAt == BP_PURCHASE_PERMANENT || expiresAt > now))
        {
            prices.SetValue(itemKey, pricePaid);
            expirations.SetValue(itemKey, expiresAt);
            uses.SetValue(itemKey, usesRemaining);
        }
    }
    delete g_ClientPurchases[client];
    delete g_ClientPurchaseExpiresAt[client];
    delete g_ClientPurchaseUsesRemaining[client];
    g_ClientPurchases[client] = prices;
    g_ClientPurchaseExpiresAt[client] = expirations;
    g_ClientPurchaseUsesRemaining[client] = uses;
    Store_MarkPurchasesChanged(client);
    g_ClientPurchasesLoaded[client] = true;
    if (reload) LoadClientPurchases(client);
}

public void SQL_OnClientBonusPointsLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int serial = pack.ReadCell();
    int requestedBalance = pack.ReadCell();
    bool wasLoaded = view_as<bool>(pack.ReadCell());
    char expectedSteamId[32];
    pack.ReadString(expectedSteamId, sizeof(expectedSteamId));
    int client = GetClientFromSerial(serial);
    bool ownsRequest = client > 0 && g_StoreBalanceLoad[client] == pack;
    delete pack;
    if (!ownsRequest) return;

    bool reload = g_StoreBalanceReload[client];
    g_StoreBalanceLoad[client] = null;
    g_StoreBalanceReload[client] = false;
    g_ClientBonusPointsPending[client] = false;
    char currentSteamId[32];
    if (!GetClientSteamId64(client, currentSteamId, sizeof(currentSteamId))
        || !StrEqual(currentSteamId, expectedSteamId)) return;
    if (!Store_IsCurrentConnection(db))
    {
        LoadClientBonusPoints(client);
        return;
    }
    if (error[0] != '\0' || results == null)
    {
        LogError("[points_store] Failed to load balance for %s: %s", expectedSteamId,
            error[0] != '\0' ? error : "missing result set");
        return;
    }
    if (g_ClientBonusPoints[client] != requestedBalance
        || g_ClientBonusPointsLoaded[client] != wasLoaded)
    {
        // Do not replace a balance mutated by another callback while SELECT ran.
        // This is a local snapshot fence, not a multi-server transaction protocol.
        LoadClientBonusPoints(client);
        return;
    }
    int balance = results.FetchRow() ? results.FetchInt(0) : 0;
    g_ClientBonusPoints[client] = balance > 0 ? balance : 0;
    g_ClientBonusPointsLoaded[client] = true;
    if (reload) LoadClientBonusPoints(client);
}

int GetCachedPurchasePrice(int client, const char[] itemKey)
{
    if (client <= 0 || client > MaxClients || g_ClientPurchases[client] == null
        || g_ClientPurchaseExpiresAt[client] == null || g_ClientPurchaseUsesRemaining[client] == null)
    {
        return 0;
    }
    int pricePaid;
    if (!g_ClientPurchases[client].GetValue(itemKey, pricePaid)) return 0;
    int expiresAt = BP_PURCHASE_PERMANENT;
    int usesRemaining = BP_PURCHASE_UNLIMITED_USES;
    g_ClientPurchaseExpiresAt[client].GetValue(itemKey, expiresAt);
    g_ClientPurchaseUsesRemaining[client].GetValue(itemKey, usesRemaining);
    if ((expiresAt != BP_PURCHASE_PERMANENT && expiresAt <= GetTime()) || usesRemaining == 0)
    {
        RemoveCachedPurchase(client, itemKey);
        return 0;
    }
    return pricePaid > 0 ? pricePaid : 0;
}

int GetConfiguredItemUses(const char[] itemKey)
{
    int itemIndex = FindStoreItem(itemKey);
    return itemIndex == -1 ? BP_PURCHASE_UNLIMITED_USES : g_ItemUses.Get(itemIndex);
}

int GetCachedPurchaseExpiresAt(int client, const char[] itemKey)
{
    if (GetCachedPurchasePrice(client, itemKey) <= 0) return -1;
    int expiresAt = BP_PURCHASE_PERMANENT;
    g_ClientPurchaseExpiresAt[client].GetValue(itemKey, expiresAt);
    return expiresAt;
}

int GetCachedPurchaseUsesRemaining(int client, const char[] itemKey)
{
    if (GetCachedPurchasePrice(client, itemKey) <= 0) return 0;
    int usesRemaining = BP_PURCHASE_UNLIMITED_USES;
    g_ClientPurchaseUsesRemaining[client].GetValue(itemKey, usesRemaining);
    return usesRemaining;
}

int ConsumeCachedPurchaseUse(int client, const char[] itemKey)
{
    if (!IsClientAuthorizedHuman(client) || !g_DatabaseReady || g_Database == null
        || GetCachedPurchasePrice(client, itemKey) <= 0) return -1;
    int usesRemaining = BP_PURCHASE_UNLIMITED_USES;
    g_ClientPurchaseUsesRemaining[client].GetValue(itemKey, usesRemaining);
    if (usesRemaining <= 0) return -1;

    usesRemaining--;
    Store_MarkPurchasesChanged(client);
    if (usesRemaining > 0)
    {
        g_ClientPurchaseUsesRemaining[client].SetValue(itemKey, usesRemaining);
    }
    else
    {
        RemoveCachedPurchase(client, itemKey);
    }
    // Queue persistence before a chat/native call can re-enter and repurchase the item.
    SavePurchaseUsesRemaining(client, itemKey, usesRemaining);
    if (usesRemaining == 0) BroadcastPurchaseRanOut(client, itemKey);
    return usesRemaining;
}

void BroadcastPurchaseRanOut(int client, const char[] itemKey)
{
    if (!Client_IsHumanInGame(client)) return;
    char itemName[BP_TRANS_ITEM_NAME_MAX];
    if (!GetStoreItemName(itemKey, itemName, sizeof(itemName))) strcopy(itemName, sizeof(itemName), itemKey);
    char prefix[96], displayName[256];
    GetCurrencyPrefix(prefix, sizeof(prefix));
    BuildPurchaseDisplayName(client, displayName, sizeof(displayName));
    if (Client_IsHumanInGame(client))
    {
        CPrintToChatAllEx(client, "%s %s's {gold}%s{default} ran out!", prefix, displayName, itemName);
    }
}

bool GetStoreItemName(const char[] itemKey, char[] itemName, int maxlen)
{
    if (maxlen <= 0) return false;
    itemName[0] = '\0';
    int itemIndex = FindStoreItem(itemKey);
    if (itemIndex == -1) return false;
    g_ItemNames.GetString(itemIndex, itemName, maxlen);
    return itemName[0] != '\0';
}

void RemoveCachedPurchase(int client, const char[] itemKey)
{
    if (client <= 0 || client > MaxClients) return;
    bool changed = false;
    if (g_ClientPurchases[client] != null) changed = g_ClientPurchases[client].Remove(itemKey);
    if (g_ClientPurchaseExpiresAt[client] != null) g_ClientPurchaseExpiresAt[client].Remove(itemKey);
    if (g_ClientPurchaseUsesRemaining[client] != null) g_ClientPurchaseUsesRemaining[client].Remove(itemKey);
    if (changed) Store_MarkPurchasesChanged(client);
}

void SavePurchaseUsesRemaining(int client, const char[] itemKey, int usesRemaining)
{
    if (!g_DatabaseReady || g_Database == null || !IsClientAuthorizedHuman(client)) return;
    char steamId[32], escapedSteamId[65], escapedItemKey[(BP_TRANS_ITEM_KEY_MAX * 2) + 1];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId))) return;
    if (!EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId))
        || !EscapeSql(itemKey, escapedItemKey, sizeof(escapedItemKey)))
    {
        LogError("[points_store] Failed to escape purchase-use update for client %d.", client);
        return;
    }
    char query[384];
    FormatEx(query, sizeof(query), "UPDATE %s SET uses_remaining = %d WHERE steamid64 = '%s' AND item_key = '%s'",
        BP_TRANS_TABLE, usesRemaining, escapedSteamId, escapedItemKey);
    g_Database.Query(SQL_OnPurchaseUsesUpdated, query);
}

public void SQL_OnPurchaseUsesUpdated(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0') LogError("[points_store] Failed to update purchase uses: %s", error);
}
