stock bool DGM_GetGameMode(char[] buffer, int maxlen)
{
    return DGM_CopyCurrentGameMode(buffer, maxlen);
}

stock int DGM_RealPlayerCount()
{
    return DGM_CountRealPlayers();
}

stock int DGM_RealTeamPlayerCount(int team)
{
    return DGM_CountRealTeamPlayers(team);
}

stock bool DGM_GetGameModeKey(char[] buffer, int maxlen)
{
    return DGM_CopyCurrentGameModeKey(buffer, maxlen);
}

stock bool DGM_GetGameModeKeyForMap(const char[] mapName, char[] buffer, int maxlen)
{
    char normalized[PLATFORM_MAX_PATH];
    if (DGM_CopyNormalizedMapName(mapName, normalized, sizeof(normalized)))
    {
        DGM_CopyGameModeKeyForMap(normalized, buffer, maxlen);
    }
    else
    {
        DGM_CopyGameModeKeyForMap(mapName, buffer, maxlen);
    }
    return buffer[0] != '\0';
}

stock bool DGM_IsSmallFormatGamemode()
{
    return DGM_CheckSmallFormatGamemode();
}

stock bool DGM_NormalizeMapName(const char[] input, char[] output, int maxlen)
{
    return DGM_CopyNormalizedMapName(input, output, maxlen);
}

stock bool DGM_CurrentNormalizedMap(char[] buffer, int maxlen)
{
    return DGM_CopyCurrentNormalizedMapName(buffer, maxlen);
}

stock int DGM_GetServerCapacity()
{
    return DGM_GetServerCapacityValue();
}

stock float DGM_GetPopulationRatio()
{
    return DGM_GetPopulationRatioValue();
}

stock bool DGM_ServerCapacitycheck(float capacityRatio = 0.50, bool inGameOnly = true)
{
    return DGM_CheckServerCapacity(capacityRatio, inGameOnly);
}

stock bool DGM_TeamsGameplayReady()
{
    return DGM_AreTeamsGameplayReady();
}

stock bool DGM_IsRoundRunning()
{
    return DGM_InternalIsRoundRunning();
}

stock bool DGM_IsSetupActive()
{
    return DGM_IsRealSetupActive();
}

stock int DGM_GetLastRoundDurationSeconds()
{
    return g_iLastRoundDuration;
}

stock int DGM_GetRoundDurationSeconds(int firstTimestamp, int secondTimestamp)
{
    return DGM_CalculateRoundDurationSeconds(firstTimestamp, secondTimestamp);
}

stock int DGM_GetRecentControlPointCaptureIntervalSeconds()
{
    return DGM_GetRecentCaptureIntervalSeconds();
}

stock float DGM_GetRoundTimeRemaining()
{
    return DGM_GetHudRoundTimerRemaining();
}

stock DGMObjectiveLeader DGM_GetObjectiveLeader(
    int &redOwned,
    int &blueOwned,
    int &neutralOwned,
    int &total)
{
    return DGM_GetObjectiveLeaderValue(redOwned, blueOwned, neutralOwned, total);
}

stock int DGM_GetObjectiveLeaderTeam()
{
    return DGM_GetObjectiveLeaderTeamValue();
}

stock bool DGM_SetTime(int seconds)
{
    return DGM_ChangeRoundTimerTime(seconds, false);
}

stock bool DGM_AddTime(int seconds)
{
    return DGM_ChangeRoundTimerTime(seconds, true);
}
