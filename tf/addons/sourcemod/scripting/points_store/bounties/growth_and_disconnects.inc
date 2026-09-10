public void Event_BountyPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int deathFlags = event.GetInt("death_flags");
    if (deathFlags & TF_DEATHFLAG_DEADRINGER)
    {
        return;
    }

    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int assister = GetClientOfUserId(event.GetInt("assister"));

    if (Client_IsHumanInGame(victim))
    {
        g_BountyMedicAssistsLife[victim] = 0;
    }

    if (Client_IsHumanInGame(assister) && assister != victim)
    {
        if (TF2_GetPlayerClass(assister) == TFClass_Medic && IsClientActiveBountyTarget(assister))
        {
            g_BountyMedicAssistsLife[assister]++;
            if (g_BountyMedicAssistsLife[assister] >= BOUNTY_MEDIC_ASSISTS_PER_GROWTH)
            {
                g_BountyMedicAssistsLife[assister] -= BOUNTY_MEDIC_ASSISTS_PER_GROWTH;
                GrowActiveBountiesForKill(assister, true);
            }
        }
        else
        {
            g_BountyMedicAssistsLife[assister] = 0;
        }
    }

    if (!Client_IsHumanInGame(attacker) || !Client_IsHumanInGame(victim) || attacker == victim)
    {
        return;
    }

    if (IsPlayerAlive(attacker))
    {
        GrowActiveBountiesForKill(attacker, false);
    }

    if (deathFlags & TF_DEATHFLAG_KILLERDOMINATION)
    {
        ClaimBountiesForDomination(attacker, victim);
    }
}

bool IsClientActiveBountyTarget(int client)
{
    if (g_ActiveBountyTargets == null)
    {
        return false;
    }

    char steamId[BOUNTY_STEAMID_MAX];
    int cacheMarker;
    return GetClientSteamId64(client, steamId, sizeof(steamId))
        && g_ActiveBountyTargets.GetValue(steamId, cacheMarker);
}

void GrowActiveBountiesForKill(int attacker, bool fromMedicAssists)
{
    if (!g_BountyDatabaseReady || g_Database == null)
    {
        return;
    }

    char attackerSteamId[BOUNTY_STEAMID_MAX];
    char escapedAttackerSteam[65];
    if (!GetClientSteamId64(attacker, attackerSteamId, sizeof(attackerSteamId))
        || !EscapeSql(attackerSteamId, escapedAttackerSteam, sizeof(escapedAttackerSteam)))
    {
        return;
    }

    int cacheMarker;
    if (g_ActiveBountyTargets == null || !g_ActiveBountyTargets.GetValue(attackerSteamId, cacheMarker))
    {
        return;
    }

    int maxAmount = GetBountyMaxAmount();
    char query[1024];
    if (g_IsMySql)
    {
        FormatEx(query, sizeof(query),
            "UPDATE %s SET bonus_amount = LEAST(%d - amount, bonus_amount + %d) WHERE bounty_id = ("
            ... "SELECT bounty_id FROM (SELECT bounty_id FROM %s WHERE target_steamid64 = '%s' "
            ... "AND status = 'active' AND expires_at > %d AND amount < %d AND amount + bonus_amount < %d "
            ... "ORDER BY bounty_id LIMIT 1) eligible_bounty)",
            BOUNTY_TABLE,
            maxAmount,
            BOUNTY_KILL_GROWTH_AMOUNT,
            BOUNTY_TABLE,
            escapedAttackerSteam,
            GetTime(),
            maxAmount,
            maxAmount);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "UPDATE %s SET bonus_amount = MIN(%d - amount, bonus_amount + %d) WHERE bounty_id = ("
            ... "SELECT bounty_id FROM %s WHERE target_steamid64 = '%s' AND status = 'active' "
            ... "AND expires_at > %d AND amount < %d AND amount + bonus_amount < %d "
            ... "ORDER BY bounty_id LIMIT 1)",
            BOUNTY_TABLE,
            maxAmount,
            BOUNTY_KILL_GROWTH_AMOUNT,
            BOUNTY_TABLE,
            escapedAttackerSteam,
            GetTime(),
            maxAmount,
            maxAmount);
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(attacker));
    pack.WriteString(attackerSteamId);
    pack.WriteCell(fromMedicAssists);
    g_Database.Query(SQL_OnBountyKillGrowth, query, pack);
}

public void SQL_OnBountyKillGrowth(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int attacker = GetClientOfUserId(pack.ReadCell());
    char attackerSteamId[BOUNTY_STEAMID_MAX];
    pack.ReadString(attackerSteamId, sizeof(attackerSteamId));
    bool fromMedicAssists = pack.ReadCell() != 0;
    delete pack;

    if (error[0] != '\0')
    {
        LogError("[points_store] Bounty kill growth failed: %s", error);
        return;
    }

    int bountyCount = results != null ? results.AffectedRows : 0;
    if (bountyCount > 0)
    {
        LogPointsStoreEvent(
            "event=bounty_kill_growth|time=%d|target=%s|client=%d|bounties=%d|growth_amount=%d|source=%s",
            GetTime(), attackerSteamId, attacker, bountyCount, BOUNTY_KILL_GROWTH_AMOUNT,
            fromMedicAssists ? "medic_assists" : "kill");
    }
}

void MarkBountyTargetDisconnected(int client)
{
    if (!g_BountyDatabaseReady || g_Database == null || client <= 0 || client > MaxClients || IsFakeClient(client))
    {
        return;
    }

    char steamId[BOUNTY_STEAMID_MAX];
    char escapedSteamId[65];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId))
        || !EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId)))
    {
        return;
    }

    char query[512];
    FormatEx(query, sizeof(query),
        "UPDATE %s SET target_disconnected_at = CASE WHEN target_disconnected_at = 0 THEN %d ELSE target_disconnected_at END "
        ... "WHERE target_steamid64 = '%s' AND status = 'active' AND expires_at > %d",
        BOUNTY_TABLE,
        GetTime(),
        escapedSteamId,
        GetTime());
    g_Database.Query(SQL_OnIgnoredResult, query);
}

void ClearBountyDisconnectForClient(int client)
{
    if (!g_BountyDatabaseReady || g_Database == null || client <= 0 || client > MaxClients
        || !IsClientConnected(client) || IsFakeClient(client))
    {
        return;
    }

    char steamId[BOUNTY_STEAMID_MAX];
    char escapedSteamId[65];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId))
        || !EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId)))
    {
        return;
    }

    char query[384];
    FormatEx(query, sizeof(query),
        "UPDATE %s SET target_disconnected_at = 0 WHERE target_steamid64 = '%s' AND status = 'active'",
        BOUNTY_TABLE,
        escapedSteamId);
    g_Database.Query(SQL_OnIgnoredResult, query);
}

void ClearConnectedBountyDisconnects()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (Client_IsHumanInGame(client))
        {
            ClearBountyDisconnectForClient(client);
        }
    }
}

void ProcessDisconnectedBountyRefunds()
{
    if (!g_BountyDatabaseReady || g_Database == null || g_BountyDisconnectRefundPending)
    {
        return;
    }

    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT bounty_id, target_steamid64 FROM %s WHERE status = 'active' AND expires_at > %d "
        ... "AND target_disconnected_at > 0 AND target_disconnected_at <= %d ORDER BY bounty_id",
        BOUNTY_TABLE,
        GetTime(),
        GetTime() - BOUNTY_DISCONNECT_GRACE_SECONDS);
    g_BountyDisconnectRefundPending = true;
    g_Database.Query(SQL_OnDisconnectedBountiesLoaded, query);
}

public void SQL_OnDisconnectedBountiesLoaded(Database db, DBResultSet rows, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        g_BountyDisconnectRefundPending = false;
        LogError("[points_store] Disconnected bounty query failed: %s", error);
        return;
    }

    char bountyIds[256];
    char fragment[24];
    char targetSteamId[BOUNTY_STEAMID_MAX];
    int refundCount = 0;
    bountyIds[0] = '\0';
    while (rows != null && rows.FetchRow())
    {
        int bountyId = rows.FetchInt(0);
        rows.FetchString(1, targetSteamId, sizeof(targetSteamId));
        int target = Kogasa_FindClientBySteamId64(targetSteamId);
        if (Client_IsHumanInGame(target))
        {
            ClearBountyDisconnectForClient(target);
            continue;
        }

        FormatEx(fragment, sizeof(fragment), "%s%d", refundCount > 0 ? "," : "", bountyId);
        StrCat(bountyIds, sizeof(bountyIds), fragment);
        refundCount++;
    }

    if (refundCount == 0)
    {
        g_BountyDisconnectRefundPending = false;
        return;
    }

    char token[BOUNTY_TOKEN_MAX];
    char escapedToken[(BOUNTY_TOKEN_MAX * 2) + 1];
    BuildBountyOperationToken("disconnect", token, sizeof(token));
    if (!EscapeSql(token, escapedToken, sizeof(escapedToken)))
    {
        g_BountyDisconnectRefundPending = false;
        return;
    }

    int now = GetTime();
    Transaction txn = new Transaction();
    char query[2048];
    FormatEx(query, sizeof(query),
        "UPDATE %s SET status = 'disconnected', resolved_at = %d, resolution_token = '%s' "
        ... "WHERE bounty_id IN (%s) AND status = 'active' AND target_disconnected_at > 0 AND target_disconnected_at <= %d",
        BOUNTY_TABLE,
        now,
        escapedToken,
        bountyIds,
        now - BOUNTY_DISCONNECT_GRACE_SECONDS);
    txn.AddQuery(query);

    if (g_IsMySql)
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO %s (steamid64, balance) "
            ... "SELECT sender_steamid64, SUM(amount) FROM %s WHERE resolution_token = '%s' AND sender_steamid64 != '%s' "
            ... "GROUP BY sender_steamid64 ON DUPLICATE KEY UPDATE balance = balance + VALUES(balance)",
            BP_BALANCE_TABLE,
            BOUNTY_TABLE,
            escapedToken,
            BOUNTY_SYSTEM_STEAMID);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO %s (steamid64, balance) "
            ... "SELECT sender_steamid64, SUM(amount) FROM %s WHERE resolution_token = '%s' AND sender_steamid64 != '%s' "
            ... "GROUP BY sender_steamid64 ON CONFLICT(steamid64) DO UPDATE SET balance = balance + excluded.balance",
            BP_BALANCE_TABLE,
            BOUNTY_TABLE,
            escapedToken,
            BOUNTY_SYSTEM_STEAMID);
    }
    txn.AddQuery(query);

    FormatEx(query, sizeof(query),
        "SELECT sender_steamid64, MAX(sender_name), target_steamid64, MAX(target_name), amount, target_disconnected_at "
        ... "FROM %s WHERE resolution_token = '%s' "
        ... "GROUP BY bounty_id, sender_steamid64, target_steamid64, amount, target_disconnected_at ORDER BY bounty_id",
        BOUNTY_TABLE,
        escapedToken);
    txn.AddQuery(query);

    DataPack pack = new DataPack();
    pack.WriteString(token);
    g_Database.Execute(txn, SQLTxn_OnDisconnectedBountiesRefunded, SQLTxn_OnDisconnectedBountyRefundFailed, pack);
}

public void SQLTxn_OnDisconnectedBountiesRefunded(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    char token[BOUNTY_TOKEN_MAX];
    pack.ReadString(token, sizeof(token));
    delete pack;
    g_BountyDisconnectRefundPending = false;

    int refundTotal = 0;
    int refundCount = 0;
    if (numQueries >= 3 && results[2] != null)
    {
        char senderSteamId[BOUNTY_STEAMID_MAX];
        char senderName[BOUNTY_NAME_MAX];
        char targetSteamId[BOUNTY_STEAMID_MAX];
        char targetName[BOUNTY_NAME_MAX];
        while (results[2].FetchRow())
        {
            results[2].FetchString(0, senderSteamId, sizeof(senderSteamId));
            results[2].FetchString(1, senderName, sizeof(senderName));
            results[2].FetchString(2, targetSteamId, sizeof(targetSteamId));
            results[2].FetchString(3, targetName, sizeof(targetName));
            int amount = results[2].FetchInt(4);
            int disconnectedAt = results[2].FetchInt(5);
            if (StrEqual(senderSteamId, BOUNTY_SYSTEM_STEAMID, false))
            {
                continue;
            }

            refundTotal += amount;
            refundCount++;
            int sender = Kogasa_FindClientBySteamId64(senderSteamId);
            if (sender > 0 && g_ClientBonusPointsLoaded[sender])
            {
                int balanceBefore = g_ClientBonusPoints[sender];
                g_ClientBonusPoints[sender] += amount;
                LogBonusPointsDelta(sender, amount, balanceBefore, g_ClientBonusPoints[sender], "bounty_disconnect_refund", 0, false, false, 1.0, true, 0, 0);
            }

            char targetDisplay[256];
            BuildBountyDisplayName(targetSteamId, targetName, targetDisplay, sizeof(targetDisplay));
            char currencyName[BP_CURRENCY_SHORT_MAX];
            GetCurrencyShortLabelForAmount(amount, currencyName, sizeof(currencyName));
            int disconnectedMinutes = (GetTime() - disconnectedAt) / 60;
            if (disconnectedMinutes < BOUNTY_DISCONNECT_GRACE_SECONDS / 60)
            {
                disconnectedMinutes = BOUNTY_DISCONNECT_GRACE_SECONDS / 60;
            }

            for (int recipient = 1; recipient <= MaxClients; recipient++)
            {
                if (Client_IsHumanInGame(recipient))
                {
                    CPrintToChatEx(recipient, sender > 0 ? sender : recipient,
                        "%s %s has been disconnected for {gold}%d minutes{default}; %s%d %s{default} has been refunded!",
                        g_BountyPrefix,
                        targetDisplay,
                        disconnectedMinutes,
                        g_CurrencyColorTag,
                        amount,
                        currencyName);
                }
            }
        }
    }

    if (refundCount > 0)
    {
        LogPointsStoreEvent(
            "event=bounty_disconnect_refund|time=%d|count=%d|refund_total=%d|token=%s",
            GetTime(), refundCount, refundTotal, token);
    }
    RefreshActiveBountyTargets();
}

public void SQLTxn_OnDisconnectedBountyRefundFailed(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    delete pack;
    g_BountyDisconnectRefundPending = false;
    LogError("[points_store] Disconnected bounty refund failed at query %d: %s", failIndex, error);
}

