public Action Command_ShowBounties(int client, int args)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Handled;
    }
    if (!g_BountyDatabaseReady || g_Database == null)
    {
        CPrintToChat(client, "%s Bounties are temporarily unavailable.", g_BountyPrefix);
        return Plugin_Handled;
    }

    if (!g_BountyListCacheReady)
    {
        CPrintToChat(client, "%s Bounties are still loading. Please try again shortly.", g_BountyPrefix);
        return Plugin_Handled;
    }

    Menu menu = BuildBountyListMenu();
    menu.Display(client, MENU_TIME_FOREVER);
    return Plugin_Handled;
}

int GetBountyListRemainingMinutes(BountyListEntry entry, int now)
{
    int seconds = GetBountyPlaytimeLimitSeconds() - entry.qualifyingPlaytime;
    int wallSeconds = entry.expiresAt - now;
    if (wallSeconds < seconds)
        seconds = wallSeconds;
    return seconds > 0 ? (seconds + 59) / 60 : 0;
}

Menu BuildBountyListMenu()
{
    Menu menu = new Menu(MenuHandler_BountyList);
    menu.SetTitle("Bounties");
    char display[256];
    char currencyLong[BP_CURRENCY_LONG_MAX];
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
    int count = 0;
    int now = GetTime();
    BountyListEntry entry;
    for (int i = 0; g_BountyListCache != null && i < g_BountyListCache.Length && count < BOUNTY_LIST_MAX_TARGETS; i++)
    {
        g_BountyListCache.GetArray(i, entry, sizeof(entry));
        int minutes = GetBountyListRemainingMinutes(entry, now);
        if (minutes == 0) continue;
        FormatEx(display, sizeof(display), "%s (%s %d) (%dm)", entry.name, currencyLong, entry.amount, minutes);
        menu.AddItem(entry.steamId, display, ITEMDRAW_DISABLED);
        count++;
    }
    if (count == 0)
    {
        menu.AddItem("none", "No active bounties", ITEMDRAW_DISABLED);
    }
    menu.ExitButton = true;
    return menu;
}

public int MenuHandler_BountyList(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    return 0;
}

void MarkActiveBountyTarget(const char[] steamId)
{
    if (g_ActiveBountyTargets == null)
    {
        g_ActiveBountyTargets = new StringMap();
    }

    int existingMarker;
    bool wasActive = g_ActiveBountyTargets.GetValue(steamId, existingMarker);
    g_BountyTargetCacheGeneration++;
    g_ActiveBountyTargets.SetValue(steamId, 1, true);
    if (!wasActive)
    {
        int target = Kogasa_FindClientBySteamId64(steamId);
        if (target > 0)
        {
            g_BountyMedicAssistsLife[target] = 0;
        }
    }
}

bool IsSteamIdActiveBountyTarget(const char[] steamId)
{
    int cacheMarker;
    return g_ActiveBountyTargets != null
        && steamId[0] != '\0'
        && g_ActiveBountyTargets.GetValue(steamId, cacheMarker);
}

void RefreshActiveBountyTargets()
{
    if (!g_BountyDatabaseReady || g_Database == null)
    {
        return;
    }

    g_BountyTargetCacheRefreshQueued = true;
    if (g_BountyTargetCachePending || g_BountyTargetCacheRefreshTimer != null)
        return;

    float elapsed = GetEngineTime() - g_BountyTargetCacheLastRequest;
    if (g_BountyTargetCacheLastRequest >= 0.0 && elapsed < BOUNTY_CACHE_REFRESH_INTERVAL)
    {
        g_BountyTargetCacheRefreshTimer = CreateTimer(
            BOUNTY_CACHE_REFRESH_INTERVAL - elapsed, Timer_RefreshBountyCache);
        return;
    }
    StartActiveBountyCacheRefresh();
}

void Bounties_OnDatabaseDisconnected()
{
    g_BountyTargetCacheGeneration++;
    g_BountyListCacheReady = false;
    g_BountyTargetCachePending = false;
    g_BountyTargetCacheRefreshQueued = false;
    g_BountyTargetCacheLastRequest = -1.0;
    delete g_BountyTargetCacheRefreshTimer;
    g_BountyTargetCacheRefreshTimer = null;
}

public Action Timer_RefreshBountyCache(Handle timer)
{
    g_BountyTargetCacheRefreshTimer = null;
    if (g_BountyTargetCacheRefreshQueued && g_BountyDatabaseReady && g_Database != null)
        StartActiveBountyCacheRefresh();
    return Plugin_Stop;
}

void BuildActiveBountyCacheQuery(char[] query, int maxlen)
{
    // The furthest-progressed stack expires first; the week-long expiry is only a backstop.
    FormatEx(query, maxlen,
        "SELECT target_steamid64, MAX(target_name), SUM(amount + bonus_amount) AS total_amount, "
        ... "MAX(qualifying_playtime_seconds), MIN(expires_at) "
        ... "FROM %s WHERE status = 'active' AND expires_at > %d "
        ... "GROUP BY target_steamid64 ORDER BY total_amount DESC, MAX(target_name) ASC, target_steamid64 ASC",
        BOUNTY_TABLE,
        GetTime());
}

void StartActiveBountyCacheRefresh()
{
    char query[1024];
    BuildActiveBountyCacheQuery(query, sizeof(query));
    g_BountyTargetCachePending = true;
    g_BountyTargetCacheRefreshQueued = false;
    g_BountyTargetCacheLastRequest = GetEngineTime();
    g_Database.Query(SQL_OnActiveBountyTargetsLoaded, query, g_BountyTargetCacheGeneration);
}

public void SQL_OnActiveBountyTargetsLoaded(Database db, DBResultSet rows, const char[] error, any generation)
{
    if (!g_BountyDatabaseReady || g_Database == null || db == null || !db.IsSameConnection(g_Database))
        return;
    g_BountyTargetCachePending = false;
    if (error[0] != '\0')
    {
        LogError("[points_store] Active bounty target cache refresh failed: %s", error);
        RefreshActiveBountyTargets();
        return;
    }
    if (generation != g_BountyTargetCacheGeneration)
    {
        RefreshActiveBountyTargets();
        return;
    }

    StringMap refreshedTargets = new StringMap();
    ArrayList refreshedList = new ArrayList(sizeof(BountyListEntry));
    BountyListEntry entry;
    int activeCount = 0;
    while (rows != null && rows.FetchRow())
    {
        rows.FetchString(0, entry.steamId, sizeof(entry.steamId));
        rows.FetchString(1, entry.name, sizeof(entry.name));
        entry.amount = rows.FetchInt(2);
        entry.qualifyingPlaytime = rows.FetchInt(3);
        entry.expiresAt = rows.FetchInt(4);
        int target = Kogasa_FindClientBySteamId64(entry.steamId);
        if (target > 0)
            GetClientName(target, entry.name, sizeof(entry.name));
        refreshedTargets.SetValue(entry.steamId, 1, true);
        refreshedList.PushArray(entry, sizeof(entry));
        activeCount++;
    }

    delete g_ActiveBountyTargets;
    g_ActiveBountyTargets = refreshedTargets;
    delete g_BountyListCache;
    g_BountyListCache = refreshedList;
    g_BountyListCacheReady = true;
    g_ActiveBountyCount = activeCount;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (Client_IsHumanInGame(client) && !IsClientActiveBountyTarget(client))
        {
            g_BountyMedicAssistsLife[client] = 0;
        }
    }
    if (g_BountyTargetCacheRefreshQueued)
        RefreshActiveBountyTargets();
}

