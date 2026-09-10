void ShowMailMainMenu(int client)
{
    Menu menu = new Menu(MenuHandler_MailMain);
    menu.SetTitle("Mail");
    menu.AddItem("send", "Send Mail");
    menu.AddItem("gift", "Gift Gems");
    menu.AddItem("inbox", "Check Inbox");
    menu.AddItem("sent", "Read Sent Mail");
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MailMain(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }

    if (action != MenuAction_Select || !IsMailClient(client))
    {
        return 0;
    }

    char info[16];
    menu.GetItem(item, info, sizeof(info));
    if (StrEqual(info, "send"))
    {
        CPrintToChat(client, "%s Type {gold}!mail playername hey how are you?{default} to send a player mail, even an offline player!", MAIL_PREFIX);
    }
    else if (StrEqual(info, "gift"))
    {
        CPrintToChat(client, "%s Type {gold}!gift playername amount{default} to mail a player Gems.", MAIL_PREFIX);
    }
    else if (StrEqual(info, "inbox"))
    {
        RequestMailList(client, MailView_Inbox);
    }
    else if (StrEqual(info, "sent"))
    {
        RequestMailList(client, MailView_Sent);
    }
    return 0;
}

void BeginMailCommand(int client)
{
    if (!g_MailDatabaseReady)
    {
        CPrintToChat(client, "%s Mail is temporarily unavailable.", MAIL_PREFIX);
        return;
    }

    char raw[MAIL_CONTENTS_MAX + MAIL_NAME_MAX];
    GetCmdArgString(raw, sizeof(raw));
    StripQuotes(raw);
    TrimString(raw);

    char search[MAIL_NAME_MAX];
    int position = BreakString(raw, search, sizeof(search));
    if (position == -1)
    {
        CPrintToChat(client, "%s Usage: {gold}!mail playername message", MAIL_PREFIX);
        return;
    }

    char contents[MAIL_CONTENTS_MAX];
    strcopy(contents, sizeof(contents), raw[position]);
    TrimString(search);
    TrimString(contents);
    if (search[0] == '\0' || contents[0] == '\0')
    {
        CPrintToChat(client, "%s Usage: {gold}!mail playername message", MAIL_PREFIX);
        return;
    }

    strcopy(g_MailPendingSearch[client], sizeof(g_MailPendingSearch[]), search);
    strcopy(g_MailPendingContents[client], sizeof(g_MailPendingContents[]), contents);
    g_MailPendingGems[client] = 0;
    RequestMailPlayerSearch(client);
}

int GetRankMinimumKillsDeaths()
{
    ConVar convar = FindConVar("sm_whaletracker_rank_min_kd_sum");
    return convar != null ? convar.IntValue : 200;
}

int GetRankMinimumPlaytime()
{
    ConVar convar = FindConVar("sm_whaletracker_rank_min_playtime_seconds");
    return convar != null ? convar.IntValue : 10800;
}

void RequestMailPlayerSearch(int client)
{
    char escapedSearch[(MAIL_NAME_MAX * 2) + 1];
    if (!EscapeMailSql(g_MailPendingSearch[client], escapedSearch, sizeof(escapedSearch)))
    {
        CPrintToChat(client, "%s Could not search for that player.", MAIL_PREFIX);
        return;
    }

    delete g_MailSearchResults[client];
    g_MailSearchResults[client] = null;
    int generation = ++g_MailSearchGeneration[client];

    char query[2048];
    FormatEx(query, sizeof(query),
        "SELECT w.steamid, "
        ... "COALESCE(NULLIF(pr.newname COLLATE utf8mb4_uca1400_ai_ci, ''), NULLIF(fs.last_name, ''), NULLIF(w.cached_personaname, ''), w.steamid), "
        ... "GREATEST(COALESCE(w.playtime, 0), 0) "
        ... "FROM whaletracker w "
        ... "LEFT JOIN filters_steam_names fs ON fs.steamid64 = w.steamid "
        ... "LEFT JOIN prename_rules pr ON pr.pattern COLLATE utf8mb4_uca1400_ai_ci = w.steamid "
        ... "WHERE (GREATEST(COALESCE(w.kills, 0), 0) + GREATEST(COALESCE(w.deaths, 0), 0)) >= %d "
        ... "AND GREATEST(COALESCE(w.playtime, 0), 0) >= %d "
        ... "AND (COALESCE(pr.newname, '') LIKE '%%%s%%' "
        ... "OR COALESCE(fs.last_name, '') LIKE '%%%s%%' "
        ... "OR COALESCE(w.cached_personaname, '') LIKE '%%%s%%') "
        ... "ORDER BY GREATEST(COALESCE(w.playtime, 0), 0) DESC, "
        ... "LOWER(COALESCE(NULLIF(pr.newname COLLATE utf8mb4_uca1400_ai_ci, ''), NULLIF(fs.last_name, ''), NULLIF(w.cached_personaname, ''), w.steamid)) ASC "
        ... "LIMIT %d",
        GetRankMinimumKillsDeaths(),
        GetRankMinimumPlaytime(),
        escapedSearch,
        escapedSearch,
        escapedSearch,
        MAIL_SEARCH_MAX);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(generation);
    g_MailDatabase.Query(SQL_OnMailPlayerSearch, query, pack);
}

int FindSearchResult(ArrayList results, const char[] steamId)
{
    MailSearchResult entry;
    for (int i = 0; i < results.Length; i++)
    {
        results.GetArray(i, entry, sizeof(entry));
        if (StrEqual(entry.steamId, steamId, false))
        {
            return i;
        }
    }
    return -1;
}

public void SQL_OnMailPlayerSearch(Database db, DBResultSet rows, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    int generation = pack.ReadCell();
    delete pack;

    if (!IsMailClient(client) || generation != g_MailSearchGeneration[client])
    {
        return;
    }

    if (error[0] != '\0')
    {
        LogError("[server_mail] Ranked-player search failed: %s", error);
        CPrintToChat(client, "%s Player search failed.", MAIL_PREFIX);
        return;
    }

    ArrayList results = new ArrayList(sizeof(MailSearchResult));
    MailSearchResult entry;
    while (rows != null && rows.FetchRow())
    {
        rows.FetchString(0, entry.steamId, sizeof(entry.steamId));
        rows.FetchString(1, entry.name, sizeof(entry.name));
        entry.playtime = rows.FetchInt(2);
        entry.connected = false;
        results.PushArray(entry, sizeof(entry));
    }

    for (int target = 1; target <= MaxClients; target++)
    {
        if (!IsMailClient(target))
        {
            continue;
        }

        char steamId[MAIL_STEAMID_MAX];
        char currentName[MAIL_NAME_MAX];
        if (!Kogasa_GetClientSteamId64(target, steamId, sizeof(steamId), true)
            || !GetClientName(target, currentName, sizeof(currentName)))
        {
            continue;
        }

        int index = FindSearchResult(results, steamId);
        int rankedHours = 0;
        if (GetFeatureStatus(FeatureType_Native, "WhaleTracker_GetRankedPlaytimeHours") == FeatureStatus_Available)
        {
            rankedHours = WhaleTracker_GetRankedPlaytimeHours(target);
        }

        if (index == -1)
        {
            if (rankedHours <= 0 || StrContains(currentName, g_MailPendingSearch[client], false) == -1)
            {
                continue;
            }

            strcopy(entry.steamId, sizeof(entry.steamId), steamId);
            strcopy(entry.name, sizeof(entry.name), currentName);
            entry.playtime = rankedHours * 3600;
            entry.connected = true;
            results.PushArray(entry, sizeof(entry));
            continue;
        }

        results.GetArray(index, entry, sizeof(entry));
        strcopy(entry.name, sizeof(entry.name), currentName);
        if (rankedHours > 0)
        {
            entry.playtime = rankedHours * 3600;
        }
        entry.connected = true;
        results.SetArray(index, entry, sizeof(entry));
    }

    results.SortCustom(SortMailSearchResults);
    g_MailSearchResults[client] = results;
    ShowMailSearchResults(client);
}

public int SortMailSearchResults(int index1, int index2, Handle array, Handle data)
{
    ArrayList results = view_as<ArrayList>(array);
    MailSearchResult left;
    MailSearchResult right;
    results.GetArray(index1, left, sizeof(left));
    results.GetArray(index2, right, sizeof(right));

    if (left.connected != right.connected)
    {
        return left.connected ? -1 : 1;
    }
    if (left.playtime != right.playtime)
    {
        return left.playtime > right.playtime ? -1 : 1;
    }
    return strcmp(left.name, right.name, false);
}

void ShowMailSearchResults(int client)
{
    ArrayList results = g_MailSearchResults[client];
    if (results == null || results.Length == 0)
    {
        CPrintToChat(client, "%s No ranked player matched '{gold}%s{default}'.", MAIL_PREFIX, g_MailPendingSearch[client]);
        return;
    }

    Menu menu = new Menu(MenuHandler_MailSearchResults);
    if (StrEqual(g_MailPendingAttachment[client], "hug"))
    {
        menu.SetTitle("Mail a hug to:");
    }
    else if (StrEqual(g_MailPendingAttachment[client], "feed"))
    {
        menu.SetTitle("Mail a feed to:");
    }
    else if (StrEqual(g_MailPendingAttachment[client], "rape"))
    {
        menu.SetTitle("Mail a rape to:");
    }
    else if (StrEqual(g_MailPendingAttachment[client], "rtd"))
    {
        menu.SetTitle("Mail an RTD to:");
    }
    else
    {
        menu.SetTitle(g_MailPendingGems[client] > 0 ? "Gift Gems to:" : "Send mail to:");
    }

    MailSearchResult entry;
    char display[256];
    int count = results.Length;
    if (count > MAIL_SEARCH_MAX)
    {
        count = MAIL_SEARCH_MAX;
    }

    for (int i = 0; i < count; i++)
    {
        results.GetArray(i, entry, sizeof(entry));
        int steamLength = strlen(entry.steamId);
        char suffix[7];
        if (steamLength > 6)
        {
            strcopy(suffix, sizeof(suffix), entry.steamId[steamLength - 6]);
        }
        else
        {
            strcopy(suffix, sizeof(suffix), entry.steamId);
        }
        Format(display, sizeof(display), "%s%s - ...%s",
            entry.name,
            entry.connected ? " [online]" : "",
            suffix);
        menu.AddItem(entry.steamId, display);
    }

    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MailSearchResults(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }

    if (action != MenuAction_Select || !IsMailClient(client)
        || g_MailPendingContents[client][0] == '\0')
    {
        return 0;
    }

    char receiverSteamId[MAIL_STEAMID_MAX];
    menu.GetItem(item, receiverSteamId, sizeof(receiverSteamId));

    char receiverName[MAIL_NAME_MAX];
    strcopy(receiverName, sizeof(receiverName), receiverSteamId);
    ArrayList results = g_MailSearchResults[client];
    int index = results != null ? FindSearchResult(results, receiverSteamId) : -1;
    if (index != -1)
    {
        MailSearchResult entry;
        results.GetArray(index, entry, sizeof(entry));
        strcopy(receiverName, sizeof(receiverName), entry.name);
    }

    QueuePendingMailToTarget(client, receiverSteamId, receiverName, false);
    return 0;
}

void ShowRtdMailCostMenu(int client, const char[] receiverSteamId, const char[] receiverName)
{
    Menu menu = new Menu(MenuHandler_RtdMailCost);
    menu.SetTitle("Spend %d Gems to mail an RTD to %s?", MAIL_RTD_GIFT_COST, receiverName);
    menu.AddItem(receiverSteamId, "Yes");
    menu.AddItem("no", "No");
    menu.ExitButton = true;
    menu.Display(client, 15);
}

public int MenuHandler_RtdMailCost(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }
    if (action == MenuAction_Cancel && IsMailClient(client))
    {
        ClearClientMailState(client);
        return 0;
    }
    if (action != MenuAction_Select || !IsMailClient(client))
    {
        return 0;
    }

    char receiverSteamId[MAIL_STEAMID_MAX];
    menu.GetItem(item, receiverSteamId, sizeof(receiverSteamId));
    if (StrEqual(receiverSteamId, "no"))
    {
        ClearClientMailState(client);
        return 0;
    }

    char receiverName[MAIL_NAME_MAX];
    strcopy(receiverName, sizeof(receiverName), receiverSteamId);
    ArrayList results = g_MailSearchResults[client];
    int index = results != null ? FindSearchResult(results, receiverSteamId) : -1;
    if (index != -1)
    {
        MailSearchResult entry;
        results.GetArray(index, entry, sizeof(entry));
        strcopy(receiverName, sizeof(receiverName), entry.name);
    }
    QueuePendingMailToTarget(client, receiverSteamId, receiverName, true);
    return 0;
}

void RefundMailSendCost(const char[] senderSteamId, int amount)
{
    if (amount <= 0)
    {
        return;
    }
    if (!IsPointsStoreGiftAvailable()
        || !PointsStore_RefundBonusPointsSteamId(
            senderSteamId,
            amount,
            "server_mail_send_refund"))
    {
        LogError("[server_mail] Failed to refund %d Gems to %s.", amount, senderSteamId);
    }
}

