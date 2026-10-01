// Steel's initial BLU adjustment lives in logic_auto.OnMultiNewRound, which can
// be absent after a skipped waiting round or a late controller load. Reconstruct
// the authored state from the entity graph instead of preserving a fallback -1.
#define DGM_STEEL_STAGE_COUNT 5
static const char g_SteelPointNames[][] = {
    "cap_a_flag", "cap_b_flag", "cap_c_flag", "cap_d_flag", "final_cap_flag"
};
static const char g_SteelRelayNames[][] = {
    "", "cap_a_add_time", "cap_b_add_time", "cap_c_add_time", "cap_d_add_time"
};
bool g_bSteelWaveProfile;
float g_flSteelWaveScale[DGM_STEEL_STAGE_COUNT][4];
float g_flSteelWaveOffset[DGM_STEEL_STAGE_COUNT][4];
float g_flSteelWaveSettleUntil;

void DGM_SteelScanWaveProfile()
{
    g_bSteelWaveProfile = false;
    bool found[5], roundBlueAdjustment, unsupported;
    int pointCount;
    for (int stage = 0; stage < DGM_STEEL_STAGE_COUNT; stage++)
        for (int team = 2; team <= 3; team++) {
            g_flSteelWaveScale[stage][team] = 1.0;
            g_flSteelWaveOffset[stage][team] = 0.0;
        }
    for (int i = 0; i < EntityLump.Length(); i++)
    {
        EntityLumpEntry entry = EntityLump.Get(i);
        char classname[64], name[128];
        entry.GetNextKey("classname", classname, sizeof(classname));
        entry.GetNextKey("targetname", name, sizeof(name));
        if (StrEqual(classname, "team_control_point"))
        {
            pointCount++;
            for (int p = 0; p < 5; p++) if (StrEqual(name, g_SteelPointNames[p])) {
                char previous[128], owner[16];
                entry.GetNextKey("team_previouspoint_3_0", previous, sizeof(previous));
                entry.GetNextKey("point_default_owner", owner, sizeof(owner));
                found[p] = StringToInt(owner) == 2
                    && StrEqual(previous, g_SteelPointNames[p == 4 ? 4 : p > 0 ? p - 1 : 0]);
            }
        }
        int stage = -1;
        char outputKey[32];
        if (StrEqual(classname, "logic_auto")) {
            stage = 0;strcopy(outputKey, sizeof(outputKey), "OnMultiNewRound");
        } else if (StrEqual(classname, "logic_relay")) {
            for (int p = 1; p < DGM_STEEL_STAGE_COUNT; p++)
                if (StrEqual(name, g_SteelRelayNames[p])) stage = p;
            strcopy(outputKey, sizeof(outputKey), "OnTrigger");
        }
        if (stage >= 0)
        {
            int position = -1;char output[512], fields[5][96];
            while ((position = entry.GetNextKey(outputKey, output, sizeof(output), position)) != -1)
            {
                ReplaceString(output, sizeof(output), "\x1B", ",");
                if (ExplodeString(output, ",", fields, sizeof(fields), sizeof(fields[])) != 5
                    || !StrEqual(fields[0], "tf_gamerules")) continue;
                int team = 0;bool set = false;
                if (StrEqual(fields[1], "SetRedTeamRespawnWaveTime")) { team = 2;set = true; }
                else if (StrEqual(fields[1], "SetBlueTeamRespawnWaveTime")) { team = 3;set = true; }
                else if (StrEqual(fields[1], "AddRedTeamRespawnWaveTime")) team = 2;
                else if (StrEqual(fields[1], "AddBlueTeamRespawnWaveTime")) team = 3;
                else continue;
                if (StringToFloat(fields[3]) != 0.0) { unsupported = true;continue; }
                float value = StringToFloat(fields[2]);
                if (stage == 0 && team == 3 && !set && value < 0.0) roundBlueAdjustment = true;
                if (set) {
                    g_flSteelWaveScale[stage][team] = 0.0;
                    g_flSteelWaveOffset[stage][team] = value;
                } else g_flSteelWaveOffset[stage][team] += value;
            }
        }
        delete entry;
    }
    g_bSteelWaveProfile = pointCount == 5 && roundBlueAdjustment && !unsupported;
    for (int p = 0; p < 5; p++) g_bSteelWaveProfile = g_bSteelWaveProfile && found[p];
    g_flSteelWaveSettleUntil = GetGameTime() + 0.35;
    if (g_bSteelWaveProfile) LogMessage("[DGM] Steel respawn policy detected from control-point and wave-output entities.");
}

bool DGM_SteelExpectedWaves(float values[4])
{
    if (!g_bSteelWaveProfile || !g_cvHalveRespawnWaves.BoolValue
        || GetGameTime() < g_flSteelWaveSettleUntil) return false;
    bool captured[4];int found;
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "team_control_point")) != -1)
    {
        char name[128];GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));
        for (int p = 0; p < 4; p++) if (StrEqual(name, g_SteelPointNames[p])) {
            found++;captured[p] = GetEntProp(entity, Prop_Send, "m_iTeamNum") == 3;
        }
    }
    if (found != 4) return false;
    ConVar fallback = FindConVar("mp_respawnwavetime");
    for (int team = 2; team <= 3; team++)
    {
        values[team] = fallback == null ? 10.0 : fallback.FloatValue;
        for (int stage = 0; stage < DGM_STEEL_STAGE_COUNT; stage++)
        {
            if (stage > 0 && !captured[stage - 1]) continue;
            values[team] = values[team] * g_flSteelWaveScale[stage][team] + g_flSteelWaveOffset[stage][team];
            if (values[team] < 0.0) values[team] = 0.0;
        }
    }
    return true;
}

void DGM_SteelSettleRound()
{
    if (!g_bSteelWaveProfile) return;
    g_flSteelWaveSettleUntil = GetGameTime() + 0.35;
    CreateTimer(0.4, DGM_SteelApplyAfterRound, g_iNativeWavesMapGeneration, TIMER_FLAG_NO_MAPCHANGE);
}

public Action DGM_SteelApplyAfterRound(Handle timer, any generation)
{
    if (generation == g_iNativeWavesMapGeneration) DGM_NativeWavesQueueApply();
    return Plugin_Stop;
}
