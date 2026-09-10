static const char gStockCountdownSounds[][] =
{
    "vo/announcer_begins_5sec.mp3",
    "vo/announcer_begins_4sec.mp3",
    "vo/announcer_begins_3sec.mp3",
    "vo/announcer_begins_2sec.mp3",
    "vo/announcer_begins_1sec.mp3"
};

static const char gStockFinalCountdownSounds[][] =
{
    "vo/announcer_ends_5sec.mp3",
    "vo/announcer_ends_4sec.mp3",
    "vo/announcer_ends_3sec.mp3",
    "vo/announcer_ends_2sec.mp3",
    "vo/announcer_ends_1sec.mp3"
};

static const char gStockControlPointEnabledSounds[][] =
{
    "vo/announcer_am_capenabled01.mp3",
    "vo/announcer_am_capenabled02.mp3",
    "vo/announcer_am_capenabled03.mp3",
    "vo/announcer_am_capenabled04.mp3"
};

static const int gCountdownSeconds[] = { 5, 4, 3, 2, 1 };

int GetStockCountdownSoundIndex(const char[] sample)
{
    char normalized[PLATFORM_MAX_PATH];
    strcopy(normalized, sizeof(normalized), sample);
    TrimString(normalized);
    while (normalized[0] != '\0' && !IsAsciiAlphaNumeric(normalized[0]))
    {
        Strings_ShiftLeft(normalized, sizeof(normalized), 1);
    }
    NormalizeSoundPath(normalized, sizeof(normalized));
    Strings_ToLower(normalized, sizeof(normalized));

    for (int i = 0; i < sizeof(gStockCountdownSounds); i++)
    {
        if (StrEqual(normalized, gStockCountdownSounds[i]))
        {
            return i;
        }
    }

    for (int i = 0; i < sizeof(gStockFinalCountdownSounds); i++)
    {
        if (StrEqual(normalized, gStockFinalCountdownSounds[i]))
        {
            return i;
        }
    }

    return -1;
}

public Action Timer_MonitorCountdowns(Handle timer)
{
    if (timer != g_hCountdownMonitorTimer)
    {
        return Plugin_Stop;
    }

    MonitorRoundStartSirenTransition();
    MonitorSetupCountdown();
    MonitorLiveRoundCountdown();
    MonitorControlPointUnlockCountdowns();
    return Plugin_Continue;
}

static void MonitorControlPointUnlockCountdowns()
{
    if (gReadyCountdownReplacements.Length == 0
        || gReadyUnlockReplacements.Length == 0)
    {
        RestoreSuppressedControlPointCountdowns();
        ClearControlPointUnlockCountdowns();
        return;
    }

    int objectiveResource = FindEntityByClassname(-1, "tf_objective_resource");
    if (objectiveResource == -1
        || !HasEntProp(objectiveResource, Prop_Send, "m_flUnlockTimes"))
    {
        ClearControlPointUnlockCountdowns();
        return;
    }

    int controlPointCount = GetEntPropArraySize(
        objectiveResource,
        Prop_Send,
        "m_flUnlockTimes"
    );
    if (HasEntProp(objectiveResource, Prop_Send, "m_iNumControlPoints"))
    {
        int reportedCount = GetEntProp(
            objectiveResource,
            Prop_Send,
            "m_iNumControlPoints"
        );
        if (reportedCount < controlPointCount)
        {
            controlPointCount = reportedCount;
        }
    }

    if (controlPointCount > MAX_TRACKED_CONTROL_POINTS)
    {
        controlPointCount = MAX_TRACKED_CONTROL_POINTS;
    }
    if (controlPointCount < 0)
    {
        controlPointCount = 0;
    }

    float now = GetGameTime();
    for (int controlPoint = 0; controlPoint < MAX_TRACKED_CONTROL_POINTS; controlPoint++)
    {
        if (controlPoint >= controlPointCount)
        {
            g_fTrackedControlPointUnlockTime[controlPoint] = 0.0;
            g_bControlPointCountdownSuppressed[controlPoint] = false;
            g_iControlPointUnlockArmedMask[controlPoint] = 0;
            g_bControlPointEnabledReplacementHandled[controlPoint] = false;
            continue;
        }

        float networkUnlockTime = GetEntPropFloat(
            objectiveResource,
            Prop_Send,
            "m_flUnlockTimes",
            controlPoint
        );
        float trackedUnlockTime = g_fTrackedControlPointUnlockTime[controlPoint];

        if (networkUnlockTime > 0.0)
        {
            if (trackedUnlockTime <= 0.0
                || FloatAbs(networkUnlockTime - trackedUnlockTime) > 0.01)
            {
                trackedUnlockTime = networkUnlockTime;
                g_fTrackedControlPointUnlockTime[controlPoint] = trackedUnlockTime;
                g_bControlPointCountdownSuppressed[controlPoint] = false;
                g_iControlPointUnlockArmedMask[controlPoint] = 0;
                g_bControlPointEnabledReplacementHandled[controlPoint] = false;

                float initialRemaining = trackedUnlockTime - now;
                if (initialRemaining > 0.0)
                {
                    ArmCountdownWarnings(
                        initialRemaining,
                        g_iControlPointUnlockArmedMask[controlPoint]
                    );
                    g_iControlPointUnlockArmedMask[controlPoint]
                        |= CONTROL_POINT_ENABLED_WARNING_BIT;
                }
            }
            else if (g_bControlPointCountdownSuppressed[controlPoint])
            {
                // The HUD deadline was republished. Suppress it again below.
                g_bControlPointCountdownSuppressed[controlPoint] = false;
            }
        }
        else if (trackedUnlockTime <= 0.0
            || !g_bControlPointCountdownSuppressed[controlPoint])
        {
            g_fTrackedControlPointUnlockTime[controlPoint] = 0.0;
            g_bControlPointCountdownSuppressed[controlPoint] = false;
            g_iControlPointUnlockArmedMask[controlPoint] = 0;
            g_bControlPointEnabledReplacementHandled[controlPoint] = false;
            continue;
        }

        float remaining = trackedUnlockTime - now;

        if (remaining <= 0.0)
        {
            g_iControlPointUnlockArmedMask[controlPoint] = 0;
            continue;
        }

        if (!g_bControlPointCountdownSuppressed[controlPoint]
            && remaining <= CONTROL_POINT_COUNTDOWN_SUPPRESS_AT)
        {
            SetEntPropFloat(
                objectiveResource,
                Prop_Send,
                "m_flUnlockTimes",
                0.0,
                controlPoint
            );
            g_bControlPointCountdownSuppressed[controlPoint] = true;

            char currentMap[PLATFORM_MAX_PATH];
            GetCurrentMap(currentMap, sizeof(currentMap));
            LogMessage(
                "[SaySounds:CPUnlock] map %s, point %d, suppressed client HUD countdown at %.2f seconds.",
                currentMap,
                controlPoint,
                remaining
            );
        }

        bool numericWarningQueued = false;
        for (int warningIndex = 0;
            warningIndex < sizeof(gCountdownSeconds);
            warningIndex++)
        {
            int warningBit = 1 << warningIndex;
            float fireAt = float(gCountdownSeconds[warningIndex] + 1);
            if ((g_iControlPointUnlockArmedMask[controlPoint] & warningBit) == 0
                || remaining > fireAt)
            {
                continue;
            }

            g_iControlPointUnlockArmedMask[controlPoint] &= ~warningBit;
            ReplaceControlPointUnlockWarning(controlPoint, warningIndex);
            numericWarningQueued = true;
            break;
        }

        if (!numericWarningQueued
            && (g_iControlPointUnlockArmedMask[controlPoint]
                & CONTROL_POINT_ENABLED_WARNING_BIT) != 0
            && remaining <= 1.0)
        {
            g_iControlPointUnlockArmedMask[controlPoint]
                &= ~CONTROL_POINT_ENABLED_WARNING_BIT;
            g_bControlPointEnabledReplacementHandled[controlPoint] = true;
            ReplaceControlPointEnabled(controlPoint, false);
        }
    }
}

static void MonitorSetupCountdown()
{
    if (gReadyCountdownReplacements.Length == 0
        && !g_bTrackedSetupAutoCountdownSuppressed)
    {
        ResetSetupCountdownTracking();
        return;
    }

    int timerEntity = FindActiveSetupCountdownTimer();
    if (timerEntity == -1)
    {
        ResetSetupCountdownTracking();
        return;
    }

    float remaining = GetRoundTimerRemaining(timerEntity);
    if (remaining < 0.0)
    {
        ResetSetupCountdownTracking();
        return;
    }

    int timerRef = EntIndexToEntRef(timerEntity);
    if (timerRef != g_iTrackedSetupCountdownTimerRef)
    {
        g_iTrackedSetupCountdownTimerRef = timerRef;
        g_iSetupCountdownArmedMask = 0;
        ArmCountdownWarnings(remaining, g_iSetupCountdownArmedMask);
    }
    else if (g_fLastSetupCountdownRemaining >= 0.0
        && remaining > g_fLastSetupCountdownRemaining + 0.2)
    {
        // Mirror CTeamRoundTimer::CalculateOutputMessages() after time is added.
        ArmCountdownWarnings(remaining, g_iSetupCountdownArmedMask);
    }

    g_fLastSetupCountdownRemaining = remaining;

    if (GetCountdownTimerBool(timerEntity, "m_bIsDisabled")
        || GetCountdownTimerBool(timerEntity, "m_bTimerPaused")
        || (GetCountdownTimerBool(timerEntity, "m_bStopWatchTimer")
            && GetCountdownTimerBool(timerEntity, "m_bInCaptureWatchState")))
    {
        return;
    }

    bool shouldEmit = IsSetupAutoCountdownEnabled(timerEntity)
        && !IsWaitingForPlayers();

    for (int i = 0; i < sizeof(gCountdownSeconds); i++)
    {
        int warningBit = 1 << i;
        if ((g_iSetupCountdownArmedMask & warningBit) == 0
            || remaining > float(gCountdownSeconds[i] + 1))
        {
            continue;
        }

        // ClientThink clears only one warning per frame because its checks are else-if.
        g_iSetupCountdownArmedMask &= ~warningBit;
        if (shouldEmit)
        {
            ReplaceCountdownWarning(i, false);
        }
        break;
    }
}

static void MonitorLiveRoundCountdown()
{
    if (gReadyCountdownReplacements.Length == 0)
    {
        ResetLiveCountdownTracking();
        return;
    }

    int timerEntity = FindActiveLiveCountdownTimer();
    if (timerEntity == -1)
    {
        ResetLiveCountdownTracking();
        return;
    }

    float remaining = GetRoundTimerRemaining(timerEntity);
    if (remaining < 0.0)
    {
        ResetLiveCountdownTracking();
        return;
    }

    int timerRef = EntIndexToEntRef(timerEntity);
    if (timerRef != g_iTrackedLiveCountdownTimerRef)
    {
        ResetLiveCountdownTracking();
        g_iTrackedLiveCountdownTimerRef = timerRef;
        ArmCountdownWarnings(remaining, g_iLiveCountdownArmedMask);
    }
    else if (g_fLastLiveCountdownRemaining >= 0.0
        && remaining > g_fLastLiveCountdownRemaining + 0.2)
    {
        ArmCountdownWarnings(remaining, g_iLiveCountdownArmedMask);
    }

    g_fLastLiveCountdownRemaining = remaining;

    if (GetCountdownTimerBool(timerEntity, "m_bIsDisabled")
        || IsWaitingForPlayers()
        || (GetCountdownTimerBool(timerEntity, "m_bStopWatchTimer")
            && GetCountdownTimerBool(timerEntity, "m_bInCaptureWatchState")))
    {
        RestoreTrackedLiveAutoCountdown();
        return;
    }

    if (remaining > LIVE_COUNTDOWN_SUPPRESS_AT)
    {
        RestoreTrackedLiveAutoCountdown();
        return;
    }

    bool shouldEmit = IsLiveAutoCountdownEnabled(timerEntity);
    if (shouldEmit)
    {
        SuppressTrackedLiveAutoCountdown();
    }

    if (GetCountdownTimerBool(timerEntity, "m_bTimerPaused"))
    {
        return;
    }

    for (int i = 0; i < sizeof(gCountdownSeconds); i++)
    {
        int warningBit = 1 << i;
        if ((g_iLiveCountdownArmedMask & warningBit) == 0
            || remaining > float(gCountdownSeconds[i] + 1))
        {
            continue;
        }

        g_iLiveCountdownArmedMask &= ~warningBit;
        if (shouldEmit)
        {
            ReplaceCountdownWarning(i, true);
        }
        break;
    }
}

static void MonitorRoundStartSirenTransition()
{
    if (gReadyRoundStartSirenReplacements.Length == 0)
    {
        ResetRoundStartSirenTracking();
        return;
    }

    int setupTimer = FindActiveSetupCountdownTimer();
    int timerEntity = EntRefToEntIndex(g_iTrackedSetupSirenTimerRef);
    if (setupTimer != -1 && setupTimer != timerEntity)
    {
        ResetRoundStartSirenTracking();
        TrackSetupSirenTimer(setupTimer);
        return;
    }

    if (IsRoundTimerEntity(timerEntity))
    {
        int state = GetEntProp(timerEntity, Prop_Send, "m_nState");
        if (state == ROUND_TIMER_STATE_SETUP)
        {
            if (g_iTrackedSetupSirenState != ROUND_TIMER_STATE_SETUP)
            {
                TrackSetupSirenTimer(timerEntity);
            }
            else
            {
                SuppressTrackedSetupAutoCountdown();
            }
            return;
        }

        if (state == ROUND_TIMER_STATE_NORMAL)
        {
            if (g_iTrackedSetupSirenState == ROUND_TIMER_STATE_SETUP)
            {
                g_iTrackedSetupSirenState = ROUND_TIMER_STATE_NORMAL;
                ScheduleRoundStartSirenReplacement();
            }
            return;
        }

    }

    ResetRoundStartSirenTracking();
    if (setupTimer != -1)
    {
        TrackSetupSirenTimer(setupTimer);
    }
}

static void TrackSetupSirenTimer(int timerEntity)
{
    if (!IsRoundTimerEntity(timerEntity))
    {
        return;
    }

    int timerRef = EntIndexToEntRef(timerEntity);
    if (timerRef != g_iTrackedSetupSirenTimerRef)
    {
        RestoreTrackedSetupAutoCountdown();
        g_iTrackedSetupSirenTimerRef = timerRef;
    }

    g_iTrackedSetupSirenState = GetEntProp(timerEntity, Prop_Send, "m_nState");
    g_bTrackedSetupAutoCountdownOriginal =
        GetCountdownTimerBool(timerEntity, "m_bAutoCountdown");
    SuppressTrackedSetupAutoCountdown();
}

static void SuppressTrackedSetupAutoCountdown()
{
    int timerEntity = EntRefToEntIndex(g_iTrackedSetupSirenTimerRef);
    if (!IsRoundTimerEntity(timerEntity)
        || !HasEntProp(timerEntity, Prop_Send, "m_bAutoCountdown"))
    {
        return;
    }

    if (!g_bTrackedSetupAutoCountdownSuppressed)
    {
        g_bTrackedSetupAutoCountdownOriginal =
            GetCountdownTimerBool(timerEntity, "m_bAutoCountdown");
        g_bTrackedSetupAutoCountdownSuppressed = true;
        LogMessage(
            "[SaySounds:Siren] Suppressed automatic countdown on HUD timer entref %d (original %d).",
            g_iTrackedSetupSirenTimerRef,
            g_bTrackedSetupAutoCountdownOriginal
        );
    }

    if (GetCountdownTimerBool(timerEntity, "m_bAutoCountdown"))
    {
        SetEntProp(timerEntity, Prop_Send, "m_bAutoCountdown", 0);
    }
}

void RestoreTrackedSetupAutoCountdown()
{
    if (!g_bTrackedSetupAutoCountdownSuppressed)
    {
        return;
    }

    int timerEntity = EntRefToEntIndex(g_iTrackedSetupSirenTimerRef);
    if (IsRoundTimerEntity(timerEntity)
        && HasEntProp(timerEntity, Prop_Send, "m_bAutoCountdown"))
    {
        SetEntProp(
            timerEntity,
            Prop_Send,
            "m_bAutoCountdown",
            g_bTrackedSetupAutoCountdownOriginal ? 1 : 0
        );
    }

    g_bTrackedSetupAutoCountdownSuppressed = false;
}

static bool IsSetupAutoCountdownEnabled(int timerEntity)
{
    if (EntIndexToEntRef(timerEntity) == g_iTrackedSetupSirenTimerRef
        && g_bTrackedSetupAutoCountdownSuppressed)
    {
        return g_bTrackedSetupAutoCountdownOriginal;
    }

    return GetCountdownTimerBool(timerEntity, "m_bAutoCountdown");
}

static void SuppressTrackedLiveAutoCountdown()
{
    int timerEntity = EntRefToEntIndex(g_iTrackedLiveCountdownTimerRef);
    if (!IsRoundTimerEntity(timerEntity)
        || !HasEntProp(timerEntity, Prop_Send, "m_bAutoCountdown"))
    {
        return;
    }

    if (!g_bTrackedLiveAutoCountdownSuppressed)
    {
        g_bTrackedLiveAutoCountdownOriginal =
            GetCountdownTimerBool(timerEntity, "m_bAutoCountdown");
        g_bTrackedLiveAutoCountdownSuppressed = true;
        LogMessage(
            "[SaySounds:Countdown] Suppressed final automatic countdown on HUD timer entref %d (original %d).",
            g_iTrackedLiveCountdownTimerRef,
            g_bTrackedLiveAutoCountdownOriginal
        );
    }

    if (GetCountdownTimerBool(timerEntity, "m_bAutoCountdown"))
    {
        SetEntProp(timerEntity, Prop_Send, "m_bAutoCountdown", 0);
    }
}

void RestoreTrackedLiveAutoCountdown()
{
    if (!g_bTrackedLiveAutoCountdownSuppressed)
    {
        return;
    }

    int timerEntity = EntRefToEntIndex(g_iTrackedLiveCountdownTimerRef);
    if (IsRoundTimerEntity(timerEntity)
        && HasEntProp(timerEntity, Prop_Send, "m_bAutoCountdown"))
    {
        SetEntProp(
            timerEntity,
            Prop_Send,
            "m_bAutoCountdown",
            g_bTrackedLiveAutoCountdownOriginal ? 1 : 0
        );
    }

    g_bTrackedLiveAutoCountdownSuppressed = false;
}

static bool IsLiveAutoCountdownEnabled(int timerEntity)
{
    if (EntIndexToEntRef(timerEntity) == g_iTrackedLiveCountdownTimerRef
        && g_bTrackedLiveAutoCountdownSuppressed)
    {
        return g_bTrackedLiveAutoCountdownOriginal;
    }

    return GetCountdownTimerBool(timerEntity, "m_bAutoCountdown");
}

static bool IsRoundTimerEntity(int entity)
{
    if (entity <= MaxClients
        || !IsValidEntity(entity)
        || !HasEntProp(entity, Prop_Send, "m_nState"))
    {
        return false;
    }

    char classname[32];
    GetEntityClassname(entity, classname, sizeof(classname));
    return StrEqual(classname, "team_round_timer");
}

void ResetRoundStartSirenTracking()
{
    RestoreTrackedSetupAutoCountdown();
    g_iTrackedSetupSirenTimerRef = INVALID_ENT_REFERENCE;
    g_iTrackedSetupSirenState = -1;
    g_bTrackedSetupAutoCountdownOriginal = false;
}

static void ReplaceControlPointUnlockWarning(int controlPoint, int warningIndex)
{
    char replacement[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    if (!GetRandomReadyReplacement(
        gReadyCountdownReplacements,
        gReadyCountdownGroups,
        replacement,
        sizeof(replacement),
        groupName,
        sizeof(groupName)))
    {
        return;
    }

    int replacementRecipientCount = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
        {
            continue;
        }

        float emitVolume;
        if (!CanPlaySaySoundToClient(client, groupName, emitVolume))
        {
            continue;
        }

        EmitSoundToClient(
            client,
            replacement,
            client,
            SNDCHAN_VOICE_BASE,
            SNDLEVEL_NONE,
            SND_NOFLAGS,
            emitVolume
        );
        replacementRecipientCount++;
    }

    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));
    LogMessage(
        "[SaySounds:CPUnlock] map %s, point %d, warning %d, replacement %s, custom %d.",
        currentMap,
        controlPoint,
        gCountdownSeconds[warningIndex],
        replacement,
        replacementRecipientCount
    );
}

void ReplaceControlPointEnabled(int controlPoint, bool stopStock)
{
    if (controlPoint < 0 || controlPoint >= MAX_TRACKED_CONTROL_POINTS)
    {
        return;
    }

    char replacement[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    int replacementCount = gReadyUnlockReplacements.Length;
    if (replacementCount == 0)
    {
        return;
    }

    if (g_iNextUnlockReplacementIndex < 0)
    {
        g_iNextUnlockReplacementIndex = GetRandomInt(0, replacementCount - 1);
    }
    else if (g_iNextUnlockReplacementIndex >= replacementCount)
    {
        g_iNextUnlockReplacementIndex %= replacementCount;
    }

    int replacementIndex = g_iNextUnlockReplacementIndex;
    gReadyUnlockReplacements.GetString(
        replacementIndex,
        replacement,
        sizeof(replacement)
    );
    gReadyUnlockGroups.GetString(
        replacementIndex,
        groupName,
        sizeof(groupName)
    );
    g_iNextUnlockReplacementIndex = (replacementIndex + 1) % replacementCount;

    int replacementRecipientCount = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
        {
            continue;
        }

        float emitVolume;
        if (!CanPlaySaySoundToClient(client, groupName, emitVolume))
        {
            continue;
        }

        if (stopStock)
        {
            for (int i = 0; i < sizeof(gStockControlPointEnabledSounds); i++)
            {
                StopSound(
                    client,
                    SNDCHAN_VOICE_BASE,
                    gStockControlPointEnabledSounds[i]
                );
            }
        }
        EmitSoundToClient(
            client,
            replacement,
            client,
            SNDCHAN_VOICE_BASE,
            SNDLEVEL_NONE,
            SND_NOFLAGS,
            emitVolume
        );
        replacementRecipientCount++;
    }

    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));
    LogMessage(
        "[SaySounds:CPUnlock] map %s, point %d, unlocked, replacement index %d/%d, replacement %s, custom %d.",
        currentMap,
        controlPoint,
        replacementIndex,
        replacementCount,
        replacement,
        replacementRecipientCount
    );
}

static void ReplaceCountdownWarning(int warningIndex, bool finalCountdown)
{
    if (warningIndex < 0 || warningIndex >= sizeof(gStockCountdownSounds))
    {
        return;
    }

    char replacement[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    bool hasReplacement = GetRandomReadyReplacement(
        gReadyCountdownReplacements,
        gReadyCountdownGroups,
        replacement,
        sizeof(replacement),
        groupName,
        sizeof(groupName));
    char stockSound[PLATFORM_MAX_PATH];
    if (finalCountdown)
    {
        strcopy(
            stockSound,
            sizeof(stockSound),
            gStockFinalCountdownSounds[warningIndex]
        );
    }
    else
    {
        strcopy(stockSound, sizeof(stockSound), gStockCountdownSounds[warningIndex]);
    }

    int replacementRecipientCount = 0;
    int stockRecipientCount = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
        {
            continue;
        }

        float emitVolume;
        if (!hasReplacement
            || !CanPlaySaySoundToClient(client, groupName, emitVolume))
        {
            EmitSoundToClient(
                client,
                stockSound,
                client,
                SNDCHAN_VOICE_BASE,
                SNDLEVEL_NONE
            );
            stockRecipientCount++;
            continue;
        }

        EmitSoundToClient(
            client,
            replacement,
            client,
            SNDCHAN_VOICE_BASE,
            SNDLEVEL_NONE,
            SND_NOFLAGS,
            emitVolume
        );
        replacementRecipientCount++;
    }

    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));
    LogMessage(
        "[SaySounds:Countdown] map %s, phase %s, warning %d, replacement %s, custom %d, stock %d.",
        currentMap,
        finalCountdown ? "live" : "setup",
        gCountdownSeconds[warningIndex],
        hasReplacement ? replacement : stockSound,
        replacementRecipientCount,
        stockRecipientCount
    );
}

static int FindActiveHudRoundTimer()
{
    int objectiveResource = -1;
    while ((objectiveResource = FindEntityByClassname(objectiveResource, "tf_objective_resource")) != -1)
    {
        if (!HasEntProp(objectiveResource, Prop_Send, "m_iTimerToShowInHUD"))
        {
            continue;
        }

        int timerEntity = GetEntProp(objectiveResource, Prop_Send, "m_iTimerToShowInHUD");
        if (IsRoundTimerEntity(timerEntity))
        {
            return timerEntity;
        }
    }

    return -1;
}

static int FindActiveSetupCountdownTimer()
{
    int hudTimer = FindActiveHudRoundTimer();
    if (hudTimer != -1)
    {
        return IsSetupCountdownTimer(hudTimer) ? hudTimer : -1;
    }

    int timerEntity = -1;
    while ((timerEntity = FindEntityByClassname(timerEntity, "team_round_timer")) != -1)
    {
        if (!IsSetupCountdownTimer(timerEntity)
            || GetCountdownTimerBool(timerEntity, "m_bIsDisabled"))
        {
            continue;
        }

        if (!HasEntProp(timerEntity, Prop_Send, "m_bShowInHUD")
            || GetCountdownTimerBool(timerEntity, "m_bShowInHUD"))
        {
            return timerEntity;
        }
    }

    return -1;
}

static int FindActiveLiveCountdownTimer()
{
    int timerEntity = FindActiveHudRoundTimer();
    if (!IsRoundTimerEntity(timerEntity)
        || GetEntProp(timerEntity, Prop_Send, "m_nState") != ROUND_TIMER_STATE_NORMAL
        || GetCountdownTimerBool(timerEntity, "m_bIsDisabled"))
    {
        return -1;
    }

    return timerEntity;
}

static bool IsSetupCountdownTimer(int entity)
{
    return entity > MaxClients
        && IsValidEntity(entity)
        && HasEntProp(entity, Prop_Send, "m_nState")
        && GetEntProp(entity, Prop_Send, "m_nState") == ROUND_TIMER_STATE_SETUP;
}

static float GetRoundTimerRemaining(int timerEntity)
{
    if (GetCountdownTimerBool(timerEntity, "m_bTimerPaused"))
    {
        if (!HasEntProp(timerEntity, Prop_Send, "m_flTimeRemaining"))
        {
            return -1.0;
        }
        return GetEntPropFloat(timerEntity, Prop_Send, "m_flTimeRemaining");
    }

    if (!HasEntProp(timerEntity, Prop_Send, "m_flTimerEndTime"))
    {
        return -1.0;
    }

    float remaining = GetEntPropFloat(timerEntity, Prop_Send, "m_flTimerEndTime") - GetGameTime();
    return remaining > 0.0 ? remaining : 0.0;
}

static bool GetCountdownTimerBool(int timerEntity, const char[] property)
{
    return HasEntProp(timerEntity, Prop_Send, property)
        && GetEntProp(timerEntity, Prop_Send, property) != 0;
}

static bool IsWaitingForPlayers()
{
    return FindEntityByClassname(-1, "tf_gamerules") != -1
        && GameRules_GetProp("m_bInWaitingForPlayers", 1) != 0;
}

static void ArmCountdownWarnings(float remaining, int &armedMask)
{
    for (int i = 0; i < sizeof(gCountdownSeconds); i++)
    {
        if (remaining >= float(gCountdownSeconds[i]))
        {
            armedMask |= 1 << i;
        }
    }
}

void ResetSetupCountdownTracking()
{
    g_iTrackedSetupCountdownTimerRef = INVALID_ENT_REFERENCE;
    g_iSetupCountdownArmedMask = 0;
    g_fLastSetupCountdownRemaining = -1.0;
}

void ResetLiveCountdownTracking()
{
    RestoreTrackedLiveAutoCountdown();
    g_iTrackedLiveCountdownTimerRef = INVALID_ENT_REFERENCE;
    g_iLiveCountdownArmedMask = 0;
    g_fLastLiveCountdownRemaining = -1.0;
    g_bTrackedLiveAutoCountdownOriginal = false;
}

void RestoreSuppressedControlPointCountdowns()
{
    int objectiveResource = FindEntityByClassname(-1, "tf_objective_resource");
    if (objectiveResource == -1
        || !HasEntProp(objectiveResource, Prop_Send, "m_flUnlockTimes"))
    {
        return;
    }

    int controlPointCount = GetEntPropArraySize(
        objectiveResource,
        Prop_Send,
        "m_flUnlockTimes"
    );
    if (controlPointCount > MAX_TRACKED_CONTROL_POINTS)
    {
        controlPointCount = MAX_TRACKED_CONTROL_POINTS;
    }

    float now = GetGameTime();
    for (int controlPoint = 0; controlPoint < controlPointCount; controlPoint++)
    {
        if (!g_bControlPointCountdownSuppressed[controlPoint])
        {
            continue;
        }

        float trackedUnlockTime = g_fTrackedControlPointUnlockTime[controlPoint];
        float networkUnlockTime = GetEntPropFloat(
            objectiveResource,
            Prop_Send,
            "m_flUnlockTimes",
            controlPoint
        );
        if (trackedUnlockTime > now && networkUnlockTime <= 0.0)
        {
            SetEntPropFloat(
                objectiveResource,
                Prop_Send,
                "m_flUnlockTimes",
                trackedUnlockTime,
                controlPoint
            );
        }

        g_bControlPointCountdownSuppressed[controlPoint] = false;
    }
}

static void ClearControlPointUnlockCountdowns()
{
    for (int controlPoint = 0;
        controlPoint < MAX_TRACKED_CONTROL_POINTS;
        controlPoint++)
    {
        g_fTrackedControlPointUnlockTime[controlPoint] = 0.0;
        g_bControlPointCountdownSuppressed[controlPoint] = false;
        g_iControlPointUnlockArmedMask[controlPoint] = 0;
        g_bControlPointEnabledReplacementHandled[controlPoint] = false;
    }
}

void ResetControlPointUnlockTracking()
{
    ClearControlPointUnlockCountdowns();
    for (int controlPoint = 0;
        controlPoint < MAX_TRACKED_CONTROL_POINTS;
        controlPoint++)
    {
        g_fLastControlPointUnlockEvent[controlPoint] = -9999.0;
    }
}

void CancelCountdownMonitorTimer()
{
    if (g_hCountdownMonitorTimer != INVALID_HANDLE)
    {
        delete g_hCountdownMonitorTimer;
        g_hCountdownMonitorTimer = INVALID_HANDLE;
    }
    ResetSetupCountdownTracking();
    ResetLiveCountdownTracking();
    RestoreSuppressedControlPointCountdowns();
    ResetControlPointUnlockTracking();
}

