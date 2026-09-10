void BeginMailRedemption(int client, int mailId)
{
    if (!g_MailDatabaseReady || g_MailDatabase == null
        || !IsPointsStoreAwardAvailable() || mailId <= 0)
    {
        CPrintToChat(client, "%s Currency redemption is temporarily unavailable.", MAIL_PREFIX);
        return;
    }

    char awardKey[MAIL_REQUEST_KEY_MAX];
    Format(awardKey, sizeof(awardKey), "server_mail:redeem:%d", mailId);
    int unused;
    if (g_MailPendingRedemptions.GetValue(awardKey, unused))
    {
        CPrintToChat(client, "%s This attachment is already being redeemed.", MAIL_PREFIX);
        return;
    }

    char steamId[MAIL_STEAMID_MAX];
    char name[MAIL_NAME_MAX];
    if (!GetMailClientIdentity(client, steamId, sizeof(steamId), name, sizeof(name)))
    {
        return;
    }

    char escapedSteam[65];
    EscapeMailSql(steamId, escapedSteam, sizeof(escapedSteam));
    char query[768];
    FormatEx(query, sizeof(query),
        "SELECT title, gems FROM %s "
        ... "WHERE mail_id = %d AND receiver_steamid64 = '%s' "
        ... "AND gems > 0 AND gems_redeemed = 0 "
        ... "AND (expires_at = 0 OR expires_at > %d) LIMIT 1",
        MAIL_TABLE,
        mailId,
        escapedSteam,
        GetTime());

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(mailId);
    pack.WriteString(steamId);
    g_MailDatabase.Query(SQL_OnMailRedemptionValidated, query, pack);
}

public void SQL_OnMailRedemptionValidated(Database db, DBResultSet rows, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    int mailId = pack.ReadCell();
    char steamId[MAIL_STEAMID_MAX];
    pack.ReadString(steamId, sizeof(steamId));
    delete pack;

    int client = GetClientOfUserId(userId);
    if (!IsMailClient(client))
    {
        return;
    }
    if (error[0] != '\0' || rows == null || !rows.FetchRow())
    {
        CPrintToChat(client, "%s This attachment is unavailable or already redeemed.", MAIL_PREFIX);
        return;
    }

    char title[MAIL_TITLE_MAX];
    rows.FetchString(0, title, sizeof(title));
    int gems = rows.FetchInt(1);

    MailRedemptionQueueResult result = QueueValidatedMailRedemption(client, mailId, steamId, title, gems);
    if (result == MailRedemption_AlreadyPending)
    {
        CPrintToChat(client, "%s This attachment is already being redeemed.", MAIL_PREFIX);
    }
    else if (result == MailRedemption_Failed)
    {
        CPrintToChat(client, "%s Currency redemption could not be queued. Try again.", MAIL_PREFIX);
    }
}

MailRedemptionQueueResult QueueValidatedMailRedemption(
    int client,
    int mailId,
    const char[] steamId,
    const char[] rawTitle,
    int gems)
{
    if (!IsMailClient(client) || mailId <= 0 || gems <= 0 || !IsPointsStoreAwardAvailable())
    {
        return MailRedemption_Failed;
    }

    char awardKey[MAIL_REQUEST_KEY_MAX];
    Format(awardKey, sizeof(awardKey), "server_mail:redeem:%d", mailId);
    int unused;
    if (g_MailPendingRedemptions.GetValue(awardKey, unused))
    {
        return MailRedemption_AlreadyPending;
    }

    char title[MAIL_TITLE_MAX];
    strcopy(title, sizeof(title), rawTitle);
    if (StrEqual(title, "N/A", false))
    {
        char currencyColor[40];
        char currencyName[64];
        GetCurrencyFormatting(currencyColor, sizeof(currencyColor), currencyName, sizeof(currencyName));
        FormatEx(title, sizeof(title), "%d %s", gems, currencyName);
    }

    g_MailPendingRedemptions.SetValue(awardKey, mailId);
    g_MailRedemptionUsers.SetValue(awardKey, GetClientUserId(client));
    g_MailRedemptionTitles.SetString(awardKey, title);
    g_MailRedemptionSteamIds.SetString(awardKey, steamId);
    g_MailRedemptionAmounts.SetValue(awardKey, gems);

    if (!PointsStore_ApplyBonusPointsSteamIdOnce(steamId, gems, awardKey, "server_mail_redemption"))
    {
        ClearPendingRedemption(awardKey);
        return MailRedemption_Failed;
    }

    return MailRedemption_Queued;
}

void ClearPendingRedemption(const char[] awardKey)
{
    g_MailPendingRedemptions.Remove(awardKey);
    g_MailRedemptionUsers.Remove(awardKey);
    g_MailRedemptionTitles.Remove(awardKey);
    g_MailRedemptionSteamIds.Remove(awardKey);
    g_MailRedemptionAmounts.Remove(awardKey);
}

public void PointsStore_OnApplyBonusPointsSteamIdOnce(const char[] awardKey, bool success, bool newlyApplied)
{
    int mailId;
    if (!g_MailPendingRedemptions.GetValue(awardKey, mailId))
    {
        return;
    }

    int userId;
    int gems;
    char steamId[MAIL_STEAMID_MAX];
    char title[MAIL_TITLE_MAX];
    g_MailRedemptionUsers.GetValue(awardKey, userId);
    g_MailRedemptionAmounts.GetValue(awardKey, gems);
    g_MailRedemptionSteamIds.GetString(awardKey, steamId, sizeof(steamId));
    g_MailRedemptionTitles.GetString(awardKey, title, sizeof(title));

    if (!success)
    {
        int client = GetClientOfUserId(userId);
        if (IsMailClient(client))
        {
            CPrintToChat(client, "%s Currency redemption failed. Try again.", MAIL_PREFIX);
        }
        ClearPendingRedemption(awardKey);
        return;
    }

    char escapedSteam[65];
    if (!EscapeMailSql(steamId, escapedSteam, sizeof(escapedSteam)))
    {
        ClearPendingRedemption(awardKey);
        return;
    }

    char query[512];
    FormatEx(query, sizeof(query),
        "UPDATE %s SET gems_redeemed = 1, expires_at = 0, "
        ... "read_at = CASE WHEN read_at = 0 THEN %d ELSE read_at END "
        ... "WHERE mail_id = %d AND receiver_steamid64 = '%s' AND gems_redeemed = 0",
        MAIL_TABLE,
        GetTime(),
        mailId,
        escapedSteam);

    DataPack pack = new DataPack();
    pack.WriteString(awardKey);
    pack.WriteCell(userId);
    pack.WriteString(steamId);
    pack.WriteString(title);
    pack.WriteCell(gems);
    g_MailDatabase.Query(SQL_OnMailMarkedRedeemed, query, pack);
}

public void SQL_OnMailMarkedRedeemed(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    char awardKey[MAIL_REQUEST_KEY_MAX];
    char steamId[MAIL_STEAMID_MAX];
    char title[MAIL_TITLE_MAX];
    pack.ReadString(awardKey, sizeof(awardKey));
    int userId = pack.ReadCell();
    pack.ReadString(steamId, sizeof(steamId));
    pack.ReadString(title, sizeof(title));
    int gems = pack.ReadCell();
    delete pack;
    ClearPendingRedemption(awardKey);

    if (error[0] != '\0' || results == null || results.AffectedRows <= 0)
    {
        if (error[0] != '\0')
        {
            LogError("[server_mail] Failed to mark mail redeemed: %s", error);
        }
        return;
    }

    int client = GetClientOfUserId(userId);
    char fallbackName[MAIL_NAME_MAX];
    strcopy(fallbackName, sizeof(fallbackName), steamId);
    if (IsMailClient(client))
    {
        GetClientName(client, fallbackName, sizeof(fallbackName));
    }
    else if (GetFeatureStatus(FeatureType_Native, "Filters_GetLastRecordedSteamName") == FeatureStatus_Available)
    {
        Filters_GetLastRecordedSteamName(steamId, fallbackName, sizeof(fallbackName));
    }

    char coloredName[256];
    char currencyColor[40];
    char currencyName[64];
    BuildColoredMailName(client, steamId, fallbackName, coloredName, sizeof(coloredName));
    GetCurrencyFormatting(currencyColor, sizeof(currencyColor), currencyName, sizeof(currencyName));
    if (StrEqual(title, "Stimulus Check", false) && IsMailClient(client))
    {
        CPrintToChatAllEx(client,
            "{cornflowerblue}[Mail] %s{default} redeemed %s%d %s{default} from a %sStimulus Check{default}!",
            coloredName,
            currencyColor,
            gems,
            currencyName,
            currencyColor);
    }
    else if (StrEqual(title, "Stimulus Check", false))
    {
        CPrintToChatAll(
            "{cornflowerblue}[Mail] %s{default} redeemed %s%d %s{default} from a %sStimulus Check{default}!",
            coloredName,
            currencyColor,
            gems,
            currencyName,
            currencyColor);
    }
    else if (IsMailClient(client))
    {
        CPrintToChatAllEx(client,
            "{cornflowerblue}[Mail] %s{default} redeemed %s%s{default}!",
            coloredName,
            currencyColor,
            title);
    }
    else
    {
        CPrintToChatAll(
            "{cornflowerblue}[Mail] %s{default} redeemed %s%s{default}!",
            coloredName,
            currencyColor,
            title);
    }

    SaySounds_TryPlayCommand(0, "xp_levelup", true);
}

