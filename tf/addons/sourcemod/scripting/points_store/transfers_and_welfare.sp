public Action Command_SendBonusPoints(int client, int args)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Handled;
    }

    char prefix[96];
    char currencyLong[BP_CURRENCY_LONG_MAX];
    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyPrefix(prefix, sizeof(prefix));
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
    GetCurrencyColorTag(colorTag, sizeof(colorTag));

    float cooldownRemaining = (GetSendBonusPointsCooldown() > 0.0) ? (g_NextSendAllowedAt[client] - GetEngineTime()) : 0.0;
    if (cooldownRemaining > 0.0)
    {
        CPrintToChat(client, "%s Wait {gold}%d{default} seconds before sending %s again.", prefix, RoundToCeil(cooldownRemaining), currencyLong);
        return Plugin_Handled;
    }

    if (args < 2)
    {
        CPrintToChat(client, "%s Usage: !sendbp <player> <amount>", prefix);
        return Plugin_Handled;
    }

    char targetArg[64];
    GetCmdArg(1, targetArg, sizeof(targetArg));
    TrimString(targetArg);

    int target = FindTarget(client, targetArg, true, false);
    if (target <= 0 || !Client_IsHumanInGame(target))
    {
        CPrintToChat(client, "%s Could not find player '%s'.", prefix, targetArg);
        return Plugin_Handled;
    }

    if (target == client)
    {
        CPrintToChat(client, "%s You cannot send %s to yourself.", prefix, currencyLong);
        return Plugin_Handled;
    }

    char amountArg[32];
    GetCmdArg(2, amountArg, sizeof(amountArg));
    int amount = StringToInt(amountArg);
    if (amount <= 0)
    {
        CPrintToChat(client, "%s Amount must be greater than 0.", prefix);
        return Plugin_Handled;
    }

    if (!AreBonusPointsReady(client))
    {
        LoadClientBonusPoints(client);
        CPrintToChat(client, "%s Your %s are loading. Try again in a moment.", prefix, currencyLong);
        return Plugin_Handled;
    }

    if (!AreBonusPointsReady(target))
    {
        LoadClientBonusPoints(target);
        CPrintToChat(client, "%s %N's %s are loading. Try again in a moment.", prefix, target, currencyLong);
        return Plugin_Handled;
    }

    if (GetCachedBonusPoints(client) < amount)
    {
        char balanceCurrencyShort[BP_CURRENCY_SHORT_MAX];
        GetCurrencyShortLabelForAmount(GetCachedBonusPoints(client), balanceCurrencyShort, sizeof(balanceCurrencyShort));
        CPrintToChat(client, "%s You only have {lightgreen}%i{default} %s.", prefix, GetCachedBonusPoints(client), balanceCurrencyShort);
        return Plugin_Handled;
    }

    if (!ApplyBonusPoints(client, -amount, false, false, 1.0, "transfer_out", target, 0.0))
    {
        CPrintToChat(client, "%s Could not spend your %s.", prefix, currencyLong);
        return Plugin_Handled;
    }

    if (!ApplyBonusPoints(target, amount, false, false, 1.0, "transfer_in", client, 0.0))
    {
        ApplyBonusPoints(client, amount, false, false, 1.0, "transfer_refund", target, 0.0);
        LogTransferEvent("transfer_failed", "target_credit_failed", client, target, amount);
        CPrintToChat(client, "%s Could not give %s to %N.", prefix, currencyLong, target);
        return Plugin_Handled;
    }

    PlayBonusPointsSound(0, true);
    LogTransferEvent("transfer_success", "ok", client, target, amount);
    StartSendBonusPointsCooldown(client);

    char senderDisplay[256];
    char targetDisplay[256];
    char sentCurrencyShort[BP_CURRENCY_SHORT_MAX];
    BuildPurchaseDisplayName(client, senderDisplay, sizeof(senderDisplay));
    BuildPurchaseDisplayName(target, targetDisplay, sizeof(targetDisplay));
    GetCurrencyShortLabelForAmount(amount, sentCurrencyShort, sizeof(sentCurrencyShort));

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!Client_IsHumanInGame(i))
        {
            continue;
        }

        CPrintToChatEx(i, client, "%s %s sent %s %i %s%s{default}!", prefix, senderDisplay, targetDisplay, amount, colorTag, sentCurrencyShort);
    }
    return Plugin_Handled;
}

public Action CommandListener_WelfareAlias(int client, const char[] command, int argc)
{
    return Command_Welfare(client, argc);
}

public Action CommandListener_WelfareChatAlias(int client, const char[] command, int argc)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Continue;
    }

    char text[32];
    GetCmdArgString(text, sizeof(text));
    TrimString(text);
    StripQuotes(text);
    TrimString(text);

    if (StrEqual(text, "gibs", false) || StrEqual(text, "welfare", false) || StrEqual(text, "ebt", false))
    {
        return Command_Welfare(client, 0);
    }

    return Plugin_Continue;
}

public Action Command_Welfare(int client, int args)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Handled;
    }

    char prefix[96];
    char currencyLong[BP_CURRENCY_LONG_MAX];
    GetCurrencyPrefix(prefix, sizeof(prefix));
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));

    if (!IsWelfareEnabled())
    {
        CPrintToChat(client, "%s Welfare is currently disabled", prefix);
        return Plugin_Handled;
    }

    int minPlayers = GetWelfareMinPlayers();
    if (minPlayers > 0 && GetWelfareHumanPlayerCount() < minPlayers)
    {
        CPrintToChat(client, "%s Minimum playercount for welfare collection is {gold}%d", prefix, minPlayers);
        return Plugin_Handled;
    }

    if (!AreBonusPointsReady(client))
    {
        LoadClientBonusPoints(client);
        CPrintToChat(client, "%s Your %s are loading. Try again in a moment.", prefix, currencyLong);
        return Plugin_Handled;
    }

    if (GetPerMapAwardCount(client, "welfare") >= 1)
    {
        CPrintToChat(client, "%s You already collected {gold}!welfare{default} this map.", prefix);
        return Plugin_Handled;
    }

    if (!g_EconomyStateLoaded)
    {
        LoadEconomyState();
        CPrintToChat(client, "%s Welfare pool is loading. Try again in a moment.", prefix);
        return Plugin_Handled;
    }

    if (g_WelfarePoolBalance <= 0)
    {
        CPrintToChat(client, "%s Welfare pool is empty right now.", prefix);
        return Plugin_Handled;
    }

    int amount = GetRandomInt(BP_WELFARE_MIN, BP_WELFARE_MAX);
    if (amount > g_WelfarePoolBalance)
    {
        amount = g_WelfarePoolBalance;
    }

    DebitWelfarePoolForClient(client, amount);
    return Plugin_Handled;
}

void DebitWelfarePoolForClient(int client, int amount)
{
    if (amount <= 0 || !g_DatabaseReady || g_Database == null)
    {
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(amount);

    char query[384];
    Format(query, sizeof(query),
        "UPDATE %s SET value = value - %d, updated_at = %d WHERE stat_key = '%s' AND value >= %d",
        BP_ECONOMY_TABLE,
        amount,
        GetTime(),
        BP_ECONOMY_WELFARE_POOL_KEY,
        amount);
    g_Database.Query(SQL_OnWelfarePoolDebited, query, pack);
}

public void SQL_OnWelfarePoolDebited(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    int amount = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    char prefix[96];
    char currencyLong[BP_CURRENCY_LONG_MAX];
    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyPrefix(prefix, sizeof(prefix));
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
    GetCurrencyColorTag(colorTag, sizeof(colorTag));

    if (error[0] != '\0')
    {
        LogError("[points_store] Welfare pool debit failed: %s", error);
        if (Client_IsHumanInGame(client))
        {
            CPrintToChat(client, "%s Could not collect welfare right now.", prefix);
        }
        return;
    }

    if (results == null || results.AffectedRows <= 0)
    {
        LoadEconomyState();
        if (Client_IsHumanInGame(client))
        {
            CPrintToChat(client, "%s Welfare pool is empty right now.", prefix);
        }
        return;
    }

    g_WelfarePoolBalance -= amount;
    if (g_WelfarePoolBalance < 0)
    {
        g_WelfarePoolBalance = 0;
    }

    if (!Client_IsHumanInGame(client) || !ApplyBonusPoints(client, amount, false, false, 1.0, "welfare", 0, 0.0, 1))
    {
        QueueEconomyDelta(BP_ECONOMY_WELFARE_POOL_KEY, amount);
        g_WelfarePoolBalance += amount;
        LogEconomyEvent("welfare_pool_refund", client, amount, "welfare", 0, g_WelfarePoolBalance, g_CumulativeSpentBalance);
        if (Client_IsHumanInGame(client))
        {
            CPrintToChat(client, "%s Could not collect welfare right now.", prefix);
        }
        return;
    }

    PlayWelfareSound();
    LogEconomyEvent("welfare_pool_debit", client, amount, "welfare", 0, g_WelfarePoolBalance, g_CumulativeSpentBalance);

    char displayName[256];
    BuildPurchaseDisplayName(client, displayName, sizeof(displayName));
    CPrintToChatAllEx(client, "{default}%s collected %s%d %s{default} from {gold}!welfare{default}", displayName, colorTag, amount, currencyLong);
}

