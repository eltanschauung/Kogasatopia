public Action Command_Mail(int client, int args)
{
    if (!IsMailClient(client))
    {
        return Plugin_Handled;
    }

    if (args == 0)
    {
        ShowMailMainMenu(client);
        return Plugin_Handled;
    }

    if (!CheckMailSendCooldown(client))
    {
        return Plugin_Handled;
    }

    BeginMailCommand(client);
    return Plugin_Handled;
}

public Action Command_Inbox(int client, int args)
{
    if (!IsMailClient(client))
    {
        return Plugin_Handled;
    }

    RequestMailList(client, MailView_Inbox);
    return Plugin_Handled;
}

public Action Command_Unread(int client, int args)
{
    if (!IsMailClient(client))
    {
        return Plugin_Handled;
    }

    RequestMailList(client, MailView_Unread);
    return Plugin_Handled;
}

public Action Command_ReadAll(int client, int args)
{
    if (!IsMailClient(client))
    {
        return Plugin_Handled;
    }
    if (!g_MailDatabaseReady || g_MailDatabase == null)
    {
        CPrintToChat(client, "%s Mail is temporarily unavailable.", MAIL_PREFIX);
        return Plugin_Handled;
    }
    if (g_MailReadAllPending[client])
    {
        CPrintToChat(client, "%s Your mail is still being updated.", MAIL_PREFIX);
        return Plugin_Handled;
    }

    char steamId[MAIL_STEAMID_MAX];
    char name[MAIL_NAME_MAX];
    char escapedSteam[65];
    if (!GetMailClientIdentity(client, steamId, sizeof(steamId), name, sizeof(name))
        || !EscapeMailSql(steamId, escapedSteam, sizeof(escapedSteam)))
    {
        return Plugin_Handled;
    }

    char query[384];
    FormatEx(query, sizeof(query),
        "UPDATE %s SET read_at = %d WHERE receiver_steamid64 = '%s' AND read_at = 0",
        MAIL_TABLE,
        GetTime(),
        escapedSteam);
    g_MailReadAllPending[client] = true;
    g_MailDatabase.Query(SQL_OnAllMailMarkedRead, query, GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnAllMailMarkedRead(Database db, DBResultSet results, const char[] error, any userId)
{
    int client = GetClientOfUserId(userId);
    if (client > 0)
    {
        g_MailReadAllPending[client] = false;
    }
    if (error[0] != '\0')
    {
        LogError("[server_mail] Failed to mark all mail as read: %s", error);
        if (IsMailClient(client))
        {
            CPrintToChat(client, "%s Failed to update your mail.", MAIL_PREFIX);
        }
        return;
    }
    if (IsMailClient(client))
    {
        CPrintToChat(client, "%s All received mail has been marked as read.", MAIL_PREFIX);
    }
}

public Action Command_RedeemAll(int client, int args)
{
    if (!IsMailClient(client))
    {
        return Plugin_Handled;
    }

    if (!g_MailDatabaseReady || g_MailDatabase == null || !IsPointsStoreAwardAvailable())
    {
        CPrintToChat(client, "%s Currency redemption is temporarily unavailable.", MAIL_PREFIX);
        return Plugin_Handled;
    }

    if (g_MailRedeemAllPending[client])
    {
        CPrintToChat(client, "%s Your mailed Gems are still being checked.", MAIL_PREFIX);
        return Plugin_Handled;
    }

    char steamId[MAIL_STEAMID_MAX];
    char name[MAIL_NAME_MAX];
    if (!GetMailClientIdentity(client, steamId, sizeof(steamId), name, sizeof(name)))
    {
        return Plugin_Handled;
    }

    char escapedSteam[65];
    if (!EscapeMailSql(steamId, escapedSteam, sizeof(escapedSteam)))
    {
        CPrintToChat(client, "%s Your Steam identity could not be prepared.", MAIL_PREFIX);
        return Plugin_Handled;
    }

    char query[768];
    FormatEx(query, sizeof(query),
        "SELECT mail_id, title, gems FROM %s "
        ... "WHERE receiver_steamid64 = '%s' AND gems > 0 AND gems_redeemed = 0 "
        ... "AND (expires_at = 0 OR expires_at > %d) ORDER BY mail_id",
        MAIL_TABLE,
        escapedSteam,
        GetTime());

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(steamId);
    g_MailRedeemAllPending[client] = true;
    g_MailDatabase.Query(SQL_OnRedeemAllLoaded, query, pack);
    return Plugin_Handled;
}

public void SQL_OnRedeemAllLoaded(Database db, DBResultSet rows, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    char steamId[MAIL_STEAMID_MAX];
    pack.ReadString(steamId, sizeof(steamId));
    delete pack;

    if (!IsMailClient(client))
    {
        return;
    }
    g_MailRedeemAllPending[client] = false;

    if (error[0] != '\0' || rows == null)
    {
        LogError("[server_mail] Failed to load redeemable mail: %s", error);
        CPrintToChat(client, "%s Your mailed Gems could not be loaded.", MAIL_PREFIX);
        return;
    }

    int queued = 0;
    int pending = 0;
    int failed = 0;
    int totalGems = 0;
    while (rows.FetchRow())
    {
        int mailId = rows.FetchInt(0);
        char title[MAIL_TITLE_MAX];
        rows.FetchString(1, title, sizeof(title));
        int gems = rows.FetchInt(2);

        MailRedemptionQueueResult result = QueueValidatedMailRedemption(client, mailId, steamId, title, gems);
        if (result == MailRedemption_Queued)
        {
            queued++;
            totalGems += gems;
        }
        else if (result == MailRedemption_AlreadyPending)
        {
            pending++;
        }
        else
        {
            failed++;
        }
    }

    if (queued > 0)
    {
        char currencyColor[40];
        char currencyName[64];
        GetCurrencyFormatting(currencyColor, sizeof(currencyColor), currencyName, sizeof(currencyName));
        CPrintToChat(client,
            "%s Redeeming {gold}%d{default} mailed Gem attachment%s worth %s%d %s{default}.",
            MAIL_PREFIX,
            queued,
            queued == 1 ? "" : "s",
            currencyColor,
            totalGems,
            currencyName);
    }
    else if (pending > 0)
    {
        CPrintToChat(client, "%s Your mailed Gems are already being redeemed.", MAIL_PREFIX);
    }
    else
    {
        CPrintToChat(client, "%s You have no unredeemed Gems in your inbox.", MAIL_PREFIX);
    }

    if (failed > 0)
    {
        CPrintToChat(client, "%s Some mailed Gems could not be queued. Try again.", MAIL_PREFIX);
    }
}

public Action Command_Gift(int client, int args)
{
    if (!IsMailClient(client))
    {
        return Plugin_Handled;
    }

    if (!g_MailDatabaseReady || !IsPointsStoreGiftAvailable())
    {
        CPrintToChat(client, "%s Gifting is temporarily unavailable.", MAIL_PREFIX);
        return Plugin_Handled;
    }

    if (!CheckMailSendCooldown(client))
    {
        return Plugin_Handled;
    }

    if (args != 2)
    {
        CPrintToChat(client, "%s Usage: {gold}!gift playername amount", MAIL_PREFIX);
        return Plugin_Handled;
    }

    char search[MAIL_NAME_MAX];
    char amountText[32];
    GetCmdArg(1, search, sizeof(search));
    GetCmdArg(2, amountText, sizeof(amountText));
    TrimString(search);
    TrimString(amountText);

    int amount;
    if (search[0] == '\0' || StringToIntEx(amountText, amount) == 0 || amount <= 0)
    {
        CPrintToChat(client, "%s Usage: {gold}!gift playername amount", MAIL_PREFIX);
        return Plugin_Handled;
    }

    if (!PointsStore_AreBonusPointsLoaded(client))
    {
        CPrintToChat(client, "%s Your currency balance is still loading.", MAIL_PREFIX);
        return Plugin_Handled;
    }

    int balance = PointsStore_GetBonusPoints(client);
    if (balance < amount)
    {
        char currencyColor[40];
        char currencyName[64];
        GetCurrencyFormatting(currencyColor, sizeof(currencyColor), currencyName, sizeof(currencyName));
        CPrintToChat(client,
            "%s You need %s%d %s{default} to send that gift.",
            MAIL_PREFIX,
            currencyColor,
            amount,
            currencyName);
        return Plugin_Handled;
    }

    char currencyColor[40];
    char currencyName[64];
    GetCurrencyFormatting(currencyColor, sizeof(currencyColor), currencyName, sizeof(currencyName));
    strcopy(g_MailPendingSearch[client], sizeof(g_MailPendingSearch[]), search);
    FormatEx(g_MailPendingContents[client], sizeof(g_MailPendingContents[]),
        "You received %d %s.", amount, currencyName);
    g_MailPendingGems[client] = amount;
    RequestMailPlayerSearch(client);
    return Plugin_Handled;
}

public Action Command_MailHug(int client, int args)
{
    return BeginAttachmentMailCommand(client, args, "hug");
}

public Action Command_MailFeed(int client, int args)
{
    return BeginAttachmentMailCommand(client, args, "feed");
}

public Action Command_MailRape(int client, int args)
{
    return BeginAttachmentMailCommand(client, args, "rape");
}

public Action Command_MailRtd(int client, int args)
{
    return BeginAttachmentMailCommand(client, args, "rtd");
}

bool IsHugsMailAvailable(const char[] attachmentType)
{
    if (StrEqual(attachmentType, "hug"))
    {
        return GetFeatureStatus(FeatureType_Native, "Hugs_RedeemMailedHug") == FeatureStatus_Available;
    }
    if (StrEqual(attachmentType, "feed"))
    {
        return GetFeatureStatus(FeatureType_Native, "Hugs_RedeemMailedFeed") == FeatureStatus_Available;
    }
    return GetFeatureStatus(FeatureType_Native, "Hugs_RedeemMailedRape") == FeatureStatus_Available;
}

bool IsRtdMailAvailable()
{
    return GetFeatureStatus(FeatureType_Native, "RTD_ApplyGiftedRoll") == FeatureStatus_Available;
}

public Action BeginAttachmentMailCommand(int client, int args, const char[] attachmentType)
{
    if (!IsMailClient(client))
    {
        return Plugin_Handled;
    }
    if (!g_MailDatabaseReady)
    {
        CPrintToChat(client, "%s Mail is temporarily unavailable.", MAIL_PREFIX);
        return Plugin_Handled;
    }
    if (!CheckMailSendCooldown(client))
    {
        return Plugin_Handled;
    }
    if (args != 1)
    {
        CPrintToChat(client, "%s Usage: {gold}!mail%s playername", MAIL_PREFIX, attachmentType);
        return Plugin_Handled;
    }
    if ((StrEqual(attachmentType, "hug") || StrEqual(attachmentType, "feed") || StrEqual(attachmentType, "rape"))
        && !IsHugsMailAvailable(attachmentType))
    {
        CPrintToChat(client, "%s Hug gifts are temporarily unavailable.", MAIL_PREFIX);
        return Plugin_Handled;
    }
    if (StrEqual(attachmentType, "rtd"))
    {
        if (!IsRtdMailAvailable() || !IsPointsStoreGiftAvailable())
        {
            CPrintToChat(client, "%s RTD gifts are temporarily unavailable.", MAIL_PREFIX);
            return Plugin_Handled;
        }
        if (!PointsStore_AreBonusPointsLoaded(client))
        {
            CPrintToChat(client, "%s Your currency balance is still loading.", MAIL_PREFIX);
            return Plugin_Handled;
        }
        if (PointsStore_GetBonusPoints(client) < MAIL_RTD_GIFT_COST)
        {
            CPrintToChat(client, "%s You need {cyan}%d Gems{default} to mail an RTD.", MAIL_PREFIX, MAIL_RTD_GIFT_COST);
            return Plugin_Handled;
        }
    }

    char search[MAIL_NAME_MAX];
    GetCmdArgString(search, sizeof(search));
    StripQuotes(search);
    TrimString(search);
    if (search[0] == '\0')
    {
        CPrintToChat(client, "%s Usage: {gold}!mail%s playername", MAIL_PREFIX, attachmentType);
        return Plugin_Handled;
    }

    strcopy(g_MailPendingSearch[client], sizeof(g_MailPendingSearch[]), search);
    strcopy(g_MailPendingAttachment[client], sizeof(g_MailPendingAttachment[]), attachmentType);
    g_MailPendingGems[client] = 0;
    if (StrEqual(attachmentType, "hug"))
    {
        strcopy(g_MailPendingContents[client], sizeof(g_MailPendingContents[]), "You received a one-time hug.");
    }
    else if (StrEqual(attachmentType, "feed"))
    {
        strcopy(g_MailPendingContents[client], sizeof(g_MailPendingContents[]), "You received a one-time feed.");
    }
    else if (StrEqual(attachmentType, "rape"))
    {
        strcopy(g_MailPendingContents[client], sizeof(g_MailPendingContents[]), "You received a one-time rape.");
    }
    else
    {
        strcopy(g_MailPendingContents[client], sizeof(g_MailPendingContents[]), "Open this mail to use your gifted RTD roll.");
    }
    RequestMailPlayerSearch(client);
    return Plugin_Handled;
}

