void AttemptLotteryAllTicketPurchase(int client)
{
    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    char currencyLong[BP_CURRENCY_LONG_MAX];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));

    if (!IsLotteryReadyForClient(client))
    {
        return;
    }

    if (g_CurrentLotteryEqual)
    {
        AttemptLotteryTicketPurchase(client, GetLotteryEqualTicketValue());
        return;
    }

    if (!AreBonusPointsReady(client))
    {
        LoadClientBonusPoints(client);
        CPrintToChat(client, "%s[Lottery]{default} Your %s are loading. Try again in a moment.", colorTag, currencyLong);
        return;
    }

    int available = GetCachedBonusPoints(client);
    if (g_ClientLotteryHasTicket[client])
    {
        available += g_ClientLotteryTicketValue[client];
    }

    AttemptLotteryTicketPurchase(client, available);
}

void AttemptLotteryTicketPurchase(int client, int amount)
{
    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    char currencyLong[BP_CURRENCY_LONG_MAX];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));

    if (!IsLotteryReadyForClient(client))
    {
        return;
    }

    if (g_LotteryDrawInProgress)
    {
        CPrintToChat(client, "%s[Lottery]{default} A lottery draw is already in progress.", colorTag);
        return;
    }

    if (amount <= 0)
    {
        CPrintToChat(client, "%s[Lottery]{default} Ticket value must be greater than 0.", colorTag);
        return;
    }

    if (g_CurrentLotteryEqual && amount != GetLotteryEqualTicketValue())
    {
        CPrintToChat(client,
            "%s[Lottery]{default} Equal Lottery tickets must have a value of {gold}%d{default}.",
            colorTag,
            GetLotteryEqualTicketValue());
        return;
    }

    amount = ClampLotteryTicketValue(client, amount);

    if (!g_CurrentLotteryEqual)
    {
        int roundedAmount = RoundLotteryTicketValue(amount);
        if (roundedAmount <= 0)
        {
            CPrintToChat(client, "%s[Lottery]{default} Ticket value must be at least %s%d %s{default}.", colorTag, colorTag, LOTTO_TICKET_UNIT, currencyLong);
            return;
        }

        if (roundedAmount != amount)
        {
            CPrintToChat(client, "%s[Lottery]{default} Ticket value rounded down to %s%d %s{default}.", colorTag, colorTag, roundedAmount, currencyLong);
            amount = roundedAmount;
        }
    }

    if (g_ClientLotteryHasTicket[client])
    {
        AttemptLotteryTicketReplacement(client, amount);
        return;
    }

    if (g_LotteryWords == null || g_LotteryWords.Length <= 0)
    {
        CPrintToChat(client, "%s[Lottery]{default} No lottery words are configured.", colorTag);
        return;
    }

    if (!AreBonusPointsReady(client))
    {
        LoadClientBonusPoints(client);
        CPrintToChat(client, "%s[Lottery]{default} Your %s are loading. Try again in a moment.", colorTag, currencyLong);
        return;
    }

    if (GetCachedBonusPoints(client) < amount)
    {
        CPrintToChat(client, "%s[Lottery]{default} You only have %s%d %s{default}.", colorTag, colorTag, GetCachedBonusPoints(client), currencyLong);
        return;
    }

    char steamId[32];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId)))
    {
        CPrintToChat(client, "%s[Lottery]{default} Could not read your SteamID64.", colorTag);
        return;
    }

    if (IsLotteryTicketWritePending(steamId))
    {
        CPrintToChat(client, "%s[Lottery]{default} Your lottery ticket is still being saved. Try again in a moment.", colorTag);
        return;
    }

    if (!CanStartLotteryTicketMutation(client))
    {
        return;
    }

    char ticket[LOTTO_TICKET_MAX];
    GenerateLotteryTicket(ticket, sizeof(ticket));
    if (ticket[0] == '\0')
    {
        CPrintToChat(client, "%s[Lottery]{default} Could not generate a ticket.", colorTag);
        return;
    }

    char displayName[LOTTO_NAME_MAX];
    BuildPurchaseDisplayName(client, displayName, sizeof(displayName));

    char escapedSteamId[65];
    char escapedTicket[(LOTTO_TICKET_MAX * 2) + 1];
    char escapedName[(LOTTO_NAME_MAX * 2) + 1];
    if (!EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId))
        || !EscapeSql(ticket, escapedTicket, sizeof(escapedTicket))
        || !EscapeSql(displayName, escapedName, sizeof(escapedName)))
    {
        CPrintToChat(client, "%s[Lottery]{default} Could not prepare your ticket.", colorTag);
        return;
    }

    if (!SpendBonusPointsWithContext(client, amount, "lottery_ticket", 0))
    {
        CPrintToChat(client, "%s[Lottery]{default} You can't afford that ticket.", colorTag);
        return;
    }

    StartLotteryTicketMutationCooldown(client);

    int createdAt = GetTime();

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(g_CurrentLotteryId);
    pack.WriteCell(amount);
    pack.WriteString(steamId);
    pack.WriteString(ticket);
    pack.WriteString(displayName);
    BeginLotteryTicketWrite(steamId);

    char query[8192];
    Format(query, sizeof(query),
        "INSERT INTO %s (lottery_id, steamid64, display_name, ticket, ticket_value, created_at) VALUES (%d, '%s', '%s', '%s', %d, %d)",
        LOTTO_TICKET_TABLE,
        g_CurrentLotteryId,
        escapedSteamId,
        escapedName,
        escapedTicket,
        amount,
        createdAt);
    g_Database.Query(SQL_OnLotteryTicketInserted, query, pack);
}

void AttemptLotteryTicketReplacement(int client, int amount)
{
    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    char currencyLong[BP_CURRENCY_LONG_MAX];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));

    if (!IsLotteryReadyForClient(client))
    {
        return;
    }

    if (g_LotteryDrawInProgress)
    {
        CPrintToChat(client, "%s[Lottery]{default} A lottery draw is already in progress.", colorTag);
        return;
    }

    if (!g_ClientLotteryHasTicket[client] || g_ClientLotteryTicketValue[client] <= 0)
    {
        AttemptLotteryTicketPurchase(client, amount);
        return;
    }

    if (g_LotteryWords == null || g_LotteryWords.Length <= 0)
    {
        CPrintToChat(client, "%s[Lottery]{default} No lottery words are configured.", colorTag);
        return;
    }

    if (!AreBonusPointsReady(client))
    {
        LoadClientBonusPoints(client);
        CPrintToChat(client, "%s[Lottery]{default} Your %s are loading. Try again in a moment.", colorTag, currencyLong);
        return;
    }

    int oldAmount = g_ClientLotteryTicketValue[client];
    if (amount == oldAmount)
    {
        CPrintToChat(client, "%s[Lottery]{default} Your current ticket is equal to {gold}%d", colorTag, amount);
        return;
    }

    int postRefundBalance = GetCachedBonusPoints(client) + oldAmount;
    if (postRefundBalance < amount)
    {
        CPrintToChat(client, "%s[Lottery]{default} Refunding your current ticket would only give you %s%d %s{default}.", colorTag, colorTag, postRefundBalance, currencyLong);
        return;
    }

    char steamId[32];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId)))
    {
        CPrintToChat(client, "%s[Lottery]{default} Could not read your SteamID64.", colorTag);
        return;
    }

    if (IsLotteryTicketWritePending(steamId))
    {
        CPrintToChat(client, "%s[Lottery]{default} Your lottery ticket is still being saved. Try again in a moment.", colorTag);
        return;
    }

    if (!CanStartLotteryTicketMutation(client))
    {
        return;
    }

    char ticket[LOTTO_TICKET_MAX];
    GenerateLotteryTicket(ticket, sizeof(ticket));
    if (ticket[0] == '\0')
    {
        CPrintToChat(client, "%s[Lottery]{default} Could not generate a ticket.", colorTag);
        return;
    }

    char displayName[LOTTO_NAME_MAX];
    BuildPurchaseDisplayName(client, displayName, sizeof(displayName));

    char escapedSteamId[65];
    char escapedOldTicket[(LOTTO_TICKET_MAX * 2) + 1];
    char escapedTicket[(LOTTO_TICKET_MAX * 2) + 1];
    char escapedName[(LOTTO_NAME_MAX * 2) + 1];
    if (!EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId))
        || !EscapeSql(g_ClientLotteryTicket[client], escapedOldTicket, sizeof(escapedOldTicket))
        || !EscapeSql(ticket, escapedTicket, sizeof(escapedTicket))
        || !EscapeSql(displayName, escapedName, sizeof(escapedName)))
    {
        CPrintToChat(client, "%s[Lottery]{default} Could not prepare your ticket.", colorTag);
        return;
    }

    int balanceDelta = oldAmount - amount;
    int createdAt = GetTime();

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(g_CurrentLotteryId);
    pack.WriteCell(amount);
    pack.WriteCell(oldAmount);
    pack.WriteCell(balanceDelta);
    pack.WriteString(steamId);
    pack.WriteString(g_ClientLotteryTicket[client]);
    pack.WriteString(ticket);
    pack.WriteString(displayName);
    StartLotteryTicketMutationCooldown(client);
    BeginLotteryTicketWrite(steamId);

    Transaction txn = new Transaction();
    char query[8192];
    Format(query, sizeof(query),
        "UPDATE %s SET display_name = '%s', ticket = '%s', ticket_value = %d, created_at = %d WHERE lottery_id = %d AND steamid64 = '%s' AND ticket = '%s' AND ticket_value = %d AND EXISTS (SELECT 1 FROM %s WHERE steamid64 = '%s' AND balance + %d >= %d)",
        LOTTO_TICKET_TABLE,
        escapedName,
        escapedTicket,
        amount,
        createdAt,
        g_CurrentLotteryId,
        escapedSteamId,
        escapedOldTicket,
        oldAmount,
        BP_BALANCE_TABLE,
        escapedSteamId,
        oldAmount,
        amount);
    txn.AddQuery(query);

    if (balanceDelta != 0)
    {
        if (g_IsMySql)
        {
            Format(query, sizeof(query),
                "INSERT INTO %s (steamid64, balance) SELECT '%s', %d FROM DUAL WHERE EXISTS (SELECT 1 FROM %s WHERE lottery_id = %d AND steamid64 = '%s' AND ticket = '%s' AND ticket_value = %d AND created_at = %d) ON DUPLICATE KEY UPDATE balance = GREATEST(0, balance + VALUES(balance))",
                BP_BALANCE_TABLE,
                escapedSteamId,
                balanceDelta,
                LOTTO_TICKET_TABLE,
                g_CurrentLotteryId,
                escapedSteamId,
                escapedTicket,
                amount,
                createdAt);
        }
        else
        {
            Format(query, sizeof(query),
                "INSERT INTO %s (steamid64, balance) SELECT '%s', %d WHERE EXISTS (SELECT 1 FROM %s WHERE lottery_id = %d AND steamid64 = '%s' AND ticket = '%s' AND ticket_value = %d AND created_at = %d) ON CONFLICT(steamid64) DO UPDATE SET balance = MAX(0, balance + excluded.balance), updated_at = CURRENT_TIMESTAMP",
                BP_BALANCE_TABLE,
                escapedSteamId,
                balanceDelta,
                LOTTO_TICKET_TABLE,
                g_CurrentLotteryId,
                escapedSteamId,
                escapedTicket,
                amount,
                createdAt);
        }
        txn.AddQuery(query);
    }

    g_Database.Execute(txn, SQLTxn_OnLotteryTicketReplaced, SQLTxn_OnLotteryTicketReplaceFailure, pack);
}

public void SQLTxn_OnLotteryTicketReplaced(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    int lotteryId = pack.ReadCell();
    int amount = pack.ReadCell();
    int oldAmount = pack.ReadCell();
    int balanceDelta = pack.ReadCell();
    char steamId[32];
    char oldTicket[LOTTO_TICKET_MAX];
    char ticket[LOTTO_TICKET_MAX];
    char displayName[LOTTO_NAME_MAX];
    pack.ReadString(steamId, sizeof(steamId));
    pack.ReadString(oldTicket, sizeof(oldTicket));
    pack.ReadString(ticket, sizeof(ticket));
    pack.ReadString(displayName, sizeof(displayName));
    delete pack;
    FinishLotteryTicketWrite(steamId);

    int client = GetClientOfUserId(userId);
    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));

    if (numQueries <= 0 || results[0] == null || results[0].AffectedRows <= 0)
    {
        if (Client_IsHumanInGame(client))
        {
            CPrintToChat(client, "%s[Lottery]{default} Your existing ticket could not be replaced. Try again in a moment.", colorTag);
            LoadClientLotteryTicket(client);
        }
        return;
    }

    if (IsClientAuthorizedHuman(client) && lotteryId == g_CurrentLotteryId)
    {
        char currentSteamId[32];
        if (GetClientSteamId64(client, currentSteamId, sizeof(currentSteamId)) && StrEqual(currentSteamId, steamId, false))
        {
            int balanceBefore = GetCachedBonusPoints(client);
            if (g_ClientBonusPointsLoaded[client])
            {
                g_ClientBonusPoints[client] += balanceDelta;
                if (g_ClientBonusPoints[client] < 0)
                {
                    g_ClientBonusPoints[client] = 0;
                }
            }

            g_ClientLotteryTicketLoaded[client] = true;
            g_ClientLotteryHasTicket[client] = true;
            g_ClientLotteryId[client] = lotteryId;
            g_ClientLotteryTicketValue[client] = amount;
            strcopy(g_ClientLotteryTicket[client], sizeof(g_ClientLotteryTicket[]), ticket);

            char currencyLong[BP_CURRENCY_LONG_MAX];
            char display[LOTTO_TICKET_PRINT_MAX];
            GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
            BuildLotteryTicketDisplay(ticket, display, sizeof(display));

            if (balanceDelta != 0)
            {
                LogBonusPointsDelta(client, balanceDelta, balanceBefore, GetCachedBonusPoints(client), "lottery_ticket_replace", lotteryId, false, false, 1.0, true, 0, 0);
            }

            CPrintToChatAllEx(client, "{default}%s changed his {gold}!lottery{default} ticket from %s%d %s{default} to %s%d %s{default}", displayName, colorTag, oldAmount, currencyLong, colorTag, amount, currencyLong);
            CPrintToChat(client, "%s[Lottery]{default} Your ticket: %s", colorTag, display);
        }
    }
}

public void SQLTxn_OnLotteryTicketReplaceFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    pack.ReadCell();
    pack.ReadCell();
    pack.ReadCell();
    pack.ReadCell();
    char steamId[32];
    pack.ReadString(steamId, sizeof(steamId));
    delete pack;
    FinishLotteryTicketWrite(steamId);

    int client = GetClientOfUserId(userId);
    if (Client_IsHumanInGame(client))
    {
        char colorTag[BP_CURRENCY_COLOR_MAX + 2];
        GetCurrencyColorTag(colorTag, sizeof(colorTag));
        CPrintToChat(client, "%s[Lottery]{default} Your ticket could not be replaced. Try again in a moment.", colorTag);
        LoadClientLotteryTicket(client);
    }

    LogError("[points_store] Lottery ticket replacement failed for %s (query %d): %s", steamId, failIndex, error);
}

public void SQL_OnLotteryTicketInserted(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    int lotteryId = pack.ReadCell();
    int amount = pack.ReadCell();
    char steamId[32];
    char ticket[LOTTO_TICKET_MAX];
    char displayName[LOTTO_NAME_MAX];
    pack.ReadString(steamId, sizeof(steamId));
    pack.ReadString(ticket, sizeof(ticket));
    pack.ReadString(displayName, sizeof(displayName));
    delete pack;
    FinishLotteryTicketWrite(steamId);

    int client = GetClientOfUserId(userId);
    if (error[0] != '\0')
    {
        LogError("[points_store] Failed to insert lottery ticket for %s: %s", steamId, error);
        CreditSteamId64BonusPoints(steamId, amount, "lottery_ticket_save_refund", lotteryId);
        if (Client_IsHumanInGame(client))
        {
            char colorTag[BP_CURRENCY_COLOR_MAX + 2];
            GetCurrencyColorTag(colorTag, sizeof(colorTag));
            CPrintToChat(client, "%s[Lottery]{default} Your ticket could not be saved, so your payment was refunded.", colorTag);
            LoadClientLotteryTicket(client);
        }
        return;
    }

    if (IsClientAuthorizedHuman(client) && lotteryId == g_CurrentLotteryId)
    {
        char currentSteamId[32];
        if (GetClientSteamId64(client, currentSteamId, sizeof(currentSteamId)) && StrEqual(currentSteamId, steamId, false))
        {
            g_ClientLotteryTicketLoaded[client] = true;
            g_ClientLotteryHasTicket[client] = true;
            g_ClientLotteryId[client] = lotteryId;
            g_ClientLotteryTicketValue[client] = amount;
            strcopy(g_ClientLotteryTicket[client], sizeof(g_ClientLotteryTicket[]), ticket);

            char colorTag[BP_CURRENCY_COLOR_MAX + 2];
            char currencyLong[BP_CURRENCY_LONG_MAX];
            char display[LOTTO_TICKET_PRINT_MAX];
            GetCurrencyColorTag(colorTag, sizeof(colorTag));
            GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
            BuildLotteryTicketDisplay(ticket, display, sizeof(display));

            CPrintToChatAllEx(client, "{default}%s bought a {gold}!lottery{default} ticket for %s%d %s{default}", displayName, colorTag, amount, currencyLong);
            CPrintToChat(client, "%s[Lottery]{default} Your ticket: %s", colorTag, display);
        }
    }
}

