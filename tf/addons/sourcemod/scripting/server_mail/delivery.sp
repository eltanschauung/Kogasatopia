void QueuePendingMailToTarget(
    int client,
    const char[] receiverSteamId,
    const char[] receiverName,
    bool rtdConfirmed)
{
    char senderSteamId[MAIL_STEAMID_MAX];
    char senderName[MAIL_NAME_MAX];
    if (!GetMailClientIdentity(client, senderSteamId, sizeof(senderSteamId), senderName, sizeof(senderName)))
    {
        CPrintToChat(client, "%s Could not resolve your Steam identity.", MAIL_PREFIX);
        ClearClientMailState(client);
        return;
    }
    if (!CheckMailSendCooldown(client))
    {
        ClearClientMailState(client);
        return;
    }
    if (StrEqual(senderSteamId, receiverSteamId, false))
    {
        CPrintToChat(client, "%s You cannot mail a gift to yourself.", MAIL_PREFIX);
        ClearClientMailState(client);
        return;
    }

    bool isRtd = StrEqual(g_MailPendingAttachment[client], "rtd");
    if (isRtd && !rtdConfirmed)
    {
        ShowRtdMailCostMenu(client, receiverSteamId, receiverName);
        return;
    }

    int gems = g_MailPendingGems[client];
    int senderCost = gems > 0 ? gems : (isRtd ? MAIL_RTD_GIFT_COST : 0);
    if (senderCost > 0)
    {
        if (!IsPointsStoreGiftAvailable() || !PointsStore_AreBonusPointsLoaded(client)
            || PointsStore_GetBonusPoints(client) < senderCost
            || !PointsStore_SpendBonusPoints(client, senderCost))
        {
            CPrintToChat(client, "%s You no longer have enough Gems for that gift.", MAIL_PREFIX);
            ClearClientMailState(client);
            return;
        }
    }

    char requestKey[MAIL_REQUEST_KEY_MAX];
    requestKey[0] = '\0';
    if (senderCost > 0 || g_MailPendingAttachment[client][0] != '\0')
    {
        g_MailGiftSerial++;
        FormatEx(requestKey, sizeof(requestKey),
            "server_mail:gift:%s:%s:%d:%d",
            senderSteamId,
            receiverSteamId,
            GetTime(),
            g_MailGiftSerial);
    }

    char title[MAIL_TITLE_MAX];
    strcopy(title, sizeof(title), "N/A");
    if (StrEqual(g_MailPendingAttachment[client], "hug"))
    {
        FormatEx(title, sizeof(title), "Hug from %s", senderName);
    }
    else if (StrEqual(g_MailPendingAttachment[client], "feed"))
    {
        FormatEx(title, sizeof(title), "Feed from %s", senderName);
    }
    else if (StrEqual(g_MailPendingAttachment[client], "rape"))
    {
        FormatEx(title, sizeof(title), "Rape from %s", senderName);
    }
    else if (isRtd)
    {
        FormatEx(title, sizeof(title), "rtd from %s", senderName);
    }

    bool queued = QueueMailInsert(
        senderSteamId,
        senderName,
        receiverSteamId,
        receiverName,
        title,
        g_MailPendingContents[client],
        gems,
        requestKey,
        GetClientUserId(client),
        true,
        true,
        g_MailPendingAttachment[client],
        senderCost);
    if (!queued)
    {
        RefundMailSendCost(senderSteamId, senderCost);
        CPrintToChat(client, "%s Failed to queue mail. Try again.", MAIL_PREFIX);
    }
    else
    {
        g_MailUserSendPending[client] = true;
    }
    ClearClientMailState(client);
}

void FireMailSendResult(const char[] requestKey, bool success, int mailId, bool newlyCreated)
{
    if (g_MailSendResultForward == null || requestKey[0] == '\0')
    {
        return;
    }

    Call_StartForward(g_MailSendResultForward);
    Call_PushString(requestKey);
    Call_PushCell(success);
    Call_PushCell(mailId);
    Call_PushCell(newlyCreated);
    Call_Finish();
}

bool QueueMailInsert(
    const char[] senderSteamId,
    const char[] senderName,
    const char[] receiverSteamId,
    const char[] receiverName,
    const char[] title,
    const char[] contents,
    int gems,
    const char[] requestKey,
    int senderUserId = 0,
    bool notifyPlayers = false,
    bool userInitiated = false,
    const char[] attachmentType = "",
    int senderCost = 0,
    int createdAtOverride = 0)
{
    if (!g_MailDatabaseReady || g_MailDatabase == null
        || !Kogasa_IsSteamId64(receiverSteamId)
        || senderName[0] == '\0' || receiverName[0] == '\0'
        || title[0] == '\0' || contents[0] == '\0' || gems < 0 || senderCost < 0
        || (attachmentType[0] != '\0'
            && !StrEqual(attachmentType, "hug")
            && !StrEqual(attachmentType, "feed")
            && !StrEqual(attachmentType, "rape")
            && !StrEqual(attachmentType, "rtd")))
    {
        return false;
    }

    if (senderSteamId[0] != '\0' && !Kogasa_IsSteamId64(senderSteamId))
    {
        return false;
    }
    if (gems > 0 && !IsPointsStoreAwardAvailable())
    {
        return false;
    }

    char escapedSenderSteam[65];
    char escapedSenderName[(MAIL_NAME_MAX * 2) + 1];
    char escapedReceiverSteam[65];
    char escapedReceiverName[(MAIL_NAME_MAX * 2) + 1];
    char escapedTitle[(MAIL_TITLE_MAX * 2) + 1];
    char escapedContents[(MAIL_CONTENTS_MAX * 2) + 1];
    char escapedRequest[(MAIL_REQUEST_KEY_MAX * 2) + 1];
    char escapedAttachment[(MAIL_ATTACHMENT_MAX * 2) + 1];
    if (!EscapeMailSql(senderSteamId, escapedSenderSteam, sizeof(escapedSenderSteam))
        || !EscapeMailSql(senderName, escapedSenderName, sizeof(escapedSenderName))
        || !EscapeMailSql(receiverSteamId, escapedReceiverSteam, sizeof(escapedReceiverSteam))
        || !EscapeMailSql(receiverName, escapedReceiverName, sizeof(escapedReceiverName))
        || !EscapeMailSql(title, escapedTitle, sizeof(escapedTitle))
        || !EscapeMailSql(contents, escapedContents, sizeof(escapedContents))
        || !EscapeMailSql(requestKey, escapedRequest, sizeof(escapedRequest))
        || !EscapeMailSql(attachmentType, escapedAttachment, sizeof(escapedAttachment)))
    {
        return false;
    }

    char idempotencyValue[(MAIL_REQUEST_KEY_MAX * 2) + 16];
    if (requestKey[0] == '\0')
    {
        strcopy(idempotencyValue, sizeof(idempotencyValue), "NULL");
    }
    else
    {
        Format(idempotencyValue, sizeof(idempotencyValue), "'%s'", escapedRequest);
    }

    int createdAt = createdAtOverride > 0 ? createdAtOverride : GetTime();
    int expiresAt = Stimulus_GetMailExpiry(title, createdAt);
    char query[4096];
    if (g_MailDatabaseIsMySql)
    {
        FormatEx(query, sizeof(query),
            "INSERT INTO %s "
            ... "(sender_steamid64, sender_name, receiver_steamid64, receiver_name, created_at, title, contents, gems, gems_redeemed, attachment_type, attachment_redeemed, expires_at, read_at, idempotency_key) "
            ... "VALUES ('%s', '%s', '%s', '%s', %d, '%s', '%s', %d, 0, '%s', 0, %d, 0, %s) "
            ... "ON DUPLICATE KEY UPDATE mail_id = LAST_INSERT_ID(mail_id)",
            MAIL_TABLE,
            escapedSenderSteam,
            escapedSenderName,
            escapedReceiverSteam,
            escapedReceiverName,
            createdAt,
            escapedTitle,
            escapedContents,
            gems,
            escapedAttachment,
            expiresAt,
            idempotencyValue);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "INSERT OR IGNORE INTO %s "
            ... "(sender_steamid64, sender_name, receiver_steamid64, receiver_name, created_at, title, contents, gems, gems_redeemed, attachment_type, attachment_redeemed, expires_at, read_at, idempotency_key) "
            ... "VALUES ('%s', '%s', '%s', '%s', %d, '%s', '%s', %d, 0, '%s', 0, %d, 0, %s)",
            MAIL_TABLE,
            escapedSenderSteam,
            escapedSenderName,
            escapedReceiverSteam,
            escapedReceiverName,
            createdAt,
            escapedTitle,
            escapedContents,
            gems,
            escapedAttachment,
            expiresAt,
            idempotencyValue);
    }

    DataPack pack = new DataPack();
    pack.WriteString(requestKey);
    pack.WriteCell(senderUserId);
    pack.WriteCell(notifyPlayers ? 1 : 0);
    pack.WriteString(senderSteamId);
    pack.WriteString(senderName);
    pack.WriteString(receiverSteamId);
    pack.WriteString(receiverName);
    pack.WriteCell(gems);
    pack.WriteCell(senderCost);
    pack.WriteCell(userInitiated ? 1 : 0);
    g_MailDatabase.Query(SQL_OnMailInserted, query, pack);
    return true;
}

public void SQL_OnMailInserted(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    char requestKey[MAIL_REQUEST_KEY_MAX];
    char senderSteamId[MAIL_STEAMID_MAX];
    char senderName[MAIL_NAME_MAX];
    char receiverSteamId[MAIL_STEAMID_MAX];
    char receiverName[MAIL_NAME_MAX];
    pack.ReadString(requestKey, sizeof(requestKey));
    int senderUserId = pack.ReadCell();
    bool notifyPlayers = view_as<bool>(pack.ReadCell());
    pack.ReadString(senderSteamId, sizeof(senderSteamId));
    pack.ReadString(senderName, sizeof(senderName));
    pack.ReadString(receiverSteamId, sizeof(receiverSteamId));
    pack.ReadString(receiverName, sizeof(receiverName));
    int gems = pack.ReadCell();
    int senderCost = pack.ReadCell();
    bool userInitiated = pack.ReadCell() != 0;
    delete pack;

    if (error[0] != '\0' || results == null)
    {
        if (userInitiated)
        {
            FinishUserMailSend(senderUserId, false);
        }

        LogError("[server_mail] Mail insert failed: %s", error);
        FireMailSendResult(requestKey, false, 0, false);
        Stimulus_OnMailInsertResult(requestKey, false, 0);

        RefundMailSendCost(senderSteamId, senderCost);

        int sender = GetClientOfUserId(senderUserId);
        if (notifyPlayers && IsMailClient(sender))
        {
            CPrintToChat(sender, "%s Failed to send mail.", MAIL_PREFIX);
        }
        return;
    }

    int mailId = results.InsertId;
    bool newlyCreated = results.AffectedRows == 1;
    if (userInitiated)
    {
        FinishUserMailSend(senderUserId, newlyCreated);
    }
    FireMailSendResult(requestKey, true, mailId, newlyCreated);
    Stimulus_OnMailInsertResult(requestKey, true, mailId);

    if (!newlyCreated && senderCost > 0)
    {
        RefundMailSendCost(senderSteamId, senderCost);
    }

    if (!notifyPlayers || !newlyCreated)
    {
        return;
    }

    int receiver = Kogasa_FindClientBySteamId64(receiverSteamId);
    int liveSender = Kogasa_FindClientBySteamId64(senderSteamId);
    if (gems > 0 && StrContains(requestKey, "server_mail:stimulus:", false) == 0)
    {
        char coloredReceiver[256];
        char currencyColor[40];
        char currencyName[64];
        BuildColoredMailName(receiver, receiverSteamId, receiverName, coloredReceiver, sizeof(coloredReceiver));
        GetCurrencyFormatting(currencyColor, sizeof(currencyColor), currencyName, sizeof(currencyName));

        if (IsMailClient(receiver))
        {
            CPrintToChatAllEx(receiver,
                "{cornflowerblue}[Mail] %s{default} received a Stimulus Check! (%s%d %s{default})",
                coloredReceiver,
                currencyColor,
                gems,
                currencyName);
        }
        else
        {
            CPrintToChatAll(
                "{cornflowerblue}[Mail] %s{default} received a Stimulus Check! (%s%d %s{default})",
                coloredReceiver,
                currencyColor,
                gems,
                currencyName);
        }
        return;
    }

    if (gems > 0 && StrContains(requestKey, "server_mail:gift:", false) == 0)
    {
        char coloredSender[256];
        char coloredReceiver[256];
        char currencyColor[40];
        char currencyName[64];
        BuildColoredMailName(liveSender, senderSteamId, senderName, coloredSender, sizeof(coloredSender));
        BuildColoredMailName(receiver, receiverSteamId, receiverName, coloredReceiver, sizeof(coloredReceiver));
        GetCurrencyFormatting(currencyColor, sizeof(currencyColor), currencyName, sizeof(currencyName));

        int author = IsMailClient(liveSender) ? liveSender : receiver;
        if (IsMailClient(author))
        {
            CPrintToChatAllEx(author,
                "{cornflowerblue}[Mail] %s{default} gifted %s{default} %s%d %s{default}!",
                coloredSender,
                coloredReceiver,
                currencyColor,
                gems,
                currencyName);
        }
        else
        {
            CPrintToChatAll(
                "{cornflowerblue}[Mail] %s{default} gifted %s{default} %s%d %s{default}!",
                coloredSender,
                coloredReceiver,
                currencyColor,
                gems,
                currencyName);
        }
        return;
    }

    int sender = GetClientOfUserId(senderUserId);
    if (IsMailClient(sender))
    {
        char coloredReceiver[256];
        BuildColoredMailName(receiver, receiverSteamId, receiverName, coloredReceiver, sizeof(coloredReceiver));
        CPrintToChatEx(sender, receiver > 0 ? receiver : sender, "%s Sent to %s{default}.", MAIL_PREFIX, coloredReceiver);
    }

    if (IsMailClient(receiver))
    {
        char coloredSender[256];
        BuildColoredMailName(liveSender, senderSteamId, senderName, coloredSender, sizeof(coloredSender));
        CPrintToChatEx(receiver, liveSender > 0 ? liveSender : receiver,
            "{cornflowerblue}[Mail] %s{default} sent you mail!",
            coloredSender);
    }
}

