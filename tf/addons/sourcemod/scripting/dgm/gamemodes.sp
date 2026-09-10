bool DGM_CopyGameModeNameToKey(const char[] gamemode, char[] buffer, int maxlen)
{
    if (StrEqual(gamemode, "Arena", false))
    {
        strcopy(buffer, maxlen, "arena");
        return true;
    }
    if (StrEqual(gamemode, "Medieval", false))
    {
        strcopy(buffer, maxlen, "medieval");
        return true;
    }
    if (StrEqual(gamemode, "Player Destruction", false))
    {
        strcopy(buffer, maxlen, "pd");
        return true;
    }
    if (StrEqual(gamemode, "King of the Hill", false))
    {
        strcopy(buffer, maxlen, "koth");
        return true;
    }
    if (StrEqual(gamemode, "Payload", false))
    {
        strcopy(buffer, maxlen, "pl");
        return true;
    }
    if (StrEqual(gamemode, "Payload Race", false))
    {
        strcopy(buffer, maxlen, "plr");
        return true;
    }
    if (StrEqual(gamemode, "Capture the Flag", false))
    {
        strcopy(buffer, maxlen, "ctf");
        return true;
    }
    if (StrEqual(gamemode, "5 Control Points", false))
    {
        strcopy(buffer, maxlen, "5cp");
        return true;
    }
    if (StrEqual(gamemode, "Attack/Defend CP", false)
        || StrEqual(gamemode, "Attack/Defend", false))
    {
        strcopy(buffer, maxlen, "ad");
        return true;
    }
    if (StrEqual(gamemode, "Territorial Control", false))
    {
        strcopy(buffer, maxlen, "tc");
        return true;
    }
    if (StrEqual(gamemode, "Default", false))
    {
        strcopy(buffer, maxlen, "default");
        return true;
    }
    if (StrEqual(gamemode, "vsh", false)
        || StrEqual(gamemode, "ultiduo", false)
        || StrEqual(gamemode, "mge", false))
    {
        strcopy(buffer, maxlen, gamemode);
        return true;
    }

    return false;
}

void DGM_CopyGameModeKeyForMap(const char[] mapName, char[] buffer, int maxlen)
{
    strcopy(buffer, maxlen, "default");

    if (StrContains(mapName, "ctf_", false) == 0)
    {
        strcopy(buffer, maxlen, "ctf");
        return;
    }
    if (StrContains(mapName, "cp_", false) == 0)
    {
        strcopy(buffer, maxlen, "cp");
        return;
    }
    if (StrContains(mapName, "pl_", false) == 0)
    {
        strcopy(buffer, maxlen, "pl");
        return;
    }
    if (StrContains(mapName, "plr_", false) == 0)
    {
        strcopy(buffer, maxlen, "plr");
        return;
    }
    if (StrContains(mapName, "koth_", false) == 0)
    {
        strcopy(buffer, maxlen, "koth");
        return;
    }
    if (StrContains(mapName, "pd_", false) == 0)
    {
        strcopy(buffer, maxlen, "pd");
        return;
    }
    if (StrContains(mapName, "sd_", false) == 0)
    {
        strcopy(buffer, maxlen, "sd");
        return;
    }
    if (StrContains(mapName, "arena_", false) == 0)
    {
        strcopy(buffer, maxlen, "arena");
        return;
    }
    if (StrContains(mapName, "vsh_", false) == 0)
    {
        strcopy(buffer, maxlen, "vsh");
        return;
    }
    if (StrContains(mapName, "ultiduo_", false) == 0)
    {
        strcopy(buffer, maxlen, "ultiduo");
        return;
    }
    if (StrContains(mapName, "mge_", false) == 0)
    {
        strcopy(buffer, maxlen, "mge");
        return;
    }
    if (StrContains(mapName, "mvm_", false) == 0)
    {
        strcopy(buffer, maxlen, "mvm");
        return;
    }
}

bool DGM_CopyNormalizedMapName(const char[] input, char[] output, int outputLen)
{
    if (outputLen <= 0)
    {
        return false;
    }

    strcopy(output, outputLen, input);
    ReplaceStringEx(output, outputLen, "workshop\\", "");
    ReplaceStringEx(output, outputLen, "workshop/", "");

    int slash = FindCharInString(output, '/', true);
    if (slash != -1 && output[slash + 1] != '\0')
    {
        strcopy(output, outputLen, output[slash + 1]);
    }

    int backslash = FindCharInString(output, '\\', true);
    if (backslash != -1 && output[backslash + 1] != '\0')
    {
        strcopy(output, outputLen, output[backslash + 1]);
    }

    int dot = FindCharInString(output, '.');
    if (dot > 0)
    {
        output[dot] = '\0';
    }

    TrimString(output);
    return output[0] != '\0';
}

bool DGM_CopyCurrentNormalizedMapName(char[] buffer, int maxlen)
{
    if (maxlen <= 0)
    {
        return false;
    }

    char rawMapName[PLATFORM_MAX_PATH];
    GetCurrentMap(rawMapName, sizeof(rawMapName));
    return DGM_CopyNormalizedMapName(rawMapName, buffer, maxlen);
}

bool DGM_CopyCurrentGameModeKey(char[] buffer, int maxlen)
{
    if (maxlen <= 0)
    {
        return false;
    }

    char gamemode[64];
    if (DGM_CopyCurrentGameMode(gamemode, sizeof(gamemode))
        && DGM_CopyGameModeNameToKey(gamemode, buffer, maxlen))
    {
        return true;
    }

    char mapName[PLATFORM_MAX_PATH];
    char normalizedMapName[PLATFORM_MAX_PATH];
    GetCurrentMap(mapName, sizeof(mapName));
    DGM_CopyNormalizedMapName(mapName, normalizedMapName, sizeof(normalizedMapName));
    DGM_CopyGameModeKeyForMap(normalizedMapName, buffer, maxlen);
    return buffer[0] != '\0';
}

bool DGM_CopyCurrentGameMode(char[] buffer, int maxlen)
{
    if (maxlen <= 0)
    {
        return false;
    }

    buffer[0] = '\0';
    if (g_cvGameMode != null)
    {
        g_cvGameMode.GetString(buffer, maxlen);
    }

    if (!buffer[0])
    {
        strcopy(buffer, maxlen, "unknown");
    }

    return buffer[0] != '\0';
}

bool DGM_CheckSmallFormatGamemode()
{
    char gamemodeKey[32];
    if (DGM_CopyCurrentGameModeKey(gamemodeKey, sizeof(gamemodeKey)))
    {
        if (StrEqual(gamemodeKey, "arena", false)
            || StrEqual(gamemodeKey, "vsh", false)
            || StrEqual(gamemodeKey, "ultiduo", false)
            || StrEqual(gamemodeKey, "mge", false))
        {
            return true;
        }
    }

    if (g_cvGameMode == null)
    {
        return false;
    }

    char gamemode[64];
    g_cvGameMode.GetString(gamemode, sizeof(gamemode));
    return StrEqual(gamemode, "Arena", false)
        || StrEqual(gamemode, "vsh", false)
        || StrEqual(gamemode, "ultiduo", false)
        || StrEqual(gamemode, "mge", false);
}

bool DGM_ShouldDisableInstantRespawn()
{
    return DGM_CheckSmallFormatGamemode();
}

