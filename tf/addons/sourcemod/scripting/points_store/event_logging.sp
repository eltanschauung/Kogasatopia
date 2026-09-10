void SanitizeLogField(char[] value, int maxlen)
{
    ReplaceString(value, maxlen, "|", "/", false);
    ReplaceString(value, maxlen, "\r", " ", false);
    ReplaceString(value, maxlen, "\n", " ", false);
    ReplaceString(value, maxlen, "\t", " ", false);
    ReplaceString(value, maxlen, "\"", "'", false);
}

void GetClientLogIdentity(int client, char[] steamId, int steamLen, char[] name, int nameLen)
{
    steamId[0] = '\0';
    name[0] = '\0';

    if (client <= 0 || client > MaxClients || !IsClientConnected(client))
    {
        strcopy(steamId, steamLen, "none");
        strcopy(name, nameLen, "none");
        return;
    }

    if (!Kogasa_GetClientSteamId64(client, steamId, steamLen, true))
    {
        strcopy(steamId, steamLen, "unknown");
    }

    if (!GetClientName(client, name, nameLen) || name[0] == '\0')
    {
        strcopy(name, nameLen, "unknown");
    }

    SanitizeLogField(steamId, steamLen);
    SanitizeLogField(name, nameLen);
}

void GetClientLogClass(int client, char[] className, int maxlen)
{
    strcopy(className, maxlen, "none");

    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
    {
        return;
    }

    TF2Classes_GetKey(TF2_GetPlayerClass(client), className, maxlen, "unknown");

    SanitizeLogField(className, maxlen);
}

bool IsBonusPointsNumericTargetType(const char[] type)
{
    return StrEqual(type, "killstreak", false)
        || StrEqual(type, "killstreak_5_10", false)
        || StrEqual(type, "killstreak_above_10", false)
        || StrEqual(type, "killstreak_end", false)
        || StrEqual(type, "killstreak_end_7_14", false)
        || StrEqual(type, "killstreak_end_15_19", false)
        || StrEqual(type, "killstreak_end_20_plus", false)
        || StrEqual(type, "multikill", false)
        || StrEqual(type, "multikill_3_4", false)
        || StrEqual(type, "multikill_5_plus", false)
        || StrEqual(type, "medic_assists", false)
        || StrEqual(type, "medic_high_uber_kill", false);
}

bool IsPointsEventLoggingEnabled()
{
    return g_CvarEventLogging != null && g_CvarEventLogging.BoolValue;
}

bool IsWelfareEnabled()
{
    return g_CvarEnableWelfare != null && g_CvarEnableWelfare.BoolValue;
}

int GetWelfareMinPlayers()
{
    if (g_CvarWelfareMinPlayers == null)
    {
        return 0;
    }

    int minPlayers = g_CvarWelfareMinPlayers.IntValue;
    return minPlayers > 0 ? minPlayers : 0;
}

int GetWelfareHumanPlayerCount()
{
    int count = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (Client_IsHumanInGame(client))
        {
            count++;
        }
    }
    return count;
}

void QueuePointsStoreEvent(const char[] message)
{
    char eventName[64];
    GetPointsStoreEventName(message, eventName, sizeof(eventName));
    PluginStats_Record(eventName, message);
}

void GetPointsStoreEventName(const char[] message, char[] output, int maxlen)
{
    int read = strncmp(message, "event=", 6, false) == 0 ? 6 : 0;
    int write = 0;
    while (message[read] && message[read] != '|' && write < maxlen - 1)
    {
        char c = message[read++];
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_')
        {
            output[write++] = c;
        }
    }
    output[write] = '\0';
    if (!output[0])
    {
        strcopy(output, maxlen, "points_store_event");
    }
}

void LogPointsStoreEvent(const char[] format, any ...)
{
    if (!IsPointsEventLoggingEnabled())
    {
        return;
    }

    char message[BP_EVENT_LOG_LINE_MAX];
    VFormat(message, sizeof(message), format, 2);
    QueuePointsStoreEvent(message);
}

void LogBonusPointsDelta(int client, int delta, int balanceBefore, int balanceAfter, const char[] type, int target, bool playSound, bool chatAlert, float randomChance, bool saveQueued, int perMap = 0, int perMapUsed = 0, const char[] targetNameSnapshot = "")
{
    if (!IsPointsEventLoggingEnabled())
    {
        return;
    }

    char steamId[32];
    char clientName[MAX_NAME_LENGTH];
    char clientClass[16];
    GetClientLogIdentity(client, steamId, sizeof(steamId), clientName, sizeof(clientName));
    GetClientLogClass(client, clientClass, sizeof(clientClass));

    char safeType[64];
    strcopy(safeType, sizeof(safeType), type);
    SanitizeLogField(safeType, sizeof(safeType));

    int targetValue = target;
    int targetClient = 0;
    char targetSteamId[32];
    char targetName[MAX_NAME_LENGTH];
    char targetClass[16];
    strcopy(targetSteamId, sizeof(targetSteamId), "none");
    strcopy(targetName, sizeof(targetName), "none");
    strcopy(targetClass, sizeof(targetClass), "none");

    if (!IsBonusPointsNumericTargetType(type) && target > 0 && target <= MaxClients && IsClientConnected(target))
    {
        targetClient = target;
        GetClientLogIdentity(target, targetSteamId, sizeof(targetSteamId), targetName, sizeof(targetName));
        GetClientLogClass(target, targetClass, sizeof(targetClass));
    }
    else if (targetNameSnapshot[0] != '\0')
    {
        strcopy(targetName, sizeof(targetName), targetNameSnapshot);
        SanitizeLogField(targetName, sizeof(targetName));
    }

    LogPointsStoreEvent(
        "event=bp_delta|time=%d|client=%d|steamid64=%s|name=\"%s\"|class=%s|delta=%d|balance_before=%d|balance_after=%d|type=%s|target_value=%d|target_client=%d|target_steamid64=%s|target_name=\"%s\"|target_class=%s|play_sound=%d|chat_alert=%d|random_chance=%.3f|save_queued=%d|per_map=%d|per_map_used=%d",
        GetTime(),
        client,
        steamId,
        clientName,
        clientClass,
        delta,
        balanceBefore,
        balanceAfter,
        safeType,
        targetValue,
        targetClient,
        targetSteamId,
        targetName,
        targetClass,
        playSound ? 1 : 0,
        chatAlert ? 1 : 0,
        randomChance,
        saveQueued ? 1 : 0,
        perMap,
        perMapUsed);
}

void LogBonusPointsRejected(const char[] reason, int client, int points, const char[] type, int target, int balance, float randomChance, float randomRoll, int perMap = 0, int perMapUsed = 0)
{
    if (!IsPointsEventLoggingEnabled())
    {
        return;
    }

    char steamId[32];
    char clientName[MAX_NAME_LENGTH];
    char clientClass[16];
    GetClientLogIdentity(client, steamId, sizeof(steamId), clientName, sizeof(clientName));
    GetClientLogClass(client, clientClass, sizeof(clientClass));

    char safeReason[64];
    char safeType[64];
    strcopy(safeReason, sizeof(safeReason), reason);
    strcopy(safeType, sizeof(safeType), type);
    SanitizeLogField(safeReason, sizeof(safeReason));
    SanitizeLogField(safeType, sizeof(safeType));

    LogPointsStoreEvent(
        "event=bp_rejected|time=%d|reason=%s|client=%d|steamid64=%s|name=\"%s\"|class=%s|requested_delta=%d|balance=%d|type=%s|target_value=%d|random_chance=%.3f|random_roll=%.3f|per_map=%d|per_map_used=%d",
        GetTime(),
        safeReason,
        client,
        steamId,
        clientName,
        clientClass,
        points,
        balance,
        safeType,
        target,
        randomChance,
        randomRoll,
        perMap,
        perMapUsed);
}

void LogBonusPointsDeferredQueue(int client, int points, const char[] type, int target, float delay, bool playSound, bool chatAlert, float randomChance, int perMap = 0)
{
    if (!IsPointsEventLoggingEnabled())
    {
        return;
    }

    char steamId[32];
    char clientName[MAX_NAME_LENGTH];
    char clientClass[16];
    GetClientLogIdentity(client, steamId, sizeof(steamId), clientName, sizeof(clientName));
    GetClientLogClass(client, clientClass, sizeof(clientClass));

    char safeType[64];
    strcopy(safeType, sizeof(safeType), type);
    SanitizeLogField(safeType, sizeof(safeType));

    LogPointsStoreEvent(
        "event=bp_deferred_queue|time=%d|client=%d|steamid64=%s|name=\"%s\"|class=%s|requested_delta=%d|type=%s|target_value=%d|delay=%.2f|play_sound=%d|chat_alert=%d|random_chance=%.3f|per_map=%d",
        GetTime(),
        client,
        steamId,
        clientName,
        clientClass,
        points,
        safeType,
        target,
        delay,
        playSound ? 1 : 0,
        chatAlert ? 1 : 0,
        randomChance,
        perMap);
}

void LogPurchaseEvent(const char[] eventName, const char[] reason, int client, const char[] itemKey, const char[] itemName, int price, int balance)
{
    if (!IsPointsEventLoggingEnabled())
    {
        return;
    }

    char steamId[32];
    char clientName[MAX_NAME_LENGTH];
    char clientClass[16];
    GetClientLogIdentity(client, steamId, sizeof(steamId), clientName, sizeof(clientName));
    GetClientLogClass(client, clientClass, sizeof(clientClass));

    char safeEvent[64];
    char safeReason[64];
    char safeItemKey[BP_TRANS_ITEM_KEY_MAX];
    char safeItemName[BP_TRANS_ITEM_NAME_MAX];
    strcopy(safeEvent, sizeof(safeEvent), eventName);
    strcopy(safeReason, sizeof(safeReason), reason);
    strcopy(safeItemKey, sizeof(safeItemKey), itemKey);
    strcopy(safeItemName, sizeof(safeItemName), itemName);
    SanitizeLogField(safeEvent, sizeof(safeEvent));
    SanitizeLogField(safeReason, sizeof(safeReason));
    SanitizeLogField(safeItemKey, sizeof(safeItemKey));
    SanitizeLogField(safeItemName, sizeof(safeItemName));

    LogPointsStoreEvent(
        "event=%s|time=%d|reason=%s|client=%d|steamid64=%s|name=\"%s\"|class=%s|item_key=%s|item_name=\"%s\"|price=%d|balance=%d",
        safeEvent,
        GetTime(),
        safeReason,
        client,
        steamId,
        clientName,
        clientClass,
        safeItemKey,
        safeItemName,
        price,
        balance);
}

void LogTransferEvent(const char[] eventName, const char[] reason, int sender, int target, int amount)
{
    if (!IsPointsEventLoggingEnabled())
    {
        return;
    }

    char senderSteamId[32];
    char senderName[MAX_NAME_LENGTH];
    char senderClass[16];
    char targetSteamId[32];
    char targetName[MAX_NAME_LENGTH];
    char targetClass[16];
    GetClientLogIdentity(sender, senderSteamId, sizeof(senderSteamId), senderName, sizeof(senderName));
    GetClientLogClass(sender, senderClass, sizeof(senderClass));
    GetClientLogIdentity(target, targetSteamId, sizeof(targetSteamId), targetName, sizeof(targetName));
    GetClientLogClass(target, targetClass, sizeof(targetClass));

    char safeEvent[64];
    char safeReason[64];
    strcopy(safeEvent, sizeof(safeEvent), eventName);
    strcopy(safeReason, sizeof(safeReason), reason);
    SanitizeLogField(safeEvent, sizeof(safeEvent));
    SanitizeLogField(safeReason, sizeof(safeReason));

    LogPointsStoreEvent(
        "event=%s|time=%d|reason=%s|sender=%d|sender_steamid64=%s|sender_name=\"%s\"|sender_class=%s|target=%d|target_steamid64=%s|target_name=\"%s\"|target_class=%s|amount=%d|sender_balance=%d|target_balance=%d",
        safeEvent,
        GetTime(),
        safeReason,
        sender,
        senderSteamId,
        senderName,
        senderClass,
        target,
        targetSteamId,
        targetName,
        targetClass,
        amount,
        GetCachedBonusPoints(sender),
        GetCachedBonusPoints(target));
}

