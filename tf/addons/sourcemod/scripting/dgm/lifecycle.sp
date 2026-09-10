public void OnPluginStart()
{

    // The respawn time
    g_cvRespawnTime = CreateConVar("respawn_time", "3.0", "Respawn time length", _, true, 0.0, true, 30.0);
    g_cvPopulationRespawns = CreateConVar("dgm_population_respawns", "1", "Allow playercount changes to adjust respawn times.", _, true, 0.0, true, 1.0);
    g_cvLowPopThreshold = CreateConVar("dgm_lowpop_threshhold", "10", "Connected human count below which respawn times are disabled.", _, true, 0.0, true, 100.0);
    // See description
    g_cvThreshold = CreateConVar("sm_highpop_threshhold", "18.0", "Threshhold for executing the highpop config", _, true, 0.0, true, 100.0);
    g_cvPopulationConfigs = CreateConVar("sm_dgm_population_configs", "0", "Enable DGM lowpop/highpop config execution.", _, true, 0.0, true, 1.0);
    // For micromanagement, if this convar isn't 0, it'll use the given time
    g_cvTimeOverride = CreateConVar("respawn_otime", "0", "Override respawn time with this", _, true, 0.0, true, 30.0);
    // Respawn times for individual teams (beta)
    g_cvRedTime = CreateConVar("respawn_redtime", "3.0", "Red respawn time length", _, true, 0.0, true, 16.0);
    g_cvBluTime = CreateConVar("respawn_blutime", "3.0", "Blu respawn time length", _, true, 0.0, true, 16.0);
    // Auto add time to king of the hill timers?
    g_cvAutoAddTime = CreateConVar("sm_autoaddtime", "300", "Automatically extend koth times? > 0 for the time in seconds");
    g_cvSetupUberMultiplier = CreateConVar("sm_tf2_setup_uber_multiplier", "12.0", "Setup-time Medigun UberCharge multiplier. Stock TF2 is 3.0.", _, true, 0.0, true, 64.0);
    g_cvSetupConstructionMultiplier = CreateConVar(
        "dgm_setup_construction_multiplier",
        "5.0",
        "Construction multiplier during setup. 0.0 or 1.0 disables the override.",
        _,
        true,
        0.0,
        true,
        64.0
    );
    g_cvUpgradeMetalPerHit = CreateConVar(
        "dgm_upgrade_metal_per_hit",
        "200",
        "Desired metal applied per wrench upgrade hit during setup; odd values round down.",
        _,
        true,
        0.0,
        true,
        1000.0
    );
    g_cvTfObjUpgradePerHit = FindConVar("tf_obj_upgrade_per_hit");
    if (g_cvTfObjUpgradePerHit == null)
    {
        SetFailState("Failed to find tf_obj_upgrade_per_hit.");
    }
    HookConVarChange(g_cvUpgradeMetalPerHit, ConVarChange_UpgradeMetalPerHit);
    // Always respawn red team on control point capture in asymmetrical gamemodes?
    g_cvAsymCapRespawn = CreateConVar("respawn_red_on_cap", "0", "Override respawn times", _, true, 0.0, true, 1.0);
    // Change the setup time to this in asymmetrical gamemodes
    g_cvSetSetupTime = CreateConVar("sm_setuptime", "40", "Set setup time to X - 0 to disable management - only enable this per-map or in gamemode configs", _, true, 0.0, true,60.0);
    g_cvNoEngineerSetupReduction = CreateConVar("sm_noengi_setup_reduction", "30.0", "Setup time to apply when no RED Engineers are detected. 0 disables this reduction.", _, true, 0.0, true, 60.0);
    // Stores the executed gamemode
    g_cvGameMode = CreateConVar("sm_gamemode", "unknown", "Stores the executed gamemode", FCVAR_NONE);
    // Hook the value of mp_disable_respawn_times
    g_cvMpDisableRespawnTimes = FindConVar("mp_disable_respawn_times");
    HookConVarChange(g_cvRespawnTime, ConVarChange_RespawnSetting);
    HookConVarChange(g_cvTimeOverride, ConVarChange_RespawnSetting);
    HookConVarChange(g_cvRedTime, ConVarChange_RespawnSetting);
    HookConVarChange(g_cvBluTime, ConVarChange_RespawnSetting);
    HookConVarChange(g_cvSetupUberMultiplier, ConVarChange_SetupUberMultiplier);

    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("teamplay_round_start", Event_RoundActive);
    HookEvent("teamplay_round_active", Event_RoundFullyActive, EventHookMode_PostNoCopy);
    HookEvent("teamplay_setup_finished", Event_SetupFinished);
    HookEvent("teamplay_round_win", Event_RoundWin, EventHookMode_Pre);
    HookEvent("teamplay_point_captured", Event_PointCaptured, EventHookMode_Post);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
    HookEvent("player_changeclass", Event_PlayerChangeClass, EventHookMode_Post);

	RegAdminCmd("sm_respawn", Command_RespawnToggle, ADMFLAG_KICK, "Toggles respawn times");
	RegAdminCmd("sm_noset", Command_ResetSetup, ADMFLAG_KICK, "Set round setup time to 10 seconds");
	RegAdminCmd("sm_extend", Command_ExtendTimer, ADMFLAG_KICK, "sm_extend <seconds> - Set round timer time");
	RegAdminCmd("sm_settime", Command_ExtendTimer, ADMFLAG_KICK, "sm_settime [seconds] - Show or set round timer time");

    g_cHostname = FindConVar("hostname");
    RegConsoleCmd("sm_st", Command_Stats, "Show player count, map and hostname");
    RegConsoleCmd("sm_objectiveleader", Command_ObjectiveLeader, "Show which team leads by objective ownership");
    RegConsoleCmd("sm_cpleader", Command_ObjectiveLeader, "Show which team leads by control-point ownership");
    RegConsoleCmd("sm_manual", Command_CvarHelp, "Displays information about plugin ConVars.");

    DGM_InitializeConstructionMultiplierDetour();
    DGM_RefreshRespawnVisualState();
}

public void OnPluginEnd()
{
    DGM_RestoreSetupUpgradeMetal();
    g_bSetupConstructionMultiplierActive = false;

    if (g_hConstructionMultiplierDetour != null)
    {
        g_hConstructionMultiplierDetour.Disable(
            Hook_Pre,
            DGM_GetConstructionMultiplierPre
        );
        delete g_hConstructionMultiplierDetour;
    }
    DGM_ClearAllRespawnTimers();
    DGM_ClearAllRespawnReminderTimers();

    if (g_cvMpDisableRespawnTimes != null)
    {
        SetConVarBool(g_cvMpDisableRespawnTimes, true);
    }

    delete g_hSetupTeamRatioReadyForward;
}

public void OnMapStart()
{
    DGM_RestoreSetupUpgradeMetal();
    g_bGameRulesReady = false;
    // NO_MAPCHANGE timers are closed by SourceMod during transitions; clear local handles.
    g_hNoEngineerSetupReductionTimer = INVALID_HANDLE;
    DGM_ClearSetupStartTimer();
    g_hSetupStateTimer = INVALID_HANDLE;
    DGM_ResetRespawnTimerHandles();
    DGM_ResetRespawnReminderTimerHandles();
    DGM_ResetCaptureIntervalStats(0);

    g_bSetupActive = false;
    g_bSetupConstructionMultiplierActive = false;
    g_bNoEngineerSetupReduced = false;
    g_bRespawnAdminTouchedThisMap = false;
    g_bSetupTeamRatioForwardFired = false;
    g_iSetupFalseChecks = 0;
    DGM_RefreshRespawnVisualState();
    DGM_UpdateSetupState();
}

public void OnMapEnd()
{
    DGM_RestoreSetupUpgradeMetal();
    g_bGameRulesReady = false;
    g_bSetupConstructionMultiplierActive = false;
    // NO_MAPCHANGE timers are closed by SourceMod during transitions; clear local handles.
    g_hNoEngineerSetupReductionTimer = INVALID_HANDLE;
    DGM_ClearSetupStartTimer();
    g_hSetupStateTimer = INVALID_HANDLE;
    DGM_ClearAllRespawnTimers();
    DGM_ResetRespawnReminderTimerHandles();
}

public void ConVarChange_RespawnSetting(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (convar == g_cvRespawnTime && !StrEqual(oldValue, newValue))
    {
        g_InternalOverride = DGM_AreRespawnTimesForcedOn();
        DGM_RefreshRespawnVisualState();
        DGM_RespawnDeadClients();
    }
}

public void ConVarChange_UpgradeMetalPerHit(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (g_bSetupConstructionMultiplierActive)
    {
        DGM_SetSetupUpgradeMetalActive(true);
    }
}

public void ConVarChange_SetupUberMultiplier(ConVar convar, const char[] oldValue, const char[] newValue)
{
    DGM_ApplySetupUberMultiplier();
}

public Action Timer_SetupStateMonitor(Handle timer)
{
    DGM_CheckSetupTeamRatioForward();

    if (DGM_IsSetupBhopActive())
    {
        g_iSetupFalseChecks = 0;
        return Plugin_Continue;
    }

    g_iSetupFalseChecks++;

    if (g_iSetupFalseChecks >= DGM_SETUP_FALSE_CONFIRM_MAX)
    {
        g_hSetupStateTimer = INVALID_HANDLE;
        DGM_SetSetupActive(false);
        return Plugin_Stop;
    }

    return Plugin_Continue;
}

// We can be sure entities are loaded by this point
public void OnConfigsExecuted()
{
    g_bGameRulesReady = true;
    DetectGameMode();
    g_InternalOverride = DGM_AreRespawnTimesForcedOn();
    g_bRoundStartedOnce = false;
    g_iRoundStartTimestamp = 0;
    g_iLastRoundDuration = 0;
    DGM_ResetCaptureIntervalStats(0);
    DGM_ApplySetupUberMultiplier();
    RequestFrame(DGM_FrameUpdateSetupState);
    DGM_QueueSetupStartCheck();
}

public void DGM_FrameUpdateSetupState(any data)
{
    DGM_UpdateSetupState();
}

// Fires when a control point is captured
public void Event_PointCaptured(Event event, const char[] name, bool dontBroadcast)
{
    DGM_RecordCaptureInterval(event);

    if (DGM_ShouldDisableInstantRespawn())
    {
        return;
    }

    //This stuff is mostly WIP for dynamic changes on maps in the future
	// For now, all of these  features are from asymmetrical gamemode types
	if (!g_bSymmetrical)
	{
		g_PointCaptures++;
		if (g_PointCaptures >= 3)
		{
            DGM_SetRespawnTimesEnabled(true);
		}
		// Asymmetrical: respawn all dead RED players
		if (GetConVarBool(g_cvAsymCapRespawn) && !g_bSymmetrical)
		{
			for (int i = 1; i <= MaxClients; i++)
				if (IsClientInGame(i) && GetClientTeam(i) == 2 && !IsPlayerAlive(i))
                {
                    DGM_ClearRespawnTimer(i);
					TF2_RespawnPlayer(i);
                }
		}
		return;
	}
}

public void OnClientPutInServer(int client)
{
    if (!IsFakeClient(client))
    {
        RequestFrame(DGM_AdjustRespawnByPlayerCount);
        RequestFrame(DGM_FrameCheckSetupTeamRatio);
    }

    if (g_bRoundStartedOnce)
    {
        RequestFrame(AdjustByPlayerCount);
    }
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    DGM_ClearRespawnTimer(GetClientOfUserId(event.GetInt("userid")));
    DGM_QueueNoEngineerSetupReductionCheck();
    RequestFrame(DGM_FrameCheckSetupTeamRatio);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    DGM_ClearRespawnTimer(GetClientOfUserId(event.GetInt("userid")));
}

public void Event_PlayerChangeClass(Event event, const char[] name, bool dontBroadcast)
{
    DGM_QueueNoEngineerSetupReductionCheck();
}

public void OnClientDisconnect(int client)
{
    DGM_ClearRespawnTimer(client);
    DGM_ClearRespawnReminderTimer(client);

    if (!IsFakeClient(client))
    {
        RequestFrame(DGM_AdjustRespawnByPlayerCount);
        RequestFrame(DGM_FrameCheckSetupTeamRatio);
    }

    if (g_bRoundStartedOnce)
    {
        RequestFrame(AdjustByPlayerCount);
    }
}

// This command lets me see everything this plugin is doing at a given moment among other things
