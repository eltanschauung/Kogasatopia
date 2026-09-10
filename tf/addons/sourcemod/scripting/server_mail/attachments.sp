void BuildMailAttachmentKey(int mailId, char[] key, int maxlen)
{
    FormatEx(key, maxlen, "server_mail:attachment:%d", mailId);
}

bool IsMailAttachmentProviderAvailable(const char[] attachmentType)
{
    if (StrEqual(attachmentType, "hug"))
    {
        return GetFeatureStatus(FeatureType_Native, "Hugs_RedeemMailedHug") == FeatureStatus_Available;
    }
    if (StrEqual(attachmentType, "feed"))
    {
        return GetFeatureStatus(FeatureType_Native, "Hugs_RedeemMailedFeed") == FeatureStatus_Available;
    }
    if (StrEqual(attachmentType, "rape"))
    {
        return GetFeatureStatus(FeatureType_Native, "Hugs_RedeemMailedRape") == FeatureStatus_Available;
    }
    if (StrEqual(attachmentType, "rtd"))
    {
        return GetFeatureStatus(FeatureType_Native, "RTD_ApplyGiftedRoll") == FeatureStatus_Available;
    }
    return false;
}

void BeginMailAttachmentRedemption(int client, int mailId)
{
    if (!g_MailDatabaseReady || g_MailDatabase == null || mailId <= 0)
    {
        CPrintToChat(client, "%s That attachment is temporarily unavailable.", MAIL_PREFIX);
        return;
    }

    char key[MAIL_REQUEST_KEY_MAX];
    BuildMailAttachmentKey(mailId, key, sizeof(key));
    int unused;
    if (g_MailPendingAttachments.GetValue(key, unused))
    {
        CPrintToChat(client, "%s That attachment is already being used.", MAIL_PREFIX);
        return;
    }

    char receiverSteamId[MAIL_STEAMID_MAX];
    char receiverName[MAIL_NAME_MAX];
    if (!GetMailClientIdentity(
            client,
            receiverSteamId,
            sizeof(receiverSteamId),
            receiverName,
            sizeof(receiverName)))
    {
        return;
    }

    char escapedReceiver[65];
    if (!EscapeMailSql(receiverSteamId, escapedReceiver, sizeof(escapedReceiver)))
    {
        return;
    }

    g_MailPendingAttachments.SetValue(key, GetClientUserId(client));
    char query[768];
    FormatEx(query, sizeof(query),
        "SELECT sender_steamid64, sender_name, attachment_type FROM %s "
        ... "WHERE mail_id = %d AND receiver_steamid64 = '%s' "
        ... "AND attachment_type != '' AND attachment_redeemed = 0 LIMIT 1",
        MAIL_TABLE,
        mailId,
        escapedReceiver);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(mailId);
    pack.WriteString(receiverSteamId);
    g_MailDatabase.Query(SQL_OnMailAttachmentValidated, query, pack);
}

public void SQL_OnMailAttachmentValidated(Database db, DBResultSet rows, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    int mailId = pack.ReadCell();
    char receiverSteamId[MAIL_STEAMID_MAX];
    pack.ReadString(receiverSteamId, sizeof(receiverSteamId));
    delete pack;

    char key[MAIL_REQUEST_KEY_MAX];
    BuildMailAttachmentKey(mailId, key, sizeof(key));
    int client = GetClientOfUserId(userId);
    if (!IsMailClient(client))
    {
        g_MailPendingAttachments.Remove(key);
        return;
    }
    if (error[0] != '\0' || rows == null || !rows.FetchRow())
    {
        if (error[0] != '\0')
        {
            LogError("[server_mail] Attachment validation failed: %s", error);
        }
        g_MailPendingAttachments.Remove(key);
        CPrintToChat(client, "%s That attachment is unavailable or already used.", MAIL_PREFIX);
        return;
    }

    char senderSteamId[MAIL_STEAMID_MAX];
    char senderName[MAIL_NAME_MAX];
    char attachmentType[MAIL_ATTACHMENT_MAX];
    rows.FetchString(0, senderSteamId, sizeof(senderSteamId));
    rows.FetchString(1, senderName, sizeof(senderName));
    rows.FetchString(2, attachmentType, sizeof(attachmentType));
    if (!IsMailAttachmentProviderAvailable(attachmentType))
    {
        g_MailPendingAttachments.Remove(key);
        CPrintToChat(client, "%s That attachment's plugin is temporarily unavailable.", MAIL_PREFIX);
        return;
    }

    char escapedReceiver[65];
    if (!EscapeMailSql(receiverSteamId, escapedReceiver, sizeof(escapedReceiver)))
    {
        g_MailPendingAttachments.Remove(key);
        return;
    }
    char query[512];
    FormatEx(query, sizeof(query),
        "UPDATE %s SET attachment_redeemed = 2 "
        ... "WHERE mail_id = %d AND receiver_steamid64 = '%s' AND attachment_redeemed = 0",
        MAIL_TABLE,
        mailId,
        escapedReceiver);

    DataPack claimPack = new DataPack();
    claimPack.WriteCell(userId);
    claimPack.WriteCell(mailId);
    claimPack.WriteString(receiverSteamId);
    claimPack.WriteString(senderSteamId);
    claimPack.WriteString(senderName);
    claimPack.WriteString(attachmentType);
    g_MailDatabase.Query(SQL_OnMailAttachmentClaimed, query, claimPack);
}

void SetMailAttachmentState(
    int mailId,
    const char[] receiverSteamId,
    int fromState,
    int toState,
    int userId,
    const char[] attachmentType)
{
    char escapedReceiver[65];
    char key[MAIL_REQUEST_KEY_MAX];
    BuildMailAttachmentKey(mailId, key, sizeof(key));
    if (!EscapeMailSql(receiverSteamId, escapedReceiver, sizeof(escapedReceiver)))
    {
        g_MailPendingAttachments.Remove(key);
        return;
    }

    char query[512];
    FormatEx(query, sizeof(query),
        "UPDATE %s SET attachment_redeemed = %d "
        ... "WHERE mail_id = %d AND receiver_steamid64 = '%s' AND attachment_redeemed = %d",
        MAIL_TABLE,
        toState,
        mailId,
        escapedReceiver,
        fromState);
    DataPack pack = new DataPack();
    pack.WriteCell(userId);
    pack.WriteCell(mailId);
    pack.WriteCell(toState);
    pack.WriteString(attachmentType);
    g_MailDatabase.Query(SQL_OnMailAttachmentStateSet, query, pack);
}

public void SQL_OnMailAttachmentClaimed(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    int mailId = pack.ReadCell();
    char receiverSteamId[MAIL_STEAMID_MAX];
    char senderSteamId[MAIL_STEAMID_MAX];
    char senderName[MAIL_NAME_MAX];
    char attachmentType[MAIL_ATTACHMENT_MAX];
    pack.ReadString(receiverSteamId, sizeof(receiverSteamId));
    pack.ReadString(senderSteamId, sizeof(senderSteamId));
    pack.ReadString(senderName, sizeof(senderName));
    pack.ReadString(attachmentType, sizeof(attachmentType));
    delete pack;

    char key[MAIL_REQUEST_KEY_MAX];
    BuildMailAttachmentKey(mailId, key, sizeof(key));
    int client = GetClientOfUserId(userId);
    if (error[0] != '\0' || results == null || results.AffectedRows != 1)
    {
        if (error[0] != '\0')
        {
            LogError("[server_mail] Attachment claim failed: %s", error);
        }
        g_MailPendingAttachments.Remove(key);
        if (IsMailClient(client))
        {
            CPrintToChat(client, "%s That attachment is unavailable or already being used.", MAIL_PREFIX);
        }
        return;
    }

    bool applied = false;
    bool providerAvailable = IsMailAttachmentProviderAvailable(attachmentType);
    if (providerAvailable && IsMailClient(client) && StrEqual(attachmentType, "hug"))
    {
        applied = Hugs_RedeemMailedHug(senderSteamId, receiverSteamId, senderName);
    }
    else if (providerAvailable && IsMailClient(client) && StrEqual(attachmentType, "feed"))
    {
        applied = Hugs_RedeemMailedFeed(senderSteamId, receiverSteamId, senderName);
    }
    else if (providerAvailable && IsMailClient(client) && StrEqual(attachmentType, "rape"))
    {
        applied = Hugs_RedeemMailedRape(senderSteamId, receiverSteamId, senderName);
    }
    else if (providerAvailable && IsMailClient(client) && StrEqual(attachmentType, "rtd"))
    {
        applied = RTD_ApplyGiftedRoll(client);
    }

    if (!applied && IsMailClient(client))
    {
        CPrintToChat(client, "%s That attachment could not be used now; it remains in your inbox.", MAIL_PREFIX);
    }
    SetMailAttachmentState(
        mailId,
        receiverSteamId,
        2,
        applied ? 1 : 0,
        userId,
        attachmentType);
}

public void SQL_OnMailAttachmentStateSet(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    pack.ReadCell();
    int mailId = pack.ReadCell();
    pack.ReadCell();
    char attachmentType[MAIL_ATTACHMENT_MAX];
    pack.ReadString(attachmentType, sizeof(attachmentType));
    delete pack;

    char key[MAIL_REQUEST_KEY_MAX];
    BuildMailAttachmentKey(mailId, key, sizeof(key));
    g_MailPendingAttachments.Remove(key);
    if (error[0] != '\0' || results == null || results.AffectedRows != 1)
    {
        LogError("[server_mail] Failed to finalize %s attachment %d: %s", attachmentType, mailId, error);
        return;
    }

}

