static const char gStockCountdownSounds[][] =
{
    "vo/announcer_begins_5sec.mp3", "vo/announcer_begins_4sec.mp3",
    "vo/announcer_begins_3sec.mp3", "vo/announcer_begins_2sec.mp3", "vo/announcer_begins_1sec.mp3"
};
static const char gStockFinalCountdownSounds[][] =
{
    "vo/announcer_ends_5sec.mp3", "vo/announcer_ends_4sec.mp3",
    "vo/announcer_ends_3sec.mp3", "vo/announcer_ends_2sec.mp3", "vo/announcer_ends_1sec.mp3"
};
static const char gStockControlPointEnabledSounds[][] =
{
    "vo/announcer_am_capenabled01.mp3", "vo/announcer_am_capenabled02.mp3",
    "vo/announcer_am_capenabled03.mp3", "vo/announcer_am_capenabled04.mp3"
};
static const int gCountdownSeconds[] = { 5, 4, 3, 2, 1 };

// Cache discovery only for a single monitor invocation. Timer state, deadlines,
// HUD selection and waiting-for-players state remain fresh between invocations.
// This avoids duplicating entity-list scans without reducing countdown frequency.
bool g_CountdownMonitorActive;
Handle g_CountdownExecutingTimer;
bool g_CountdownObjectiveResolved, g_CountdownHudResolved, g_CountdownRulesResolved;
int g_CountdownObjectiveRef = INVALID_ENT_REFERENCE;
int g_CountdownHudRef = INVALID_ENT_REFERENCE;
int g_CountdownRulesRef = INVALID_ENT_REFERENCE;
int g_ControlPointCountdownOwnerRef = INVALID_ENT_REFERENCE;
int g_ControlPointCountdownGeneration;

int GetStockCountdownSoundIndex(const char[] sample)
{
    char normalized[PLATFORM_MAX_PATH];
    strcopy(normalized, sizeof(normalized), sample);
    TrimString(normalized);
    int start = 0;
    while (normalized[start] != '\0' && !IsAsciiAlphaNumeric(normalized[start])) start++;
    // Strip all engine sound flags in one shift, not one full copy per character.
    if (start > 0) Strings_ShiftLeft(normalized, sizeof(normalized), start);
    NormalizeSoundPath(normalized, sizeof(normalized));
    Strings_ToLower(normalized, sizeof(normalized));
    for (int i = 0; i < sizeof(gStockCountdownSounds); i++)
    {
        if (StrEqual(normalized, gStockCountdownSounds[i])
            || StrEqual(normalized, gStockFinalCountdownSounds[i])) return i;
    }
    return -1;
}

public Action Timer_MonitorCountdowns(Handle timer)
{
    if (timer != g_hCountdownMonitorTimer) return Plugin_Stop;
    if (g_CountdownMonitorActive) return Plugin_Continue;
    g_CountdownMonitorActive = true;
    g_CountdownExecutingTimer = timer;
    g_CountdownObjectiveResolved = false;
    g_CountdownHudResolved = false;
    g_CountdownRulesResolved = false;

    MonitorRoundStartSirenTransition();
    if (timer == g_hCountdownMonitorTimer) MonitorSetupCountdown();
    if (timer == g_hCountdownMonitorTimer) MonitorLiveRoundCountdown();
    if (timer == g_hCountdownMonitorTimer) MonitorControlPointUnlockCountdowns();

    g_CountdownExecutingTimer = null;
    g_CountdownMonitorActive = false;
    return timer == g_hCountdownMonitorTimer ? Plugin_Continue : Plugin_Stop;
}

static int Countdown_FindObjectiveResource()
{
    if (g_CountdownMonitorActive && g_CountdownObjectiveResolved)
        return EntRefToEntIndex(g_CountdownObjectiveRef);
    int entity = FindEntityByClassname(-1, "tf_objective_resource");
    if (g_CountdownMonitorActive)
    {
        g_CountdownObjectiveResolved = true;
        g_CountdownObjectiveRef = entity > MaxClients ? EntIndexToEntRef(entity) : INVALID_ENT_REFERENCE;
    }
    return entity;
}

static void MonitorControlPointUnlockCountdowns()
{
    if (gReadyCountdownReplacements.Length == 0 || gReadyUnlockReplacements.Length == 0)
    {
        RestoreSuppressedControlPointCountdowns();
        ClearControlPointUnlockCountdowns();
        return;
    }
    int objectiveResource = Countdown_FindObjectiveResource();
    if (objectiveResource <= MaxClients || !IsValidEntity(objectiveResource)
        || !HasEntProp(objectiveResource, Prop_Send, "m_flUnlockTimes"))
    {
        ClearControlPointUnlockCountdowns();
        return;
    }
    int resourceRef = EntIndexToEntRef(objectiveResource);
    if (resourceRef != g_ControlPointCountdownOwnerRef)
    {
        // A replacement objective entity must never inherit the old entity's
        // suppressed network deadlines merely because it reused the same index.
        RestoreSuppressedControlPointCountdowns();
        ClearControlPointUnlockCountdowns();
        g_ControlPointCountdownOwnerRef = resourceRef;
    }
    int generation = g_ControlPointCountdownGeneration;
    int controlPointCount = GetEntPropArraySize(objectiveResource, Prop_Send, "m_flUnlockTimes");
    if (HasEntProp(objectiveResource, Prop_Send, "m_iNumControlPoints"))
    {
        int reportedCount = GetEntProp(objectiveResource, Prop_Send, "m_iNumControlPoints");
        if (reportedCount < controlPointCount) controlPointCount = reportedCount;
    }
    if (controlPointCount > MAX_TRACKED_CONTROL_POINTS) controlPointCount = MAX_TRACKED_CONTROL_POINTS;
    if (controlPointCount < 0) controlPointCount = 0;
    float now = GetGameTime();

    for (int controlPoint = 0; controlPoint < MAX_TRACKED_CONTROL_POINTS; controlPoint++)
    {
        // Sound emission calls third-party sound hooks synchronously.
        if (generation != g_ControlPointCountdownGeneration) return;
        objectiveResource = EntRefToEntIndex(resourceRef);
        if (objectiveResource <= MaxClients || !IsValidEntity(objectiveResource)) return;
        if (controlPoint >= controlPointCount)
        {
            Countdown_ClearControlPoint(controlPoint);
            continue;
        }
        float networkUnlockTime = GetEntPropFloat(objectiveResource, Prop_Send, "m_flUnlockTimes", controlPoint);
        float trackedUnlockTime = g_fTrackedControlPointUnlockTime[controlPoint];
        if (networkUnlockTime > 0.0)
        {
            if (trackedUnlockTime <= 0.0 || FloatAbs(networkUnlockTime - trackedUnlockTime) > 0.01)
            {
                trackedUnlockTime = networkUnlockTime;
                g_fTrackedControlPointUnlockTime[controlPoint] = trackedUnlockTime;
                g_bControlPointCountdownSuppressed[controlPoint] = false;
                g_iControlPointUnlockArmedMask[controlPoint] = 0;
                g_bControlPointEnabledReplacementHandled[controlPoint] = false;
                float initialRemaining = trackedUnlockTime - now;
                if (initialRemaining > 0.0)
                {
                    ArmCountdownWarnings(initialRemaining, g_iControlPointUnlockArmedMask[controlPoint]);
                    g_iControlPointUnlockArmedMask[controlPoint] |= CONTROL_POINT_ENABLED_WARNING_BIT;
                }
            }
            else if (g_bControlPointCountdownSuppressed[controlPoint])
            {
                g_bControlPointCountdownSuppressed[controlPoint] = false;
            }
        }
        else if (trackedUnlockTime <= 0.0 || !g_bControlPointCountdownSuppressed[controlPoint])
        {
            Countdown_ClearControlPoint(controlPoint);
            continue;
        }
        float remaining = trackedUnlockTime - now;
        if (remaining <= 0.0)
        {
            g_iControlPointUnlockArmedMask[controlPoint] = 0;
            continue;
        }
        if (!g_bControlPointCountdownSuppressed[controlPoint] && remaining <= CONTROL_POINT_COUNTDOWN_SUPPRESS_AT)
        {
            SetEntPropFloat(objectiveResource, Prop_Send, "m_flUnlockTimes", 0.0, controlPoint);
            g_bControlPointCountdownSuppressed[controlPoint] = true;
            char currentMap[PLATFORM_MAX_PATH];
            GetCurrentMap(currentMap, sizeof(currentMap));
            LogMessage("[SaySounds:CPUnlock] map %s, point %d, suppressed client HUD countdown at %.2f seconds.",
                currentMap, controlPoint, remaining);
        }
        bool numericWarningQueued = false;
        for (int warningIndex = 0; warningIndex < sizeof(gCountdownSeconds); warningIndex++)
        {
            int warningBit = 1 << warningIndex;
            if ((g_iControlPointUnlockArmedMask[controlPoint] & warningBit) == 0
                || remaining > float(gCountdownSeconds[warningIndex] + 1)) continue;
            // Consume before emitting: a sound hook must not re-emit this warning.
            g_iControlPointUnlockArmedMask[controlPoint] &= ~warningBit;
            ReplaceControlPointUnlockWarning(controlPoint, warningIndex);
            numericWarningQueued = true;
            break;
        }
        if (generation != g_ControlPointCountdownGeneration) return;
        if (!numericWarningQueued && (g_iControlPointUnlockArmedMask[controlPoint] & CONTROL_POINT_ENABLED_WARNING_BIT) != 0
            && remaining <= 1.0)
        {
            g_iControlPointUnlockArmedMask[controlPoint] &= ~CONTROL_POINT_ENABLED_WARNING_BIT;
            g_bControlPointEnabledReplacementHandled[controlPoint] = true;
            ReplaceControlPointEnabled(controlPoint, false);
        }
    }
}

static void MonitorSetupCountdown()
{
    if (gReadyCountdownReplacements.Length == 0 && !g_bTrackedSetupAutoCountdownSuppressed)
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
    else if (g_fLastSetupCountdownRemaining >= 0.0 && remaining > g_fLastSetupCountdownRemaining + 0.2)
    {
        ArmCountdownWarnings(remaining, g_iSetupCountdownArmedMask);
    }
    g_fLastSetupCountdownRemaining = remaining;
    if (GetCountdownTimerBool(timerEntity, "m_bIsDisabled") || GetCountdownTimerBool(timerEntity, "m_bTimerPaused")
        || (GetCountdownTimerBool(timerEntity, "m_bStopWatchTimer") && GetCountdownTimerBool(timerEntity, "m_bInCaptureWatchState"))) return;
    bool shouldEmit = IsSetupAutoCountdownEnabled(timerEntity) && !IsWaitingForPlayers();
    for (int i = 0; i < sizeof(gCountdownSeconds); i++)
    {
        int bit = 1 << i;
        if ((g_iSetupCountdownArmedMask & bit) == 0 || remaining > float(gCountdownSeconds[i] + 1)) continue;
        g_iSetupCountdownArmedMask &= ~bit;
        if (shouldEmit) ReplaceCountdownWarning(i, false);
        break; // Preserve the engine's one-warning-per-frame behavior.
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
    else if (g_fLastLiveCountdownRemaining >= 0.0 && remaining > g_fLastLiveCountdownRemaining + 0.2)
        ArmCountdownWarnings(remaining, g_iLiveCountdownArmedMask);
    g_fLastLiveCountdownRemaining = remaining;
    if (GetCountdownTimerBool(timerEntity, "m_bIsDisabled") || IsWaitingForPlayers()
        || (GetCountdownTimerBool(timerEntity, "m_bStopWatchTimer") && GetCountdownTimerBool(timerEntity, "m_bInCaptureWatchState"))
        || remaining > LIVE_COUNTDOWN_SUPPRESS_AT)
    {
        RestoreTrackedLiveAutoCountdown();
        return;
    }
    bool shouldEmit = IsLiveAutoCountdownEnabled(timerEntity);
    if (shouldEmit) SuppressTrackedLiveAutoCountdown();
    if (GetCountdownTimerBool(timerEntity, "m_bTimerPaused")) return;
    for (int i = 0; i < sizeof(gCountdownSeconds); i++)
    {
        int bit = 1 << i;
        if ((g_iLiveCountdownArmedMask & bit) == 0 || remaining > float(gCountdownSeconds[i] + 1)) continue;
        g_iLiveCountdownArmedMask &= ~bit;
        if (shouldEmit) ReplaceCountdownWarning(i, true);
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
            if (g_iTrackedSetupSirenState != ROUND_TIMER_STATE_SETUP) TrackSetupSirenTimer(timerEntity);
            else SuppressTrackedSetupAutoCountdown();
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
    if (setupTimer != -1) TrackSetupSirenTimer(setupTimer);
}

static void TrackSetupSirenTimer(int timerEntity)
{
    if (!IsRoundTimerEntity(timerEntity)) return;
    int timerRef = EntIndexToEntRef(timerEntity);
    if (timerRef != g_iTrackedSetupSirenTimerRef)
    {
        RestoreTrackedSetupAutoCountdown();
        g_iTrackedSetupSirenTimerRef = timerRef;
    }
    g_iTrackedSetupSirenState = GetEntProp(timerEntity, Prop_Send, "m_nState");
    // Do not replace the original value with our own suppressed zero on a
    // normal -> setup transition of the same timer entity.
    if (!g_bTrackedSetupAutoCountdownSuppressed)
        g_bTrackedSetupAutoCountdownOriginal = GetCountdownTimerBool(timerEntity, "m_bAutoCountdown");
    SuppressTrackedSetupAutoCountdown();
}

static void SuppressTrackedSetupAutoCountdown()
{
    int entity = EntRefToEntIndex(g_iTrackedSetupSirenTimerRef);
    if (!IsRoundTimerEntity(entity) || !HasEntProp(entity, Prop_Send, "m_bAutoCountdown")) return;
    if (!g_bTrackedSetupAutoCountdownSuppressed)
    {
        g_bTrackedSetupAutoCountdownOriginal = GetCountdownTimerBool(entity, "m_bAutoCountdown");
        g_bTrackedSetupAutoCountdownSuppressed = true;
        LogMessage("[SaySounds:Siren] Suppressed automatic countdown on HUD timer entref %d (original %d).",
            g_iTrackedSetupSirenTimerRef, g_bTrackedSetupAutoCountdownOriginal);
    }
    if (GetCountdownTimerBool(entity, "m_bAutoCountdown")) SetEntProp(entity, Prop_Send, "m_bAutoCountdown", 0);
}

void RestoreTrackedSetupAutoCountdown()
{
    if (!g_bTrackedSetupAutoCountdownSuppressed) return;
    int entity = EntRefToEntIndex(g_iTrackedSetupSirenTimerRef);
    g_bTrackedSetupAutoCountdownSuppressed = false;
    if (IsRoundTimerEntity(entity) && HasEntProp(entity, Prop_Send, "m_bAutoCountdown"))
        SetEntProp(entity, Prop_Send, "m_bAutoCountdown", g_bTrackedSetupAutoCountdownOriginal ? 1 : 0);
}

static bool IsSetupAutoCountdownEnabled(int timerEntity)
{
    if (EntIndexToEntRef(timerEntity) == g_iTrackedSetupSirenTimerRef && g_bTrackedSetupAutoCountdownSuppressed)
        return g_bTrackedSetupAutoCountdownOriginal;
    return GetCountdownTimerBool(timerEntity, "m_bAutoCountdown");
}

static void SuppressTrackedLiveAutoCountdown()
{
    int entity = EntRefToEntIndex(g_iTrackedLiveCountdownTimerRef);
    if (!IsRoundTimerEntity(entity) || !HasEntProp(entity, Prop_Send, "m_bAutoCountdown")) return;
    if (!g_bTrackedLiveAutoCountdownSuppressed)
    {
        g_bTrackedLiveAutoCountdownOriginal = GetCountdownTimerBool(entity, "m_bAutoCountdown");
        g_bTrackedLiveAutoCountdownSuppressed = true;
        LogMessage("[SaySounds:Countdown] Suppressed final automatic countdown on HUD timer entref %d (original %d).",
            g_iTrackedLiveCountdownTimerRef, g_bTrackedLiveAutoCountdownOriginal);
    }
    if (GetCountdownTimerBool(entity, "m_bAutoCountdown")) SetEntProp(entity, Prop_Send, "m_bAutoCountdown", 0);
}

void RestoreTrackedLiveAutoCountdown()
{
    if (!g_bTrackedLiveAutoCountdownSuppressed) return;
    int entity = EntRefToEntIndex(g_iTrackedLiveCountdownTimerRef);
    g_bTrackedLiveAutoCountdownSuppressed = false;
    if (IsRoundTimerEntity(entity) && HasEntProp(entity, Prop_Send, "m_bAutoCountdown"))
        SetEntProp(entity, Prop_Send, "m_bAutoCountdown", g_bTrackedLiveAutoCountdownOriginal ? 1 : 0);
}

static bool IsLiveAutoCountdownEnabled(int timerEntity)
{
    if (EntIndexToEntRef(timerEntity) == g_iTrackedLiveCountdownTimerRef && g_bTrackedLiveAutoCountdownSuppressed)
        return g_bTrackedLiveAutoCountdownOriginal;
    return GetCountdownTimerBool(timerEntity, "m_bAutoCountdown");
}

static bool IsRoundTimerEntity(int entity)
{
    if (entity <= MaxClients || !IsValidEntity(entity) || !HasEntProp(entity, Prop_Send, "m_nState")) return false;
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

static bool Countdown_CanEmitToClient(int client, const char[] groupName, float &volume)
{
    if (!IsClientInGame(client) || IsFakeClient(client)) return false;
    int serial = GetClientSerial(client);
    if (!CanPlaySaySoundToClient(client, groupName, volume)) return false;
    return GetClientFromSerial(serial) == client && IsClientInGame(client);
}

static void ReplaceControlPointUnlockWarning(int controlPoint, int warningIndex)
{
    if (warningIndex < 0 || warningIndex >= sizeof(gCountdownSeconds)) return;
    char replacement[PLATFORM_MAX_PATH], groupName[MAX_GROUP_NAME];
    if (!GetRandomReadyReplacement(gReadyCountdownReplacements, gReadyCountdownGroups,
        replacement, sizeof(replacement), groupName, sizeof(groupName))) return;
    int recipients;
    for (int client = 1; client <= MaxClients; client++)
    {
        float volume;
        if (!Countdown_CanEmitToClient(client, groupName, volume)) continue;
        EmitSoundToClient(client, replacement, client, SNDCHAN_VOICE_BASE, SNDLEVEL_NONE, SND_NOFLAGS, volume);
        recipients++;
    }
    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));
    LogMessage("[SaySounds:CPUnlock] map %s, point %d, warning %d, replacement %s, custom %d.",
        currentMap, controlPoint, gCountdownSeconds[warningIndex], replacement, recipients);
}

void ReplaceControlPointEnabled(int controlPoint, bool stopStock)
{
    if (controlPoint < 0 || controlPoint >= MAX_TRACKED_CONTROL_POINTS) return;
    int replacementCount = gReadyUnlockReplacements.Length;
    if (replacementCount == 0) return;
    if (g_iNextUnlockReplacementIndex < 0) g_iNextUnlockReplacementIndex = GetRandomInt(0, replacementCount - 1);
    else if (g_iNextUnlockReplacementIndex >= replacementCount) g_iNextUnlockReplacementIndex %= replacementCount;
    int replacementIndex = g_iNextUnlockReplacementIndex;
    char replacement[PLATFORM_MAX_PATH], groupName[MAX_GROUP_NAME];
    gReadyUnlockReplacements.GetString(replacementIndex, replacement, sizeof(replacement));
    gReadyUnlockGroups.GetString(replacementIndex, groupName, sizeof(groupName));
    g_iNextUnlockReplacementIndex = (replacementIndex + 1) % replacementCount;
    int recipients;
    for (int client = 1; client <= MaxClients; client++)
    {
        float volume;
        if (!Countdown_CanEmitToClient(client, groupName, volume)) continue;
        if (stopStock)
        {
            for (int i = 0; i < sizeof(gStockControlPointEnabledSounds); i++)
                StopSound(client, SNDCHAN_VOICE_BASE, gStockControlPointEnabledSounds[i]);
        }
        EmitSoundToClient(client, replacement, client, SNDCHAN_VOICE_BASE, SNDLEVEL_NONE, SND_NOFLAGS, volume);
        recipients++;
    }
    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));
    LogMessage("[SaySounds:CPUnlock] map %s, point %d, unlocked, replacement index %d/%d, replacement %s, custom %d.",
        currentMap, controlPoint, replacementIndex, replacementCount, replacement, recipients);
}

static void ReplaceCountdownWarning(int warningIndex, bool finalCountdown)
{
    if (warningIndex < 0 || warningIndex >= sizeof(gStockCountdownSounds)) return;
    char replacement[PLATFORM_MAX_PATH], groupName[MAX_GROUP_NAME], stockSound[PLATFORM_MAX_PATH];
    bool hasReplacement = GetRandomReadyReplacement(gReadyCountdownReplacements, gReadyCountdownGroups,
        replacement, sizeof(replacement), groupName, sizeof(groupName));
    if (finalCountdown) strcopy(stockSound, sizeof(stockSound), gStockFinalCountdownSounds[warningIndex]);
    else strcopy(stockSound, sizeof(stockSound), gStockCountdownSounds[warningIndex]);
    int replacementRecipients, stockRecipients;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client)) continue;
        int serial = GetClientSerial(client);
        float volume;
        bool custom = hasReplacement && Countdown_CanEmitToClient(client, groupName, volume);
        if (GetClientFromSerial(serial) != client || !IsClientInGame(client)) continue;
        if (custom)
        {
            EmitSoundToClient(client, replacement, client, SNDCHAN_VOICE_BASE, SNDLEVEL_NONE, SND_NOFLAGS, volume);
            replacementRecipients++;
        }
        else
        {
            EmitSoundToClient(client, stockSound, client, SNDCHAN_VOICE_BASE, SNDLEVEL_NONE);
            stockRecipients++;
        }
    }
    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));
    LogMessage("[SaySounds:Countdown] map %s, phase %s, warning %d, replacement %s, custom %d, stock %d.",
        currentMap, finalCountdown ? "live" : "setup", gCountdownSeconds[warningIndex],
        hasReplacement ? replacement : stockSound, replacementRecipients, stockRecipients);
}

static int FindActiveHudRoundTimer()
{
    if (g_CountdownMonitorActive && g_CountdownHudResolved)
    {
        int cached = EntRefToEntIndex(g_CountdownHudRef);
        return IsRoundTimerEntity(cached) ? cached : -1;
    }
    int timerEntity = -1;
    int objectiveResource = Countdown_FindObjectiveResource();
    while (objectiveResource != -1)
    {
        if (HasEntProp(objectiveResource, Prop_Send, "m_iTimerToShowInHUD"))
        {
            int candidate = GetEntProp(objectiveResource, Prop_Send, "m_iTimerToShowInHUD");
            if (IsRoundTimerEntity(candidate))
            {
                timerEntity = candidate;
                break;
            }
        }
        objectiveResource = FindEntityByClassname(objectiveResource, "tf_objective_resource");
    }
    if (g_CountdownMonitorActive)
    {
        g_CountdownHudResolved = true;
        g_CountdownHudRef = timerEntity > MaxClients ? EntIndexToEntRef(timerEntity) : INVALID_ENT_REFERENCE;
    }
    return timerEntity;
}

static int FindActiveSetupCountdownTimer()
{
    int hudTimer = FindActiveHudRoundTimer();
    if (hudTimer != -1) return IsSetupCountdownTimer(hudTimer) ? hudTimer : -1;
    int timerEntity = -1;
    while ((timerEntity = FindEntityByClassname(timerEntity, "team_round_timer")) != -1)
    {
        if (!IsSetupCountdownTimer(timerEntity) || GetCountdownTimerBool(timerEntity, "m_bIsDisabled")) continue;
        if (!HasEntProp(timerEntity, Prop_Send, "m_bShowInHUD") || GetCountdownTimerBool(timerEntity, "m_bShowInHUD")) return timerEntity;
    }
    return -1;
}

static int FindActiveLiveCountdownTimer()
{
    int timerEntity = FindActiveHudRoundTimer();
    if (!IsRoundTimerEntity(timerEntity) || GetEntProp(timerEntity, Prop_Send, "m_nState") != ROUND_TIMER_STATE_NORMAL
        || GetCountdownTimerBool(timerEntity, "m_bIsDisabled")) return -1;
    return timerEntity;
}

static bool IsSetupCountdownTimer(int entity)
{
    return IsRoundTimerEntity(entity) && GetEntProp(entity, Prop_Send, "m_nState") == ROUND_TIMER_STATE_SETUP;
}

static float GetRoundTimerRemaining(int timerEntity)
{
    if (GetCountdownTimerBool(timerEntity, "m_bTimerPaused"))
    {
        if (!HasEntProp(timerEntity, Prop_Send, "m_flTimeRemaining")) return -1.0;
        return GetEntPropFloat(timerEntity, Prop_Send, "m_flTimeRemaining");
    }
    if (!HasEntProp(timerEntity, Prop_Send, "m_flTimerEndTime")) return -1.0;
    float remaining = GetEntPropFloat(timerEntity, Prop_Send, "m_flTimerEndTime") - GetGameTime();
    return remaining > 0.0 ? remaining : 0.0;
}

static bool GetCountdownTimerBool(int timerEntity, const char[] property)
{
    return HasEntProp(timerEntity, Prop_Send, property) && GetEntProp(timerEntity, Prop_Send, property) != 0;
}

static bool IsWaitingForPlayers()
{
    int rules;
    if (g_CountdownMonitorActive && g_CountdownRulesResolved) rules = EntRefToEntIndex(g_CountdownRulesRef);
    else
    {
        rules = FindEntityByClassname(-1, "tf_gamerules");
        if (g_CountdownMonitorActive)
        {
            g_CountdownRulesResolved = true;
            g_CountdownRulesRef = rules > MaxClients ? EntIndexToEntRef(rules) : INVALID_ENT_REFERENCE;
        }
    }
    return rules > MaxClients && IsValidEntity(rules) && GameRules_GetProp("m_bInWaitingForPlayers", 1) != 0;
}

static void ArmCountdownWarnings(float remaining, int &armedMask)
{
    for (int i = 0; i < sizeof(gCountdownSeconds); i++)
        if (remaining >= float(gCountdownSeconds[i])) armedMask |= 1 << i;
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
    // Restore only the entity whose deadlines this plugin actually suppressed.
    int resource = EntRefToEntIndex(g_ControlPointCountdownOwnerRef);
    if (resource <= MaxClients || !IsValidEntity(resource) || !HasEntProp(resource, Prop_Send, "m_flUnlockTimes")) return;
    int count = GetEntPropArraySize(resource, Prop_Send, "m_flUnlockTimes");
    if (count > MAX_TRACKED_CONTROL_POINTS) count = MAX_TRACKED_CONTROL_POINTS;
    float now = GetGameTime();
    for (int point = 0; point < count; point++)
    {
        if (!g_bControlPointCountdownSuppressed[point]) continue;
        float deadline = g_fTrackedControlPointUnlockTime[point];
        float published = GetEntPropFloat(resource, Prop_Send, "m_flUnlockTimes", point);
        g_bControlPointCountdownSuppressed[point] = false;
        if (deadline > now && published <= 0.0) SetEntPropFloat(resource, Prop_Send, "m_flUnlockTimes", deadline, point);
    }
}

static void Countdown_ClearControlPoint(int point)
{
    g_fTrackedControlPointUnlockTime[point] = 0.0;
    g_bControlPointCountdownSuppressed[point] = false;
    g_iControlPointUnlockArmedMask[point] = 0;
    g_bControlPointEnabledReplacementHandled[point] = false;
}

static void ClearControlPointUnlockCountdowns()
{
    g_ControlPointCountdownGeneration++;
    g_ControlPointCountdownOwnerRef = INVALID_ENT_REFERENCE;
    for (int point = 0; point < MAX_TRACKED_CONTROL_POINTS; point++) Countdown_ClearControlPoint(point);
}

void ResetControlPointUnlockTracking()
{
    ClearControlPointUnlockCountdowns();
    for (int point = 0; point < MAX_TRACKED_CONTROL_POINTS; point++) g_fLastControlPointUnlockEvent[point] = -9999.0;
}

void CancelCountdownMonitorTimer()
{
    Handle timer = g_hCountdownMonitorTimer;
    g_hCountdownMonitorTimer = INVALID_HANDLE;
    // If cancellation re-enters from a sound hook, let the active callback stop
    // itself. Never delete a timer and then return Continue for that same handle.
    if (timer != g_CountdownExecutingTimer) delete timer;
    ResetSetupCountdownTracking();
    ResetLiveCountdownTracking();
    RestoreSuppressedControlPointCountdowns();
    ResetControlPointUnlockTracking();
}
