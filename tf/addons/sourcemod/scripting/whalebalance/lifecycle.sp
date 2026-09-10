public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    DuelDetection_Initialize();
    g_hLogEnabled = CreateConVar("sm_autobalance_log", "1", "Enable autobalance debug logging.", _, true, 0.0, true, 1.0);
    g_hDiffThreshold = CreateConVar("sm_autobalance_diff", "1", "Autobalance when team size difference is above this value.", _, true, 1.0, true, 10.0);
    g_hActionDelay = CreateConVar("sm_autobalance_action_delay", "10", "Seconds an imbalance must persist before normal autobalance can move a player.", _, true, 0.0, true, 120.0);
    g_hMaxUnbalanceTime = CreateConVar("sm_autobalance_max_unbalance_time", "5", "Maximum seconds an imbalance may persist before forced autobalance. 0 disables.", _, true, 0.0, true, 300.0);
    g_hForceThresholdDelta = CreateConVar("sm_autobalance_force_threshold_delta", "1", "Force autobalance when team-size diff is at least normal threshold plus this value.", _, true, 0.0, true, 10.0);
    g_hSimpleSelection = CreateConVar("sm_autobalance_simple_selection", "1", "If enabled, autobalance prefers the most recently joined dead player without Engineer buildings on the oversized team, then falls back to lower-priority eligible players by userID.", _, true, 0.0, true, 1.0);
    g_hIgnoreWinning = CreateConVar("sm_autobalance_ignore_winning", "3", "0 disables. 1 blocks losing-to-winning moves. Values above 1 allow losing-to-winning moves when value is >= current team-size diff.", _, true, 0.0);
    g_hDatabaseConfig = CreateConVar("sm_autobalance_database", "default", "Database config name from databases.cfg to use for persistent autobalance immunity.");
    RegAdminCmd("sm_immune", Command_Immune, ADMFLAG_GENERIC, "sm_immune <name> - Toggle persistent autobalance immunity for a player.");
    RegConsoleCmd("sm_volunteer", Command_Volunteer, "sm_volunteer [name] - Toggle autobalance volunteer status.");
    RegConsoleCmd("sm_swap", Command_RequestTeamSwap, "sm_swap [name] - Request a team swap with an enemy player.");
    RegConsoleCmd("sm_requestswap", Command_RequestTeamSwap, "sm_requestswap [name] - Request a team swap with an enemy player.");
    RegConsoleCmd("sm_sw", Command_RequestTeamSwap, "sm_sw [name] - Request a team swap with an enemy player.");
    RegAdminCmd("sm_forceswap", Command_ForceTeamSwap, ADMFLAG_GENERIC, "sm_forceswap <name> [name] - Force two players to swap teams.");
    RegConsoleCmd("sm_yes", Command_AcceptTeamSwap, "Accept a pending team-swap request.");
    LogBalance("[whalebalance] Plugin started.");
    g_hMapImmunity = new StringMap();
    g_hPersistentImmunity = new StringMap();
    g_hVolunteers = new StringMap();
    g_hScrambleImmunity = new StringMap();
    TeamBalance_ResetRuntime();
    ClearAllTeamSwapRequests();

    ApplyServerBalanceCvars(true);
    ConnectImmunityDatabase();
    WhaleScramble_OnPluginStart();
}

public void OnMapStart()
{
    TeamBalance_ResetRuntime();
    ClearAllTeamSwapRequests();
    StopAutobalanceTimer();
    g_fImbalanceDetectedAt = 0.0;
    g_hAutoBalanceTimer = CreateTimer(MAP_START_DELAY, Timer_StartAutobalance);

    if (g_hMapImmunity != null)
    {
        g_hMapImmunity.Clear();
    }
    WhaleScramble_OnMapStart();
}

public void OnMapEnd()
{
    TeamBalance_ResetRuntime();
    ClearAllTeamSwapRequests();
    StopAutobalanceTimer();
    g_fImbalanceDetectedAt = 0.0;
    WhaleScramble_OnMapEnd();
}

public void OnClientDisconnect(int client)
{
    TeamBalance_ClearRespawnState(client);
    if (client > 0 && client <= MaxClients)
    {
        g_fBalanceMovedUntil[client] = 0.0;
    }
    ClearTeamSwapRequestsForClient(client);
    WhaleScramble_OnClientDisconnect(client);
}

public void OnPluginEnd()
{
    WhaleScramble_OnPluginEnd();
    ApplyServerBalanceCvars(false);
    DuelDetection_Shutdown();
    ClearAllTeamSwapRequests();

    StopAutobalanceTimer();

    Db_CancelTimer(g_hImmunityDbReconnectTimer);
    g_bImmunityDbReady = false;
    g_bVolunteerDbReady = false;

    if (g_hImmunityDb != null)
    {
        delete g_hImmunityDb;
        g_hImmunityDb = null;
    }

    if (g_hMapImmunity != null)
    {
        delete g_hMapImmunity;
        g_hMapImmunity = null;
    }

    if (g_hPersistentImmunity != null)
    {
        delete g_hPersistentImmunity;
        g_hPersistentImmunity = null;
    }

    if (g_hVolunteers != null)
    {
        delete g_hVolunteers;
        g_hVolunteers = null;
    }

    if (g_hScrambleImmunity != null)
    {
        delete g_hScrambleImmunity;
        g_hScrambleImmunity = null;
    }

}

// ---------------------------------------------------------------------------
// Voluntary team swaps
// ---------------------------------------------------------------------------

