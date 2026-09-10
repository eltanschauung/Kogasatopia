void BuildBountyDisplayName(const char[] steamId, const char[] fallbackName, char[] buffer, int maxlen)
{
    int client = Kogasa_FindClientBySteamId64(steamId);
    if (client > 0)
    {
        BuildPurchaseDisplayName(client, buffer, maxlen);
        return;
    }

    char colorTag[32];
    if (GetFeatureStatus(FeatureType_Native, "Filters_GetSteamIdColorTag") == FeatureStatus_Available
        && Filters_GetSteamIdColorTag(steamId, colorTag, sizeof(colorTag))
        && colorTag[0] != '\0')
    {
        FormatEx(buffer, maxlen, "%s%s{default}", colorTag, fallbackName);
        return;
    }
    strcopy(buffer, maxlen, fallbackName);
}

void RequestBountyProgress()
{
    if (!g_BountyDatabaseReady || g_Database == null || g_BountyProgressPending)
    {
        return;
    }
    if (GetFeatureStatus(FeatureType_Native, "WhaleTracker_GetRankedPlaytimeSeconds") != FeatureStatus_Available)
    {
        return;
    }

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT DISTINCT target_steamid64 FROM %s WHERE status = 'active' AND expires_at > %d",
        BOUNTY_TABLE,
        GetTime());
    g_BountyProgressPending = true;
    g_Database.Query(SQL_OnBountyProgressTargetsLoaded, query);
}

public void SQL_OnBountyProgressTargetsLoaded(Database db, DBResultSet rows, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        g_BountyProgressPending = false;
        LogError("[points_store] Bounty progress target query failed: %s", error);
        return;
    }

    bool countPlaytime = IsBountyPopulationEligible();
    int now = GetTime();
    int playtimeLimit = GetBountyPlaytimeLimitSeconds();
    int halftime = GetBountyHalftimeSeconds();
    int updateCount = 0;
    Transaction txn = new Transaction();
    char targetSteamId[BOUNTY_STEAMID_MAX];
    char escapedTargetSteam[65];
    char query[2048];
    while (rows != null && rows.FetchRow())
    {
        rows.FetchString(0, targetSteamId, sizeof(targetSteamId));
        int target = Kogasa_FindClientBySteamId64(targetSteamId);
        if (!Client_IsHumanInGame(target))
        {
            continue;
        }

        int currentPlaytime = WhaleTracker_GetRankedPlaytimeSeconds(target);
        if (currentPlaytime <= 0 || !EscapeSql(targetSteamId, escapedTargetSteam, sizeof(escapedTargetSteam)))
        {
            continue;
        }

        if (g_IsMySql)
        {
            FormatEx(query, sizeof(query),
                "UPDATE %s SET qualifying_playtime_seconds = LEAST(%d, qualifying_playtime_seconds + "
                ... "IF(%d = 1 AND last_target_playtime_seconds > 0 AND %d >= last_target_playtime_seconds, "
                ... "%d - last_target_playtime_seconds, 0)), last_target_playtime_seconds = %d "
                ... "WHERE target_steamid64 = '%s' AND status = 'active' AND expires_at > %d",
                BOUNTY_TABLE,
                playtimeLimit,
                countPlaytime ? 1 : 0,
                currentPlaytime,
                currentPlaytime,
                currentPlaytime,
                escapedTargetSteam,
                now);
        }
        else
        {
            FormatEx(query, sizeof(query),
                "UPDATE %s SET qualifying_playtime_seconds = MIN(%d, qualifying_playtime_seconds + "
                ... "CASE WHEN %d = 1 AND last_target_playtime_seconds > 0 AND %d >= last_target_playtime_seconds "
                ... "THEN %d - last_target_playtime_seconds ELSE 0 END), last_target_playtime_seconds = %d "
                ... "WHERE target_steamid64 = '%s' AND status = 'active' AND expires_at > %d",
                BOUNTY_TABLE,
                playtimeLimit,
                countPlaytime ? 1 : 0,
                currentPlaytime,
                currentPlaytime,
                currentPlaytime,
                escapedTargetSteam,
                now);
        }
        txn.AddQuery(query);
        updateCount++;
    }

    if (updateCount == 0)
    {
        delete txn;
        g_BountyProgressPending = false;
        return;
    }

    char token[BOUNTY_TOKEN_MAX];
    char escapedToken[(BOUNTY_TOKEN_MAX * 2) + 1];
    BuildBountyOperationToken("survived", token, sizeof(token));
    if (!EscapeSql(token, escapedToken, sizeof(escapedToken)))
    {
        delete txn;
        g_BountyProgressPending = false;
        return;
    }

    FormatEx(query, sizeof(query),
        "UPDATE %s SET halftime_announced = 2 "
        ... "WHERE status = 'active' AND expires_at > %d AND halftime_announced = 0 "
        ... "AND qualifying_playtime_seconds >= %d",
        BOUNTY_TABLE,
        now,
        halftime);
    txn.AddQuery(query);

    int halftimeQueryIndex = updateCount + 1;
    FormatEx(query, sizeof(query),
        "SELECT SUM(all_bounties.amount + all_bounties.bonus_amount), all_bounties.target_steamid64, MAX(all_bounties.target_name) "
        ... "FROM %s all_bounties WHERE all_bounties.status = 'active' AND all_bounties.expires_at > %d "
        ... "AND EXISTS (SELECT 1 FROM %s alert_bounty WHERE alert_bounty.target_steamid64 = all_bounties.target_steamid64 "
        ... "AND alert_bounty.status = 'active' AND alert_bounty.halftime_announced = 2) "
        ... "GROUP BY all_bounties.target_steamid64 ORDER BY all_bounties.target_steamid64",
        BOUNTY_TABLE,
        now,
        BOUNTY_TABLE);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query),
        "UPDATE %s SET halftime_announced = 1 WHERE halftime_announced = 2",
        BOUNTY_TABLE);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query),
        "UPDATE %s SET status = 'survived', resolved_at = %d, resolution_token = '%s' "
        ... "WHERE status = 'active' AND expires_at > %d AND qualifying_playtime_seconds >= %d",
        BOUNTY_TABLE,
        now,
        escapedToken,
        now,
        playtimeLimit);
    txn.AddQuery(query);

    if (g_IsMySql)
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO %s (steamid64, balance) "
            ... "SELECT target_steamid64, SUM(amount + bonus_amount) FROM %s "
            ... "WHERE resolution_token = '%s' GROUP BY target_steamid64 "
            ... "ON DUPLICATE KEY UPDATE balance = balance + VALUES(balance)",
            BP_BALANCE_TABLE,
            BOUNTY_TABLE,
            escapedToken);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO %s (steamid64, balance) "
            ... "SELECT target_steamid64, SUM(amount + bonus_amount) FROM %s "
            ... "WHERE resolution_token = '%s' GROUP BY target_steamid64 "
            ... "ON CONFLICT(steamid64) DO UPDATE SET balance = balance + excluded.balance",
            BP_BALANCE_TABLE,
            BOUNTY_TABLE,
            escapedToken);
    }
    txn.AddQuery(query);

    int summaryQueryIndex = updateCount + 5;
    FormatEx(query, sizeof(query),
        "SELECT target_steamid64, MAX(target_name), SUM(amount + bonus_amount) "
        ... "FROM %s WHERE resolution_token = '%s' GROUP BY target_steamid64",
        BOUNTY_TABLE,
        escapedToken);
    txn.AddQuery(query);

    DataPack pack = new DataPack();
    pack.WriteString(token);
    pack.WriteCell(halftimeQueryIndex);
    pack.WriteCell(summaryQueryIndex);
    g_Database.Execute(txn, SQLTxn_OnBountiesSurvived, SQLTxn_OnBountyProgressFailed, pack);
}

public void SQLTxn_OnBountiesSurvived(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    char token[BOUNTY_TOKEN_MAX];
    pack.ReadString(token, sizeof(token));
    int halftimeQueryIndex = pack.ReadCell();
    int summaryQueryIndex = pack.ReadCell();
    delete pack;
    g_BountyProgressPending = false;

    if (halftimeQueryIndex < numQueries && results[halftimeQueryIndex] != null)
    {
        char targetSteamId[BOUNTY_STEAMID_MAX];
        char targetName[BOUNTY_NAME_MAX];
        char targetDisplay[256];
        char currencyName[BP_CURRENCY_SHORT_MAX];
        while (results[halftimeQueryIndex].FetchRow())
        {
            int amount = results[halftimeQueryIndex].FetchInt(0);
            results[halftimeQueryIndex].FetchString(1, targetSteamId, sizeof(targetSteamId));
            results[halftimeQueryIndex].FetchString(2, targetName, sizeof(targetName));
            BuildBountyDisplayName(targetSteamId, targetName, targetDisplay, sizeof(targetDisplay));
            GetCurrencyShortLabelForAmount(amount, currencyName, sizeof(currencyName));

            int target = Kogasa_FindClientBySteamId64(targetSteamId);
            for (int recipient = 1; recipient <= MaxClients; recipient++)
            {
                if (Client_IsHumanInGame(recipient))
                {
                    CPrintToChatEx(recipient, target > 0 ? target : recipient,
                        "%s %s's bounty is now %s%d %s{default} and expires in {gold}%d minutes{default}!",
                        g_BountyPrefix,
                        targetDisplay,
                        g_CurrencyColorTag,
                        amount,
                        currencyName,
                        GetBountyHalftimeRemainingMinutes());
                }
            }
            LogPointsStoreEvent(
                "event=bounty_halftime|time=%d|target=%s|amount=%d",
                GetTime(), targetSteamId, amount);
        }
    }

    bool resolvedAny = false;
    if (summaryQueryIndex < numQueries && results[summaryQueryIndex] != null)
    {
        char targetSteamId[BOUNTY_STEAMID_MAX];
        char targetName[BOUNTY_NAME_MAX];
        while (results[summaryQueryIndex].FetchRow())
        {
            results[summaryQueryIndex].FetchString(0, targetSteamId, sizeof(targetSteamId));
            results[summaryQueryIndex].FetchString(1, targetName, sizeof(targetName));
            int payout = results[summaryQueryIndex].FetchInt(2);
            resolvedAny = true;

            int target = Kogasa_FindClientBySteamId64(targetSteamId);
            if (target > 0 && g_ClientBonusPointsLoaded[target])
            {
                int balanceBefore = g_ClientBonusPoints[target];
                g_ClientBonusPoints[target] += payout;
                LogBonusPointsDelta(target, payout, balanceBefore, g_ClientBonusPoints[target], "bounty_survived", 0, true, true, 1.0, true, 0, 0);
                PlayLevelUpSound(target);
            }

            char targetDisplay[256];
            BuildBountyDisplayName(targetSteamId, targetName, targetDisplay, sizeof(targetDisplay));
            char currencyName[BP_CURRENCY_SHORT_MAX];
            GetCurrencyShortLabelForAmount(payout, currencyName, sizeof(currencyName));
            for (int recipient = 1; recipient <= MaxClients; recipient++)
            {
                if (Client_IsHumanInGame(recipient))
                {
                    CPrintToChatEx(recipient, target > 0 ? target : recipient,
                        "%s %s received %s%d %s{default} for surviving a bounty hunt!",
                        g_BountyPrefix,
                        targetDisplay,
                        g_CurrencyColorTag,
                        payout,
                        currencyName);
                }
            }

            LogPointsStoreEvent(
                "event=bounty_survived|time=%d|target=%s|payout=%d|token=%s",
                GetTime(), targetSteamId, payout, token);
        }
    }

    if (resolvedAny)
    {
        PlayBountySaySound(BOUNTY_EVENT_SOUND);
        RefreshActiveBountyTargets();
    }
}

public void SQLTxn_OnBountyProgressFailed(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    delete pack;
    g_BountyProgressPending = false;
    LogError("[points_store] Bounty progress failed at query %d: %s", failIndex, error);
}
