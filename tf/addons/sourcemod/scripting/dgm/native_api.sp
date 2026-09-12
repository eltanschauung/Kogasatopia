public any Native_DGM_GetGameMode(Handle plugin, int numParams)
{
    char gamemode[64];
    bool hasGamemode = DGM_CopyCurrentGameMode(gamemode, sizeof(gamemode));
    SetNativeString(1, gamemode, GetNativeCell(2), true);
    return hasGamemode;
}

public any Native_DGM_RealPlayerCount(Handle plugin, int numParams)
{
    return DGM_CountRealPlayers();
}

public any Native_DGM_GetGameModeKey(Handle plugin, int numParams)
{
    char gamemodeKey[32];
    bool hasGamemodeKey = DGM_CopyCurrentGameModeKey(gamemodeKey, sizeof(gamemodeKey));
    SetNativeString(1, gamemodeKey, GetNativeCell(2), true);
    return hasGamemodeKey;
}

public any Native_DGM_IsSmallFormatGamemode(Handle plugin, int numParams)
{
    return DGM_CheckSmallFormatGamemode();
}

public any Native_DGM_NormalizeMapName(Handle plugin, int numParams)
{
    char input[PLATFORM_MAX_PATH];
    char output[PLATFORM_MAX_PATH];
    GetNativeString(1, input, sizeof(input));
    bool hasMapName = DGM_CopyNormalizedMapName(input, output, sizeof(output));
    SetNativeString(2, output, GetNativeCell(3), true);
    return hasMapName;
}

public any Native_DGM_ServerCapacitycheck(Handle plugin, int numParams)
{
    float capacityRatio = 0.50;
    bool inGameOnly = true;
    if (numParams >= 1)
    {
        capacityRatio = view_as<float>(GetNativeCell(1));
    }
    if (numParams >= 2)
    {
        inGameOnly = view_as<bool>(GetNativeCell(2));
    }

    return DGM_CheckServerCapacity(capacityRatio, inGameOnly);
}

public any Native_DGM_TeamsGameplayReady(Handle plugin, int numParams)
{
    return DGM_AreTeamsGameplayReady();
}

public any Native_DGM_RealTeamPlayerCount(Handle plugin, int numParams)
{
    int team = GetNativeCell(1);
    return DGM_CountRealTeamPlayers(team);
}

public any Native_DGM_GetObjectiveLeader(Handle plugin, int numParams)
{
    int redOwned, blueOwned, neutralOwned, total;
    DGMObjectiveLeader leader = DGM_GetObjectiveLeaderValue(redOwned, blueOwned, neutralOwned, total);

    SetNativeCellRef(1, redOwned);
    SetNativeCellRef(2, blueOwned);
    SetNativeCellRef(3, neutralOwned);
    SetNativeCellRef(4, total);

    return view_as<any>(leader);
}

public any Native_DGM_GetObjectiveLeaderTeam(Handle plugin, int numParams)
{
    return DGM_GetObjectiveLeaderTeamValue();
}

public any Native_DGM_GetGameModeKeyForMap(Handle plugin, int numParams)
{
    char input[PLATFORM_MAX_PATH];
    char normalized[PLATFORM_MAX_PATH];
    char gamemodeKey[32];
    GetNativeString(1, input, sizeof(input));
    bool hasMapName = DGM_CopyNormalizedMapName(input, normalized, sizeof(normalized));
    if (hasMapName)
    {
        DGM_CopyGameModeKeyForMap(normalized, gamemodeKey, sizeof(gamemodeKey));
    }
    else
    {
        DGM_CopyGameModeKeyForMap(input, gamemodeKey, sizeof(gamemodeKey));
    }
    SetNativeString(2, gamemodeKey, GetNativeCell(3), true);
    return gamemodeKey[0] != '\0';
}

public any Native_DGM_CurrentNormalizedMap(Handle plugin, int numParams)
{
    char mapName[PLATFORM_MAX_PATH];
    bool hasMapName = DGM_CopyCurrentNormalizedMapName(mapName, sizeof(mapName));
    SetNativeString(1, mapName, GetNativeCell(2), true);
    return hasMapName;
}

public any Native_DGM_GetServerCapacity(Handle plugin, int numParams)
{
    return DGM_GetServerCapacityValue();
}

public any Native_DGM_GetPopulationRatio(Handle plugin, int numParams)
{
    return view_as<any>(DGM_GetPopulationRatioValue());
}

public any Native_DGM_IsRoundRunning(Handle plugin, int numParams)
{
    return DGM_InternalIsRoundRunning();
}

public any Native_DGM_IsSetupActive(Handle plugin, int numParams)
{
    return DGM_IsRealSetupActive();
}

public any Native_DGM_GetLastRoundDurationSeconds(Handle plugin, int numParams)
{
    return g_iLastRoundDuration;
}

public any Native_DGM_GetRoundDurationSeconds(Handle plugin, int numParams)
{
    int firstTimestamp = GetNativeCell(1);
    int secondTimestamp = GetNativeCell(2);
    return DGM_CalculateRoundDurationSeconds(firstTimestamp, secondTimestamp);
}

public any Native_DGM_GetRecentControlPointCaptureIntervalSeconds(Handle plugin, int numParams)
{
    return DGM_GetRecentCaptureIntervalSeconds();
}

public any Native_DGM_SetTime(Handle plugin, int numParams)
{
    return DGM_ChangeRoundTimerTime(GetNativeCell(1), false);
}

public any Native_DGM_AddTime(Handle plugin, int numParams)
{
    return DGM_ChangeRoundTimerTime(GetNativeCell(1), true);
}

public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int errMax)
{
    MarkNativeAsOptional("TF2SetupUber_SetMultiplier");
    MarkNativeAsOptional("TF2SetupUber_IsAvailable");
    MarkNativeAsOptional("TF2_IsSetupTimeActive");
    RegPluginLibrary("dgm");
    g_hSetupTeamRatioReadyForward = new GlobalForward(
        "DGM_OnSetupTeamRatioReady",
        ET_Ignore,
        Param_Cell,
        Param_Cell);
    CreateNative("DGM_GetGameMode", Native_DGM_GetGameMode);
    CreateNative("DGM_RealPlayerCount", Native_DGM_RealPlayerCount);
    CreateNative("DGM_RealTeamPlayerCount", Native_DGM_RealTeamPlayerCount);
    CreateNative("DGM_GetGameModeKey", Native_DGM_GetGameModeKey);
    CreateNative("DGM_GetGameModeKeyForMap", Native_DGM_GetGameModeKeyForMap);
    CreateNative("DGM_IsSmallFormatGamemode", Native_DGM_IsSmallFormatGamemode);
    CreateNative("DGM_NormalizeMapName", Native_DGM_NormalizeMapName);
    CreateNative("DGM_CurrentNormalizedMap", Native_DGM_CurrentNormalizedMap);
    CreateNative("DGM_GetServerCapacity", Native_DGM_GetServerCapacity);
    CreateNative("DGM_GetPopulationRatio", Native_DGM_GetPopulationRatio);
    CreateNative("DGM_ServerCapacitycheck", Native_DGM_ServerCapacitycheck);
    CreateNative("DGM_TeamsGameplayReady", Native_DGM_TeamsGameplayReady);
    CreateNative("DGM_IsRoundRunning", Native_DGM_IsRoundRunning);
    CreateNative("DGM_IsSetupActive", Native_DGM_IsSetupActive);
    CreateNative("DGM_GetLastRoundDurationSeconds", Native_DGM_GetLastRoundDurationSeconds);
    CreateNative("DGM_GetRoundDurationSeconds", Native_DGM_GetRoundDurationSeconds);
    CreateNative("DGM_GetRecentControlPointCaptureIntervalSeconds", Native_DGM_GetRecentControlPointCaptureIntervalSeconds);
    CreateNative("DGM_GetObjectiveLeader", Native_DGM_GetObjectiveLeader);
    CreateNative("DGM_GetObjectiveLeaderTeam", Native_DGM_GetObjectiveLeaderTeam);
    CreateNative("DGM_SetTime", Native_DGM_SetTime);
    CreateNative("DGM_AddTime", Native_DGM_AddTime);
    return APLRes_Success;
}
