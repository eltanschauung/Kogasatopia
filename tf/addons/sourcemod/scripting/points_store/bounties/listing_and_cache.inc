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

    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT target_steamid64, MAX(target_name), SUM(amount + bonus_amount) AS total_amount "
        ... "FROM %s WHERE status = 'active' AND expires_at > %d "
        ... "GROUP BY target_steamid64 ORDER BY total_amount DESC, MAX(target_name) ASC LIMIT 100",
        BOUNTY_TABLE,
        GetTime());
    g_Database.Query(SQL_OnBountyListLoaded, query, GetClientUserId(client));
    return Plugin_Handled;
}

public void SQL_OnBountyListLoaded(Database db, DBResultSet rows, const char[] error, any userId)
{
    int client = GetClientOfUserId(userId);
    if (!Client_IsHumanInGame(client))
    {
        return;
    }
    if (error[0] != '\0')
    {
        LogError("[points_store] Bounty list failed: %s", error);
        CPrintToChat(client, "%s Failed to load bounties.", g_BountyPrefix);
        return;
    }

    Menu menu = new Menu(MenuHandler_BountyList);
    menu.SetTitle("Bounties");
    char steamId[BOUNTY_STEAMID_MAX];
    char name[BOUNTY_NAME_MAX];
    char display[256];
    char currencyLong[BP_CURRENCY_LONG_MAX];
    GetCurrencyLongLabel(currencyLong, sizeof(currencyLong));
    int count = 0;
    while (rows != null && rows.FetchRow())
    {
        rows.FetchString(0, steamId, sizeof(steamId));
        rows.FetchString(1, name, sizeof(name));
        int amount = rows.FetchInt(2);
        int target = Kogasa_FindClientBySteamId64(steamId);
        if (target > 0)
        {
            GetClientName(target, name, sizeof(name));
        }
        FormatEx(display, sizeof(display), "%s (%d %s)", name, amount, currencyLong);
        menu.AddItem(steamId, display, ITEMDRAW_DISABLED);
        count++;
    }
    if (count == 0)
    {
        menu.AddItem("none", "No active bounties", ITEMDRAW_DISABLED);
    }
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
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

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT target_steamid64, COUNT(*) FROM %s WHERE status = 'active' AND expires_at > %d GROUP BY target_steamid64",
        BOUNTY_TABLE,
        GetTime());

    g_BountyTargetCacheGeneration++;
    g_Database.Query(SQL_OnActiveBountyTargetsLoaded, query, g_BountyTargetCacheGeneration);
}

public void SQL_OnActiveBountyTargetsLoaded(Database db, DBResultSet rows, const char[] error, any generation)
{
    if (error[0] != '\0')
    {
        LogError("[points_store] Active bounty target cache refresh failed: %s", error);
        return;
    }
    if (generation != g_BountyTargetCacheGeneration)
    {
        return;
    }

    StringMap refreshedTargets = new StringMap();
    char steamId[BOUNTY_STEAMID_MAX];
    int activeCount = 0;
    while (rows != null && rows.FetchRow())
    {
        rows.FetchString(0, steamId, sizeof(steamId));
        refreshedTargets.SetValue(steamId, 1, true);
        activeCount++;
    }

    delete g_ActiveBountyTargets;
    g_ActiveBountyTargets = refreshedTargets;
    g_ActiveBountyCount = activeCount;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (Client_IsHumanInGame(client) && !IsClientActiveBountyTarget(client))
        {
            g_BountyMedicAssistsLife[client] = 0;
        }
    }
}

