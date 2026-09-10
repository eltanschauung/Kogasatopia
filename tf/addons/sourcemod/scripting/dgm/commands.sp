public Action Command_Stats(int client, int args)
{
    bool fromConsole = (client <= 0 || !IsClientInGame(client));

    // Connected clients, matching SourceMod's raw client count.
    int playerCount = GetClientCount(false);

    // Current map name
    char map[64];
    DGM_CopyCurrentNormalizedMapName(map, sizeof(map));

    // Hostname string
    char hostname[128];
    if (g_cHostname != null)
    {
        g_cHostname.GetString(hostname, sizeof(hostname));
    }
    else
    {
        strcopy(hostname, sizeof(hostname), "Unknown");
    }

    int visMax = DGM_GetServerCapacityValue();

    // Respawn-related ConVars
    float respawnTime = GetConVarFloat(g_cvRespawnTime);
    float timeOverride = GetConVarFloat(g_cvTimeOverride);
    float redTime = GetConVarFloat(g_cvRedTime);
    float bluTime = GetConVarFloat(g_cvBluTime);
    int asymCapRespawn = GetConVarInt(g_cvAsymCapRespawn);

    // Output function (chooses chat or console)
    if (fromConsole)
    {
        PrintToServer("[DGM] Players: %d", playerCount);
        PrintToServer("Map: %s | Server: %s | Max Players: %d", map, hostname, visMax);
        PrintToServer("  respawn_time: %.2f", respawnTime);
        PrintToServer("  red: %.2f | blu: %.2f | otime:%.2f", redTime, bluTime, timeOverride);
        PrintToServer("  last_round_duration: %d seconds", g_iLastRoundDuration);
        PrintToServer("  respawn_red_on_cap: %d",
                      asymCapRespawn);
    }
    else
    {
        PrintToChat(client, "\x04[DGM]\x01 Players: \x04%d\x01 | Map: \x04%s\x01 | Server: \x04%s\x01 | Max: \x04%d",
                    playerCount, map, hostname, visMax);

        PrintToChat(client, "\x04[Respawn]\x01 respawn_time: \x04%.2f\x01 | respawn_otime: \x04%.2f",
                    respawnTime, timeOverride);

        PrintToChat(client, "\x04[Respawn]\x01 red: \x04%.2f\x01 | blu: \x04%.2f", redTime, bluTime);

        PrintToChat(client, "\x04[DGM]\x01 Last round duration: \x04%d\x01 seconds", g_iLastRoundDuration);

        PrintToChat(client, "\x04[Respawn]\x01 respawn_red_on_cap: \x04%d",
                    asymCapRespawn);
    }

    return Plugin_Handled;
}

public Action Command_ObjectiveLeader(int client, int args)
{
    int redOwned, blueOwned, neutralOwned, total;
    DGMObjectiveLeader leader = DGM_GetObjectiveLeaderValue(redOwned, blueOwned, neutralOwned, total);

    if (leader == DGMObjectiveLeader_None)
    {
        if (client <= 0 || !IsClientInGame(client))
        {
            PrintToServer("[DGM] No control points were found or counted on this map.");
        }
        else
        {
            PrintToChat(client, "\x04[DGM]\x01 No control points were found or counted on this map.");
        }

        return Plugin_Handled;
    }

    char status[96];
    DGM_ObjectiveLeaderToString(leader, status, sizeof(status));

    if (client <= 0 || !IsClientInGame(client))
    {
        if (DGM_IsCurrentKothMode())
        {
            PrintToServer("[DGM] %s | RED time=%d BLU time=%d",
                status, redOwned, blueOwned);
        }
        else
        {
            PrintToServer("[DGM] %s | RED=%d BLU=%d Neutral=%d TotalCounted=%d",
                status, redOwned, blueOwned, neutralOwned, total);
        }
    }
    else
    {
        if (DGM_IsCurrentKothMode())
        {
            PrintToChat(client, "\x04[DGM]\x01 %s | RED time=\x04%d\x01 BLU time=\x04%d",
                status, redOwned, blueOwned);
        }
        else
        {
            PrintToChat(client, "\x04[DGM]\x01 %s | RED=\x04%d\x01 BLU=\x04%d\x01 Neutral=\x04%d\x01 Total=\x04%d",
                status, redOwned, blueOwned, neutralOwned, total);
        }
    }

    return Plugin_Handled;
}

public Action Command_CvarHelp(int client, int args)
{
    char lines[][] = {
        "respawn_time: float - Default respawn delay (seconds). Set to 30 to disable plugin handling.",
        "dgm_lowpop_threshhold: int - Disable respawn times below this connected human count.",
        "sm_highpop_threshhold: int - Player count threshold to execute high-pop configs",
        "sm_dgm_population_configs: 0/1 - Enables low-pop/high-pop config execution",
        "respawn_otime: float - If >0, forces this respawn delay for all players",
        "respawn_redtime: float - Respawn time (seconds) specifically for Red team (beta)",
        "respawn_blutime: float - Respawn time (seconds) specifically for Blu team (beta)",
        "sm_autoaddtime: int - Seconds to add to KOTH timers when enabled (0 disables)",
        "dgm_setup_construction_multiplier: float - Construction multiplier during setup (0.0 or 1.0 disables)",
        "dgm_upgrade_metal_per_hit: int - Desired metal per wrench upgrade hit during setup",
        "respawn_red_on_cap: 0/1 - In asymmetrical modes, when 1, respawns Red instantly on cap",
        "sm_setuptime: int - Forces round setup time to this value (0 = disabled)",
        "sm_gamemode: string - Read-only; stores the detected gamemode name",
        "mp_disable_respawn_times: 0/1 - Server cvar hooked by this plugin to toggle visual respawn behavior"
    };

    bool fromConsole = (client <= 0 || !IsClientInGame(client));

    if (fromConsole)
    {
        PrintToServer("[DGM ConVar Help]");
        for (int i = 0; i < sizeof(lines); i++)
        {
            PrintToServer("  %s", lines[i]);
        }
    }
    else
    {
        PrintToChat(client, "\x04[DGM ConVar Help]\x01");
        for (int i = 0; i < sizeof(lines); i++)
        {
            PrintToChat(client, "\x01%s", lines[i]);
        }
    }

    return Plugin_Handled;
}

public Action Command_RespawnToggle(int client, int args)
{
    if (DGM_ShouldDisableInstantRespawn())
    {
        ReplyToCommand(client, "DGM respawn management is disabled on small-format maps.");
        return Plugin_Handled;
    }

    g_bRespawnAdminTouchedThisMap = true;
    DGM_SetRespawnTimesEnabled(!DGM_AreRespawnTimesForcedOn());
    DGM_RespawnDeadClients();
    DGM_ClearAllRespawnReminderTimers();
    if (!g_InternalOverride && client > 0 && IsClientInGame(client))
    {
        DGM_StartRespawnReminderTimer(client);
    }

    float respawnTime = g_cvRespawnTime.FloatValue;
    int roundedRespawnTime = RoundToNearest(respawnTime);
    char respawnTimeText[16];
    if (FloatCompare(respawnTime, float(roundedRespawnTime)) == 0)
    {
        IntToString(roundedRespawnTime, respawnTimeText, sizeof(respawnTimeText));
    }
    else
    {
        FormatEx(respawnTimeText, sizeof(respawnTimeText), "%.1f", respawnTime);
    }

    DGM_LogRespawnToggle(client, g_InternalOverride, respawnTime);
    if (client <= 0)
    {
        PrintToServer("Respawn times %s (%ss)", g_InternalOverride ? "forced on" : "forced off", respawnTimeText);
        return Plugin_Handled;
    }

    if (IsClientInGame(client))
    {
        PrintToChat(client, "Respawn times %s (%ss)", g_InternalOverride ? "forced on" : "forced off", respawnTimeText);
    }
    return Plugin_Handled;
}

