void DGM_ApplySetupUberMultiplier()
{
    if (GetFeatureStatus(FeatureType_Native, "TF2SetupUber_SetMultiplier") != FeatureStatus_Available
        || GetFeatureStatus(FeatureType_Native, "TF2SetupUber_IsAvailable") != FeatureStatus_Available
        || !TF2SetupUber_IsAvailable())
    {
        if (!g_bSetupUberUnavailableLogged)
        {
            PrintToServer("[DGM] TF2 setup Über extension unavailable; setup Über multiplier remains stock.");
            g_bSetupUberUnavailableLogged = true;
        }
        return;
    }

    float multiplier = g_cvSetupUberMultiplier.FloatValue;
    TF2SetupUber_SetMultiplier(multiplier);
    g_bSetupUberUnavailableLogged = false;
    PrintToServer("[DGM] Setup ÜberCharge multiplier set to %.2f.", multiplier);
}

// Short DGM timers require TF2's native respawn waves to be disabled.
void DGM_RefreshRespawnVisualState()
{
    if (g_cvMpDisableRespawnTimes == null)
    {
        return;
    }

    SetConVarBool(g_cvMpDisableRespawnTimes, g_cvRespawnTime.FloatValue < 5.0);
}

bool DGM_AreRespawnTimesForcedOn()
{
    return FloatCompare(g_cvRespawnTime.FloatValue, DGM_RESPAWN_DISABLED_TIME) == 0;
}

void DGM_SetRespawnTimesEnabled(bool enabled)
{
    g_InternalOverride = enabled;

    float targetTime = DGM_RESPAWN_DISABLED_TIME;
    if (!enabled)
    {
        targetTime = DGM_CountRealPlayers() < DGM_RESPAWN_HIGH_POP_THRESHOLD
            ? DGM_RESPAWN_LOW_POP_RESTORE_TIME
            : DGM_RESPAWN_HIGH_POP_RESTORE_TIME;
    }

    if (FloatCompare(g_cvRespawnTime.FloatValue, targetTime) != 0)
    {
        g_cvRespawnTime.SetFloat(targetTime);
    }
    else
    {
        DGM_RefreshRespawnVisualState();
    }

    if (enabled)
    {
        DGM_ClearAllRespawnReminderTimers();
    }
}

bool DGM_InternalIsRoundRunning()
{
    if (!g_bGameRulesReady || FindEntityByClassname(-1, "tf_gamerules") == -1)
    {
        return false;
    }

    return GameRules_GetRoundState() == RoundState_RoundRunning
        && !DGM_IsRealSetupActive();
}

bool DGM_IsSetupTimeExtensionAvailable()
{
    return GetFeatureStatus(FeatureType_Native, "TF2_IsSetupTimeActive") == FeatureStatus_Available;
}

bool DGM_IsSetupGameRulesActive()
{
    if (g_bGameRulesReady
        && FindEntityByClassname(-1, "tf_gamerules") != -1
        && GameRules_GetProp("m_bInSetup", 1) != 0)
    {
        return true;
    }

    if (DGM_IsSetupTimeExtensionAvailable() && TF2_IsSetupTimeActive())
    {
        return true;
    }

    return false;
}

bool DGM_HasSetupRoundTimer()
{
    int timerEnt = -1;

    while ((timerEnt = FindEntityByClassname(timerEnt, "team_round_timer")) != -1)
    {
        if (!IsValidEntity(timerEnt))
        {
            continue;
        }

        if (HasEntProp(timerEnt, Prop_Send, "m_bIsDisabled")
            && GetEntProp(timerEnt, Prop_Send, "m_bIsDisabled") != 0)
        {
            continue;
        }

        if (HasEntProp(timerEnt, Prop_Send, "m_nState")
            && GetEntProp(timerEnt, Prop_Send, "m_nState") == DGM_RT_STATE_SETUP)
        {
            return true;
        }
    }

    return false;
}

bool DGM_IsRealSetupActive()
{
    return DGM_IsSetupGameRulesActive() || DGM_HasSetupRoundTimer();
}

bool DGM_HasWaitingForPlayersTimer()
{
    int timerEnt = -1;
    char timerName[64];

    while ((timerEnt = FindEntityByClassname(timerEnt, "team_round_timer")) != -1)
    {
        if (!IsValidEntity(timerEnt) || !HasEntProp(timerEnt, Prop_Data, "m_iName"))
        {
            continue;
        }

        GetEntPropString(timerEnt, Prop_Data, "m_iName", timerName, sizeof(timerName));
        if (StrEqual(timerName, "zz_teamplay_waiting_timer", false))
        {
            return true;
        }
    }

    return false;
}

bool DGM_IsSetupBhopActive()
{
    return DGM_IsRealSetupActive() || DGM_HasWaitingForPlayersTimer();
}

void DGM_OpenWaitingSetupDoorsForBhop()
{
    int doorEnt = -1;
    int opened = 0;

    while ((doorEnt = FindEntityByClassname(doorEnt, "func_door")) != -1)
    {
        if (!IsValidEntity(doorEnt))
        {
            continue;
        }

        AcceptEntityInput(doorEnt, "Open");
        opened++;
    }

    if (opened > 0)
    {
        PrintToServer("[DGM] Opened %d func_door entities while waiting/setup timer was active.", opened);
    }
}

bool DGM_IsNoEngineerSetupReductionGamemode()
{
    char gamemodeKey[32];
    if (DGM_CopyCurrentGameModeKey(gamemodeKey, sizeof(gamemodeKey))
        && (StrEqual(gamemodeKey, "pl", false)
            || StrEqual(gamemodeKey, "ad", false)))
    {
        return true;
    }

    return false;
}

bool DGM_RedHasEngineer()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!Client_IsInGame(client)
            || IsFakeClient(client)
            || GetClientTeam(client) != view_as<int>(TFTeam_Red)
            || TF2_GetPlayerClass(client) != TFClass_Engineer)
        {
            continue;
        }

        return true;
    }

    return false;
}

int DGM_FindSetupRoundTimer()
{
    int firstVisible = -1;
    int firstAny = -1;
    int timerEnt = -1;

    while ((timerEnt = FindEntityByClassname(timerEnt, "team_round_timer")) != -1)
    {
        if (!IsValidEntity(timerEnt))
        {
            continue;
        }

        if (firstAny == -1)
        {
            firstAny = timerEnt;
        }

        bool visible = !HasEntProp(timerEnt, Prop_Send, "m_bShowInHUD")
            || GetEntProp(timerEnt, Prop_Send, "m_bShowInHUD") != 0;

        if (visible && firstVisible == -1)
        {
            firstVisible = timerEnt;
        }

        if (HasEntProp(timerEnt, Prop_Send, "m_nState")
            && GetEntProp(timerEnt, Prop_Send, "m_nState") == DGM_RT_STATE_SETUP)
        {
            return timerEnt;
        }
    }

    return firstVisible != -1 ? firstVisible : firstAny;
}

void DGM_SetSetupTimerTime(int timerEnt, int time)
{
    SetVariantInt(time);
    AcceptEntityInput(timerEnt, "SetSetupTime");
}

int DGM_GetSetupTimerLength(int timerEnt)
{
    if (!IsValidEntity(timerEnt))
    {
        return -1;
    }

    if (HasEntProp(timerEnt, Prop_Send, "m_nSetupTimeLength"))
    {
        return GetEntProp(timerEnt, Prop_Send, "m_nSetupTimeLength");
    }

    if (HasEntProp(timerEnt, Prop_Data, "m_nSetupTimeLength"))
    {
        return GetEntProp(timerEnt, Prop_Data, "m_nSetupTimeLength");
    }

    return DGM_GetRoundTimerRemaining(timerEnt);
}

bool DGM_ShouldApplySetupTimerTime(int timerEnt, int proposedTime, int executor)
{
    if (executor > 0)
    {
        return true;
    }

    int currentSetupTime = DGM_GetSetupTimerLength(timerEnt);
    if (currentSetupTime >= 0 && currentSetupTime < proposedTime)
    {
        PrintToServer("[Kogasa] Setup time left unchanged: map setup time is %i seconds, below configured %i seconds.", currentSetupTime, proposedTime);
        return false;
    }

    return true;
}

void DGM_CheckNoEngineerSetupReduction()
{
    if (g_bNoEngineerSetupReduced
        || !DGM_IsRealSetupActive()
        || !DGM_IsNoEngineerSetupReductionGamemode()
        || !DGM_AreTeamsGameplayReady()
        || DGM_RedHasEngineer())
    {
        return;
    }

    int timerEnt = DGM_FindSetupRoundTimer();
    int reducedSetupTime = RoundToNearest(g_cvNoEngineerSetupReduction.FloatValue);
    if (reducedSetupTime <= 0)
    {
        return;
    }

    if (timerEnt == -1 || DGM_GetRoundTimerRemaining(timerEnt) <= reducedSetupTime)
    {
        return;
    }

    DGM_SetSetupTimerTime(timerEnt, reducedSetupTime);
    g_bNoEngineerSetupReduced = true;
    PrintToChatAll("No Engineers detected; setup time reduced");
    PrintToServer("[Kogasa] Setup time reduced to %d seconds: no RED Engineers detected.", reducedSetupTime);
}

public Action Timer_CheckNoEngineerSetupReduction(Handle timer)
{
    g_hNoEngineerSetupReductionTimer = INVALID_HANDLE;
    DGM_CheckNoEngineerSetupReduction();
    return Plugin_Stop;
}

void DGM_ClearNoEngineerSetupReductionTimer()
{
    if (g_hNoEngineerSetupReductionTimer == INVALID_HANDLE)
    {
        return;
    }

    KillTimer(g_hNoEngineerSetupReductionTimer);
    g_hNoEngineerSetupReductionTimer = INVALID_HANDLE;
}

void DGM_QueueNoEngineerSetupReductionCheck()
{
    if (g_bNoEngineerSetupReduced || !DGM_IsRealSetupActive())
    {
        DGM_ClearNoEngineerSetupReductionTimer();
        return;
    }

    DGM_ClearNoEngineerSetupReductionTimer();
    g_hNoEngineerSetupReductionTimer = CreateTimer(DGM_NO_ENGINEER_SETUP_CHECK_DELAY, Timer_CheckNoEngineerSetupReduction, _, TIMER_FLAG_NO_MAPCHANGE);
}

void DGM_ClearSetupStartTimer()
{
    g_hSetupStartTimer = INVALID_HANDLE;
}

void DGM_QueueSetupStartCheck()
{
    if (g_bSetupActive || g_hSetupStartTimer != INVALID_HANDLE)
    {
        return;
    }

    g_iSetupStartChecks = 0;
    g_hSetupStartTimer = CreateTimer(DGM_SETUP_START_CHECK_INTERVAL, Timer_CheckSetupStart, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_CheckSetupStart(Handle timer)
{
    g_iSetupStartChecks++;

    if (DGM_IsSetupBhopActive())
    {
        g_hSetupStartTimer = INVALID_HANDLE;
        DGM_SetSetupActive(true);
        return Plugin_Stop;
    }

    if (g_iSetupStartChecks >= DGM_SETUP_START_CHECK_MAX)
    {
        g_hSetupStartTimer = INVALID_HANDLE;
        return Plugin_Stop;
    }

    return Plugin_Continue;
}
