public void OnPluginStart()
{
    RegConsoleCmd("sm_mail", Command_Mail, "Open mail or send mail to a ranked player.");
    RegConsoleCmd("sm_dm", Command_Mail, "Open mail or send mail to a ranked player.");
    RegConsoleCmd("sm_inbox", Command_Inbox, "Open your mail inbox.");
    RegConsoleCmd("sm_unread", Command_Unread, "Open unread mail.");
    RegConsoleCmd("sm_readall", Command_ReadAll, "Mark all received mail as read.");
    RegConsoleCmd("sm_redeem", Command_RedeemAll, "Redeem every unclaimed Gem attachment in your inbox.");
    RegConsoleCmd("sm_redeemall", Command_RedeemAll, "Redeem every unclaimed Gem attachment in your inbox.");
    RegConsoleCmd("sm_gift", Command_Gift, "Mail Gems to a ranked player.");
    RegConsoleCmd("sm_mailhug", Command_MailHug, "Mail a one-use hug to a ranked player.");
    RegConsoleCmd("sm_hugmail", Command_MailHug, "Mail a one-use hug to a ranked player.");
    RegConsoleCmd("sm_gifthug", Command_MailHug, "Mail a one-use hug to a ranked player.");
    RegConsoleCmd("sm_mailfeed", Command_MailFeed, "Mail a one-use feed to a ranked player.");
    RegConsoleCmd("sm_feedmail", Command_MailFeed, "Mail a one-use feed to a ranked player.");
    RegConsoleCmd("sm_mailrape", Command_MailRape, "Mail a one-use rape to a ranked player.");
    RegConsoleCmd("sm_rapemail", Command_MailRape, "Mail a one-use rape to a ranked player.");
    RegConsoleCmd("sm_giftrape", Command_MailRape, "Mail a one-use rape to a ranked player.");
    RegConsoleCmd("sm_mailrtd", Command_MailRtd, "Mail a prepaid RTD roll to a ranked player.");
    RegConsoleCmd("sm_sendrtd", Command_MailRtd, "Mail a prepaid RTD roll to a ranked player.");
    RegConsoleCmd("sm_giftrtd", Command_MailRtd, "Mail a prepaid RTD roll to a ranked player.");
    HookEvent("player_team", Event_MailPlayerTeam, EventHookMode_Post);
    g_MailUnreadReminderCookie = new Cookie(
        "server_mail_unread_reminder_day",
        "Last date the unread-mail reminder was displayed.",
        CookieAccess_Private);
    Stimulus_OnPluginStart();

    g_MailPendingRedemptions = new StringMap();
    g_MailRedemptionUsers = new StringMap();
    g_MailRedemptionTitles = new StringMap();
    g_MailRedemptionSteamIds = new StringMap();
    g_MailRedemptionAmounts = new StringMap();
    g_MailPendingAttachments = new StringMap();

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            ClearClientMailState(client);
            ResetUnreadMailReminder(client);
            ScheduleUnreadMailReminder(client);
        }
    }

    ConnectMailDatabase();
}

public void OnPluginEnd()
{
    delete g_MailSendResultForward;
    delete g_MailPendingRedemptions;
    delete g_MailRedemptionUsers;
    delete g_MailRedemptionTitles;
    delete g_MailRedemptionSteamIds;
    delete g_MailRedemptionAmounts;
    delete g_MailPendingAttachments;

    for (int client = 1; client <= MaxClients; client++)
    {
        delete g_MailSearchResults[client];
        delete g_MailUnreadReminderTimer[client];
    }

    delete g_MailUnreadReminderCookie;

    if (g_MailReconnectTimer != null)
    {
        delete g_MailReconnectTimer;
        g_MailReconnectTimer = null;
    }
    delete g_MailDatabase;
    g_MailDatabase = null;
}

public void OnClientPutInServer(int client)
{
    ResetUnreadMailReminder(client);
}

public void OnClientDisconnect(int client)
{
    ResetUnreadMailReminder(client);
    ClearClientMailState(client);
    g_MailNextSendAllowedAt[client] = 0.0;
    g_MailUserSendPending[client] = false;
    g_MailRedeemAllPending[client] = false;
    g_MailReadAllPending[client] = false;
    Stimulus_ResetClient(client);
}

public void OnMapStart()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        g_MailUnreadReminderTimer[client] = null;
    }
    Stimulus_OnMapStart();
}

public void Event_MailPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsMailClient(client))
    {
        return;
    }

    int team = event.GetInt("team");
    if (team == 2 || team == 3)
    {
        ScheduleUnreadMailReminder(client);
    }
    else
    {
        CancelUnreadMailReminder(client);
    }
}

void ScheduleUnreadMailReminder(int client, float delay = MAIL_UNREAD_REMINDER_DELAY)
{
    if (!IsMailClient(client) || (GetClientTeam(client) != 2 && GetClientTeam(client) != 3)
        || g_MailUnreadReminderTimer[client] != null || g_MailUnreadReminderPending[client])
    {
        return;
    }

    g_MailUnreadReminderTimer[client] = CreateTimer(
        delay,
        Timer_CheckUnreadMail,
        GetClientUserId(client),
        TIMER_FLAG_NO_MAPCHANGE);
}

void CancelUnreadMailReminder(int client)
{
    delete g_MailUnreadReminderTimer[client];
    g_MailUnreadReminderTimer[client] = null;
}

void ResetUnreadMailReminder(int client)
{
    CancelUnreadMailReminder(client);
    g_MailUnreadReminderPending[client] = false;
}

public Action Timer_CheckUnreadMail(Handle timer, any userId)
{
    int client = GetClientOfUserId(userId);
    if (client > 0 && client <= MaxClients)
    {
        g_MailUnreadReminderTimer[client] = null;
    }

    if (!IsMailClient(client) || (GetClientTeam(client) != 2 && GetClientTeam(client) != 3))
    {
        return Plugin_Stop;
    }
    if (!AreClientCookiesCached(client))
    {
        ScheduleUnreadMailReminder(client, MAIL_UNREAD_REMINDER_RETRY);
        return Plugin_Stop;
    }
    if (!g_MailDatabaseReady || g_MailDatabase == null)
    {
        ScheduleUnreadMailReminder(client, MAIL_UNREAD_REMINDER_RETRY);
        return Plugin_Stop;
    }

    char today[16];
    char lastReminderDay[16];
    FormatTime(today, sizeof(today), "%Y%m%d", GetTime());
    g_MailUnreadReminderCookie.Get(client, lastReminderDay, sizeof(lastReminderDay));
    if (StrEqual(today, lastReminderDay))
    {
        return Plugin_Stop;
    }

    char steamId[MAIL_STEAMID_MAX];
    char name[MAIL_NAME_MAX];
    char escapedSteam[(MAIL_STEAMID_MAX * 2) + 1];
    if (!GetMailClientIdentity(client, steamId, sizeof(steamId), name, sizeof(name))
        || !EscapeMailSql(steamId, escapedSteam, sizeof(escapedSteam)))
    {
        return Plugin_Stop;
    }

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT 1 FROM %s WHERE receiver_steamid64 = '%s' AND read_at = 0 "
        ... "AND (expires_at = 0 OR expires_at > %d OR gems_redeemed != 0) LIMIT 1",
        MAIL_TABLE,
        escapedSteam,
        GetTime());

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(today);
    g_MailUnreadReminderPending[client] = true;
    g_MailDatabase.Query(SQL_OnUnreadMailReminderChecked, query, pack);
    return Plugin_Stop;
}

public void SQL_OnUnreadMailReminderChecked(Database db, DBResultSet rows, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    char reminderDay[16];
    pack.ReadString(reminderDay, sizeof(reminderDay));
    delete pack;

    if (client > 0 && client <= MaxClients)
    {
        g_MailUnreadReminderPending[client] = false;
    }
    if (error[0] != '\0')
    {
        LogError("[server_mail] Unread-mail reminder query failed: %s", error);
        return;
    }
    if (!IsMailClient(client) || (GetClientTeam(client) != 2 && GetClientTeam(client) != 3)
        || rows == null || !rows.FetchRow())
    {
        return;
    }

    g_MailUnreadReminderCookie.Set(client, reminderDay);
    CPrintToChat(client,
        "%s You have unread server mail; use {gold}!inbox{default} to read it!",
        MAIL_PREFIX);
}

public void OnLibraryRemoved(const char[] name)
{
    if (!StrEqual(name, "points_store", false))
    {
        return;
    }

    g_MailPendingRedemptions.Clear();
    g_MailRedemptionUsers.Clear();
    g_MailRedemptionTitles.Clear();
    g_MailRedemptionSteamIds.Clear();
    g_MailRedemptionAmounts.Clear();
}

void ClearClientMailState(int client)
{
    delete g_MailSearchResults[client];
    g_MailSearchResults[client] = null;
    g_MailPendingContents[client][0] = '\0';
    g_MailPendingSearch[client][0] = '\0';
    g_MailPendingGems[client] = 0;
    g_MailPendingAttachment[client][0] = '\0';
    g_MailSearchGeneration[client]++;
}

bool IsMailClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}

bool CheckMailSendCooldown(int client)
{
    if (g_MailUserSendPending[client])
    {
        CPrintToChat(client, "%s Your mail is still being sent. Try again in a moment.", MAIL_PREFIX);
        return false;
    }

    float remaining = g_MailNextSendAllowedAt[client] - GetEngineTime();
    if (remaining > 0.0)
    {
        CPrintToChat(client,
            "%s Wait {gold}%d{default} seconds before sending mail or gifts again.",
            MAIL_PREFIX,
            RoundToCeil(remaining));
        return false;
    }

    return true;
}

void FinishUserMailSend(int senderUserId, bool success)
{
    int client = GetClientOfUserId(senderUserId);
    if (!IsMailClient(client))
    {
        return;
    }

    g_MailUserSendPending[client] = false;
    if (success)
    {
        g_MailNextSendAllowedAt[client] = GetEngineTime() + MAIL_SEND_COOLDOWN;
    }
}

bool IsPointsStoreAwardAvailable()
{
    return GetFeatureStatus(FeatureType_Native, "PointsStore_ApplyBonusPointsSteamIdOnce") == FeatureStatus_Available;
}

bool IsPointsStoreGiftAvailable()
{
    return IsPointsStoreAwardAvailable()
        && GetFeatureStatus(FeatureType_Native, "PointsStore_AreBonusPointsLoaded") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "PointsStore_GetBonusPoints") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "PointsStore_SpendBonusPoints") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "PointsStore_RefundBonusPointsSteamId") == FeatureStatus_Available;
}

