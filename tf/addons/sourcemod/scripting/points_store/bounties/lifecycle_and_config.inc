static const char g_BountyHelpLines[][] =
{
    "When a client with a bounty on them is dominated, the bounty ends and pays the dominator the Gems.",
    "Each kill, or every 2 assists as Medic, increases the bounty by 5 Gems."
};

void Bounties_OnPluginStart()
{
    RegConsoleCmd("sm_bounty", Command_PlaceBounty, "Place a bounty on a ranked player.");
    RegConsoleCmd("sm_placebounty", Command_PlaceBounty, "Place a bounty on a ranked player.");
    RegConsoleCmd("sm_bounties", Command_ShowBounties, "Show active player bounties.");
    RegConsoleCmd("sm_bh", Command_BountyHelp, "Explain player bounties.");
    RegConsoleCmd("sm_bountyhelp", Command_BountyHelp, "Explain player bounties.");
    HookEvent("player_death", Event_BountyPlayerDeath, EventHookMode_Post);
    HookEvent("teamplay_round_start", Event_BountyRoundStart, EventHookMode_PostNoCopy);

    g_ActiveBountyTargets = new StringMap();
    g_BountyKillAssistsOffset = FindSendPropInfo("CTFPlayerResource", "m_iKillAssists");

    for (int client = 1; client <= MaxClients; client++)
    {
        ResetBountyClientState(client);
    }

    g_BountyMaintenanceTimer = CreateTimer(
        BOUNTY_MAINTENANCE_INTERVAL,
        Timer_BountyMaintenance,
        _,
        TIMER_REPEAT);
    Bounties_RefreshPrefix();
}

void Bounties_RefreshPrefix()
{
    FormatEx(g_BountyPrefix, sizeof(g_BountyPrefix), "%s[Bounties]{default}", g_CurrencyColorTag);
}

int GetBountyMinPlayers()
{
    return g_CvarBountyMinPlayers != null ? g_CvarBountyMinPlayers.IntValue : 6;
}

int GetBountyMaxAmount()
{
    return g_CvarBountyMaxAmount != null ? g_CvarBountyMaxAmount.IntValue : 1000;
}

int GetBountyMinAmount()
{
    return g_CvarBountyMinAmount != null ? g_CvarBountyMinAmount.IntValue : 50;
}

int GetAutomaticBountyMinDeaths()
{
    return g_CvarAutoBountyMinDeaths != null ? g_CvarAutoBountyMinDeaths.IntValue : 2;
}

int GetBountyPlaytimeLimitSeconds()
{
    float minutes = g_CvarBountyTimeLimitMinutes != null ? g_CvarBountyTimeLimitMinutes.FloatValue : 20.0;
    return RoundToCeil(minutes * 60.0);
}

int GetBountyHalftimeSeconds()
{
    return GetBountyPlaytimeLimitSeconds() / 2;
}

int GetBountyHalftimeRemainingMinutes()
{
    return RoundToCeil(float(GetBountyPlaytimeLimitSeconds() - GetBountyHalftimeSeconds()) / 60.0);
}

bool IsBountyPopulationEligible()
{
    return GetClientCount(false) >= GetBountyMinPlayers();
}

int GetBountyPlacementCooldownRemaining(int client)
{
    int remaining = (g_BountyLastPlacementAt[client] + BOUNTY_PLACEMENT_COOLDOWN_SECONDS) - GetTime();
    return remaining > 0 ? remaining : 0;
}

void LoadBountyPlacementCooldown(int client)
{
    if (!g_BountyDatabaseReady || g_Database == null || client <= 0 || client > MaxClients
        || !IsClientConnected(client) || IsFakeClient(client))
    {
        return;
    }

    char steamId[BOUNTY_STEAMID_MAX];
    char escapedSteamId[65];
    if (!GetClientSteamId64(client, steamId, sizeof(steamId))
        || !EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId)))
    {
        return;
    }

    char query[384];
    FormatEx(query, sizeof(query),
        "SELECT COALESCE(MAX(placed_at), 0) FROM %s WHERE sender_steamid64 = '%s'",
        BOUNTY_TABLE,
        escapedSteamId);
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(steamId);
    g_Database.Query(SQL_OnBountyPlacementCooldownLoaded, query, pack);
}

public void SQL_OnBountyPlacementCooldownLoaded(Database db, DBResultSet rows, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    char expectedSteamId[BOUNTY_STEAMID_MAX];
    pack.ReadString(expectedSteamId, sizeof(expectedSteamId));
    delete pack;

    if (error[0] != '\0')
    {
        LogError("[points_store] Bounty cooldown query failed: %s", error);
        return;
    }

    char currentSteamId[BOUNTY_STEAMID_MAX];
    if (client <= 0 || client > MaxClients || !IsClientConnected(client) || IsFakeClient(client)
        || !GetClientSteamId64(client, currentSteamId, sizeof(currentSteamId))
        || !StrEqual(currentSteamId, expectedSteamId, false))
    {
        return;
    }

    g_BountyLastPlacementAt[client] = rows != null && rows.FetchRow() ? rows.FetchInt(0) : 0;
}

public Action Command_BountyHelp(int client, int args)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Handled;
    }

    char firstLine[256];
    FormatEx(firstLine, sizeof(firstLine),
        "Use {gold}'!bounty makocake 100'{default} to place a %s100 Gem{default} bounty on Makocake.",
        g_CurrencyColorTag);
    CPrintToChat(client, "%s %s", g_BountyPrefix, firstLine);
    CPrintToChat(client,
        "%s Bounties last {gold}%d minutes{default} of qualifying playtime or one week in real time.",
        g_BountyPrefix,
        (GetBountyPlaytimeLimitSeconds() + 59) / 60);
    for (int i = 0; i < sizeof(g_BountyHelpLines); i++)
    {
        CPrintToChat(client, "%s %s", g_BountyPrefix, g_BountyHelpLines[i]);
    }
    CPrintToChat(client,
        "%s Individual bounties must be between %s%d and %d %s{default}.",
        g_BountyPrefix,
        g_CurrencyColorTag,
        GetBountyMinAmount(),
        GetBountyMaxAmount(),
        g_CurrencyLongLabel);
    int thresholdDisplay = GetBountyMinPlayers() - 1;
    if (thresholdDisplay < 0)
    {
        thresholdDisplay = 0;
    }
    CPrintToChat(client,
        "%s Bounties can only be placed when more than {gold}%d{default} players are connected, and playtime does not count below that threshold.",
        g_BountyPrefix,
        thresholdDisplay);
    return Plugin_Handled;
}

void Bounties_OnPluginEnd()
{
    delete g_BountyMaintenanceTimer;
    delete g_ActiveBountyTargets;
    g_ActiveBountyTargets = null;
    for (int client = 1; client <= MaxClients; client++)
    {
        delete g_BountySearchResults[client];
        g_BountySearchResults[client] = null;
    }
}

void Bounties_OnMapStart()
{
    g_BountyAutomaticPlacementPending = false;
    for (int client = 1; client <= MaxClients; client++)
    {
        g_BountyMedicAssistsLife[client] = 0;
    }

    if (g_BountyDatabaseReady)
    {
        ProcessExpiredBounties();
        RequestBountyProgress();
        RefreshActiveBountyTargets();
    }
}

