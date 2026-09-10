void BuildBountyOperationToken(const char[] prefix, char[] buffer, int maxlen)
{
    ConVar hostPort = FindConVar("hostport");
    int port = hostPort != null ? hostPort.IntValue : 0;
    g_BountyOperationSerial++;
    FormatEx(buffer, maxlen, "%s_%d_%d_%d_%d", prefix, GetTime(), port, g_BountyOperationSerial, GetRandomInt(1000, 999999));
}

void PlayBountySaySound(const char[] command)
{
    if (GetFeatureStatus(FeatureType_Native, "SaySounds_PlayCommand") == FeatureStatus_Available)
    {
        SaySounds_PlayCommand(0, command, true);
    }
}

void ClaimBountiesForDomination(int attacker, int victim)
{
    if (!g_BountyDatabaseReady || g_Database == null)
    {
        return;
    }

    char attackerSteamId[BOUNTY_STEAMID_MAX];
    char victimSteamId[BOUNTY_STEAMID_MAX];
    char attackerName[BOUNTY_NAME_MAX];
    char victimName[BOUNTY_NAME_MAX];
    GetClientName(attacker, attackerName, sizeof(attackerName));
    GetClientName(victim, victimName, sizeof(victimName));
    if (!GetClientSteamId64(attacker, attackerSteamId, sizeof(attackerSteamId))
        || !GetClientSteamId64(victim, victimSteamId, sizeof(victimSteamId)))
    {
        return;
    }

    char token[BOUNTY_TOKEN_MAX];
    BuildBountyOperationToken("claim", token, sizeof(token));
    char escapedToken[(BOUNTY_TOKEN_MAX * 2) + 1];
    char escapedAttackerSteam[65];
    char escapedAttackerName[(BOUNTY_NAME_MAX * 2) + 1];
    char escapedVictimSteam[65];
    if (!EscapeSql(token, escapedToken, sizeof(escapedToken))
        || !EscapeSql(attackerSteamId, escapedAttackerSteam, sizeof(escapedAttackerSteam))
        || !EscapeSql(attackerName, escapedAttackerName, sizeof(escapedAttackerName))
        || !EscapeSql(victimSteamId, escapedVictimSteam, sizeof(escapedVictimSteam)))
    {
        return;
    }

    int now = GetTime();
    Transaction txn = new Transaction();
    char query[2048];
    FormatEx(query, sizeof(query),
        "UPDATE %s SET status = 'claimed', resolved_at = %d, resolution_token = '%s', "
        ... "claimed_by_steamid64 = '%s', claimed_by_name = '%s' "
        ... "WHERE target_steamid64 = '%s' AND status = 'active' AND expires_at > %d",
        BOUNTY_TABLE,
        now,
        escapedToken,
        escapedAttackerSteam,
        escapedAttackerName,
        escapedVictimSteam,
        now);
    txn.AddQuery(query);

    if (g_IsMySql)
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO %s (steamid64, balance) "
            ... "SELECT '%s', SUM(amount + bonus_amount) FROM %s WHERE resolution_token = '%s' HAVING SUM(amount + bonus_amount) > 0 "
            ... "ON DUPLICATE KEY UPDATE balance = balance + VALUES(balance)",
            BP_BALANCE_TABLE,
            escapedAttackerSteam,
            BOUNTY_TABLE,
            escapedToken);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO %s (steamid64, balance) "
            ... "SELECT '%s', SUM(amount + bonus_amount) FROM %s WHERE resolution_token = '%s' HAVING SUM(amount + bonus_amount) > 0 "
            ... "ON CONFLICT(steamid64) DO UPDATE SET balance = balance + excluded.balance",
            BP_BALANCE_TABLE,
            escapedAttackerSteam,
            BOUNTY_TABLE,
            escapedToken);
    }
    txn.AddQuery(query);

    FormatEx(query, sizeof(query),
        "SELECT COALESCE(SUM(amount + bonus_amount), 0) FROM %s WHERE resolution_token = '%s'",
        BOUNTY_TABLE,
        escapedToken);
    txn.AddQuery(query);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(attacker));
    pack.WriteString(attackerSteamId);
    pack.WriteString(attackerName);
    pack.WriteString(victimSteamId);
    pack.WriteString(victimName);
    pack.WriteString(token);
    g_Database.Execute(txn, SQLTxn_OnBountyClaimed, SQLTxn_OnBountyClaimFailed, pack);
}

public void SQLTxn_OnBountyClaimed(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int attacker = GetClientOfUserId(pack.ReadCell());
    char attackerSteamId[BOUNTY_STEAMID_MAX];
    char attackerName[BOUNTY_NAME_MAX];
    char victimSteamId[BOUNTY_STEAMID_MAX];
    char victimName[BOUNTY_NAME_MAX];
    char token[BOUNTY_TOKEN_MAX];
    pack.ReadString(attackerSteamId, sizeof(attackerSteamId));
    pack.ReadString(attackerName, sizeof(attackerName));
    pack.ReadString(victimSteamId, sizeof(victimSteamId));
    pack.ReadString(victimName, sizeof(victimName));
    pack.ReadString(token, sizeof(token));
    delete pack;

    int amount = 0;
    if (numQueries >= 3 && results[2] != null && results[2].FetchRow())
    {
        amount = results[2].FetchInt(0);
    }
    if (amount <= 0)
    {
        return;
    }

    RefreshActiveBountyTargets();

    if (Client_IsHumanInGame(attacker))
    {
        char currentSteamId[BOUNTY_STEAMID_MAX];
        if (GetClientSteamId64(attacker, currentSteamId, sizeof(currentSteamId))
            && StrEqual(currentSteamId, attackerSteamId, false)
            && g_ClientBonusPointsLoaded[attacker])
        {
            int balanceBefore = g_ClientBonusPoints[attacker];
            g_ClientBonusPoints[attacker] += amount;
            LogBonusPointsDelta(attacker, amount, balanceBefore, g_ClientBonusPoints[attacker], "bounty_claim", 0, true, true, 1.0, true, 0, 0);
        }
        PlayBonusPointsSound(attacker, true);
    }

    char attackerDisplay[256];
    char victimDisplay[256];
    if (Client_IsHumanInGame(attacker))
    {
        BuildPurchaseDisplayName(attacker, attackerDisplay, sizeof(attackerDisplay));
    }
    else
    {
        strcopy(attackerDisplay, sizeof(attackerDisplay), attackerName);
    }
    int victim = Kogasa_FindClientBySteamId64(victimSteamId);
    if (victim > 0)
    {
        BuildPurchaseDisplayName(victim, victimDisplay, sizeof(victimDisplay));
    }
    else
    {
        strcopy(victimDisplay, sizeof(victimDisplay), victimName);
    }

    char currencyColor[BP_CURRENCY_COLOR_MAX + 2];
    char currencyName[BP_CURRENCY_SHORT_MAX];
    GetCurrencyColorTag(currencyColor, sizeof(currencyColor));
    GetCurrencyShortLabelForAmount(amount, currencyName, sizeof(currencyName));
    for (int recipient = 1; recipient <= MaxClients; recipient++)
    {
        if (Client_IsHumanInGame(recipient))
        {
            CPrintToChatEx(recipient, Client_IsHumanInGame(attacker) ? attacker : recipient,
                "%s %s received %s%d %s{default} for dominating %s!",
                g_BountyPrefix,
                attackerDisplay,
                currencyColor,
                amount,
                currencyName,
                victimDisplay);
        }
    }
    PlayBountySaySound(BOUNTY_EVENT_SOUND);

    LogPointsStoreEvent(
        "event=bounty_claimed|time=%d|claimant=%s|target=%s|amount=%d|token=%s",
        GetTime(), attackerSteamId, victimSteamId, amount, token);
}

public void SQLTxn_OnBountyClaimFailed(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    DataPack pack = view_as<DataPack>(data);
    delete pack;
    LogError("[points_store] Bounty claim failed at query %d: %s", failIndex, error);
}

