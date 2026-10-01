// Map-authored waves remain the baseline; DGM owns only the applied multiplier.
DynamicDetour g_hNativeWaveSet;
DynamicDetour g_hNativeWaveAdd;
DynamicDetour g_hNativeWaveRound;
bool g_bNativeWaveSetHooked;
bool g_bNativeWaveAddPreHooked;
bool g_bNativeWaveAddPostHooked;
bool g_bNativeWaveRoundPreHooked;
bool g_bNativeWaveRoundPostHooked;
bool g_bNativeWavesAvailable;
bool g_bNativeWavesMapReady;
bool g_bNativeWavesCompatible;
bool g_bNativeWavesActive;
bool g_bNativeWavesOwnInput;
bool g_bNativeWavesApplyQueued;
int g_iNativeWavesMapGeneration;
int g_iNativeWavesRoundDepth;
float g_flNativeWaveBaseline[4];

bool DGM_NativeWavesActive()
{
    return g_bNativeWavesActive;
}

void DGM_NativeWavesInitialize()
{
    GameData data = new GameData("dgm");
    if (data == null)
    {
        LogError("[DGM] Native wave gamedata unavailable; using legacy respawn handling.");
        return;
    }

    Address setWave = data.GetMemSig("CTeamplayRoundBasedRules::SetTeamRespawnWaveTime");
    Address addWave = data.GetMemSig("CTeamplayRoundBasedRules::AddTeamRespawnWaveTime");
    Address round = data.GetMemSig("CTFGameRules::RoundRespawn");
    delete data;
    if (setWave == Address_Null || addWave == Address_Null || round == Address_Null)
    {
        LogError("[DGM] Native wave signatures unavailable; using legacy respawn handling.");
        return;
    }

    g_hNativeWaveSet = new DynamicDetour(setWave, CallConv_THISCALL,
        ReturnType_Void, ThisPointer_Address);
    g_hNativeWaveSet.AddParam(HookParamType_Int);
    g_hNativeWaveSet.AddParam(HookParamType_Float);
    g_hNativeWaveAdd = new DynamicDetour(addWave, CallConv_THISCALL,
        ReturnType_Void, ThisPointer_Address);
    g_hNativeWaveAdd.AddParam(HookParamType_Int);
    g_hNativeWaveAdd.AddParam(HookParamType_Float);
    g_hNativeWaveRound = new DynamicDetour(round, CallConv_THISCALL,
        ReturnType_Void, ThisPointer_Address);

    g_bNativeWaveSetHooked = g_hNativeWaveSet.Enable(Hook_Post, DGM_NativeWaveSetPost);
    g_bNativeWaveAddPreHooked = g_hNativeWaveAdd.Enable(Hook_Pre, DGM_NativeWaveAddPre);
    g_bNativeWaveAddPostHooked = g_hNativeWaveAdd.Enable(Hook_Post, DGM_NativeWaveAddPost);
    g_bNativeWaveRoundPreHooked = g_hNativeWaveRound.Enable(Hook_Pre, DGM_NativeWaveRoundPre);
    g_bNativeWaveRoundPostHooked = g_hNativeWaveRound.Enable(Hook_Post, DGM_NativeWaveRoundPost);
    g_bNativeWavesAvailable = g_bNativeWaveSetHooked && g_bNativeWaveAddPreHooked
        && g_bNativeWaveAddPostHooked && g_bNativeWaveRoundPreHooked
        && g_bNativeWaveRoundPostHooked;
    if (!g_bNativeWavesAvailable)
    {
        DGM_NativeWavesShutdown();
        LogError("[DGM] Native wave hooks unavailable; using legacy respawn handling.");
        return;
    }

    DGM_NativeWavesOnMapStart();
}

void DGM_NativeWavesShutdown()
{
    DGM_NativeWavesRestore();
    DGM_NativeWavesInvalidateMap();
    if (g_bNativeWaveSetHooked)
        g_hNativeWaveSet.Disable(Hook_Post, DGM_NativeWaveSetPost);
    if (g_bNativeWaveAddPreHooked)
        g_hNativeWaveAdd.Disable(Hook_Pre, DGM_NativeWaveAddPre);
    if (g_bNativeWaveAddPostHooked)
        g_hNativeWaveAdd.Disable(Hook_Post, DGM_NativeWaveAddPost);
    if (g_bNativeWaveRoundPreHooked)
        g_hNativeWaveRound.Disable(Hook_Pre, DGM_NativeWaveRoundPre);
    if (g_bNativeWaveRoundPostHooked)
        g_hNativeWaveRound.Disable(Hook_Post, DGM_NativeWaveRoundPost);
    delete g_hNativeWaveSet;
    delete g_hNativeWaveAdd;
    delete g_hNativeWaveRound;
    g_bNativeWavesAvailable = false;
    g_bNativeWaveSetHooked = false;
    g_bNativeWaveAddPreHooked = false;
    g_bNativeWaveAddPostHooked = false;
    g_bNativeWaveRoundPreHooked = false;
    g_bNativeWaveRoundPostHooked = false;
}

void DGM_NativeWavesInvalidateMap()
{
    g_iNativeWavesMapGeneration++;
    g_bNativeWavesMapReady = false;
    g_bNativeWavesActive = false;
    g_bNativeWavesCompatible = false;
    g_bNativeWavesApplyQueued = false;
    g_iNativeWavesRoundDepth = 0;
}

void DGM_NativeWavesOnMapStart()
{
    DGM_NativeWavesScanMap();
    g_bNativeWavesMapReady = true;
    DGM_NativeWavesQueueApply();
}

void DGM_NativeWavesScanMap()
{
    StringMap targets = new StringMap();
    bool excluded;
    for (int i = 0; i < EntityLump.Length(); i++)
    {
        EntityLumpEntry entry = EntityLump.Get(i);
        char classname[64], target[128];
        entry.GetNextKey("classname", classname, sizeof(classname));
        if (StrEqual(classname, "tf_gamerules"))
        {
            entry.GetNextKey("targetname", target, sizeof(target));
            if (target[0])
                targets.SetValue(target, 1);
        }
        if (StrEqual(classname, "tf_logic_arena")
            || StrEqual(classname, "tf_logic_mann_vs_machine")
            || StrEqual(classname, "tf_logic_robot_destruction")
            || StrEqual(classname, "trigger_player_respawn_override"))
            excluded = true;
        delete entry;
    }

    bool red, blue;
    for (int i = 0; !excluded && i < EntityLump.Length(); i++)
    {
        EntityLumpEntry entry = EntityLump.Get(i);
        for (int j = 0; j < entry.Length; j++)
        {
            char key[128], output[1024], fields[5][128];
            entry.Get(j, key, sizeof(key), output, sizeof(output));
            if (StrContains(key, "On", false) != 0)
                continue;
            ReplaceString(output, sizeof(output), "\x1B", ",");
            if (ExplodeString(output, ",", fields, sizeof(fields), sizeof(fields[])) != 5)
                continue;
            int unused;
            if (!targets.GetValue(fields[0], unused))
                continue;
            if (StrEqual(fields[1], "SetRedTeamRespawnWaveTime", false))
                red = true;
            if (StrEqual(fields[1], "SetBlueTeamRespawnWaveTime", false))
                blue = true;
        }
        delete entry;
    }
    delete targets;
    g_bNativeWavesCompatible = !excluded && red && blue;
}

static bool DGM_NativeWavesSend(int team, float value)
{
    int rules = FindEntityByClassname(-1, "tf_gamerules");
    if (rules == -1)
        return false;
    g_bNativeWavesOwnInput = true;
    SetVariantFloat(value);
    bool success = AcceptEntityInput(rules, team == 2
        ? "SetRedTeamRespawnWaveTime" : "SetBlueTeamRespawnWaveTime");
    g_bNativeWavesOwnInput = false;
    return success;
}

void DGM_NativeWavesRestore()
{
    if (!g_bNativeWavesActive)
        return;
    g_bNativeWavesActive = false;
    if (g_bNativeWavesMapReady)
    {
        DGM_NativeWavesSend(2, g_flNativeWaveBaseline[2]);
        DGM_NativeWavesSend(3, g_flNativeWaveBaseline[3]);
    }
    LogMessage("[DGM] Restored native waves: RED %.3f, BLU %.3f.",
        g_flNativeWaveBaseline[2], g_flNativeWaveBaseline[3]);
}

static bool DGM_NativeWavesApply()
{
    bool red = DGM_NativeWavesSend(2, g_flNativeWaveBaseline[2] * 0.5);
    bool blue = DGM_NativeWavesSend(3, g_flNativeWaveBaseline[3] * 0.5);
    if (!red || !blue)
    {
        DGM_NativeWavesRestore();
        g_bNativeWavesCompatible = false;
        LogError("[DGM] Native wave inputs failed; reverting to legacy respawn handling.");
        return false;
    }
    return true;
}

void DGM_NativeWavesSync()
{
    bool requested = g_cvHalveRespawnWaves.BoolValue
        && !DGM_AreRespawnTimesForcedOn() && !g_InternalOverride
        && !DGM_ShouldDisableInstantRespawn();
    if (!requested)
    {
        DGM_NativeWavesRestore();
        DGM_RefreshRespawnVisualState();
        return;
    }

    if (!g_bNativeWavesActive && g_bNativeWavesAvailable
        && g_bNativeWavesMapReady && g_bNativeWavesCompatible
        && FindEntityByClassname(-1, "tf_gamerules") != -1
        && g_iNativeWavesRoundDepth == 0)
    {
        float red = GameRules_GetPropFloat("m_TeamRespawnWaveTimes", 2);
        float blue = GameRules_GetPropFloat("m_TeamRespawnWaveTimes", 3);
        // -1 means the map has not supplied a team wave; never invent a baseline.
        if (red >= 0.0 && blue >= 0.0)
        {
            g_flNativeWaveBaseline[2] = red;
            g_flNativeWaveBaseline[3] = blue;
            g_bNativeWavesActive = true;
            DGM_ClearAllRespawnTimers();
            if (DGM_NativeWavesApply())
                LogMessage("[DGM] Halved native waves: RED %.3f -> %.3f, BLU %.3f -> %.3f.",
                    red, red * 0.5, blue, blue * 0.5);
        }
    }
    DGM_RefreshRespawnVisualState();
}

void DGM_NativeWavesQueueApply()
{
    if (!g_bNativeWavesAvailable || !g_bNativeWavesMapReady
        || g_bNativeWavesApplyQueued)
        return;
    g_bNativeWavesApplyQueued = true;
    RequestFrame(DGM_NativeWavesFrameApply, g_iNativeWavesMapGeneration);
}

public void DGM_NativeWavesFrameApply(int generation)
{
    if (generation != g_iNativeWavesMapGeneration)
        return;
    g_bNativeWavesApplyQueued = false;
    if (g_iNativeWavesRoundDepth != 0)
        return;

    bool wasActive = g_bNativeWavesActive;
    DGM_NativeWavesSync();
    if (wasActive && g_bNativeWavesActive)
    {
        DGM_NativeWavesApply();
        DGM_RefreshRespawnVisualState();
    }
}

public void DGM_ConVarChangeNativeWaves(ConVar convar,
    const char[] oldValue, const char[] newValue)
{
    DGM_ClearAllRespawnTimers();
    DGM_NativeWavesSync();
}

public MRESReturn DGM_NativeWaveSetPost(Address rules, DHookParam params)
{
    int team = params.Get(1);
    if (g_bNativeWavesOwnInput || !g_bNativeWavesMapReady
        || (team != 2 && team != 3))
        return MRES_Ignored;
    if (g_bNativeWavesActive && g_iNativeWavesRoundDepth == 0)
        g_flNativeWaveBaseline[team] = GameRules_GetPropFloat("m_TeamRespawnWaveTimes", team);
    if (g_cvHalveRespawnWaves.BoolValue)
        DGM_NativeWavesQueueApply();
    return MRES_Ignored;
}

public MRESReturn DGM_NativeWaveAddPre(Address rules, DHookParam params)
{
    int team = params.Get(1);
    if (!g_bNativeWavesOwnInput && g_bNativeWavesActive
        && g_iNativeWavesRoundDepth == 0 && (team == 2 || team == 3))
    {
        // Native Add sees the unscaled baseline, including multiple writes in one tick.
        float delta = params.Get(2);
        float current = GameRules_GetPropFloat("m_TeamRespawnWaveTimes", team);
        params.Set(2, g_flNativeWaveBaseline[team] + delta - current);
        return MRES_ChangedHandled;
    }
    return MRES_Ignored;
}

public MRESReturn DGM_NativeWaveAddPost(Address rules, DHookParam params)
{
    int team = params.Get(1);
    if (!g_bNativeWavesOwnInput && g_bNativeWavesActive
        && g_iNativeWavesRoundDepth == 0 && (team == 2 || team == 3))
    {
        g_flNativeWaveBaseline[team] = GameRules_GetPropFloat("m_TeamRespawnWaveTimes", team);
        DGM_NativeWavesQueueApply();
    }
    return MRES_Ignored;
}

public MRESReturn DGM_NativeWaveRoundPre(Address rules)
{
    if (g_bNativeWavesMapReady)
        g_iNativeWavesRoundDepth++;
    return MRES_Ignored;
}

public MRESReturn DGM_NativeWaveRoundPost(Address rules)
{
    if (!g_bNativeWavesMapReady || g_iNativeWavesRoundDepth == 0)
        return MRES_Ignored;
    g_iNativeWavesRoundDepth--;
    // RoundRespawn can run before the round-start event (or without one).
    // Keep the admin's selected mode, not round-win's temporary timer suppression.
    if (g_cvHalveRespawnWaves.BoolValue && g_iNativeWavesRoundDepth == 0)
        g_InternalOverride = DGM_AreRespawnTimesForcedOn();
    if (g_bNativeWavesActive && g_iNativeWavesRoundDepth == 0)
    {
        g_flNativeWaveBaseline[2] = GameRules_GetPropFloat("m_TeamRespawnWaveTimes", 2);
        g_flNativeWaveBaseline[3] = GameRules_GetPropFloat("m_TeamRespawnWaveTimes", 3);
    }
    if (g_cvHalveRespawnWaves.BoolValue)
        DGM_NativeWavesQueueApply();
    return MRES_Ignored;
}

void DGM_ReplyNativeWaveState(int client)
{
    if (!g_cvHalveRespawnWaves.BoolValue)
        return;
    char state[32] = "legacy fallback";
    if (DGM_AreRespawnTimesForcedOn())
        strcopy(state, sizeof(state), "normal");
    else if (g_bNativeWavesActive)
        strcopy(state, sizeof(state), "halved");
    if (!g_bNativeWavesMapReady || FindEntityByClassname(-1, "tf_gamerules") == -1)
    {
        ReplyToCommand(client, "[Respawn] Native waves: unavailable");
        return;
    }
    float red = GameRules_GetPropFloat("m_TeamRespawnWaveTimes", 2);
    float blue = GameRules_GetPropFloat("m_TeamRespawnWaveTimes", 3);
    ReplyToCommand(client, "[Respawn] Native waves: %s | RED %.3f / BLU %.3f | normal %.3f / %.3f",
        state, red, blue, g_bNativeWavesActive ? g_flNativeWaveBaseline[2] : red,
        g_bNativeWavesActive ? g_flNativeWaveBaseline[3] : blue);
}
