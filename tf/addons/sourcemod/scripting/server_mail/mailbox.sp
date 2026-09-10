void BuildMailListDisplay(
    const char[] title,
    int timestamp,
    int gems,
    const char[] partyName,
    bool unread,
    char[] output,
    int maxlen)
{
    char date[32];
    char currencyColor[40];
    char currencyName[64];
    char markedPartyName[MAIL_NAME_MAX + 8];
    FormatTime(date, sizeof(date), "%m-%d-%Y", timestamp);
    GetCurrencyFormatting(currencyColor, sizeof(currencyColor), currencyName, sizeof(currencyName));
    FormatEx(markedPartyName, sizeof(markedPartyName), unread ? "%s (!)" : "%s", partyName);

    if (StrEqual(title, "N/A", false))
    {
        if (gems > 0)
        {
            FormatEx(output, maxlen, "%s (%d %s) - %s", markedPartyName, gems, currencyName, date);
        }
        else
        {
            FormatEx(output, maxlen, "%s - %s", markedPartyName, date);
        }
        return;
    }

    if (gems > 0)
    {
        FormatEx(output, maxlen, "%s (%d %s) - %s - %s", markedPartyName, gems, currencyName, title, date);
    }
    else
    {
        FormatEx(output, maxlen, "%s - %s - %s", markedPartyName, title, date);
    }
}

void RequestMailList(int client, MailViewMode mode)
{
    if (!g_MailDatabaseReady)
    {
        CPrintToChat(client, "%s Mail is temporarily unavailable.", MAIL_PREFIX);
        return;
    }

    char steamId[MAIL_STEAMID_MAX];
    char name[MAIL_NAME_MAX];
    if (!GetMailClientIdentity(client, steamId, sizeof(steamId), name, sizeof(name)))
    {
        return;
    }

    char escapedSteam[65];
    if (!EscapeMailSql(steamId, escapedSteam, sizeof(escapedSteam)))
    {
        return;
    }

    char query[1024];
    int now = GetTime();
    if (mode != MailView_Sent)
    {
        char unreadClause[32];
        strcopy(unreadClause, sizeof(unreadClause), mode == MailView_Unread ? "AND read_at = 0 " : "");
        FormatEx(query, sizeof(query),
            "SELECT mail_id, title, created_at, gems, sender_name, read_at FROM %s "
            ... "WHERE receiver_steamid64 = '%s' "
            ... "AND (expires_at = 0 OR expires_at > %d OR gems_redeemed != 0) "
            ... "%s"
            ... "ORDER BY created_at DESC, mail_id DESC LIMIT %d",
            MAIL_TABLE,
            escapedSteam,
            now,
            unreadClause,
            MAIL_LIST_MAX);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "SELECT mail_id, title, created_at, gems, receiver_name, read_at FROM %s "
            ... "WHERE sender_steamid64 = '%s' "
            ... "AND (expires_at = 0 OR expires_at > %d OR gems_redeemed != 0) "
            ... "ORDER BY created_at DESC, mail_id DESC LIMIT %d",
            MAIL_TABLE,
            escapedSteam,
            now,
            MAIL_LIST_MAX);
    }

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(view_as<int>(mode));
    g_MailDatabase.Query(SQL_OnMailListLoaded, query, pack);
}

public void SQL_OnMailListLoaded(Database db, DBResultSet rows, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    MailViewMode mode = view_as<MailViewMode>(pack.ReadCell());
    delete pack;

    if (!IsMailClient(client))
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[server_mail] Mail list query failed: %s", error);
        CPrintToChat(client, "%s Failed to load mail.", MAIL_PREFIX);
        return;
    }

    Menu menu = new Menu(MenuHandler_MailList);
    if (mode == MailView_Unread)
    {
        menu.SetTitle("Unread Mail");
    }
    else
    {
        menu.SetTitle(mode == MailView_Inbox ? "Inbox" : "Sent Mail");
    }

    char info[32];
    char title[MAIL_TITLE_MAX];
    char partyName[MAIL_NAME_MAX];
    char display[384];
    int count;
    while (rows != null && rows.FetchRow())
    {
        int mailId = rows.FetchInt(0);
        rows.FetchString(1, title, sizeof(title));
        int timestamp = rows.FetchInt(2);
        int gems = rows.FetchInt(3);
        rows.FetchString(4, partyName, sizeof(partyName));
        bool unread = mode != MailView_Sent && rows.FetchInt(5) == 0;
        BuildMailListDisplay(title, timestamp, gems, partyName, unread, display, sizeof(display));

        Format(info, sizeof(info), "%c:%d", mode == MailView_Sent ? 's' : 'i', mailId);
        menu.AddItem(info, display);
        count++;
    }

    if (count == 0)
    {
        if (mode == MailView_Unread)
        {
            menu.AddItem("none", "No unread mail", ITEMDRAW_DISABLED);
        }
        else
        {
            menu.AddItem("none", mode == MailView_Inbox ? "No received mail" : "No sent mail", ITEMDRAW_DISABLED);
        }
    }
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MailList(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }
    if (action == MenuAction_Cancel && item == MenuCancel_ExitBack && IsMailClient(client))
    {
        ShowMailMainMenu(client);
        return 0;
    }
    if (action != MenuAction_Select || !IsMailClient(client))
    {
        return 0;
    }

    char info[32];
    menu.GetItem(item, info, sizeof(info));
    if (info[1] != ':' || (info[0] != 'i' && info[0] != 's'))
    {
        return 0;
    }

    RequestMailDetails(client, StringToInt(info[2]), info[0] == 'i' ? MailView_Inbox : MailView_Sent);
    return 0;
}

void RequestMailDetails(int client, int mailId, MailViewMode mode)
{
    if (!g_MailDatabaseReady || g_MailDatabase == null)
    {
        CPrintToChat(client, "%s Mail is temporarily unavailable.", MAIL_PREFIX);
        return;
    }

    char steamId[MAIL_STEAMID_MAX];
    char name[MAIL_NAME_MAX];
    if (mailId <= 0 || !GetMailClientIdentity(client, steamId, sizeof(steamId), name, sizeof(name)))
    {
        return;
    }

    char escapedSteam[65];
    if (!EscapeMailSql(steamId, escapedSteam, sizeof(escapedSteam)))
    {
        return;
    }
    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT mail_id, sender_steamid64, sender_name, receiver_steamid64, receiver_name, contents, gems, gems_redeemed, attachment_type, attachment_redeemed "
        ... "FROM %s WHERE mail_id = %d AND %s = '%s' "
        ... "AND (expires_at = 0 OR expires_at > %d OR gems_redeemed != 0) LIMIT 1",
        MAIL_TABLE,
        mailId,
        mode == MailView_Inbox ? "receiver_steamid64" : "sender_steamid64",
        escapedSteam,
        GetTime());

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(view_as<int>(mode));
    g_MailDatabase.Query(SQL_OnMailDetailsLoaded, query, pack);
}

void MarkMailRead(int mailId)
{
    if (!g_MailDatabaseReady || g_MailDatabase == null || mailId <= 0)
    {
        return;
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "UPDATE %s SET read_at = %d WHERE mail_id = %d AND read_at = 0",
        MAIL_TABLE,
        GetTime(),
        mailId);
    g_MailDatabase.Query(SQL_OnMailMarkedRead, query);
}

public void SQL_OnMailMarkedRead(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[server_mail] Failed to mark mail as read: %s", error);
    }
}

public void SQL_OnMailDetailsLoaded(Database db, DBResultSet rows, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    MailViewMode mode = view_as<MailViewMode>(pack.ReadCell());
    delete pack;

    if (!IsMailClient(client))
    {
        return;
    }
    if (error[0] != '\0' || rows == null || !rows.FetchRow())
    {
        CPrintToChat(client, "%s That mail could not be loaded.", MAIL_PREFIX);
        return;
    }

    int mailId = rows.FetchInt(0);
    char senderSteamId[MAIL_STEAMID_MAX];
    char senderName[MAIL_NAME_MAX];
    char receiverSteamId[MAIL_STEAMID_MAX];
    char receiverName[MAIL_NAME_MAX];
    char contents[MAIL_CONTENTS_MAX];
    rows.FetchString(1, senderSteamId, sizeof(senderSteamId));
    rows.FetchString(2, senderName, sizeof(senderName));
    rows.FetchString(3, receiverSteamId, sizeof(receiverSteamId));
    rows.FetchString(4, receiverName, sizeof(receiverName));
    rows.FetchString(5, contents, sizeof(contents));
    int gems = rows.FetchInt(6);
    bool redeemed = rows.FetchInt(7) != 0;
    char attachmentType[MAIL_ATTACHMENT_MAX];
    rows.FetchString(8, attachmentType, sizeof(attachmentType));
    bool attachmentRedeemed = rows.FetchInt(9) == 1;

    if (mode == MailView_Inbox)
    {
        MarkMailRead(mailId);

        bool hugsInteraction = StrEqual(attachmentType, "hug")
            || StrEqual(attachmentType, "feed")
            || StrEqual(attachmentType, "rape");
        if (!hugsInteraction)
        {
            int sender = Kogasa_FindClientBySteamId64(senderSteamId);
            char coloredSender[256];
            BuildColoredMailName(sender, senderSteamId, senderName, coloredSender, sizeof(coloredSender));
            CPrintToChatEx(client,
                sender > 0 ? sender : client,
                "{cornflowerblue}[Mail] %s{default}: %s",
                coloredSender,
                contents);
        }
        else if (attachmentRedeemed
            && GetFeatureStatus(FeatureType_Native, "Hugs_AnnounceMailedInteraction") == FeatureStatus_Available)
        {
            Hugs_AnnounceMailedInteraction(
                client,
                senderSteamId,
                senderName,
                attachmentType);
        }

        if (gems > 0 && !redeemed)
        {
            BeginMailRedemption(client, mailId);
        }
        if (attachmentType[0] != '\0' && !attachmentRedeemed)
        {
            BeginMailAttachmentRedemption(client, mailId);
        }
        return;
    }

    int receiver = Kogasa_FindClientBySteamId64(receiverSteamId);
    char coloredReceiver[256];
    BuildColoredMailName(receiver, receiverSteamId, receiverName, coloredReceiver, sizeof(coloredReceiver));
    CPrintToChatEx(client,
        receiver > 0 ? receiver : client,
        "{cornflowerblue}[Mail]{default} To %s{default}: %s",
        coloredReceiver,
        contents);
}

