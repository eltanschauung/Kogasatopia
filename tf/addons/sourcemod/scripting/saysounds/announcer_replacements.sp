static void ReplaceRoundStartSiren(int index, int transitionSerial)
{
    if (gReadyRoundStartSirenReplacements.Length == 0)
    {
        return;
    }

    if (index < 0 || index >= gReadyRoundStartSirenReplacements.Length)
    {
        LogError("[SaySounds:Siren] Invalid replacement index %d for %d configured sounds.",
            index,
            gReadyRoundStartSirenReplacements.Length);
        return;
    }

    float now = GetGameTime();
    if (now - g_fLastRoundStartSirenTime < ROUND_START_SIREN_DUPLICATE_GUARD)
    {
        LogMessage("[SaySounds:Siren] Suppressed duplicate setup-timer transition.");
        return;
    }
    g_fLastRoundStartSirenTime = now;

    char replacement[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    gReadyRoundStartSirenReplacements.GetString(index, replacement, sizeof(replacement));
    gReadyRoundStartSirenGroups.GetString(index, groupName, sizeof(groupName));
    int replacementRecipientCount = 0;
    int stockRecipientCount = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
        {
            continue;
        }

        float emitVolume;
        if (!CanPlaySaySoundToClient(client, groupName, emitVolume))
        {
            g_bEmittingRoundStartSiren = true;
            g_iEmittingRoundStartSirenSerial = transitionSerial;
            g_iEmittingRoundStartSirenIndex = index;
            g_iEmittingRoundStartSirenClient = client;
            EmitSoundToClient(
                client,
                STOCK_ROUND_START_SIREN,
                client,
                SNDCHAN_AUTO,
                SNDLEVEL_NONE
            );
            g_bEmittingRoundStartSiren = false;
            stockRecipientCount++;
            continue;
        }

        // The fixed entity/channel pair replaces the prior round-start sound.
        g_bEmittingRoundStartSiren = true;
        g_iEmittingRoundStartSirenSerial = transitionSerial;
        g_iEmittingRoundStartSirenIndex = index;
        g_iEmittingRoundStartSirenClient = client;
        EmitSoundToClient(
            client,
            replacement,
            client,
            ROUND_START_SIREN_CHANNEL,
            SNDLEVEL_NONE,
            SND_NOFLAGS,
            emitVolume
        );
        g_bEmittingRoundStartSiren = false;
        replacementRecipientCount++;
    }

    g_iEmittingRoundStartSirenSerial = 0;
    g_iEmittingRoundStartSirenIndex = -1;
    g_iEmittingRoundStartSirenClient = 0;

    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));
    LogMessage(
        "[SaySounds:Siren] Played one replacement: %s (map %s, serial %d, index %d, timer entref %d, custom %d, stock %d).",
        replacement,
        currentMap,
        transitionSerial,
        index,
        g_iPendingSetupSirenTimerRef,
        replacementRecipientCount,
        stockRecipientCount
    );
}

void ScheduleRoundStartSirenReplacement()
{
    CancelRoundStartSirenTimer();

    int replacementCount = gReadyRoundStartSirenReplacements.Length;
    if (replacementCount == 0)
    {
        return;
    }

    if (g_iNextRoundStartSirenIndex < 0)
    {
        g_iNextRoundStartSirenIndex = GetRandomInt(0, replacementCount - 1);
    }
    else if (g_iNextRoundStartSirenIndex >= replacementCount)
    {
        g_iNextRoundStartSirenIndex %= replacementCount;
    }

    g_iRoundStartSirenTransitionSerial++;
    if (g_iRoundStartSirenTransitionSerial <= 0)
    {
        g_iRoundStartSirenTransitionSerial = 1;
    }

    g_iPendingSetupSirenTimerRef = g_iTrackedSetupSirenTimerRef;
    g_iPendingRoundStartSirenSerial = g_iRoundStartSirenTransitionSerial;
    g_iPendingRoundStartSirenIndex = g_iNextRoundStartSirenIndex;
    g_hRoundStartSirenTimer = CreateTimer(
        ROUND_START_SIREN_REPLACEMENT_DELAY,
        Timer_ReplaceRoundStartSiren,
        g_iNextRoundStartSirenIndex,
        TIMER_FLAG_NO_MAPCHANGE
    );

    char replacement[PLATFORM_MAX_PATH];
    gReadyRoundStartSirenReplacements.GetString(
        g_iPendingRoundStartSirenIndex,
        replacement,
        sizeof(replacement)
    );
    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));
    LogMessage(
        "[SaySounds:SirenTrace] Scheduled timer: map %s, serial %d, index %d, sample %s, timer entref %d.",
        currentMap,
        g_iPendingRoundStartSirenSerial,
        g_iPendingRoundStartSirenIndex,
        replacement,
        g_iPendingSetupSirenTimerRef
    );
}

public Action Timer_ReplaceRoundStartSiren(Handle timer, any data)
{
    if (timer != g_hRoundStartSirenTimer)
    {
        LogMessage(
            "[SaySounds:SirenTrace] Rejected stale timer callback: payload index %d, pending serial %d, pending index %d, timer entref %d.",
            data,
            g_iPendingRoundStartSirenSerial,
            g_iPendingRoundStartSirenIndex,
            g_iPendingSetupSirenTimerRef
        );
        return Plugin_Stop;
    }

    g_hRoundStartSirenTimer = INVALID_HANDLE;
    int replacementIndex = data;
    int transitionSerial = g_iPendingRoundStartSirenSerial;
    LogMessage(
        "[SaySounds:SirenTrace] Firing timer: serial %d, payload index %d, pending index %d, timer entref %d.",
        transitionSerial,
        replacementIndex,
        g_iPendingRoundStartSirenIndex,
        g_iPendingSetupSirenTimerRef
    );
    ReplaceRoundStartSiren(replacementIndex, transitionSerial);

    int replacementCount = gReadyRoundStartSirenReplacements.Length;
    if (replacementCount > 0)
    {
        g_iNextRoundStartSirenIndex = (replacementIndex + 1) % replacementCount;
    }
    else
    {
        g_iNextRoundStartSirenIndex = -1;
    }

    ScheduleRoundStartAutoCountdownRestore();
    g_iPendingSetupSirenTimerRef = INVALID_ENT_REFERENCE;
    g_iPendingRoundStartSirenSerial = 0;
    g_iPendingRoundStartSirenIndex = -1;
    return Plugin_Stop;
}

static void CancelRoundStartSirenTimer()
{
    if (g_hRoundStartSirenTimer != INVALID_HANDLE)
    {
        LogMessage(
            "[SaySounds:SirenTrace] Cancelled pending timer: serial %d, index %d, timer entref %d.",
            g_iPendingRoundStartSirenSerial,
            g_iPendingRoundStartSirenIndex,
            g_iPendingSetupSirenTimerRef
        );
        delete g_hRoundStartSirenTimer;
        g_hRoundStartSirenTimer = INVALID_HANDLE;
    }

    g_iPendingSetupSirenTimerRef = INVALID_ENT_REFERENCE;
    g_iPendingRoundStartSirenSerial = 0;
    g_iPendingRoundStartSirenIndex = -1;
}

static void ScheduleRoundStartAutoCountdownRestore()
{
    if (!g_bTrackedSetupAutoCountdownSuppressed)
    {
        return;
    }

    if (g_hRoundStartAutoCountdownRestoreTimer != INVALID_HANDLE)
    {
        delete g_hRoundStartAutoCountdownRestoreTimer;
    }

    g_hRoundStartAutoCountdownRestoreTimer = CreateTimer(
        ROUND_START_AUTO_COUNTDOWN_RESTORE_DELAY,
        Timer_RestoreRoundStartAutoCountdown,
        _,
        TIMER_FLAG_NO_MAPCHANGE
    );
}

public Action Timer_RestoreRoundStartAutoCountdown(Handle timer)
{
    if (timer != g_hRoundStartAutoCountdownRestoreTimer)
    {
        return Plugin_Stop;
    }

    g_hRoundStartAutoCountdownRestoreTimer = INVALID_HANDLE;
    RestoreTrackedSetupAutoCountdown();
    return Plugin_Stop;
}

void CancelRoundStartSirenTimers()
{
    CancelRoundStartSirenTimer();

    if (g_hRoundStartAutoCountdownRestoreTimer != INVALID_HANDLE)
    {
        delete g_hRoundStartAutoCountdownRestoreTimer;
        g_hRoundStartAutoCountdownRestoreTimer = INVALID_HANDLE;
    }
}

void ResetRoundResultPairing()
{
    g_iActiveRoundResultReplacementIndex = -1;
    g_fRoundResultSelectionTime = -9999.0;
}

static bool CanPairRoundResultReplacements()
{
    return gReadyRoundWinReplacements.Length > 0
        && gReadyRoundWinReplacements.Length == gReadyRoundLoseReplacements.Length;
}

static int GetPairedRoundResultReplacementIndex()
{
    int replacementCount = gReadyRoundWinReplacements.Length;
    float now = GetGameTime();
    if (g_iActiveRoundResultReplacementIndex >= 0
        && g_iActiveRoundResultReplacementIndex < replacementCount
        && now >= g_fRoundResultSelectionTime
        && now - g_fRoundResultSelectionTime <= ROUND_RESULT_PAIR_WINDOW)
    {
        return g_iActiveRoundResultReplacementIndex;
    }

    if (g_iNextRoundResultReplacementIndex < 0)
    {
        g_iNextRoundResultReplacementIndex = GetRandomInt(0, replacementCount - 1);
    }
    else if (g_iNextRoundResultReplacementIndex >= replacementCount)
    {
        g_iNextRoundResultReplacementIndex %= replacementCount;
    }

    g_iActiveRoundResultReplacementIndex = g_iNextRoundResultReplacementIndex;
    g_iNextRoundResultReplacementIndex =
        (g_iActiveRoundResultReplacementIndex + 1) % replacementCount;
    g_fRoundResultSelectionTime = now;
    g_iRoundResultSelectionSerial++;
    if (g_iRoundResultSelectionSerial <= 0)
    {
        g_iRoundResultSelectionSerial = 1;
    }

    return g_iActiveRoundResultReplacementIndex;
}

public Action Event_BroadcastAudio(Event event, const char[] name, bool dontBroadcast)
{
    char stockSound[64];
    event.GetString("sound", stockSound, sizeof(stockSound));

    ArrayList replacements;
    ArrayList groups;
    bool isRoundResult = false;
    if (StrEqual(stockSound, STOCK_ROUND_WIN_SOUND))
    {
        replacements = gReadyRoundWinReplacements;
        groups = gReadyRoundWinGroups;
        isRoundResult = true;
    }
    else if (StrEqual(stockSound, STOCK_ROUND_LOSE_SOUND))
    {
        replacements = gReadyRoundLoseReplacements;
        groups = gReadyRoundLoseGroups;
        isRoundResult = true;
    }
    else if (StrEqual(stockSound, STOCK_OVERTIME_SOUND)
        || StrEqual(stockSound, STOCK_CP_SUCCESS)
        || StrEqual(stockSound, STOCK_CP_FAILURE))
    {
        replacements = gReadyAnnouncerMiscReplacements;
        groups = gReadyAnnouncerMiscGroups;
    }
    else
    {
        return Plugin_Continue;
    }

    if (replacements == null || replacements.Length == 0)
    {
        return Plugin_Continue;
    }

    int team = event.GetInt("team");
    bool pairedSelection = isRoundResult && CanPairRoundResultReplacements();
    int index = pairedSelection
        ? GetPairedRoundResultReplacementIndex()
        : GetRandomInt(0, replacements.Length - 1);
    char replacement[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    replacements.GetString(index, replacement, sizeof(replacement));
    groups.GetString(index, groupName, sizeof(groupName));

    if (isRoundResult)
    {
        char currentMap[PLATFORM_MAX_PATH];
        GetCurrentMap(currentMap, sizeof(currentMap));
        LogMessage(
            "[SaySounds:RoundResult] map %s, stock %s, paired %d, serial %d, index %d, sample %s, win count %d, loss count %d.",
            currentMap,
            stockSound,
            pairedSelection,
            pairedSelection ? g_iRoundResultSelectionSerial : 0,
            index,
            replacement,
            gReadyRoundWinReplacements.Length,
            gReadyRoundLoseReplacements.Length
        );
    }

    bool sentToClient = false;
    bool broadcastToAllTeams = team <= 1 || team == 255;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client)
            || IsFakeClient(client)
            || (!broadcastToAllTeams && GetClientTeam(client) != team))
        {
            continue;
        }

        sentToClient = true;
        float emitVolume;
        if (!CanPlaySaySoundToClient(client, groupName, emitVolume))
        {
            EmitGameSoundToClient(client, stockSound);
            continue;
        }

        EmitSoundToClient(
            client,
            replacement,
            client,
            SNDCHAN_AUTO,
            SNDLEVEL_NONE,
            SND_NOFLAGS,
            emitVolume
        );
    }

    return sentToClient ? Plugin_Handled : Plugin_Continue;
}

static bool IdentifyRoundStartSirenSample(
    const char[] sample,
    bool &isStock,
    int &replacementIndex)
{
    char normalized[PLATFORM_MAX_PATH];
    strcopy(normalized, sizeof(normalized), sample);
    TrimString(normalized);
    while (normalized[0] != '\0' && !IsAsciiAlphaNumeric(normalized[0]))
    {
        Strings_ShiftLeft(normalized, sizeof(normalized), 1);
    }
    NormalizeSoundPath(normalized, sizeof(normalized));

    isStock = StrEqual(normalized, STOCK_ROUND_START_SIREN, false);
    replacementIndex = -1;
    if (isStock)
    {
        return true;
    }

    char configuredSample[PLATFORM_MAX_PATH];
    for (int i = 0; i < gReadyRoundStartSirenReplacements.Length; i++)
    {
        gReadyRoundStartSirenReplacements.GetString(
            i,
            configuredSample,
            sizeof(configuredSample)
        );
        NormalizeSoundPath(configuredSample, sizeof(configuredSample));
        if (StrEqual(normalized, configuredSample, false))
        {
            replacementIndex = i;
            return true;
        }
    }

    return false;
}

public Action AnnouncementReplacement_AmbientSoundHook(
    char sample[PLATFORM_MAX_PATH],
    int &entity,
    float &volume,
    int &level,
    int &pitch,
    float pos[3],
    int &flags,
    float &delay)
{
    bool isStock;
    int replacementIndex;
    if (!IdentifyRoundStartSirenSample(sample, isStock, replacementIndex))
    {
        return Plugin_Continue;
    }

    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));
    LogMessage(
        "[SaySounds:SirenTrace] Ambient emission: map %s, sample %s, stock %d, configured index %d, entity %d, level %d, flags %d, volume %.3f, pitch %d, delay %.3f, position %.1f %.1f %.1f, intentional %d, serial %d, assigned index %d, target client %d.",
        currentMap,
        sample,
        isStock,
        replacementIndex,
        entity,
        level,
        flags,
        volume,
        pitch,
        delay,
        pos[0],
        pos[1],
        pos[2],
        g_bEmittingRoundStartSiren,
        g_iEmittingRoundStartSirenSerial,
        g_iEmittingRoundStartSirenIndex,
        g_iEmittingRoundStartSirenClient
    );
    return Plugin_Continue;
}

public Action AnnouncementReplacement_NormalSoundHook(
    int clients[MAXPLAYERS],
    int &numClients,
    char sample[PLATFORM_MAX_PATH],
    int &entity,
    int &channel,
    float &volume,
    int &level,
    int &pitch,
    int &flags,
    char soundEntry[PLATFORM_MAX_PATH],
    int &seed)
{
    bool sirenIsStock;
    int sirenReplacementIndex;
    if (IdentifyRoundStartSirenSample(sample, sirenIsStock, sirenReplacementIndex))
    {
        char currentMap[PLATFORM_MAX_PATH];
        GetCurrentMap(currentMap, sizeof(currentMap));
        LogMessage(
            "[SaySounds:SirenTrace] Normal emission: map %s, sample %s, stock %d, configured index %d, entity %d, channel %d, recipients %d, level %d, flags %d, volume %.3f, pitch %d, sound entry %s, intentional %d, serial %d, assigned index %d, target client %d.",
            currentMap,
            sample,
            sirenIsStock,
            sirenReplacementIndex,
            entity,
            channel,
            numClients,
            level,
            flags,
            volume,
            pitch,
            soundEntry,
            g_bEmittingRoundStartSiren,
            g_iEmittingRoundStartSirenSerial,
            g_iEmittingRoundStartSirenIndex,
            g_iEmittingRoundStartSirenClient
        );
    }

    // StopSound() also passes through the normal-sound hook. Never turn a
    // suppression packet into a new replacement emission.
    if ((flags & SND_STOP) != 0)
    {
        return Plugin_Continue;
    }

    ArrayList replacements;
    ArrayList groups;
    if (IsStockControlPointAnnouncerSample(sample)
        && gReadyAnnouncerMiscReplacements.Length > 0)
    {
        replacements = gReadyAnnouncerMiscReplacements;
        groups = gReadyAnnouncerMiscGroups;
    }
    else if (GetStockCountdownSoundIndex(sample) != -1
        && gReadyCountdownReplacements.Length > 0)
    {
        replacements = gReadyCountdownReplacements;
        groups = gReadyCountdownGroups;
    }
    else
    {
        return Plugin_Continue;
    }

    char replacement[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    if (!GetRandomReadyReplacement(
        replacements,
        groups,
        replacement,
        sizeof(replacement),
        groupName,
        sizeof(groupName)))
    {
        return Plugin_Continue;
    }

    int stockRecipientCount = 0;
    int customRecipientCount = 0;
    for (int i = 0; i < numClients; i++)
    {
        int client = clients[i];
        float clientVolume;
        if (client > 0
            && client <= MaxClients
            && IsClientInGame(client)
            && !IsFakeClient(client)
            && CanPlaySaySoundToClient(client, groupName, clientVolume))
        {
            EmitSoundToClient(
                client,
                replacement,
                entity,
                channel,
                level,
                flags,
                volume * clientVolume,
                pitch
            );
            customRecipientCount++;
            continue;
        }

        clients[stockRecipientCount++] = client;
    }

    if (customRecipientCount == 0)
    {
        return Plugin_Continue;
    }

    numClients = stockRecipientCount;
    return stockRecipientCount == 0 ? Plugin_Stop : Plugin_Changed;
}

public void Event_PointStartCapture(Event event, const char[] name, bool dontBroadcast)
{
    if (gReadyAnnouncerMiscReplacements.Length == 0)
    {
        return;
    }

    int capturingTeam = event.GetInt("capteam");
    if (capturingTeam <= 1)
    {
        capturingTeam = event.GetInt("team");
    }

    if (capturingTeam <= 1)
    {
        return;
    }

    CreateTimer(
        CLIENT_ANNOUNCER_REPLACEMENT_DELAY,
        Timer_ReplaceClientCaptureWarning,
        capturingTeam,
        TIMER_FLAG_NO_MAPCHANGE
    );
}

public void Event_PointUnlocked(Event event, const char[] name, bool dontBroadcast)
{
    int controlPoint = event.GetInt("cp");
    if (controlPoint < 0 || controlPoint >= MAX_TRACKED_CONTROL_POINTS)
    {
        return;
    }

    float now = GetGameTime();
    if (now - g_fLastControlPointUnlockEvent[controlPoint]
        < CONTROL_POINT_UNLOCK_EVENT_DEBOUNCE)
    {
        return;
    }

    g_fLastControlPointUnlockEvent[controlPoint] = now;
    bool needsFallback = gReadyUnlockReplacements.Length > 0
        && !g_bControlPointEnabledReplacementHandled[controlPoint];
    g_fTrackedControlPointUnlockTime[controlPoint] = 0.0;
    g_bControlPointCountdownSuppressed[controlPoint] = false;
    g_iControlPointUnlockArmedMask[controlPoint] = 0;
    g_bControlPointEnabledReplacementHandled[controlPoint] = false;
    if (needsFallback)
    {
        ReplaceControlPointEnabled(controlPoint, true);
    }
}

public Action Timer_ReplaceClientCaptureWarning(Handle timer, any capturingTeam)
{
    char replacement[PLATFORM_MAX_PATH];
    char groupName[MAX_GROUP_NAME];
    if (!GetRandomReadyReplacement(
        gReadyAnnouncerMiscReplacements,
        gReadyAnnouncerMiscGroups,
        replacement,
        sizeof(replacement),
        groupName,
        sizeof(groupName)))
    {
        return Plugin_Stop;
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client)
            || IsFakeClient(client)
            || GetClientTeam(client) <= 1
            || GetClientTeam(client) == capturingTeam)
        {
            continue;
        }

        float emitVolume;
        if (!CanPlaySaySoundToClient(client, groupName, emitVolume))
        {
            continue;
        }

        StopClientCaptureWarningSounds(client);
        EmitSoundToClient(
            client,
            replacement,
            client,
            SNDCHAN_VOICE_BASE,
            SNDLEVEL_NONE,
            SND_NOFLAGS,
            emitVolume
        );
    }

    return Plugin_Stop;
}

bool GetRandomReadyReplacement(
    ArrayList replacements,
    ArrayList groups,
    char[] replacement,
    int replacementLen,
    char[] groupName,
    int groupNameLen)
{
    if (replacements == null || groups == null || replacements.Length == 0)
    {
        return false;
    }

    int index = GetRandomInt(0, replacements.Length - 1);
    replacements.GetString(index, replacement, replacementLen);
    groups.GetString(index, groupName, groupNameLen);
    return replacement[0] != '\0';
}

static bool IsStockControlPointAnnouncerSample(const char[] sample)
{
    static const char stockSamples[][] =
    {
        "vo/announcer_we_secured_control.mp3",
        "vo/announcer_we_captured_control.mp3",
        "vo/announcer_we_lost_control.mp3",
        "vo/announcer_we_captured_center_control.mp3",
        "vo/announcer_we_lost_center_control.mp3",
        "vo/announcer_success_captured_final_control.mp3",
        "vo/announcer_success_captured_last_control.mp3",
        "vo/announcer_success_secured_final_control.mp3",
        "vo/announcer_success_secured_last_control.mp3"
    };

    char normalized[PLATFORM_MAX_PATH];
    strcopy(normalized, sizeof(normalized), sample);
    TrimString(normalized);
    while (normalized[0] != '\0' && !IsAsciiAlphaNumeric(normalized[0]))
    {
        Strings_ShiftLeft(normalized, sizeof(normalized), 1);
    }
    NormalizeSoundPath(normalized, sizeof(normalized));
    Strings_ToLower(normalized, sizeof(normalized));

    for (int i = 0; i < sizeof(stockSamples); i++)
    {
        if (StrEqual(normalized, stockSamples[i]))
        {
            return true;
        }
    }

    return false;
}

bool IsAsciiAlphaNumeric(int character)
{
    return (character >= 'a' && character <= 'z')
        || (character >= 'A' && character <= 'Z')
        || (character >= '0' && character <= '9');
}

static void StopClientCaptureWarningSounds(int client)
{
    static const char stockSamples[][] =
    {
        "vo/announcer_control_point_warning.mp3",
        "vo/announcer_control_point_warning2.mp3",
        "vo/announcer_control_point_warning3.mp3",
        "vo/announcer_last_flag.mp3",
        "vo/announcer_last_flag2.mp3"
    };

    for (int i = 0; i < sizeof(stockSamples); i++)
    {
        StopSound(client, SNDCHAN_VOICE_BASE, stockSamples[i]);
    }
}

