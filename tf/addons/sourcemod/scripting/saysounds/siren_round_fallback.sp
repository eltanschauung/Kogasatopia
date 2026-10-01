void ResetRoundStartSirenRoundFallback()
{
    if (g_hRoundActiveSirenTimer != INVALID_HANDLE)
    {
        delete g_hRoundActiveSirenTimer;
        g_hRoundActiveSirenTimer = INVALID_HANDLE;
    }
    g_bRoundActiveSirenQueued = false;
}

public void Event_SirenNewRound(Event event, const char[] name, bool dontBroadcast)
{
    // Once per actual round, rather than once per map. The live-phase checks
    // below still avoid waiting-for-players/setup and duplicate sirens.
    ResetRoundStartSirenRoundFallback();
    CancelRoundStartSirenTimer();
    g_bPendingSirenFallback = false;
    g_bSirenFallbackPlayedThisRound = false;
    Event_SirenLivePhase(event, name, dontBroadcast);
}

public void Event_SirenLivePhase(Event event, const char[] name, bool dontBroadcast)
{
    if (StrEqual(name, "teamplay_round_active") && !g_bHudSetupSirenTimerSeenThisMap)
    {
        int rules = FindEntityByClassname(-1, "tf_gamerules");
        LogMessage("[SaySounds:SirenTrace] round_active: rules=%d waiting=%d setup=%d played_this_round=%d.",
            rules,
            rules == -1 ? -1 : GameRules_GetProp("m_bInWaitingForPlayers", 1),
            rules == -1 ? -1 : GameRules_GetProp("m_bInSetup", 1),
            g_bSirenFallbackPlayedThisRound);
    }

    if (g_bHudSetupSirenTimerSeenThisMap || g_bSirenFallbackPlayedThisRound
        || g_bRoundActiveSirenQueued || g_hRoundStartSirenTimer != INVALID_HANDLE
        || gReadyRoundStartSirenReplacements.Length == 0
        || FindEntityByClassname(-1, "tf_gamerules") == -1
        || GameRules_GetProp("m_bInWaitingForPlayers", 1) != 0)
    {
        return;
    }

    if (StrEqual(name, "teamplay_round_active")
        && GameRules_GetProp("m_bInSetup", 1) != 0)
    {
        return;
    }

    g_bRoundActiveSirenQueued = true;
    g_hRoundActiveSirenTimer = CreateTimer(ROUND_START_SIREN_ACTIVE_GRACE + 3.0,
        Timer_RoundActiveSiren, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RoundActiveSiren(Handle timer)
{
    if (timer != g_hRoundActiveSirenTimer) return Plugin_Stop;
    g_hRoundActiveSirenTimer = INVALID_HANDLE;
    g_bRoundActiveSirenQueued = false;
    if (g_bHudSetupSirenTimerSeenThisMap || g_bSirenFallbackPlayedThisRound
        || g_hRoundStartSirenTimer != INVALID_HANDLE
        || gReadyRoundStartSirenReplacements.Length == 0
        || FindEntityByClassname(-1, "tf_gamerules") == -1
        || GameRules_GetRoundState() != RoundState_RoundRunning
        || GameRules_GetProp("m_bInWaitingForPlayers", 1) != 0
        || GameRules_GetProp("m_bInSetup", 1) != 0)
    {
        return Plugin_Stop;
    }

    LogMessage("[SaySounds:Siren] Live round on a map without a HUD setup siren timer; scheduling replacement.");
    ScheduleRoundStartSirenReplacement();
    g_bPendingSirenFallback = g_hRoundStartSirenTimer != INVALID_HANDLE;
    return Plugin_Stop;
}
