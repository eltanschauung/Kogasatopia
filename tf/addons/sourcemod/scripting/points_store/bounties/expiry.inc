void ProcessExpiredBounties()
{
    if (!g_BountyDatabaseReady || g_Database == null || g_BountyExpiryPending)
    {
        return;
    }

    char token[BOUNTY_TOKEN_MAX];
    BuildBountyOperationToken("expire", token, sizeof(token));
    char escapedToken[(BOUNTY_TOKEN_MAX * 2) + 1];
    if (!EscapeSql(token, escapedToken, sizeof(escapedToken)))
    {
        return;
    }

    int now = GetTime();
    Transaction txn = new Transaction();
    char query[2048];
    FormatEx(query, sizeof(query),
        "UPDATE %s SET status = 'expired', resolved_at = %d, resolution_token = '%s' "
        ... "WHERE status = 'active' AND expires_at <= %d",
        BOUNTY_TABLE,
        now,
        escapedToken,
        now);
    txn.AddQuery(query);

    if (g_IsMySql)
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO %s (steamid64, balance) "
            ... "SELECT sender_steamid64, SUM(amount) FROM %s WHERE resolution_token = '%s' AND sender_steamid64 != '%s' GROUP BY sender_steamid64 "
            ... "ON DUPLICATE KEY UPDATE balance = balance + VALUES(balance)",
            BP_BALANCE_TABLE,
            BOUNTY_TABLE,
            escapedToken,
            BOUNTY_SYSTEM_STEAMID);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO %s (steamid64, balance) "
            ... "SELECT sender_steamid64, SUM(amount) FROM %s WHERE resolution_token = '%s' AND sender_steamid64 != '%s' GROUP BY sender_steamid64 "
            ... "ON CONFLICT(steamid64) DO UPDATE SET balance = balance + excluded.balance",
            BP_BALANCE_TABLE,
            BOUNTY_TABLE,
            escapedToken,
            BOUNTY_SYSTEM_STEAMID);
    }
    txn.AddQuery(query);

    FormatEx(query, sizeof(query),
        "SELECT sender_steamid64, MAX(sender_name), target_steamid64, MAX(target_name), amount "
        ... "FROM %s WHERE resolution_token = '%s' "
        ... "GROUP BY bounty_id, sender_steamid64, target_steamid64, amount ORDER BY bounty_id",
        BOUNTY_TABLE,
        escapedToken);
    txn.AddQuery(query);

    DataPack pack = new DataPack();
    pack.WriteString(token);
    g_BountyExpiryPending = true;
    g_Database.Execute(txn, SQLTxn_OnBountiesExpired, SQLTxn_OnBountyExpiryFailed, pack);
}

public void SQLTxn_OnBountiesExpired(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    char token[BOUNTY_TOKEN_MAX];
    pack.ReadString(token, sizeof(token));
    delete pack;
    g_BountyExpiryPending = false;

    int totalRefunded = 0;
    int expiredCount = 0;
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
            bool systemBounty = StrEqual(senderSteamId, BOUNTY_SYSTEM_STEAMID, false);
            expiredCount++;
            if (!systemBounty)
            {
                totalRefunded += amount;
            }
            int sender = Kogasa_FindClientBySteamId64(senderSteamId);
            if (!systemBounty && sender > 0 && g_ClientBonusPointsLoaded[sender])
            {
                int balanceBefore = g_ClientBonusPoints[sender];
                g_ClientBonusPoints[sender] += amount;
                LogBonusPointsDelta(sender, amount, balanceBefore, g_ClientBonusPoints[sender], "bounty_week_refund", 0, false, false, 1.0, true, 0, 0);
            }

            char senderDisplay[256];
            char targetDisplay[256];
            BuildBountyDisplayName(senderSteamId, senderName, senderDisplay, sizeof(senderDisplay));
            BuildBountyDisplayName(targetSteamId, targetName, targetDisplay, sizeof(targetDisplay));
            for (int recipient = 1; recipient <= MaxClients; recipient++)
            {
                if (Client_IsHumanInGame(recipient))
                {
                    CPrintToChatEx(recipient, sender > 0 ? sender : recipient,
                        "%s %s's bounty on %s expired due to one week without resolution!",
                        g_BountyPrefix,
                        senderDisplay,
                        targetDisplay);
                }
            }
        }
    }
    if (expiredCount > 0)
    {
        LogPointsStoreEvent(
            "event=bounty_expired|time=%d|refund_total=%d|token=%s",
            GetTime(), totalRefunded, token);
        PlayBountySaySound(BOUNTY_EVENT_SOUND);
        RefreshActiveBountyTargets();
    }
}

public void SQLTxn_OnBountyExpiryFailed(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    delete pack;
    g_BountyExpiryPending = false;
    LogError("[points_store] Bounty expiry failed at query %d: %s", failIndex, error);
}

