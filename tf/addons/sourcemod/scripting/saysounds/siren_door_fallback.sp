void ResetRoundStartSirenDoorFallback(bool roundStarted)
{
    if (g_hDoorSirenTimer != INVALID_HANDLE)
    {
        delete g_hDoorSirenTimer;
        g_hDoorSirenTimer = INVALID_HANDLE;
    }
    g_bSirenRoundStarted = roundStarted;
    g_bHudSetupSirenTimerSeenThisRound = false;
    g_bSirenScheduledThisRound = false;
    g_bDoorSirenTriggeredThisRound = false;
}

public void Event_SirenRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    ResetRoundStartSirenDoorFallback(true);
}

static bool SirenDoor_IsLiveRound()
{
    if (FindEntityByClassname(-1, "tf_gamerules") == -1
        || GameRules_GetRoundState() != RoundState_RoundRunning
        || GameRules_GetProp("m_bInWaitingForPlayers", 1) != 0
        || GameRules_GetProp("m_bInSetup", 1) != 0)
    {
        return false;
    }

    return GetFeatureStatus(FeatureType_Native, "DGM_IsSetupActive") != FeatureStatus_Available
        || !DGM_IsSetupActive();
}

public void Event_RoundStartDoorOpened(const char[] output, int caller, int activator, float delay)
{
    if (!g_bSirenRoundStarted || g_bDoorSirenTriggeredThisRound
        || g_bHudSetupSirenTimerSeenThisMap || g_bHudSetupSirenTimerSeenThisRound
        || g_bSirenScheduledThisRound
        || gReadyRoundStartSirenReplacements.Length == 0
        || activator < 1 || activator > MaxClients
        || !IsClientInGame(activator) || IsFakeClient(activator)
        || !SirenDoor_IsLiveRound())
    {
        return;
    }

    g_bDoorSirenTriggeredThisRound = true;
    g_hDoorSirenTimer = CreateTimer(ROUND_START_SIREN_DOOR_GRACE,
        Timer_RoundStartDoorSiren, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RoundStartDoorSiren(Handle timer)
{
    if (timer != g_hDoorSirenTimer) return Plugin_Stop;
    g_hDoorSirenTimer = INVALID_HANDLE;
    if (!g_bSirenRoundStarted || g_bHudSetupSirenTimerSeenThisMap
        || g_bHudSetupSirenTimerSeenThisRound
        || g_bSirenScheduledThisRound || gReadyRoundStartSirenReplacements.Length == 0
        || !SirenDoor_IsLiveRound())
    {
        return Plugin_Stop;
    }

    LogMessage("[SaySounds:Siren] First human door open in a round without a HUD setup siren timer; scheduling replacement.");
    ScheduleRoundStartSirenReplacement();
    return Plugin_Stop;
}
