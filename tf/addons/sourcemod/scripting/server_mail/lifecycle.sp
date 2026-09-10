// Request packs belong to SQL; owner slots are tokens, never owning handles.
DataPack g_MailReminderRequest[MAXPLAYERS + 1];
int g_MailReminderGeneration[MAXPLAYERS + 1];

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
    g_MailUnreadReminderCookie = new Cookie("server_mail_unread_reminder_day",
        "Last date the unread-mail reminder was displayed.", CookieAccess_Private);
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
    for (int client = 1; client <= MaxClients; client++)
    {
        ResetUnreadMailReminder(client);
        delete g_MailSearchResults[client];
    }
    delete g_MailSendResultForward;
    delete g_MailPendingRedemptions;
    delete g_MailRedemptionUsers;
    delete g_MailRedemptionTitles;
    delete g_MailRedemptionSteamIds;
    delete g_MailRedemptionAmounts;
    delete g_MailPendingAttachments;
    delete g_MailUnreadReminderCookie;
    delete g_MailReconnectTimer;
    g_MailReconnectTimer = null;
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
        // These timers are explicitly owned (not NO_MAPCHANGE). Their handles
        // remain valid until we close them, including the initial late load.
        ResetUnreadMailReminder(client);
        ScheduleUnreadMailReminder(client);
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
        // Invalidate the SELECT as well as its preceding timer.
        ResetUnreadMailReminder(client);
    }
}

bool MailReminder_IsEligible(int client)
{
    return IsMailClient(client)
        && (GetClientTeam(client) == 2 || GetClientTeam(client) == 3);
}

void ScheduleUnreadMailReminder(int client, float delay = MAIL_UNREAD_REMINDER_DELAY)
{
    if (!MailReminder_IsEligible(client)
        || g_MailUnreadReminderTimer[client] != null
        || g_MailReminderRequest[client] != null)
    {
        return;
    }
    if (!(delay >= 0.1))
    {
        delay = MAIL_UNREAD_REMINDER_RETRY;
    }
    g_MailUnreadReminderTimer[client] = CreateTimer(
        delay, Timer_CheckUnreadMail, GetClientSerial(client));
}

void CancelUnreadMailReminder(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }
    Handle timer = g_MailUnreadReminderTimer[client];
    g_MailUnreadReminderTimer[client] = null;
    delete timer;
}

void ResetUnreadMailReminder(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }
    CancelUnreadMailReminder(client);
    g_MailReminderGeneration[client]++;
    g_MailReminderRequest[client] = null;
    g_MailUnreadReminderPending[client] = false;
}

public Action Timer_CheckUnreadMail(Handle timer, any serial)
{
    int client = GetClientFromSerial(serial);
    if (client <= 0 || g_MailUnreadReminderTimer[client] != timer)
    {
        return Plugin_Stop;
    }
    g_MailUnreadReminderTimer[client] = null;
    if (!MailReminder_IsEligible(client))
    {
        return Plugin_Stop;
    }
    if (!AreClientCookiesCached(client) || !g_MailDatabaseReady || g_MailDatabase == null)
    {
        ScheduleUnreadMailReminder(client, MAIL_UNREAD_REMINDER_RETRY);
        return Plugin_Stop;
    }
    char today[16], lastReminderDay[16];
    FormatTime(today, sizeof(today), "%Y%m%d", GetTime());
    g_MailUnreadReminderCookie.Get(client, lastReminderDay, sizeof(lastReminderDay));
    if (StrEqual(today, lastReminderDay))
    {
        return Plugin_Stop;
    }
    char steamId[MAIL_STEAMID_MAX], name[MAIL_NAME_MAX];
    char escapedSteam[(MAIL_STEAMID_MAX * 2) + 1];
    if (!GetMailClientIdentity(client, steamId, sizeof(steamId), name, sizeof(name))
        || !EscapeMailSql(steamId, escapedSteam, sizeof(escapedSteam)))
    {
        ScheduleUnreadMailReminder(client, MAIL_UNREAD_REMINDER_RETRY);
        return Plugin_Stop;
    }
    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT 1 FROM %s WHERE receiver_steamid64 = '%s' AND read_at = 0 "
        ... "AND (expires_at = 0 OR expires_at > %d OR gems_redeemed != 0) LIMIT 1",
        MAIL_TABLE, escapedSteam, GetTime());
    DataPack pack = new DataPack();
    pack.WriteCell(serial);
    pack.WriteCell(g_MailReminderGeneration[client]);
    pack.WriteString(steamId);
    pack.WriteString(today);
    g_MailReminderRequest[client] = pack;
    g_MailUnreadReminderPending[client] = true;
    g_MailDatabase.Query(SQL_OnUnreadMailReminderChecked, query, pack, DBPrio_Low);
    return Plugin_Stop;
}

public void SQL_OnUnreadMailReminderChecked(Database db, DBResultSet rows,
    const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int serial = pack.ReadCell();
    int client = GetClientFromSerial(serial);
    int generation = pack.ReadCell();
    char expectedSteam[MAIL_STEAMID_MAX], reminderDay[16];
    pack.ReadString(expectedSteam, sizeof(expectedSteam));
    pack.ReadString(reminderDay, sizeof(reminderDay));
    bool ownsRequest = client > 0 && g_MailReminderRequest[client] == pack
        && g_MailReminderGeneration[client] == generation;
    delete pack;
    if (!ownsRequest)
    {
        return;
    }
    g_MailReminderRequest[client] = null;
    g_MailUnreadReminderPending[client] = false;
    if (!MailReminder_IsEligible(client))
    {
        return;
    }
    if (db == null || g_MailDatabase == null || !g_MailDatabaseReady
        || !db.IsSameConnection(g_MailDatabase) || error[0] || rows == null)
    {
        if (error[0])
        {
            LogError("[server_mail] Unread-mail reminder query failed: %s", error);
        }
        ScheduleUnreadMailReminder(client, MAIL_UNREAD_REMINDER_RETRY);
        return;
    }
    char steamId[MAIL_STEAMID_MAX], name[MAIL_NAME_MAX];
    if (!GetMailClientIdentity(client, steamId, sizeof(steamId), name, sizeof(name))
        || !StrEqual(steamId, expectedSteam) || !AreClientCookiesCached(client))
    {
        return;
    }
    char today[16], lastReminderDay[16];
    FormatTime(today, sizeof(today), "%Y%m%d", GetTime());
    if (!StrEqual(today, reminderDay))
    {
        ScheduleUnreadMailReminder(client, MAIL_UNREAD_REMINDER_RETRY);
        return;
    }
    g_MailUnreadReminderCookie.Get(client, lastReminderDay, sizeof(lastReminderDay));
    if (StrEqual(today, lastReminderDay) || !rows.FetchRow())
    {
        return;
    }
    // Commit the daily guard before dispatching chat hooks.
    g_MailUnreadReminderCookie.Set(client, today);
    CPrintToChat(client,
        "%s You have unread server mail; use {gold}!inbox{default} to read it!", MAIL_PREFIX);
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
    if (client <= 0 || client > MaxClients)
    {
        return;
    }
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
    if (!IsMailClient(client))
    {
        return false;
    }
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
            MAIL_PREFIX, RoundToCeil(remaining));
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
