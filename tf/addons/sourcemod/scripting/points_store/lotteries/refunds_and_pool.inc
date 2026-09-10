void RefundLotteryTicket(int client)
{
    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));

    if (!IsLotteryReadyForClient(client))
    {
        return;
    }

    if (g_LotteryDrawInProgress)
    {
        CPrintToChat(client, "%s[Lottery]{default} You cannot refund while a lottery draw is in progress.", colorTag);
        return;
    }

    if (!g_ClientLotteryHasTicket[client])
    {
        CPrintToChat(client, "%s[Lottery]{default} You do not have a ticket in the current lottery.", colorTag);
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

    char escapedSteamId[65];
    char escapedTicket[(LOTTO_TICKET_MAX * 2) + 1];
    if (!EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId))
        || !EscapeSql(g_ClientLotteryTicket[client], escapedTicket, sizeof(escapedTicket)))
    {
        CPrintToChat(client, "%s[Lottery]{default} Could not prepare your refund.", colorTag);
        return;
    }

    char displayName[LOTTO_NAME_MAX];
    BuildPurchaseDisplayName(client, displayName, sizeof(displayName));

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(g_CurrentLotteryId);
    pack.WriteCell(g_ClientLotteryTicketValue[client]);
    pack.WriteString(steamId);
    pack.WriteString(g_ClientLotteryTicket[client]);
    pack.WriteString(displayName);
    StartLotteryTicketMutationCooldown(client);
    BeginLotteryTicketWrite(steamId);

    char query[384];
    Format(query, sizeof(query),
        "DELETE FROM %s WHERE lottery_id = %d AND steamid64 = '%s' AND ticket = '%s' AND ticket_value = %d",
        LOTTO_TICKET_TABLE,
        g_CurrentLotteryId,
        escapedSteamId,
        escapedTicket,
        g_ClientLotteryTicketValue[client]);
    g_Database.Query(SQL_OnLotteryTicketRefunded, query, pack);
}

public void SQL_OnLotteryTicketRefunded(Database db, DBResultSet results, const char[] error, any data)
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
    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));

    if (error[0] != '\0')
    {
        LogError("[points_store] Failed to refund lottery ticket for %s: %s", steamId, error);
        if (Client_IsHumanInGame(client))
        {
            CPrintToChat(client, "%s[Lottery]{default} Could not refund your ticket.", colorTag);
        }
        return;
    }

    if (results == null || results.AffectedRows <= 0)
    {
        LogError("[points_store] Lottery refund skipped for %s because the cached ticket was stale.", steamId);
        if (Client_IsHumanInGame(client))
        {
            CPrintToChat(client, "%s[Lottery]{default} Your ticket changed. Try again in a moment.", colorTag);
            LoadClientLotteryTicket(client);
        }
        return;
    }

    CreditSteamId64BonusPoints(steamId, amount, "lottery_ticket_refund", lotteryId);
    if (IsClientAuthorizedHuman(client) && lotteryId == g_CurrentLotteryId)
    {
        ClearClientLotteryTicketCache(client);
        g_ClientLotteryTicketLoaded[client] = true;
    }

    if (Client_IsHumanInGame(client))
    {
        CPrintToChatAllEx(client, "{default}%s refunded his lottery ticket! %s(%d){default}", displayName, colorTag, amount);
    }
    else
    {
        CPrintToChatAll("{default}%s refunded his lottery ticket! %s(%d){default}", displayName, colorTag, amount);
    }
}

void PrintLotteryPrizePool(int client)
{
    if (!IsLotteryReadyForClient(client, false))
    {
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(g_CurrentLotteryId);

    char query[256];
    Format(query, sizeof(query),
        "SELECT COALESCE(SUM(ticket_value), 0), COUNT(*) FROM %s WHERE lottery_id = %d",
        LOTTO_TICKET_TABLE,
        g_CurrentLotteryId);
    g_Database.Query(SQL_OnLotteryPrizePoolLoaded, query, pack);
}

public void SQL_OnLotteryPrizePoolLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    int lotteryId = pack.ReadCell();
    delete pack;

    int client = GetClientOfUserId(userId);
    if (!Client_IsHumanInGame(client) || lotteryId != g_CurrentLotteryId)
    {
        return;
    }

    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));
    if (error[0] != '\0')
    {
        CPrintToChat(client, "%s[Lotto]{default} Could not load the prize pool.", colorTag);
        LogError("[points_store] Failed to load lottery prize pool: %s", error);
        return;
    }

    int pool = 0;
    int participants = 0;
    if (results != null && results.FetchRow())
    {
        pool = results.FetchInt(0);
        participants = results.FetchInt(1);
    }

    CPrintToChat(client, "%s[Lotto]{default} Prize pool: %s%d", colorTag, colorTag, pool);
    PrintLotteryTime(client, false);
    CPrintToChat(client, "{default}Participants: {gold}%d", participants);
}

