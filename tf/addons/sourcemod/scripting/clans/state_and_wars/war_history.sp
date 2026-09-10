void BuildPlainClanTag(const char[] storedTag, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (!storedTag[0])
    {
        return;
    }

    char rawTag[CLAN_TAG_STORE_MAXLEN];
    ExtractRawClanTag(storedTag, rawTag, sizeof(rawTag));
    CRemoveTags(rawTag, sizeof(rawTag));
    TrimString(rawTag);

    if (!rawTag[0])
    {
        return;
    }

    FormatEx(buffer, maxlen, "[%s]", rawTag);
}

void BuildClanWarTagLabel(const char[] storedTag, const char[] clanName, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (storedTag[0])
    {
        BuildClanDisplayTag(storedTag, buffer, maxlen);
        return;
    }

    strcopy(buffer, maxlen, clanName);
}

void BuildClanHistoryTagLabel(const char[] storedTag, const char[] clanName, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (storedTag[0])
    {
        BuildPlainClanTag(storedTag, buffer, maxlen);
        if (buffer[0])
        {
            return;
        }
    }

    strcopy(buffer, maxlen, clanName);
    CRemoveTags(buffer, maxlen);
    TrimString(buffer);
}

void BuildClanWarHistorySummary(int viewerClanId, int clanIdA, int scoreA, int scoreB, int winnerClanId, ClanWarStatus status, const char[] clanNameA, const char[] clanTagA, const char[] clanNameB, const char[] clanTagB, char[] buffer, int maxlen)
{
    char labelA[96];
    char labelB[96];
    BuildClanHistoryTagLabel(clanTagA, clanNameA, labelA, sizeof(labelA));
    BuildClanHistoryTagLabel(clanTagB, clanNameB, labelB, sizeof(labelB));

    bool viewerIsClanA = (viewerClanId == clanIdA);
    int ownScore = viewerIsClanA ? scoreA : scoreB;
    int otherScore = viewerIsClanA ? scoreB : scoreA;

    char opponentLabel[96];
    if (viewerIsClanA)
    {
        strcopy(opponentLabel, sizeof(opponentLabel), labelB);
    }
    else
    {
        strcopy(opponentLabel, sizeof(opponentLabel), labelA);
    }

    if (status == ClanWarStatus_Active)
    {
        FormatEx(buffer, maxlen, "Active vs %s (%d-%d)", opponentLabel, ownScore, otherScore);
        return;
    }

    if (status == ClanWarStatus_Expired)
    {
        FormatEx(buffer, maxlen, "Expired vs %s (%d-%d)", opponentLabel, ownScore, otherScore);
        return;
    }

    if (status == ClanWarStatus_Surrendered)
    {
        if (winnerClanId == viewerClanId)
        {
            FormatEx(buffer, maxlen, "Won by surrender vs %s (%d-%d)", opponentLabel, ownScore, otherScore);
        }
        else
        {
            FormatEx(buffer, maxlen, "Surrendered to %s (%d-%d)", opponentLabel, ownScore, otherScore);
        }
        return;
    }

    if (winnerClanId == viewerClanId)
    {
        FormatEx(buffer, maxlen, "Won vs %s (%d-%d)", opponentLabel, ownScore, otherScore);
        return;
    }

    if (winnerClanId > 0)
    {
        FormatEx(buffer, maxlen, "Lost vs %s (%d-%d)", opponentLabel, ownScore, otherScore);
        return;
    }

    FormatEx(buffer, maxlen, "War vs %s (%d-%d)", opponentLabel, ownScore, otherScore);
}

void ShowClanWarHistoryDetailsMenu(int client, int clanId, const char[] clanName, int warInstanceId)
{
    if (client <= 0 || !IsClientInGame(client) || warInstanceId <= 0 || !EnsureDatabaseReady(client))
    {
        return;
    }

    g_iClanHistoryMenuClanId[client] = clanId;
    strcopy(g_sClanHistoryMenuClanName[client], sizeof(g_sClanHistoryMenuClanName[]), clanName);

    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT i.id, i.clan_id_a, i.clan_id_b, "
        ... "COALESCE(w.score_a, i.score_a), COALESCE(w.score_b, i.score_b), "
        ... "COALESCE(w.winner_clan_id, COALESCE(i.winner_clan_id, 0)), "
        ... "COALESCE(w.status, i.status), i.created_at, COALESCE(w.finished_at, COALESCE(i.finished_at, 0)), "
        ... "COALESCE(ca.name, ''), COALESCE(ca.tag, ''), COALESCE(cb.name, ''), COALESCE(cb.tag, '') "
        ... "FROM clan_war_instances i "
        ... "LEFT JOIN clan_wars w ON w.id = i.war_id AND w.created_at = i.created_at AND w.status = %d "
        ... "LEFT JOIN clans ca ON ca.id = i.clan_id_a "
        ... "LEFT JOIN clans cb ON cb.id = i.clan_id_b "
        ... "WHERE i.id = %d AND (i.clan_id_a = %d OR i.clan_id_b = %d) "
        ... "LIMIT 1",
        view_as<int>(ClanWarStatus_Active),
        warInstanceId,
        clanId,
        clanId);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Clan war detail query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load war details.");
        delete results;
        return;
    }

    if (!results.FetchRow())
    {
        PrintToChat(client, "[Clans] That war could not be found.");
        delete results;
        return;
    }

    int clanIdA = results.FetchInt(1);
    int scoreA = results.FetchInt(3);
    int scoreB = results.FetchInt(4);
    int winnerClanId = results.FetchInt(5);
    ClanWarStatus status = view_as<ClanWarStatus>(results.FetchInt(6));
    int createdAt = results.FetchInt(7);
    int finishedAt = results.FetchInt(8);

    char clanNameA[CLAN_NAME_MAXLEN + 1];
    char clanTagA[CLAN_TAG_STORE_MAXLEN];
    char clanNameB[CLAN_NAME_MAXLEN + 1];
    char clanTagB[CLAN_TAG_STORE_MAXLEN];
    results.FetchString(9, clanNameA, sizeof(clanNameA));
    results.FetchString(10, clanTagA, sizeof(clanTagA));
    results.FetchString(11, clanNameB, sizeof(clanNameB));
    results.FetchString(12, clanTagB, sizeof(clanTagB));
    delete results;

    char summary[192];
    char startedText[32];
    char finishedText[32];
    BuildClanWarHistorySummary(clanId, clanIdA, scoreA, scoreB, winnerClanId, status, clanNameA, clanTagA, clanNameB, clanTagB, summary, sizeof(summary));
    FormatTime(startedText, sizeof(startedText), "%Y-%m-%d %H:%M", createdAt);
    if (finishedAt > 0)
    {
        FormatTime(finishedText, sizeof(finishedText), "%Y-%m-%d %H:%M", finishedAt);
    }
    else
    {
        strcopy(finishedText, sizeof(finishedText), "Ongoing");
    }

    Menu menu = new Menu(MenuHandler_ClanWarHistoryDetails);
    char title[192];
    char line[192];
    FormatEx(title, sizeof(title), "War Details\n%s", clanName);
    menu.SetTitle(title);

    FormatEx(line, sizeof(line), "Summary: %s", summary);
    menu.AddItem("summary", line, ITEMDRAW_DISABLED);

    FormatEx(line, sizeof(line), "Started: %s", startedText);
    menu.AddItem("started", line, ITEMDRAW_DISABLED);

    FormatEx(line, sizeof(line), "Finished: %s", finishedText);
    menu.AddItem("finished", line, ITEMDRAW_DISABLED);

    menu.AddItem("top5", "Top 5 Kills", ITEMDRAW_DISABLED);

    FormatEx(query, sizeof(query),
        "SELECT wk.steamid64, wk.clan_id, wk.kills, COALESCE(wk.currency_stolen, 0), COALESCE(c.name, ''), COALESCE(c.tag, '') "
        ... "FROM clan_war_member_kills wk "
        ... "LEFT JOIN clans c ON c.id = wk.clan_id "
        ... "WHERE wk.war_instance_id = %d "
        ... "ORDER BY wk.kills DESC, wk.clan_id ASC, wk.steamid64 ASC "
        ... "LIMIT 5",
        warInstanceId);

    results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Clan war leader query failed: %s", error);
        delete results;
        menu.AddItem("leaders_error", "Failed to load kill leaders", ITEMDRAW_DISABLED);
    }
    else
    {
        bool addedLeaders = false;
        int place = 1;
        while (results.FetchRow())
        {
            char steamid64[STEAMID64_MAXLEN];
            char leaderClanName[CLAN_NAME_MAXLEN + 1];
            char leaderClanTag[CLAN_TAG_STORE_MAXLEN];
            char clanLabel[96];
            char playerName[MAX_NAME_LENGTH * 2];

            results.FetchString(0, steamid64, sizeof(steamid64));
            results.FetchString(4, leaderClanName, sizeof(leaderClanName));
            results.FetchString(5, leaderClanTag, sizeof(leaderClanTag));
            BuildClanHistoryTagLabel(leaderClanTag, leaderClanName, clanLabel, sizeof(clanLabel));
            ResolvePlayerDisplayName(steamid64, playerName, sizeof(playerName));

            if (clanLabel[0])
            {
                FormatEx(line, sizeof(line), "%d. %s %s - %d kills, %d Gems stolen", place, clanLabel, playerName, results.FetchInt(2), results.FetchInt(3));
            }
            else
            {
                FormatEx(line, sizeof(line), "%d. %s - %d kills, %d Gems stolen", place, playerName, results.FetchInt(2), results.FetchInt(3));
            }

            menu.AddItem("leader", line, ITEMDRAW_DISABLED);
            place++;
            addedLeaders = true;
        }
        delete results;

        if (!addedLeaders)
        {
            menu.AddItem("leaders_none", "No tracked kills yet", ITEMDRAW_DISABLED);
        }
    }

    menu.ExitBackButton = true;
    menu.Display(client, CLAN_MENU_TIME);
}

void ShowClanHistoryMenu(int client, int clanId, const char[] clanName)
{
    if (client <= 0 || !IsClientInGame(client) || clanId <= 0 || !EnsureDatabaseReady(client))
    {
        return;
    }

    g_iClanHistoryMenuClanId[client] = clanId;
    strcopy(g_sClanHistoryMenuClanName[client], sizeof(g_sClanHistoryMenuClanName[]), clanName);

    Menu menu = new Menu(MenuHandler_ClanHistory);
    char title[192];
    char line[320];
    char query[1024];
    char timestamp[32];
    FormatEx(title, sizeof(title), "Clan History\n%s", clanName);
    menu.SetTitle(title);
    menu.ExitBackButton = true;

    bool added = false;

    FormatEx(query, sizeof(query),
        "SELECT i.id, i.clan_id_a, i.clan_id_b, "
        ... "COALESCE(w.score_a, i.score_a), COALESCE(w.score_b, i.score_b), "
        ... "COALESCE(w.winner_clan_id, COALESCE(i.winner_clan_id, 0)), "
        ... "COALESCE(w.status, i.status), i.created_at, COALESCE(w.finished_at, COALESCE(i.finished_at, 0)), "
        ... "COALESCE(ca.name, ''), COALESCE(ca.tag, ''), COALESCE(cb.name, ''), COALESCE(cb.tag, '') "
        ... "FROM clan_war_instances i "
        ... "LEFT JOIN clan_wars w ON w.id = i.war_id AND w.created_at = i.created_at AND w.status = %d "
        ... "LEFT JOIN clans ca ON ca.id = i.clan_id_a "
        ... "LEFT JOIN clans cb ON cb.id = i.clan_id_b "
        ... "WHERE i.clan_id_a = %d OR i.clan_id_b = %d "
        ... "ORDER BY CASE WHEN w.id IS NOT NULL THEN i.created_at ELSE COALESCE(i.finished_at, i.created_at) END DESC, i.id DESC "
        ... "LIMIT 100",
        view_as<int>(ClanWarStatus_Active),
        clanId,
        clanId);

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Clan war history query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load your clan history.");
        delete results;
        delete menu;
        return;
    }

    bool addedWars = false;
    while (results.FetchRow())
    {
        if (!addedWars)
        {
            menu.AddItem("wars_header", "Wars", ITEMDRAW_DISABLED);
            addedWars = true;
        }

        char clanNameA[CLAN_NAME_MAXLEN + 1];
        char clanTagA[CLAN_TAG_STORE_MAXLEN];
        char clanNameB[CLAN_NAME_MAXLEN + 1];
        char clanTagB[CLAN_TAG_STORE_MAXLEN];
        char summary[192];
        char info[32];

        results.FetchString(9, clanNameA, sizeof(clanNameA));
        results.FetchString(10, clanTagA, sizeof(clanTagA));
        results.FetchString(11, clanNameB, sizeof(clanNameB));
        results.FetchString(12, clanTagB, sizeof(clanTagB));
        BuildClanWarHistorySummary(
            clanId,
            results.FetchInt(1),
            results.FetchInt(3),
            results.FetchInt(4),
            results.FetchInt(5),
            view_as<ClanWarStatus>(results.FetchInt(6)),
            clanNameA,
            clanTagA,
            clanNameB,
            clanTagB,
            summary,
            sizeof(summary));

        int displayTime = results.FetchInt(8);
        if (displayTime <= 0)
        {
            displayTime = results.FetchInt(7);
        }
        FormatTime(timestamp, sizeof(timestamp), "%Y-%m-%d", displayTime);
        FormatEx(line, sizeof(line), "%s - %s", timestamp, summary);
        FormatEx(info, sizeof(info), "war:%d", results.FetchInt(0));
        menu.AddItem(info, line);
        added = true;
    }
    delete results;

    FormatEx(query, sizeof(query),
        "SELECT summary, created_at FROM clan_history WHERE clan_id = %d ORDER BY created_at DESC, id DESC LIMIT 100",
        clanId);

    results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Clan history query failed: %s", error);
        PrintToChat(client, "[Clans] Failed to load your clan history.");
        delete results;
        delete menu;
        return;
    }

    bool addedActivity = false;
    char summary[CLAN_HISTORY_SUMMARY_MAXLEN + 1];
    while (results.FetchRow())
    {
        if (!addedActivity)
        {
            menu.AddItem("activity_header", "Activity", ITEMDRAW_DISABLED);
            addedActivity = true;
        }

        results.FetchString(0, summary, sizeof(summary));
        FormatTime(timestamp, sizeof(timestamp), "%Y-%m-%d", results.FetchInt(1));
        FormatEx(line, sizeof(line), "%s - %s", timestamp, summary);
        menu.AddItem("history", line, ITEMDRAW_DISABLED);
        added = true;
    }
    delete results;

    if (!added)
    {
        menu.AddItem("none", "No clan history yet", ITEMDRAW_DISABLED);
    }

    menu.Display(client, CLAN_MENU_TIME);
}

void BuildWarPlayerLabel(int client, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
    {
        return;
    }

    char displayName[384];
    BuildClanChatSenderName(client, displayName, sizeof(displayName));

    char steamid64[STEAMID64_MAXLEN];
    char selectedTag[256];
    char displayTag[256];
    if (GetClientSteam64(client, steamid64, sizeof(steamid64))
        && TryGetSelectedTag(client, steamid64, selectedTag, sizeof(selectedTag)))
    {
        BuildClanDisplayTag(selectedTag, displayTag, sizeof(displayTag));
        if (displayTag[0])
        {
            FormatEx(buffer, maxlen, "%s %s", displayTag, displayName);
            ResolveClientTeamColorTag(client, buffer, maxlen);
            return;
        }
    }

    strcopy(buffer, maxlen, displayName);
    ResolveClientTeamColorTag(client, buffer, maxlen);
}

