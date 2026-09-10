static void CopyStatsField(const char[] input, char[] output, int maxlen)
{
    int pos = 0;
    for (int i = 0; input[i] != '\0' && pos < maxlen - 1; i++)
    {
        char c = input[i];
        if (c == '|' || c == '\n' || c == '\r' || c == '\t')
        {
            c = ' ';
        }
        output[pos++] = c;
    }
    output[pos] = '\0';
    TrimString(output);
}

void LogSaySoundUsage(const char[] eventName, int sourceClient, int targetClient, const char[] selectedCommand, const char[] soundPath, const char[] groupName, bool fromGroup, const char[] sourceGroup, bool fromApi, const char[] source)
{
    if (!ShouldLogSaySoundUsage())
    {
        return;
    }

    char steamId[KOGASA_STEAMID_MAX];
    if (!Kogasa_GetClientSteamId64(sourceClient, steamId, sizeof(steamId), false))
    {
        steamId[0] = '\0';
    }

    char safeCommand[MAX_COMMAND_NAME];
    char safePath[PLATFORM_MAX_PATH];
    char safeGroup[MAX_GROUP_NAME];
    char safeSourceGroup[MAX_GROUP_NAME];
    char safeSource[32];
    CopyStatsField(selectedCommand, safeCommand, sizeof(safeCommand));
    CopyStatsField(soundPath, safePath, sizeof(safePath));
    CopyStatsField(groupName, safeGroup, sizeof(safeGroup));
    CopyStatsField(sourceGroup, safeSourceGroup, sizeof(safeSourceGroup));
    CopyStatsField(source, safeSource, sizeof(safeSource));

    char message[512];
    Format(message, sizeof(message),
        "event=%s|steamid64=%s|client=%d|userid=%d|target_client=%d|sound=%s|path=%s|group=%s|from_group=%d|source_group=%s|from_api=%d|source=%s",
        eventName,
        steamId,
        sourceClient,
        (sourceClient > 0 && sourceClient <= MaxClients) ? GetClientUserId(sourceClient) : 0,
        targetClient,
        safeCommand,
        safePath,
        safeGroup,
        fromGroup ? 1 : 0,
        safeSourceGroup,
        fromApi ? 1 : 0,
        safeSource);
    PluginStats_Record(eventName, message);
}

static bool ShouldLogSaySoundUsage()
{
    g_iSaySoundStatsCounter++;
    if (g_iSaySoundStatsCounter >= SAYSOUNDS_STATS_SAMPLE_RATE)
    {
        g_iSaySoundStatsCounter = 0;
        return true;
    }

    return false;
}

void LogSoundPreferenceChange(int client, SaySoundPreferenceType type, const char[] value)
{
    char steamId[KOGASA_STEAMID_MAX];
    if (!Kogasa_GetClientSteamId64(client, steamId, sizeof(steamId), false))
    {
        steamId[0] = '\0';
    }

    char safeValue[MAX_COMMAND_NAME * 4];
    CopyStatsField(value, safeValue, sizeof(safeValue));

    char message[384];
    Format(message, sizeof(message),
        "event=%s|steamid64=%s|client=%d|userid=%d|value=%s|cleared=%d",
        type == SaySoundPreference_Death ? "diesound_preference_changed" : "killsound_preference_changed",
        steamId,
        client,
        GetClientUserId(client),
        safeValue,
        safeValue[0] ? 0 : 1);
    PluginStats_Record(
        type == SaySoundPreference_Death
            ? "diesound_preference_changed"
            : "killsound_preference_changed",
        message);
}

