#if defined _public_activity_included
 #endinput
#endif
#define _public_activity_included

// Shared by public chat, presence, and announcements. One SteamID64 per line;
// the real account list belongs in the server config, never in source control.
static StringMap g_PublicActivityExclusions;
static float g_PublicActivityNextRead;

stock void PublicActivity_Refresh()
{
    float now = GetEngineTime();
    if (g_PublicActivityExclusions != null && now < g_PublicActivityNextRead) return;
    g_PublicActivityNextRead = now + 10.0;
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/public_activity_exclusions.txt");
    File file = OpenFile(path, "r");
    if (file == null)
    {
        if (g_PublicActivityExclusions == null) g_PublicActivityExclusions = new StringMap();
        return; // Keep the last valid list if a replacement is temporarily unreadable.
    }
    StringMap next = new StringMap();
    char line[128];
    while (file.ReadLine(line, sizeof(line)))
    {
        TrimString(line);
        if (strlen(line) != 17) continue;
        bool valid = true;
        for (int i = 0; i < 17; i++) if (line[i] < '0' || line[i] > '9') { valid = false; break; }
        if (valid) next.SetValue(line, 1);
    }
    delete file;
    delete g_PublicActivityExclusions;
    g_PublicActivityExclusions = next;
}

stock bool PublicActivity_IsExcludedSteam(const char[] steamId64)
{
    PublicActivity_Refresh();
    int value;
    return g_PublicActivityExclusions.GetValue(steamId64, value);
}

stock bool PublicActivity_IsExcluded(int client)
{
    if (client <= 0 || client > MaxClients || !IsClientConnected(client) || IsFakeClient(client)) return false;
    char steamId64[32];
    return GetClientAuthId(client, AuthId_SteamID64, steamId64, sizeof(steamId64))
        && PublicActivity_IsExcludedSteam(steamId64);
}

stock bool PublicActivity_IsPairExcluded(int first, int second)
{
    return PublicActivity_IsExcluded(first) || PublicActivity_IsExcluded(second);
}
