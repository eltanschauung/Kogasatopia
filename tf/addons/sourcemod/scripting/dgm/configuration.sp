void DetectGameMode()
{
    TF2_GameMode gameMode = TF2_DetectGameMode();
    CreateDefaultConfigs();
    bool sym = false;
    char modeName[32] = "unknown";
    char mapName[64];

    switch (gameMode)
    {
        case TF2_GameMode_Arena:
        {
            ServerCommand("exec d_arena.cfg");
            sym = true;
            strcopy(modeName, sizeof(modeName), "Arena");
        }
        case TF2_GameMode_Medieval:
        {
            ServerCommand("exec d_medieval.cfg");
            sym = false;
            strcopy(modeName, sizeof(modeName), "Medieval");
        }
        case TF2_GameMode_PD:
        {
            ServerCommand("exec d_pd.cfg");
            sym = true;
            strcopy(modeName, sizeof(modeName), "Player Destruction");
            // Issue: many of the modern Arena maps are using player destruction logic, I can try checking for both later
        }
        case TF2_GameMode_KOTH:
        {
            ServerCommand("exec d_koth.cfg");
            sym = true;
            strcopy(modeName, sizeof(modeName), "King of the Hill");
        }
        case TF2_GameMode_PL:
        {
            ServerCommand("exec d_payload.cfg");
            strcopy(modeName, sizeof(modeName), "Payload");
        }
        case TF2_GameMode_PLR:
        {
            ServerCommand("exec d_payloadrace.cfg");
            sym = true;
            strcopy(modeName, sizeof(modeName), "Payload Race");
        }
        case TF2_GameMode_CTF:
        {
            ServerCommand("exec d_ctf.cfg");
            sym = true;
            strcopy(modeName, sizeof(modeName), "Capture the Flag");
        }
        case TF2_GameMode_5CP:
        {
            ServerCommand("exec d_5cp.cfg");
            sym = true;
            strcopy(modeName, sizeof(modeName), "5 Control Points");
        }
        case TF2_GameMode_ADCP:
        {
            ServerCommand("exec d_adcp.cfg");
            strcopy(modeName, sizeof(modeName), "Attack/Defend CP");
        }
        case TF2_GameMode_TC:
        {
            ServerCommand("exec d_tc.cfg");
            strcopy(modeName, sizeof(modeName), "Territorial Control");
        }
        default:
        {
            ServerCommand("exec d_default.cfg");
            sym = true;
            strcopy(modeName, sizeof(modeName), "Default");
        }
    }

    GetCurrentMap(mapName, sizeof(mapName));
    if (StrContains(mapName, "vsh_", false) != -1)
    {
        strcopy(modeName, sizeof(modeName), "vsh");
    }
    else if (StrContains(mapName, "ultiduo_", false) != -1)
    {
        strcopy(modeName, sizeof(modeName), "ultiduo");
    }
    else if (StrContains(mapName, "mge_", false) != -1)
    {
        strcopy(modeName, sizeof(modeName), "mge");
    }

    g_bSymmetrical = sym;
    g_cvGameMode.SetString(modeName);
}

void CreateDefaultConfigs()
{
    char configNames[][] = {
        "d_arena.cfg",
        "d_koth.cfg",
        "d_payload.cfg",
        "d_payloadrace.cfg",
        "d_ctf.cfg",
        "d_5cp.cfg",
        "d_adcp.cfg",
        "d_tc.cfg",
        "d_medieval.cfg",
        "d_pd.cfg",
        "d_default.cfg",
        "d_highpop_a.cfg",
        "d_highpop.cfg",
        "d_lowpop_a.cfg",
        "d_lowpop.cfg",
    };

    char configPath[PLATFORM_MAX_PATH];

    for (int i = 0; i < sizeof(configNames); i++)
    {
        BuildPath(Path_SM, configPath, sizeof(configPath), "../../cfg/%s", configNames[i]);
        if (!FileExists(configPath))
        {
            File file = OpenFile(configPath, "w");
            if (file != null)
            {
                file.WriteLine("// %s configuration", configNames[i]);
                file.WriteLine("// This file is auto-generated");
                file.WriteLine("");
                file.WriteLine("echo \"Executing %s\"", configNames[i]);
                file.Close();
                LogMessage("Created config file: %s", configPath);
            }
        }
    }
}


