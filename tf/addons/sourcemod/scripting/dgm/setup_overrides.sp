void DGM_SetSetupActive(bool setupActive)
{
    if (setupActive)
    {
        g_iSetupFalseChecks = 0;
    }

    // Waiting-for-players shares DGM's setup handling, but this engine override
    // applies only during an actual setup round.
    bool realSetupActive = setupActive && DGM_IsRealSetupActive();
    g_bSetupConstructionMultiplierActive = realSetupActive;
    DGM_SetSetupUpgradeMetalActive(realSetupActive);

    if (g_bSetupActive == setupActive)
    {
        return;
    }

    g_bSetupActive = setupActive;

    if (setupActive)
    {
        g_bNoEngineerSetupReduced = false;
        DGM_ClearNoEngineerSetupReductionTimer();
        DGM_ClearSetupStartTimer();

        if (!g_bRespawnAdminTouchedThisMap && !DGM_ShouldDisableInstantRespawn())
        {
            DGM_SetRespawnTimesEnabled(false);
            DGM_RespawnDeadClients();
            DGM_ClearAllRespawnReminderTimers();
        }

        PrintToChatAll("Setup detected, bhop enabled");
        ServerCommand("exec d_setup.cfg");
        ServerExecute();

        if (DGM_HasWaitingForPlayersTimer())
        {
            DGM_OpenWaitingSetupDoorsForBhop();
        }

        if (g_hSetupStateTimer == INVALID_HANDLE)
        {
            g_hSetupStateTimer = CreateTimer(1.0, Timer_SetupStateMonitor, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        }

        DGM_CheckSetupTeamRatioForward();
        DGM_QueueNoEngineerSetupReductionCheck();
    }
    else
    {
        DGM_ClearNoEngineerSetupReductionTimer();
        ServerCommand("exec d_endsetup.cfg");
        ServerExecute();

        if (g_hSetupStateTimer != INVALID_HANDLE)
        {
            KillTimer(g_hSetupStateTimer);
            g_hSetupStateTimer = INVALID_HANDLE;
        }
    }
}

void DGM_InitializeConstructionMultiplierDetour()
{
    GameData gameData = new GameData("dgm");
    if (gameData == null)
    {
        SetFailState("Failed to load dgm gamedata.");
    }

    g_hConstructionMultiplierDetour = DynamicDetour.FromConf(
        gameData,
        "CBaseObject::GetConstructionMultiplier"
    );
    delete gameData;

    if (g_hConstructionMultiplierDetour == null)
    {
        SetFailState("Failed to create CBaseObject::GetConstructionMultiplier detour.");
    }
    if (!g_hConstructionMultiplierDetour.Enable(
        Hook_Pre,
        DGM_GetConstructionMultiplierPre
    ))
    {
        SetFailState("Failed to enable CBaseObject::GetConstructionMultiplier detour.");
    }
}

public MRESReturn DGM_GetConstructionMultiplierPre(
    int building,
    DHookReturn hReturn)
{
    if (!g_bSetupConstructionMultiplierActive
        || g_cvSetupConstructionMultiplier == null)
    {
        return MRES_Ignored;
    }

    float multiplier = g_cvSetupConstructionMultiplier.FloatValue;
    if (multiplier == 0.0 || multiplier == 1.0)
    {
        return MRES_Ignored;
    }

    hReturn.Value = multiplier;
    return MRES_Supercede;
}

void DGM_SetSetupUpgradeMetalActive(bool active)
{
    if (!active)
    {
        DGM_RestoreSetupUpgradeMetal();
        return;
    }

    if (g_cvTfObjUpgradePerHit == null || g_cvUpgradeMetalPerHit == null)
    {
        return;
    }

    if (!g_bSetupUpgradeMetalActive)
    {
        g_iOriginalUpgradePerHit = g_cvTfObjUpgradePerHit.IntValue;
        g_bSetupUpgradeMetalActive = true;
    }

    int baseMetal = g_cvUpgradeMetalPerHit.IntValue / 2;
    if (g_cvTfObjUpgradePerHit.IntValue != baseMetal)
    {
        g_cvTfObjUpgradePerHit.IntValue = baseMetal;
    }
}

void DGM_RestoreSetupUpgradeMetal()
{
    if (!g_bSetupUpgradeMetalActive)
    {
        return;
    }

    if (g_cvTfObjUpgradePerHit != null)
    {
        g_cvTfObjUpgradePerHit.IntValue = g_iOriginalUpgradePerHit;
    }

    g_bSetupUpgradeMetalActive = false;
    g_iOriginalUpgradePerHit = 0;
}

void DGM_UpdateSetupState()
{
    if (DGM_IsSetupBhopActive())
    {
        g_iSetupFalseChecks = 0;
        DGM_SetSetupActive(true);
        return;
    }

    if (g_bSetupActive)
    {
        g_iSetupFalseChecks++;

        if (g_iSetupFalseChecks >= DGM_SETUP_FALSE_CONFIRM_MAX)
        {
            DGM_SetSetupActive(false);
        }

        return;
    }

    DGM_QueueSetupStartCheck();
}

void DGM_CheckSetupTeamRatioForward()
{
    if (g_bSetupTeamRatioForwardFired || !DGM_IsRealSetupActive())
    {
        return;
    }

    int connectedClients = GetClientCount(false);
    if (connectedClients <= 0)
    {
        return;
    }

    int realTeamPlayers = DGM_CountRealPlayers();
    if ((realTeamPlayers * 100) < (connectedClients * DGM_SETUP_TEAM_RATIO_PERCENT))
    {
        return;
    }

    g_bSetupTeamRatioForwardFired = true;
    Call_StartForward(g_hSetupTeamRatioReadyForward);
    Call_PushCell(realTeamPlayers);
    Call_PushCell(connectedClients);
    Call_Finish();
}

public void DGM_FrameCheckSetupTeamRatio(any data)
{
    DGM_CheckSetupTeamRatioForward();
}

void SetSetupTime(int executor)
{
    int timerEnt = DGM_FindSetupRoundTimer();

    if (timerEnt != -1)
    {
        int time = GetConVarInt(g_cvSetSetupTime);
        if (!DGM_ShouldApplySetupTimerTime(timerEnt, time, executor))
        {
            return;
        }

        DGM_SetSetupTimerTime(timerEnt, time);
        PrintToServer("[Kogasa] Setup time set to %i seconds.", time);
    }
}

public void AdjustByPlayerCount(any data)
{
    if (g_cvPopulationConfigs != null && !g_cvPopulationConfigs.BoolValue)
    {
        return;
    }

    if (!g_bRoundStartedOnce)
    {
        return;
    }
    int playerCount = DGM_CountRealPlayers();
    int threshhold = GetConVarInt(g_cvThreshold);
    if (!g_bSymmetrical) {
        ServerCommand(playerCount > threshhold ? "exec d_highpop_a.cfg" : "exec d_lowpop_a.cfg");
    } else {
        ServerCommand(playerCount > threshhold ? "exec d_highpop.cfg" : "exec d_lowpop.cfg");
    }
}

public void DGM_AdjustRespawnByPlayerCount(any data)
{
    if (!g_cvPopulationRespawns.BoolValue
        || g_bRespawnAdminTouchedThisMap
        || DGM_ShouldDisableInstantRespawn())
    {
        return;
    }

    bool enableRespawnTimes = DGM_CountConnectedHumans() >= g_cvLowPopThreshold.IntValue;
    if (DGM_AreRespawnTimesForcedOn() == enableRespawnTimes)
    {
        return;
    }

    DGM_SetRespawnTimesEnabled(enableRespawnTimes);
    DGM_RespawnDeadClients();
    DGM_ClearAllRespawnReminderTimers();
}

