public any Native_PointsStore_AreBonusPointsLoaded(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    return AreBonusPointsReady(client);
}

public any Native_PointsStore_GetBonusPoints(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    return GetCachedBonusPoints(client);
}

public any Native_PointsStore_ApplyBonusPoints(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char rewardId[BP_REWARD_ID_MAX];
    GetNativeString(2, rewardId, sizeof(rewardId));
    TrimString(rewardId);

    RewardDefinition reward;
    if (!GetRewardDefinition(rewardId, reward))
    {
        return false;
    }

    bool playSound = (numParams >= 3) ? view_as<bool>(GetNativeCell(3)) : true;
    bool chatAlert = (numParams >= 4) ? view_as<bool>(GetNativeCell(4)) : true;
    float randomChance = (numParams >= 5) ? view_as<float>(GetNativeCell(5)) : 1.0;
    int target = (numParams >= 6) ? GetNativeCell(6) : 0;
    float delay = (numParams >= 7) ? view_as<float>(GetNativeCell(7)) : 3.0;
    return ApplyBonusPoints(
        client,
        reward.amount,
        playSound,
        chatAlert,
        randomChance,
        reward.id,
        target,
        delay,
        reward.perMapLimit,
        true);
}

public any Native_PointsStore_ApplyBonusPointsSteamId(Handle plugin, int numParams)
{
    char steamId[32];
    GetNativeString(1, steamId, sizeof(steamId));
    TrimString(steamId);

    char rewardId[BP_REWARD_ID_MAX];
    GetNativeString(2, rewardId, sizeof(rewardId));
    TrimString(rewardId);

    RewardDefinition reward;
    if (!GetRewardDefinition(rewardId, reward))
    {
        return false;
    }

    bool playSound = (numParams >= 3) ? view_as<bool>(GetNativeCell(3)) : true;
    bool chatAlert = (numParams >= 4) ? view_as<bool>(GetNativeCell(4)) : true;
    return ApplyBonusPointsSteamId(
        steamId,
        reward.amount,
        playSound,
        chatAlert,
        reward.id,
        reward.perMapLimit,
        true);
}

public any Native_PointsStore_RefundBonusPoints(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int points = GetNativeCell(2);
    char type[64];
    strcopy(type, sizeof(type), "api_refund");
    if (numParams >= 3)
    {
        GetNativeString(3, type, sizeof(type));
        TrimString(type);
    }
    return points > 0 && ApplyBonusPoints(client, points, false, false, 1.0, type, 0, 0.0);
}

bool GetNativeRewardDefinition(int parameter, RewardDefinition definition)
{
    char rewardId[BP_REWARD_ID_MAX];
    GetNativeString(parameter, rewardId, sizeof(rewardId));
    TrimString(rewardId);
    return GetRewardDefinition(rewardId, definition);
}

public any Native_PointsStore_GetRewardAmount(Handle plugin, int numParams)
{
    RewardDefinition reward;
    return GetNativeRewardDefinition(1, reward) ? reward.amount : 0;
}

public any Native_PointsStore_GetRewardPerMapLimit(Handle plugin, int numParams)
{
    RewardDefinition reward;
    return GetNativeRewardDefinition(1, reward) ? reward.perMapLimit : -1;
}

public any Native_PointsStore_GetRewardLongName(Handle plugin, int numParams)
{
    RewardDefinition reward;
    return GetNativeRewardDefinition(1, reward)
        && SetNativeString(2, reward.longName, GetNativeCell(3), true) == SP_ERROR_NONE;
}

public any Native_PointsStore_GetRewardShortDescription(Handle plugin, int numParams)
{
    RewardDefinition reward;
    return GetNativeRewardDefinition(1, reward)
        && SetNativeString(2, reward.shortDescription, GetNativeCell(3), true) == SP_ERROR_NONE;
}

public any Native_PointsStore_GetRewardLongDescription(Handle plugin, int numParams)
{
    RewardDefinition reward;
    return GetNativeRewardDefinition(1, reward)
        && SetNativeString(2, reward.longDescription, GetNativeCell(3), true) == SP_ERROR_NONE;
}

public any Native_PointsStore_RefundBonusPointsSteamId(Handle plugin, int numParams)
{
    char steamId[32];
    GetNativeString(1, steamId, sizeof(steamId));
    TrimString(steamId);
    int points = GetNativeCell(2);
    char type[64];
    strcopy(type, sizeof(type), "api_refund");
    if (numParams >= 3)
    {
        GetNativeString(3, type, sizeof(type));
        TrimString(type);
    }
    return points > 0 && ApplyBonusPointsSteamId(steamId, points, false, false, type);
}

public any Native_PointsStore_ApplyBonusPointsSteamIdOnce(Handle plugin, int numParams)
{
    char steamId[32];
    char awardKey[BP_IDEMPOTENT_KEY_MAX];
    char type[64];
    GetNativeString(1, steamId, sizeof(steamId));
    int amount = GetNativeCell(2);
    GetNativeString(3, awardKey, sizeof(awardKey));
    strcopy(type, sizeof(type), "api_idempotent_award");
    if (numParams >= 4)
    {
        GetNativeString(4, type, sizeof(type));
    }
    TrimString(steamId);
    TrimString(awardKey);
    TrimString(type);

    return QueueIdempotentBonusPointsAward(steamId, amount, awardKey, type);
}

public any Native_PointsStore_SpendBonusPoints(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int points = GetNativeCell(2);
    char type[64];
    BuildCallerSpendType(plugin, type, sizeof(type));
    return SpendBonusPointsWithContext(client, points, type);
}

public any Native_PointsStore_StealBonusPoints(Handle plugin, int numParams)
{
    int victim = GetNativeCell(1);
    int recipient = GetNativeCell(2);
    int points = GetNativeCell(3);

    char type[64];
    type[0] = '\0';
    if (numParams >= 4)
    {
        GetNativeString(4, type, sizeof(type));
        TrimString(type);
    }
    if (type[0] == '\0')
    {
        strcopy(type, sizeof(type), "api_steal");
    }

    return StealBonusPointsWithContext(victim, recipient, points, type);
}

public any Native_PointsStore_AwardMemomanEvent(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char sourceId[64];
    char detailId[64];
    char detailName[128];
    GetNativeString(2, sourceId, sizeof(sourceId));
    if (numParams >= 3)
    {
        GetNativeString(3, detailId, sizeof(detailId));
    }
    if (numParams >= 4)
    {
        GetNativeString(4, detailName, sizeof(detailName));
    }
    TrimString(sourceId);
    TrimString(detailId);
    TrimString(detailName);
    return MemomanEvent_QueueReward(client, sourceId, detailId, detailName);
}

public any Native_PointsStore_HasPurchase(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemKey[BP_TRANS_ITEM_KEY_MAX];
    GetNativeString(2, itemKey, sizeof(itemKey));
    return GetCachedPurchasePrice(client, itemKey) > 0;
}

public any Native_PointsStore_GetPurchasePrice(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemKey[BP_TRANS_ITEM_KEY_MAX];
    GetNativeString(2, itemKey, sizeof(itemKey));
    return GetCachedPurchasePrice(client, itemKey);
}

public any Native_PointsStore_GetPurchaseExpiresAt(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemKey[BP_TRANS_ITEM_KEY_MAX];
    GetNativeString(2, itemKey, sizeof(itemKey));
    return GetCachedPurchaseExpiresAt(client, itemKey);
}

public any Native_PointsStore_GetPurchaseUsesRemaining(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemKey[BP_TRANS_ITEM_KEY_MAX];
    GetNativeString(2, itemKey, sizeof(itemKey));
    return GetCachedPurchaseUsesRemaining(client, itemKey);
}

public any Native_PointsStore_ConsumePurchaseUse(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char itemKey[BP_TRANS_ITEM_KEY_MAX];
    GetNativeString(2, itemKey, sizeof(itemKey));
    return ConsumeCachedPurchaseUse(client, itemKey);
}
