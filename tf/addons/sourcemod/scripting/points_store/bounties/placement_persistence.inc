void QueueBountyPlacement(int client)
{
    char senderSteamId[BOUNTY_STEAMID_MAX];
    char senderName[BOUNTY_NAME_MAX];
    GetClientName(client, senderName, sizeof(senderName));
    if (!GetClientSteamId64(client, senderSteamId, sizeof(senderSteamId)))
    {
        return;
    }

    int amount = g_BountyPendingAmount[client];
    char escapedSenderSteam[65];
    char escapedSenderName[(BOUNTY_NAME_MAX * 2) + 1];
    char escapedTargetSteam[65];
    char escapedTargetName[(BOUNTY_NAME_MAX * 2) + 1];
    if (!IsBountyAmountAllowed(amount)
        || !EscapeSql(senderSteamId, escapedSenderSteam, sizeof(escapedSenderSteam))
        || !EscapeSql(senderName, escapedSenderName, sizeof(escapedSenderName))
        || !EscapeSql(g_BountyPendingTargetSteamId[client], escapedTargetSteam, sizeof(escapedTargetSteam))
        || !EscapeSql(g_BountyPendingTargetName[client], escapedTargetName, sizeof(escapedTargetName)))
    {
        CPrintToChat(client, "%s Could not place that bounty.", g_BountyPrefix);
        return;
    }

    int now = GetTime();
    int target = Kogasa_FindClientBySteamId64(g_BountyPendingTargetSteamId[client]);
    if (!Client_IsHumanInGame(target))
    {
        CPrintToChat(client, "%s That player is no longer online.", g_BountyPrefix);
        return;
    }
    int targetPlaytime = 0;
    if (GetFeatureStatus(FeatureType_Native, "WhaleTracker_GetRankedPlaytimeSeconds") == FeatureStatus_Available)
    {
        targetPlaytime = WhaleTracker_GetRankedPlaytimeSeconds(target, g_BountyPendingTargetSteamId[client]);
    }
    int playtimeLimit = GetBountyPlaytimeLimitSeconds();
    int halftime = GetBountyHalftimeSeconds();
    Transaction txn = new Transaction();
    char query[4096];
    FormatEx(query, sizeof(query),
        "UPDATE %s SET balance = balance - %d WHERE steamid64 = '%s' AND balance >= %d "
        ... "AND (EXISTS (SELECT 1 FROM %s WHERE target_steamid64 = '%s' AND status = 'active' AND expires_at > %d) "
        ... "OR (SELECT COUNT(DISTINCT target_steamid64) FROM %s WHERE status = 'active' AND expires_at > %d) < %d) "
        ... "AND NOT EXISTS (SELECT 1 FROM %s WHERE sender_steamid64 = '%s' AND placed_at > %d)",
        BP_BALANCE_TABLE,
        amount,
        escapedSenderSteam,
        amount,
        BOUNTY_TABLE,
        escapedTargetSteam,
        now,
        BOUNTY_TABLE,
        now,
        BOUNTY_MAX_ACTIVE,
        BOUNTY_TABLE,
        escapedSenderSteam,
        now - BOUNTY_PLACEMENT_COOLDOWN_SECONDS);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query),
        "INSERT INTO %s (sender_steamid64, sender_name, target_steamid64, target_name, amount, placed_at, expires_at, "
        ... "qualifying_playtime_seconds, last_target_playtime_seconds, halftime_announced, status) "
        ... "SELECT '%s', '%s', '%s', '%s', %d, %d, %d, "
        ... "CASE WHEN current_bounty.row_count = 0 OR %d >= current_bounty.total_amount THEN 0 "
        ... "ELSE %s(0, current_bounty.progress_seconds - ((%d * %d) / current_bounty.total_amount)) END, "
        ... "%d, 0, 'active' FROM (SELECT COUNT(*) AS row_count, "
        ... "COALESCE(SUM(amount + bonus_amount), 0) AS total_amount, "
        ... "COALESCE(MIN(qualifying_playtime_seconds), 0) AS progress_seconds FROM %s "
        ... "WHERE target_steamid64 = '%s' AND status = 'active' AND expires_at > %d) current_bounty "
        ... "WHERE %s = 1",
        BOUNTY_TABLE,
        escapedSenderSteam,
        escapedSenderName,
        escapedTargetSteam,
        escapedTargetName,
        amount,
        now,
        now + BOUNTY_WALL_EXPIRY_SECONDS,
        amount,
        g_IsMySql ? "GREATEST" : "MAX",
        playtimeLimit,
        amount,
        targetPlaytime,
        BOUNTY_TABLE,
        escapedTargetSteam,
        now,
        g_IsMySql ? "ROW_COUNT()" : "changes()");
    txn.AddQuery(query);

    if (g_IsMySql)
    {
        FormatEx(query, sizeof(query),
            "UPDATE %s existing_bounty JOIN (SELECT qualifying_playtime_seconds, last_target_playtime_seconds "
            ... "FROM %s WHERE bounty_id = LAST_INSERT_ID() AND sender_steamid64 = '%s' "
            ... "AND target_steamid64 = '%s' AND placed_at = %d) new_bounty "
            ... "SET existing_bounty.qualifying_playtime_seconds = new_bounty.qualifying_playtime_seconds, "
            ... "existing_bounty.last_target_playtime_seconds = new_bounty.last_target_playtime_seconds, "
            ... "existing_bounty.halftime_announced = IF(new_bounty.qualifying_playtime_seconds < %d, 0, 1) "
            ... "WHERE existing_bounty.target_steamid64 = '%s' AND existing_bounty.status = 'active' "
            ... "AND existing_bounty.expires_at > %d",
            BOUNTY_TABLE,
            BOUNTY_TABLE,
            escapedSenderSteam,
            escapedTargetSteam,
            now,
            halftime,
            escapedTargetSteam,
            now);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "UPDATE %s SET "
            ... "qualifying_playtime_seconds = (SELECT qualifying_playtime_seconds FROM %s WHERE bounty_id = last_insert_rowid()), "
            ... "last_target_playtime_seconds = (SELECT last_target_playtime_seconds FROM %s WHERE bounty_id = last_insert_rowid()), "
            ... "halftime_announced = CASE WHEN (SELECT qualifying_playtime_seconds FROM %s WHERE bounty_id = last_insert_rowid()) < %d THEN 0 ELSE 1 END "
            ... "WHERE target_steamid64 = '%s' AND status = 'active' AND expires_at > %d "
            ... "AND EXISTS (SELECT 1 FROM %s WHERE bounty_id = last_insert_rowid() AND sender_steamid64 = '%s' "
            ... "AND target_steamid64 = '%s' AND placed_at = %d)",
            BOUNTY_TABLE,
            BOUNTY_TABLE,
            BOUNTY_TABLE,
            BOUNTY_TABLE,
            halftime,
            escapedTargetSteam,
            now,
            BOUNTY_TABLE,
            escapedSenderSteam,
            escapedTargetSteam,
            now);
    }
    txn.AddQuery(query);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(senderSteamId);
    pack.WriteString(senderName);
    pack.WriteString(g_BountyPendingTargetSteamId[client]);
    pack.WriteString(g_BountyPendingTargetName[client]);
    pack.WriteCell(amount);
    g_BountyPlacementPending[client] = true;
    g_Database.Execute(txn, SQLTxn_OnBountyPlaced, SQLTxn_OnBountyPlacementFailed, pack);
}

public void SQLTxn_OnBountyPlaced(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    char senderSteamId[BOUNTY_STEAMID_MAX];
    char senderName[BOUNTY_NAME_MAX];
    char targetSteamId[BOUNTY_STEAMID_MAX];
    char targetName[BOUNTY_NAME_MAX];
    pack.ReadString(senderSteamId, sizeof(senderSteamId));
    pack.ReadString(senderName, sizeof(senderName));
    pack.ReadString(targetSteamId, sizeof(targetSteamId));
    pack.ReadString(targetName, sizeof(targetName));
    int amount = pack.ReadCell();
    delete pack;

    bool placed = numQueries >= 3 && results[1] != null && results[1].AffectedRows > 0;
    if (client > 0)
    {
        g_BountyPlacementPending[client] = false;
    }
    if (!placed)
    {
        if (Client_IsHumanInGame(client))
        {
            LoadClientBonusPoints(client);
            CPrintToChat(client,
                "%s The bounty could not be placed; check your balance, cooldown, and the active bounty limit.",
                g_BountyPrefix);
            LoadBountyPlacementCooldown(client);
        }
        return;
    }

    MarkActiveBountyTarget(targetSteamId);
    RefreshActiveBountyTargets();

    if (Client_IsHumanInGame(client))
    {
        char currentSteamId[BOUNTY_STEAMID_MAX];
        if (GetClientSteamId64(client, currentSteamId, sizeof(currentSteamId))
            && StrEqual(currentSteamId, senderSteamId, false)
            && g_ClientBonusPointsLoaded[client])
        {
            int balanceBefore = g_ClientBonusPoints[client];
            g_ClientBonusPoints[client] -= amount;
            if (g_ClientBonusPoints[client] < 0)
            {
                g_ClientBonusPoints[client] = 0;
            }
            LogBonusPointsDelta(client, -amount, balanceBefore, g_ClientBonusPoints[client], "bounty_escrow", 0, false, false, 1.0, true, 0, 0);
        }
        g_BountyLastPlacementAt[client] = GetTime();
    }

    int target = Kogasa_FindClientBySteamId64(targetSteamId);
    char senderDisplay[256];
    char targetDisplay[256];
    if (Client_IsHumanInGame(client))
    {
        BuildPurchaseDisplayName(client, senderDisplay, sizeof(senderDisplay));
    }
    else
    {
        strcopy(senderDisplay, sizeof(senderDisplay), senderName);
    }
    if (target > 0)
    {
        BuildPurchaseDisplayName(target, targetDisplay, sizeof(targetDisplay));
    }
    else
    {
        strcopy(targetDisplay, sizeof(targetDisplay), targetName);
    }

    char currencyColor[BP_CURRENCY_COLOR_MAX + 2];
    char currencyName[BP_CURRENCY_SHORT_MAX];
    GetCurrencyColorTag(currencyColor, sizeof(currencyColor));
    GetCurrencyShortLabelForAmount(amount, currencyName, sizeof(currencyName));
    for (int recipient = 1; recipient <= MaxClients; recipient++)
    {
        if (Client_IsHumanInGame(recipient))
        {
            CPrintToChatEx(recipient, Client_IsHumanInGame(client) ? client : recipient,
                "%s %s placed a %s%d %s{default} bounty on %s! Dominate him to get the gems!",
                g_BountyPrefix,
                senderDisplay,
                currencyColor,
                amount,
                currencyName,
                targetDisplay);
        }
    }
    PlayBountySaySound(BOUNTY_CHALLENGE_SOUND);
    PrintBountyTargetInstructions(target);

    LogPointsStoreEvent(
        "event=bounty_placed|time=%d|sender=%s|target=%s|amount=%d|expires_at=%d",
        GetTime(), senderSteamId, targetSteamId, amount, GetTime() + BOUNTY_WALL_EXPIRY_SECONDS);
}

public void SQLTxn_OnBountyPlacementFailed(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    delete pack;
    if (client > 0)
    {
        g_BountyPlacementPending[client] = false;
    }
    LogError("[points_store] Bounty placement failed at query %d: %s", failIndex, error);
    if (Client_IsHumanInGame(client))
    {
        LoadClientBonusPoints(client);
        CPrintToChat(client, "%s Could not place that bounty.", g_BountyPrefix);
    }
}

