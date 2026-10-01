// Scale TF2's final wave calculation, never the map's stored/original settings.
DynamicDetour g_hNativeWaveLength;
DynamicDetour g_hNativeWaveSet;
DynamicDetour g_hNativeWaveAdd;
DynamicDetour g_hNativeWaveRound;
Handle g_hNativeWaveLengthCall;
bool g_bNativeWaveLengthHooked;
bool g_bNativeWaveSetPreHooked;
bool g_bNativeWaveSetPostHooked;
bool g_bNativeWaveAddPreHooked;
bool g_bNativeWaveAddPostHooked;
bool g_bNativeWaveRoundPreHooked;
bool g_bNativeWaveRoundPostHooked;
bool g_bNativeWavesAvailable;
bool g_bNativeWavesMapReady;
bool g_bNativeWavesCompatible;
bool g_bNativeWavesActive;
bool g_bNativeWavesMeasureNormal;
bool g_bNativeWavesApplyQueued;
bool g_bNativeWavePendingSnapshot;
int g_iNativeWavesMapGeneration;
int g_iNativeWavesRoundDepth;
float g_flNativeWaveInterval[4];
#include "steel_respawn_policy.sp"

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

    Address length = data.GetMemSig("CTFGameRules::GetRespawnWaveMaxLength");
    Address setWave = data.GetMemSig("CTeamplayRoundBasedRules::SetTeamRespawnWaveTime");
    Address addWave = data.GetMemSig("CTeamplayRoundBasedRules::AddTeamRespawnWaveTime");
    Address round = data.GetMemSig("CTFGameRules::RoundRespawn");
    StartPrepSDKCall(SDKCall_GameRules);
    bool prepared = PrepSDKCall_SetFromConf(data, SDKConf_Signature,
        "CTFGameRules::GetRespawnWaveMaxLength");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
    PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);
    g_hNativeWaveLengthCall = EndPrepSDKCall();
    delete data;
    if (!prepared || g_hNativeWaveLengthCall == null || length == Address_Null
        || setWave == Address_Null || addWave == Address_Null || round == Address_Null)
    {
        DGM_NativeWavesShutdown();
        LogError("[DGM] Native wave signatures unavailable; using legacy respawn handling.");
        return;
    }

    g_hNativeWaveLength = new DynamicDetour(length, CallConv_THISCALL,
        ReturnType_Float, ThisPointer_Address);
    g_hNativeWaveLength.AddParam(HookParamType_Int);
    g_hNativeWaveLength.AddParam(HookParamType_Bool);
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

    g_bNativeWaveLengthHooked = g_hNativeWaveLength.Enable(Hook_Post, DGM_NativeWaveLengthPost);
    g_bNativeWaveSetPreHooked = g_hNativeWaveSet.Enable(Hook_Pre, DGM_NativeWaveWritePre);
    g_bNativeWaveSetPostHooked = g_hNativeWaveSet.Enable(Hook_Post, DGM_NativeWaveWritePost);
    g_bNativeWaveAddPreHooked = g_hNativeWaveAdd.Enable(Hook_Pre, DGM_NativeWaveWritePre);
    g_bNativeWaveAddPostHooked = g_hNativeWaveAdd.Enable(Hook_Post, DGM_NativeWaveWritePost);
    g_bNativeWaveRoundPreHooked = g_hNativeWaveRound.Enable(Hook_Pre, DGM_NativeWaveRoundPre);
    g_bNativeWaveRoundPostHooked = g_hNativeWaveRound.Enable(Hook_Post, DGM_NativeWaveRoundPost);
    g_bNativeWavesAvailable = g_bNativeWaveLengthHooked
        && g_bNativeWaveSetPreHooked && g_bNativeWaveSetPostHooked
        && g_bNativeWaveAddPreHooked && g_bNativeWaveAddPostHooked
        && g_bNativeWaveRoundPreHooked && g_bNativeWaveRoundPostHooked;
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
    if (g_bNativeWaveLengthHooked)
        g_hNativeWaveLength.Disable(Hook_Post, DGM_NativeWaveLengthPost);
    if (g_bNativeWaveSetPreHooked)
        g_hNativeWaveSet.Disable(Hook_Pre, DGM_NativeWaveWritePre);
    if (g_bNativeWaveSetPostHooked)
        g_hNativeWaveSet.Disable(Hook_Post, DGM_NativeWaveWritePost);
    if (g_bNativeWaveAddPreHooked)
        g_hNativeWaveAdd.Disable(Hook_Pre, DGM_NativeWaveWritePre);
    if (g_bNativeWaveAddPostHooked)
        g_hNativeWaveAdd.Disable(Hook_Post, DGM_NativeWaveWritePost);
    if (g_bNativeWaveRoundPreHooked)
        g_hNativeWaveRound.Disable(Hook_Pre, DGM_NativeWaveRoundPre);
    if (g_bNativeWaveRoundPostHooked)
        g_hNativeWaveRound.Disable(Hook_Post, DGM_NativeWaveRoundPost);
    delete g_hNativeWaveLength;
    delete g_hNativeWaveSet;
    delete g_hNativeWaveAdd;
    delete g_hNativeWaveRound;
    delete g_hNativeWaveLengthCall;
    g_bNativeWavesAvailable = false;
    g_bNativeWaveLengthHooked = false;
    g_bNativeWaveSetPreHooked = false;
    g_bNativeWaveSetPostHooked = false;
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
    g_bNativeWavePendingSnapshot = false;
    g_bSteelWaveProfile = false;
    g_iNativeWavesRoundDepth = 0;
    g_flNativeWaveInterval[2] = 0.0;
    g_flNativeWaveInterval[3] = 0.0;
}

void DGM_NativeWavesOnMapStart()
{
    DGM_NativeWavesInvalidateMap();
    DGM_NativeWavesScanMap();
    DGM_SteelScanWaveProfile();
    g_bNativeWavesMapReady = true;
    DGM_SteelSettleRound();
    DGM_NativeWavesQueueApply();
}

void DGM_NativeWavesScanMap()
{
    bool excluded;
    for (int i = 0; i < EntityLump.Length(); i++)
    {
        EntityLumpEntry entry = EntityLump.Get(i);
        char classname[64];
        entry.GetNextKey("classname", classname, sizeof(classname));
        if (StrEqual(classname, "tf_logic_arena")
            || StrEqual(classname, "tf_logic_mann_vs_machine")
            || StrEqual(classname, "tf_logic_robot_destruction")
            || StrEqual(classname, "trigger_player_respawn_override"))
            excluded = true;
        delete entry;
    }
    // -1 team settings are valid: TF2 resolves its own default wave in GetRespawnWaveMaxLength.
    g_bNativeWavesCompatible = !excluded;
}

static float DGM_NativeWaveLength(int team, bool scaled = true, bool normal = false)
{
    if (g_hNativeWaveLengthCall == null)
        return 0.0;
    g_bNativeWavesMeasureNormal = normal;
    float length = SDKCall(g_hNativeWaveLengthCall, team, scaled);
    g_bNativeWavesMeasureNormal = false;
    return length;
}

static void DGM_NativeWavesReschedule()
{
    if (!g_bNativeWavesMapReady || FindEntityByClassname(-1, "tf_gamerules") == -1)
        return;
    float now = GetGameTime();
    for (int team = 2; team <= 3; team++)
    {
        float oldLength = g_flNativeWaveInterval[team];
        float length = DGM_NativeWaveLength(team);
        float next = GameRules_GetPropFloat("m_flNextRespawnWave", team);
        if (oldLength > 0.0 && length > 0.0 && next > now
            && FloatAbs(oldLength - length) > 0.001)
        {
            // Preserve wave phase instead of leaving a full-length wave queued after toggling.
            float remaining = next - now;
            if (remaining > oldLength)
                remaining = oldLength;
            GameRules_SetPropFloat("m_flNextRespawnWave", now + remaining * length / oldLength, team);
        }
        g_flNativeWaveInterval[team] = length;
    }
}

void DGM_NativeWavesRestore()
{
    if (!g_bNativeWavesActive)
        return;
    g_bNativeWavesActive = false;
    DGM_NativeWavesReschedule();
}

void DGM_NativeWavesSync()
{
    bool requested = g_cvHalveRespawnWaves.BoolValue
        && !DGM_AreRespawnTimesForcedOn() && !g_InternalOverride
        && !DGM_ShouldDisableInstantRespawn();
    bool active = requested && g_bNativeWavesAvailable
        && g_bNativeWavesMapReady && g_bNativeWavesCompatible
        && FindEntityByClassname(-1, "tf_gamerules") != -1;
    float authored[4];bool repair;
    if (g_bNativeWavesAvailable && g_bNativeWavesMapReady
        && FindEntityByClassname(-1, "tf_gamerules") != -1 && DGM_SteelExpectedWaves(authored))
        for (int team = 2; team <= 3; team++)
            repair = repair || FloatAbs(GameRules_GetPropFloat("m_TeamRespawnWaveTimes", team) - authored[team]) > 0.001;
    if ((active != g_bNativeWavesActive || repair) && !g_bNativeWavePendingSnapshot)
        for (int team = 2; team <= 3; team++) g_flNativeWaveInterval[team] = DGM_NativeWaveLength(team);
    if (repair)
        for (int team = 2; team <= 3; team++)
            GameRules_SetPropFloat("m_TeamRespawnWaveTimes", authored[team], team);
    if (active != g_bNativeWavesActive)
    {
        g_bNativeWavesActive = active;
        DGM_ClearAllRespawnTimers();
        LogMessage("[DGM] Native respawn waves: %s (map settings and death/freezecam unchanged).",
            active ? "halved" : "normal/fallback");
    }
    DGM_NativeWavesReschedule();
    g_bNativeWavePendingSnapshot = false;
    DGM_RefreshRespawnVisualState();
}

void DGM_NativeWavesQueueApply()
{
    if (!g_bNativeWavesAvailable || !g_bNativeWavesMapReady || g_bNativeWavesApplyQueued)
        return;
    g_bNativeWavesApplyQueued = true;
    RequestFrame(DGM_NativeWavesFrameApply, g_iNativeWavesMapGeneration);
}

public void DGM_NativeWavesFrameApply(int generation)
{
    if (generation != g_iNativeWavesMapGeneration)
        return;
    g_bNativeWavesApplyQueued = false;
    if (g_iNativeWavesRoundDepth == 0)
        DGM_NativeWavesSync();
}

public void DGM_ConVarChangeNativeWaves(ConVar convar, const char[] oldValue, const char[] newValue)
{
    DGM_ClearAllRespawnTimers();
    DGM_NativeWavesSync();
}

public MRESReturn DGM_NativeWaveLengthPost(Address rules, DHookReturn ret, DHookParam params)
{
    int team = params.Get(1);
    if (!g_bNativeWavesActive || g_bNativeWavesMeasureNormal
        || (team != 2 && team != 3))
        return MRES_Ignored;
    float length = ret.Value;
    if (length <= 0.0)
        return MRES_Ignored;
    ret.Value = length * 0.5;
    return MRES_Override;
}

public MRESReturn DGM_NativeWaveWritePre(Address rules, DHookParam params)
{
    int team = params.Get(1);
    if ((g_bNativeWavesActive || (g_bSteelWaveProfile && g_cvHalveRespawnWaves.BoolValue))
        && g_iNativeWavesRoundDepth == 0
        && (team == 2 || team == 3) && !g_bNativeWavePendingSnapshot)
    {
        // Cache once before a batch of Set/Add inputs; never rewrite the input or its original value.
        for (int t = 2; t <= 3; t++)
            g_flNativeWaveInterval[t] = DGM_NativeWaveLength(t);
        g_bNativeWavePendingSnapshot = true;
    }
    return MRES_Ignored;
}

public MRESReturn DGM_NativeWaveWritePost(Address rules, DHookParam params)
{
    if (g_bNativeWavesActive || (g_bSteelWaveProfile && g_cvHalveRespawnWaves.BoolValue))
        DGM_NativeWavesQueueApply();
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
    if (g_iNativeWavesRoundDepth == 0) DGM_SteelSettleRound();
    if (g_cvHalveRespawnWaves.BoolValue && g_iNativeWavesRoundDepth == 0)
        g_InternalOverride = DGM_AreRespawnTimesForcedOn();
    DGM_NativeWavesQueueApply();
    return MRES_Ignored;
}

void DGM_ReplyNativeWaveState(int client)
{
    if (!g_cvHalveRespawnWaves.BoolValue)
        return;
    if (!g_bNativeWavesMapReady || FindEntityByClassname(-1, "tf_gamerules") == -1)
    {
        ReplyToCommand(client, "[Respawn] Native waves: unavailable");
        return;
    }
    char state[32] = "legacy fallback";
    if (DGM_AreRespawnTimesForcedOn())
        strcopy(state, sizeof(state), "normal");
    else if (g_bNativeWavesActive)
        strcopy(state, sizeof(state), "halved");
    ReplyToCommand(client, "[Respawn] Native waves: %s | effective RED %.3f / BLU %.3f | normal %.3f / %.3f",
        state, DGM_NativeWaveLength(2), DGM_NativeWaveLength(3),
        DGM_NativeWaveLength(2, true, true), DGM_NativeWaveLength(3, true, true));
    if (g_bSteelWaveProfile) ReplyToCommand(client, "[Respawn] Steel entity-derived wave policy is active.");
    ReplyToCommand(client, "[Respawn] Map settings RED %.3f / BLU %.3f (-1 = native default); death/freezecam unchanged.",
        GameRules_GetPropFloat("m_TeamRespawnWaveTimes", 2),
        GameRules_GetPropFloat("m_TeamRespawnWaveTimes", 3));
}
