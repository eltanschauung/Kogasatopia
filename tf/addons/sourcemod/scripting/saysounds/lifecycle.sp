public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int errlen)
{
    MarkNativeAsOptional(POINTS_STORE_HAS_PURCHASE_NATIVE);
    MarkNativeAsOptional("DGM_CurrentNormalizedMap");
    MarkNativeAsOptional("DGM_NormalizeMapName");
    MarkNativeAsOptional("DGM_GetGameModeKey");
    MarkNativeAsOptional("Filters_GetSteamIdColorTag");
    RegPluginLibrary("saysounds");
    CreateNative("SaySounds_ShouldPlay", Native_ShouldPlay);
    CreateNative("SaySounds_PlaySoundToOptedIn", Native_PlaySoundToOptedIn);
    CreateNative("SaySounds_PlayCommand", Native_PlayCommand);
    CreateNative("SaySounds_PlayCommandAs", Native_PlayCommandAs);
    CreateNative("SaySounds_CanClientUseCommand", Native_CanClientUseCommand);
    CreateNative("SaySounds_IsCommandPaid", Native_IsCommandPaid);
    CreateNative("SaySounds_GetCommandGroup", Native_GetCommandGroup);
    return APLRes_Success;
}

public void OnPluginStart()
{
    gSoundMap = new StringMap();
    gSoundGroupMap = new StringMap();
    gAPIOnlyGroups = new StringMap();
    gForcedSoundGroups = new StringMap();
    gPaidSaysoundGroups = new StringMap();
    gGroupAliases = new StringMap();
    gCommandNames = new ArrayList(ByteCountToCells(MAX_COMMAND_NAME));
    gGroupNames = new ArrayList(ByteCountToCells(MAX_GROUP_NAME));
    gRoundStartSirenReplacements = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    gRoundStartSirenGroups = new ArrayList(ByteCountToCells(MAX_GROUP_NAME));
    gReadyRoundStartSirenReplacements = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    gReadyRoundStartSirenGroups = new ArrayList(ByteCountToCells(MAX_GROUP_NAME));
    gRoundWinReplacements = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    gRoundWinGroups = new ArrayList(ByteCountToCells(MAX_GROUP_NAME));
    gReadyRoundWinReplacements = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    gReadyRoundWinGroups = new ArrayList(ByteCountToCells(MAX_GROUP_NAME));
    gRoundLoseReplacements = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    gRoundLoseGroups = new ArrayList(ByteCountToCells(MAX_GROUP_NAME));
    gReadyRoundLoseReplacements = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    gReadyRoundLoseGroups = new ArrayList(ByteCountToCells(MAX_GROUP_NAME));
    gAnnouncerMiscReplacements = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    gAnnouncerMiscGroups = new ArrayList(ByteCountToCells(MAX_GROUP_NAME));
    gReadyAnnouncerMiscReplacements = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    gReadyAnnouncerMiscGroups = new ArrayList(ByteCountToCells(MAX_GROUP_NAME));
    gCountdownReplacements = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    gCountdownGroups = new ArrayList(ByteCountToCells(MAX_GROUP_NAME));
    gReadyCountdownReplacements = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    gReadyCountdownGroups = new ArrayList(ByteCountToCells(MAX_GROUP_NAME));
    gUnlockReplacements = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    gUnlockGroups = new ArrayList(ByteCountToCells(MAX_GROUP_NAME));
    gReadyUnlockReplacements = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    gReadyUnlockGroups = new ArrayList(ByteCountToCells(MAX_GROUP_NAME));

    g_hForce = CreateConVar("saysounds_force", "0", "Force everyone to hear saysounds");
    g_hForcedGroups = CreateConVar(
        "sm_saysounds_forced_groups",
        "",
        "Comma-separated saysound groups that ignore client opt-out preferences."
    );
    HookConVarChange(g_hForcedGroups, ConVar_ForcedGroupsChanged);
    g_hDefaultDeathSound = CreateConVar("saysounds_default_death_sound", "doh", "Saysound command/group used when a victim has no death sound set and the attacker has no kill sound.");
    g_hDefaultVolume = CreateConVar("saysounds_default_volume", "0.5", "Default saysound volume for clients with no saved volume preference.", _, true, MIN_VOLUME, true, MAX_VOLUME);
    g_hVolumeCookie = RegClientCookie("saysounds_volume", "Preferred say sound volume", CookieAccess_Public);
    g_hDeathCookie = RegClientCookie("saysounds_death", "Preferred saysound on death", CookieAccess_Public);
    g_hKillCookie = RegClientCookie("saysounds_kill", "Preferred saysound on kill", CookieAccess_Public);
    g_hDisabledGroupsCookie = RegClientCookie("saysounds_disabled_groups", "Disabled saysound groups", CookieAccess_Public);
    RegConsoleCmd("sm_opt", Command_ToggleSoundOpt);
    RegConsoleCmd("sm_optlist", Command_ListOptedInClients);
    RegConsoleCmd("sm_opts", Command_ShowGroupOptions);
    RegConsoleCmd("sm_touhouonly", Command_TouhouOnly);
    RegConsoleCmd("sm_sounds", Command_ListSounds);
    RegConsoleCmd("sm_saysounds", Command_ListSounds);
    RegConsoleCmd("sm_groups", Command_ListGroups);
    RegAdminCmd("sm_soundgroups", Command_ListGroups, 0, "Lists SaySound groups.");
    RegAdminCmd("sm_saysoundgroups", Command_ListGroups, 0, "Lists SaySound groups.");
    RegConsoleCmd("sm_vol", Command_SetVolume);
    RegConsoleCmd("sm_diesounds", Command_ShowDeathSoundsMenu);
    RegConsoleCmd("sm_deathsounds", Command_ShowDeathSoundsMenu);
    RegConsoleCmd("sm_killsounds", Command_ShowKillSoundsMenu);
    RegConsoleCmd("sm_diesound", Command_SetDeathSound);
    RegConsoleCmd("sm_deathsound", Command_SetDeathSound);
    RegConsoleCmd("sm_killsound", Command_SetKillSound);
    RegConsoleCmd("sm_saysound", Command_PlaySpecificSound);
    LoadSaySoundConfig();
    AddCommandListener(ChatCommandListener, "say");
    AddCommandListener(ChatCommandListener, "say_team");
    HookEvent("player_death", Event_PlayerDeathPost, EventHookMode_Post);
    HookEvent("teamplay_broadcast_audio", Event_BroadcastAudio, EventHookMode_Pre);
    HookEvent("teamplay_point_startcapture", Event_PointStartCapture, EventHookMode_Post);
    HookEvent("teamplay_point_unlocked", Event_PointUnlocked, EventHookMode_Post);
    AddNormalSoundHook(AnnouncementReplacement_NormalSoundHook);
    gNormalSoundHookAdded = true;
    AddAmbientSoundHook(AnnouncementReplacement_AmbientSoundHook);
    gAmbientSoundHookAdded = true;
    SaySounds_StartCountdownMonitor();
    for (int client = 1; client <= MaxClients; client++)
    {
        SaySounds_ResetClientPreferences(client);
        if (IsClientInGame(client) && AreClientCookiesCached(client))
        {
            OnClientCookiesCached(client);
        }
    }
}

void SaySounds_StartCountdownMonitor()
{
    if (g_hCountdownMonitorTimer == null)
    {
        // Explicitly owned across maps; OnMapEnd cancels before entities disappear.
        g_hCountdownMonitorTimer = CreateTimer(COUNTDOWN_MONITOR_INTERVAL,
            Timer_MonitorCountdowns, _, TIMER_REPEAT);
    }
}

public void OnPluginEnd()
{
    CancelCountdownMonitorTimer();
    CancelRoundStartSirenTimers();
    RestoreTrackedSetupAutoCountdown();
    RestoreTrackedLiveAutoCountdown();
    if (gNormalSoundHookAdded)
    {
        RemoveNormalSoundHook(AnnouncementReplacement_NormalSoundHook);
        gNormalSoundHookAdded = false;
    }
    if (gAmbientSoundHookAdded)
    {
        RemoveAmbientSoundHook(AnnouncementReplacement_AmbientSoundHook);
        gAmbientSoundHookAdded = false;
    }
    delete gSoundMap;
    gSoundMap = null;
    delete gSoundGroupMap;
    gSoundGroupMap = null;
    delete gAPIOnlyGroups;
    gAPIOnlyGroups = null;
    delete gForcedSoundGroups;
    gForcedSoundGroups = null;
    delete gPaidSaysoundGroups;
    gPaidSaysoundGroups = null;
    delete gGroupAliases;
    gGroupAliases = null;
    delete gCommandNames;
    gCommandNames = null;
    delete gGroupNames;
    gGroupNames = null;
    delete gRoundStartSirenReplacements;
    gRoundStartSirenReplacements = null;
    delete gRoundStartSirenGroups;
    gRoundStartSirenGroups = null;
    delete gReadyRoundStartSirenReplacements;
    gReadyRoundStartSirenReplacements = null;
    delete gReadyRoundStartSirenGroups;
    gReadyRoundStartSirenGroups = null;
    delete gRoundWinReplacements;
    gRoundWinReplacements = null;
    delete gRoundWinGroups;
    gRoundWinGroups = null;
    delete gReadyRoundWinReplacements;
    gReadyRoundWinReplacements = null;
    delete gReadyRoundWinGroups;
    gReadyRoundWinGroups = null;
    delete gRoundLoseReplacements;
    gRoundLoseReplacements = null;
    delete gRoundLoseGroups;
    gRoundLoseGroups = null;
    delete gReadyRoundLoseReplacements;
    gReadyRoundLoseReplacements = null;
    delete gReadyRoundLoseGroups;
    gReadyRoundLoseGroups = null;
    delete gAnnouncerMiscReplacements;
    gAnnouncerMiscReplacements = null;
    delete gAnnouncerMiscGroups;
    gAnnouncerMiscGroups = null;
    delete gReadyAnnouncerMiscReplacements;
    gReadyAnnouncerMiscReplacements = null;
    delete gReadyAnnouncerMiscGroups;
    gReadyAnnouncerMiscGroups = null;
    delete gCountdownReplacements;
    gCountdownReplacements = null;
    delete gCountdownGroups;
    gCountdownGroups = null;
    delete gReadyCountdownReplacements;
    gReadyCountdownReplacements = null;
    delete gReadyCountdownGroups;
    gReadyCountdownGroups = null;
    delete gUnlockReplacements;
    gUnlockReplacements = null;
    delete gUnlockGroups;
    gUnlockGroups = null;
    delete gReadyUnlockReplacements;
    gReadyUnlockReplacements = null;
    delete gReadyUnlockGroups;
    gReadyUnlockGroups = null;
    for (int client = 1; client <= MaxClients; client++)
    {
        delete g_hClientDisabledGroups[client];
        g_hClientDisabledGroups[client] = null;
    }
}

void SaySounds_ResetClientPreferences(int client)
{
    g_fClientVolume[client] = GetDefaultVolume();
    g_fNextAllowedSound[client] = 0.0;
    g_szDeathSound[client][0] = '\0';
    g_szKillSound[client][0] = '\0';
    ResetClientDisabledGroups(client);
}

public void OnClientPutInServer(int client)
{
    SaySounds_ResetClientPreferences(client);
    if (AreClientCookiesCached(client))
    {
        OnClientCookiesCached(client);
    }
}

public void OnClientCookiesCached(int client)
{
    LoadVolumePreference(client);
    LoadDeathSoundPreference(client);
    LoadKillSoundPreference(client);
    LoadDisabledGroupPreferences(client);
}

public void OnClientDisconnect(int client)
{
    SaveVolumePreference(client);
    SaveDeathSoundPreference(client);
    SaveKillSoundPreference(client);
    SaveDisabledGroupPreferences(client);
    SaySounds_ResetClientPreferences(client);
}

public void OnConfigsExecuted()
{
    LoadSaySoundConfig();
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && AreClientCookiesCached(client))
        {
            LoadDisabledGroupPreferences(client);
        }
    }
    PrecacheConfiguredSounds();
}

public void OnMapStart()
{
    CancelRoundStartSirenTimers();
    // Restore owned network overrides before dropping their entity references.
    CancelCountdownMonitorTimer();
    ResetRoundStartSirenTracking();
    ResetRoundResultPairing();
    g_fLastRoundStartSirenTime = -9999.0;
    PrecacheConfiguredSounds();
    SaySounds_StartCountdownMonitor();
}

public void OnMapEnd()
{
    CancelCountdownMonitorTimer();
    CancelRoundStartSirenTimers();
    ResetRoundStartSirenTracking();
    ResetRoundResultPairing();
}
