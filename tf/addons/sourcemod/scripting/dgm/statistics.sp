int DGM_CalculateRoundDurationSeconds(int firstTimestamp, int secondTimestamp)
{
    if (firstTimestamp <= 0 || secondTimestamp <= firstTimestamp)
    {
        return 0;
    }

    return secondTimestamp - firstTimestamp;
}

void DGM_ResetCaptureIntervalStats(int startTimestamp)
{
    g_iLastCaptureTimestamp = startTimestamp;
    g_iCaptureIntervalCount = 0;
}

int DGM_GetRecentCaptureIntervalSeconds()
{
    if (DGM_GetCurrentControlPointCount() <= 2 || g_iCaptureIntervalCount <= 0)
    {
        return 0;
    }

    return g_iCaptureIntervalSeconds[g_iCaptureIntervalCount - 1];
}

void DGM_RecordCaptureInterval(Event event)
{
    if (g_iCaptureIntervalCount >= DGM_MAX_CAPTURE_INTERVALS)
    {
        return;
    }

    int now = GetTime();
    int previousTimestamp = g_iLastCaptureTimestamp;
    if (previousTimestamp <= 0)
    {
        previousTimestamp = g_iRoundStartTimestamp;
    }

    int interval = DGM_CalculateRoundDurationSeconds(previousTimestamp, now);
    int roundElapsed = DGM_CalculateRoundDurationSeconds(g_iRoundStartTimestamp, now);
    int index = g_iCaptureIntervalCount++;

    g_iCaptureIntervalSeconds[index] = interval;
    g_iCaptureRoundElapsedSeconds[index] = roundElapsed;
    g_iCaptureTeam[index] = event.GetInt("team");
    g_iCapturePoint[index] = event.GetInt("cp");
    g_iLastCaptureTimestamp = now;
}

void DGM_LogCaptureIntervalStats(int winnerTeam, int roundDuration)
{
    for (int i = 0; i < g_iCaptureIntervalCount; i++)
    {
        char message[384];
        Format(message, sizeof(message),
            "event=control_point_capture_interval|winner_team=%d|capture_team=%d|capture_point=%d|capture_sequence=%d|capture_count=%d|interval_seconds=%d|round_elapsed_seconds=%d|round_duration_seconds=%d|real_players=%d",
            winnerTeam,
            g_iCaptureTeam[i],
            g_iCapturePoint[i],
            i + 1,
            g_iCaptureIntervalCount,
            g_iCaptureIntervalSeconds[i],
            g_iCaptureRoundElapsedSeconds[i],
            roundDuration,
            DGM_CountRealPlayers());
        PluginStats_Record("control_point_capture_interval", message);
    }
}

void DGM_SanitizeStatsField(char[] value, int maxlen)
{
    ReplaceString(value, maxlen, "|", "/");
    ReplaceString(value, maxlen, "\"", "'");
    ReplaceString(value, maxlen, "\n", " ");
    ReplaceString(value, maxlen, "\r", " ");
}

void DGM_LogRespawnToggle(int client, bool forcedOn, float respawnTime)
{
    char steamId64[32];
    char adminName[MAX_NAME_LENGTH];
    int userId = 0;

    strcopy(steamId64, sizeof(steamId64), "console");
    strcopy(adminName, sizeof(adminName), "console");

    if (client > 0 && IsClientInGame(client))
    {
        userId = GetClientUserId(client);
        GetClientName(client, adminName, sizeof(adminName));

        if (!GetClientAuthId(client, AuthId_SteamID64, steamId64, sizeof(steamId64), true))
        {
            strcopy(steamId64, sizeof(steamId64), "unknown");
        }
    }

    DGM_SanitizeStatsField(adminName, sizeof(adminName));

    char message[384];
    Format(message, sizeof(message),
        "event=respawn_toggle|time=%d|client=%d|userid=%d|steamid64=%s|name=\"%s\"|toggle_value=%d|respawn_time=%.2f|real_players=%d",
        GetTime(),
        client,
        userId,
        steamId64,
        adminName,
        forcedOn ? 1 : 0,
        respawnTime,
        DGM_CountRealPlayers());
    PluginStats_Record("respawn_toggle", message);
}

