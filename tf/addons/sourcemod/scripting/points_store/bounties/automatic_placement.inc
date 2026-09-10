public void Event_BountyRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_BountyDatabaseReady || g_Database == null)
    {
        return;
    }

    ProcessDisconnectedBountyRefunds();
    if (g_BountyAutomaticPlacementPending || g_ActiveBountyCount >= BOUNTY_MAX_ACTIVE
        || GetRandomInt(1, 100) > BOUNTY_AUTOMATIC_CHANCE_PERCENT)
    {
        return;
    }

    char steamIds[2048];
    char steamId[BOUNTY_STEAMID_MAX];
    char escapedSteamId[(BOUNTY_STEAMID_MAX * 2) + 1];
    char fragment[80];
    int candidateCount = 0;
    int playerResource = GetPlayerResourceEntity();
    steamIds[0] = '\0';

    for (int client = 1; client <= MaxClients; client++)
    {
        int team = Client_IsHumanInGame(client) ? GetClientTeam(client) : 0;
        int kills = team == 2 || team == 3 ? GetClientFrags(client) : 0;
        int deaths = team == 2 || team == 3 ? GetClientDeaths(client) : 0;
        int assists = playerResource != -1 && g_BountyKillAssistsOffset > 0 && (team == 2 || team == 3)
            ? GetEntData(playerResource, g_BountyKillAssistsOffset + (client * 4))
            : 0;
        if ((team != 2 && team != 3) || !AreBonusPointsReady(client)
            || GetCachedBonusPoints(client) <= BOUNTY_AUTOMATIC_MIN_BALANCE
            || deaths < GetAutomaticBountyMinDeaths()
            || (kills + assists) < (BOUNTY_AUTOMATIC_MIN_RATIO * (deaths > 0 ? deaths : 1))
            || !GetClientSteamId64(client, steamId, sizeof(steamId))
            || !EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId)))
        {
            continue;
        }

        FormatEx(fragment, sizeof(fragment), "%s_binary'%s'", candidateCount > 0 ? "," : "", escapedSteamId);
        StrCat(steamIds, sizeof(steamIds), fragment);
        candidateCount++;
    }

    if (candidateCount == 0)
    {
        return;
    }

    char query[3072];
    FormatEx(query, sizeof(query),
        "SELECT b.steamid64 FROM %s b "
        ... "WHERE BINARY b.steamid64 IN (%s) AND b.balance > %d "
        ... "AND NOT EXISTS (SELECT 1 FROM %s active_bounty WHERE BINARY active_bounty.target_steamid64 = BINARY b.steamid64 "
        ... "AND active_bounty.status = 'active' AND active_bounty.expires_at > %d) "
        ... "AND NOT EXISTS (SELECT 1 FROM %s recent_automatic WHERE BINARY recent_automatic.target_steamid64 = BINARY b.steamid64 "
        ... "AND recent_automatic.sender_steamid64 = '%s' AND recent_automatic.placed_at > %d) "
        ... "ORDER BY %s LIMIT 1",
        BP_BALANCE_TABLE,
        steamIds,
        BOUNTY_AUTOMATIC_MIN_BALANCE,
        BOUNTY_TABLE,
        GetTime(),
        BOUNTY_TABLE,
        BOUNTY_SYSTEM_STEAMID,
        GetTime() - BOUNTY_AUTOMATIC_TARGET_COOLDOWN_SECONDS,
        g_IsMySql ? "RAND()" : "RANDOM()");
    g_BountyAutomaticPlacementPending = true;
    g_Database.Query(SQL_OnAutomaticBountyCandidateSelected, query);
}

public void SQL_OnAutomaticBountyCandidateSelected(Database db, DBResultSet rows, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        g_BountyAutomaticPlacementPending = false;
        LogError("[points_store] Automatic bounty candidate query failed: %s", error);
        return;
    }

    char steamId[BOUNTY_STEAMID_MAX];
    if (rows == null || !rows.FetchRow())
    {
        g_BountyAutomaticPlacementPending = false;
        return;
    }
    rows.FetchString(0, steamId, sizeof(steamId));

    int target = Kogasa_FindClientBySteamId64(steamId);
    int team = Client_IsHumanInGame(target) ? GetClientTeam(target) : 0;
    if ((team != 2 && team != 3) || !AreBonusPointsReady(target)
        || GetCachedBonusPoints(target) <= BOUNTY_AUTOMATIC_MIN_BALANCE)
    {
        g_BountyAutomaticPlacementPending = false;
        return;
    }

    QueueAutomaticBounty(target, steamId);
}

void QueueAutomaticBounty(int target, const char[] targetSteamId)
{
    char targetName[BOUNTY_NAME_MAX];
    char escapedTargetSteam[(BOUNTY_STEAMID_MAX * 2) + 1];
    char escapedTargetName[(BOUNTY_NAME_MAX * 2) + 1];
    GetClientName(target, targetName, sizeof(targetName));
    if (!EscapeSql(targetSteamId, escapedTargetSteam, sizeof(escapedTargetSteam))
        || !EscapeSql(targetName, escapedTargetName, sizeof(escapedTargetName)))
    {
        g_BountyAutomaticPlacementPending = false;
        return;
    }

    int now = GetTime();
    int targetPlaytime = 0;
    if (GetFeatureStatus(FeatureType_Native, "WhaleTracker_GetRankedPlaytimeSeconds") == FeatureStatus_Available)
    {
        targetPlaytime = WhaleTracker_GetRankedPlaytimeSeconds(target, targetSteamId);
    }

    char query[1536];
    FormatEx(query, sizeof(query),
        "INSERT INTO %s (sender_steamid64, sender_name, target_steamid64, target_name, amount, placed_at, expires_at, "
        ... "qualifying_playtime_seconds, last_target_playtime_seconds, status) "
        ... "SELECT '%s', 'kogasa.tf', '%s', '%s', %d, %d, %d, 0, %d, 'active' "
        ... "WHERE (SELECT COUNT(DISTINCT target_steamid64) FROM %s WHERE status = 'active' AND expires_at > %d) < %d "
        ... "AND NOT EXISTS (SELECT 1 FROM %s WHERE target_steamid64 = '%s' AND status = 'active' AND expires_at > %d) "
        ... "AND NOT EXISTS (SELECT 1 FROM %s WHERE target_steamid64 = '%s' AND sender_steamid64 = '%s' AND placed_at > %d)",
        BOUNTY_TABLE,
        BOUNTY_SYSTEM_STEAMID,
        escapedTargetSteam,
        escapedTargetName,
        BOUNTY_AUTOMATIC_AMOUNT,
        now,
        now + BOUNTY_WALL_EXPIRY_SECONDS,
        targetPlaytime,
        BOUNTY_TABLE,
        now,
        BOUNTY_MAX_ACTIVE,
        BOUNTY_TABLE,
        escapedTargetSteam,
        now,
        BOUNTY_TABLE,
        escapedTargetSteam,
        BOUNTY_SYSTEM_STEAMID,
        now - BOUNTY_AUTOMATIC_TARGET_COOLDOWN_SECONDS);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(target));
    pack.WriteString(targetSteamId);
    pack.WriteString(targetName);
    g_Database.Query(SQL_OnAutomaticBountyPlaced, query, pack);
}

public void SQL_OnAutomaticBountyPlaced(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int target = GetClientOfUserId(pack.ReadCell());
    char targetSteamId[BOUNTY_STEAMID_MAX];
    char targetName[BOUNTY_NAME_MAX];
    pack.ReadString(targetSteamId, sizeof(targetSteamId));
    pack.ReadString(targetName, sizeof(targetName));
    delete pack;
    g_BountyAutomaticPlacementPending = false;

    if (error[0] != '\0')
    {
        LogError("[points_store] Automatic bounty placement failed: %s", error);
        return;
    }
    if (results == null || results.AffectedRows <= 0)
    {
        return;
    }

    MarkActiveBountyTarget(targetSteamId);
    RefreshActiveBountyTargets();

    char targetDisplay[256];
    BuildBountyDisplayName(targetSteamId, targetName, targetDisplay, sizeof(targetDisplay));
    char currencyName[BP_CURRENCY_SHORT_MAX];
    GetCurrencyShortLabelForAmount(BOUNTY_AUTOMATIC_AMOUNT, currencyName, sizeof(currencyName));
    for (int recipient = 1; recipient <= MaxClients; recipient++)
    {
        if (Client_IsHumanInGame(recipient))
        {
            CPrintToChatEx(recipient, target > 0 ? target : recipient,
                "%s Dominate %s to get %s%d %s{default}!",
                g_BountyPrefix,
                targetDisplay,
                g_CurrencyColorTag,
                BOUNTY_AUTOMATIC_AMOUNT,
                currencyName);
        }
    }
    PrintBountyTargetInstructions(target);
    PlayBountySaySound(BOUNTY_CHALLENGE_SOUND);
    LogPointsStoreEvent(
        "event=bounty_placed|time=%d|sender=%s|target=%s|amount=%d|expires_at=%d|automatic=1",
        GetTime(), BOUNTY_SYSTEM_STEAMID, targetSteamId, BOUNTY_AUTOMATIC_AMOUNT,
        GetTime() + BOUNTY_WALL_EXPIRY_SECONDS);
}

void PrintBountyTargetInstructions(int target)
{
    if (!Client_IsHumanInGame(target))
    {
        return;
    }

    CPrintToChat(target,
        "%s If an enemy dominates you, they collect the bounty; if you avoid being dominated for {gold}%d minutes{default}, you collect the gems yourself!",
        g_BountyPrefix,
        (GetBountyPlaytimeLimitSeconds() + 59) / 60);
}

