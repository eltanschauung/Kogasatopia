void ClearClientLotteryTicketCache(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    g_ClientLotteryTicketLoaded[client] = false;
    g_ClientLotteryHasTicket[client] = false;
    g_ClientLotteryId[client] = 0;
    g_ClientLotteryTicketValue[client] = 0;
    g_ClientLotteryTicket[client][0] = '\0';
}

void ClearAllClientLotteryCaches()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        ClearClientLotteryTicketCache(i);
    }
}

void ReloadAllClientLotteryTickets()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientAuthorizedHuman(i))
        {
            LoadClientLotteryTicket(i);
        }
    }
}

bool IsLotteryTicketWritePending(const char[] steamId)
{
    int pending = 0;
    return g_LotteryPendingSteamIds != null && g_LotteryPendingSteamIds.GetValue(steamId, pending);
}

void BeginLotteryTicketWrite(const char[] steamId)
{
    if (g_LotteryPendingSteamIds != null && !IsLotteryTicketWritePending(steamId))
    {
        g_LotteryPendingSteamIds.SetValue(steamId, 1, true);
        g_LotteryPendingTicketWrites++;

        DataPack pack = new DataPack();
        pack.WriteString(steamId);
        CreateTimer(LOTTO_TICKET_WRITE_TIMEOUT, Timer_LotteryTicketWriteTimeout, pack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
    }
}

void FinishLotteryTicketWrite(const char[] steamId)
{
    if (g_LotteryPendingSteamIds != null && IsLotteryTicketWritePending(steamId))
    {
        g_LotteryPendingSteamIds.Remove(steamId);
        if (g_LotteryPendingTicketWrites > 0)
        {
            g_LotteryPendingTicketWrites--;
        }
    }
}

public Action Timer_LotteryTicketWriteTimeout(Handle timer, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    char steamId[32];
    pack.ReadString(steamId, sizeof(steamId));

    if (IsLotteryTicketWritePending(steamId))
    {
        LogError("[points_store] Lottery ticket write for %s timed out; clearing pending guard.", steamId);
        FinishLotteryTicketWrite(steamId);
    }

    return Plugin_Stop;
}

void LoadClientLotteryTicket(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    ClearClientLotteryTicketCache(client);
    if (!IsLotteryEnabled() || !g_DatabaseReady || g_Database == null || !g_LotteryReady || g_CurrentLotteryId <= 0 || !IsClientAuthorizedHuman(client))
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
        LogError("[points_store] Failed to escape SteamID64 for lottery ticket load for client %d.", client);
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(g_CurrentLotteryId);
    pack.WriteString(steamId);

    char query[384];
    Format(query, sizeof(query),
        "SELECT ticket, ticket_value FROM %s WHERE lottery_id = %d AND steamid64 = '%s' LIMIT 1",
        LOTTO_TICKET_TABLE,
        g_CurrentLotteryId,
        escapedSteamId);
    g_Database.Query(SQL_OnClientLotteryTicketLoaded, query, pack);
}

public void SQL_OnClientLotteryTicketLoaded(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    int expectedLotteryId = pack.ReadCell();
    char expectedSteamId[32];
    pack.ReadString(expectedSteamId, sizeof(expectedSteamId));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (!IsLotteryEnabled() || !IsClientAuthorizedHuman(client) || expectedLotteryId != g_CurrentLotteryId)
    {
        return;
    }

    char currentSteamId[32];
    if (!GetClientSteamId64(client, currentSteamId, sizeof(currentSteamId)) || !StrEqual(currentSteamId, expectedSteamId, false))
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[points_store] Failed to load lottery ticket for %s: %s", expectedSteamId, error);
        g_ClientLotteryTicketLoaded[client] = false;
        return;
    }

    g_ClientLotteryTicketLoaded[client] = true;
    g_ClientLotteryHasTicket[client] = false;
    g_ClientLotteryId[client] = expectedLotteryId;
    g_ClientLotteryTicketValue[client] = 0;
    g_ClientLotteryTicket[client][0] = '\0';

    if (results != null && results.FetchRow())
    {
        results.FetchString(0, g_ClientLotteryTicket[client], sizeof(g_ClientLotteryTicket[]));
        g_ClientLotteryTicketValue[client] = results.FetchInt(1);
        g_ClientLotteryHasTicket[client] = g_ClientLotteryTicket[client][0] != '\0' && g_ClientLotteryTicketValue[client] > 0;
    }
}

bool IsLotteryReadyForClient(int client, bool needTicketLoaded = true)
{
    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));

    if (!IsLotteryEnabled())
    {
        CPrintToChat(client, "%s[Lotto]{default} The lottery is disabled on this server.", colorTag);
        return false;
    }

    if (!g_DatabaseReady || g_Database == null || !g_LotteryReady || g_CurrentLotteryId <= 0)
    {
        CPrintToChat(client, "%s[Lotto]{default} The lottery database is not ready.", colorTag);
        EnsureActiveLottery();
        return false;
    }

    if (needTicketLoaded && g_LotteryEqualRefundInProgress)
    {
        CPrintToChat(client, "%s[Lotto]{default} Equal Lottery tickets are being updated. Try again in a moment.", colorTag);
        return false;
    }

    if (needTicketLoaded
        && (!g_ClientLotteryTicketLoaded[client] || g_ClientLotteryId[client] != g_CurrentLotteryId))
    {
        LoadClientLotteryTicket(client);
        CPrintToChat(client, "%s[Lotto]{default} Your lottery ticket is loading. Try again in a moment.", colorTag);
        return false;
    }

    return true;
}

bool CanStartLotteryTicketMutation(int client)
{
    float remaining = g_NextLotteryTicketMutationAt[client] - GetEngineTime();
    if (remaining <= 0.0)
    {
        return true;
    }

    char colorTag[BP_CURRENCY_COLOR_MAX + 2];
    GetCurrencyColorTag(colorTag, sizeof(colorTag));
    CPrintToChat(
        client,
        "%s[Lottery]{default} Wait {gold}%d seconds{default} before buying, refunding, or changing a ticket.",
        colorTag,
        RoundToCeil(remaining));
    return false;
}

void StartLotteryTicketMutationCooldown(int client)
{
    g_NextLotteryTicketMutationAt[client] = GetEngineTime() + LOTTO_TICKET_MUTATION_COOLDOWN;
}

