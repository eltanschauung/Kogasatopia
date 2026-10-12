#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <tf2>

#define TEST_BRIDGE "disabled/rtd_full_events_probe_bridge.smx"
int g_Checks;
int g_Frames;
int g_Entities;
int g_Added;
int g_Removed;
int g_Failures;

public Plugin myinfo =
{
    name = "RTD isolated bridge regression probe",
    author = "Hombre",
    version = "1.0"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int length)
{
    CreateNative("RTD2_GetRuntimeOwner", GetOwner);
    return APLRes_Success;
}

public int GetOwner(Handle plugin, int count)
{
    return view_as<int>(GetMyHandle());
}

void Check(bool result)
{
    g_Checks++;
    if (!result)
        g_Failures++;
}

public void OnPluginStart()
{
    RegAdminCmd("sm_rtd_bridge_probe", TestBridge, ADMFLAG_ROOT);
}

public bool RTD_Full_IsEnabled() { return true; }
public void RTD_Full_GameFrame() { g_Frames++; }
public void RTD_Full_EntityCreated(int entity, const char[] classname)
{
    if (entity == 0 && StrEqual(classname, "probe_dummy"))
        g_Entities++;
}
public void RTD_Full_ConditionAdded(int client, TFCond condition)
{
    if (client == 0 && condition == TFCond_CritOnWin)
        g_Added++;
}
public void RTD_Full_ConditionRemoved(int client, TFCond condition)
{
    if (client == 0 && condition == TFCond_CritOnWin)
        g_Removed++;
}
public Action RTD_Full_PlayerRunCmd(int client, int &buttons, int &impulse,
    float velocity[3], float angles[3], int &weapon)
{
    // Never change a real player's command, even if the engine calls us.
    if (client != 0)
        return Plugin_Continue;
    buttons |= 512;
    impulse = 27;
    velocity[2] = 42.0;
    angles[0] = 15.0;
    weapon = 33;
    return Plugin_Changed;
}
public Action RTD_Full_AttackCritical(int client, int weapon, char[] name, bool &critical)
{
    if (client != 0)
        return Plugin_Continue;
    critical = true;
    return Plugin_Changed;
}

public Action TestBridge(int client, int args)
{
    g_Checks = 0;
    g_Failures = 0;
    ServerCommand("sm plugins load " ... TEST_BRIDGE);
    CreateTimer(0.2, TestLoadedBridge);
    return Plugin_Handled;
}

public Action TestLoadedBridge(Handle timer)
{
    Handle bridge = FindPluginByFile(TEST_BRIDGE);
    Check(bridge != null && GetPluginStatus(bridge) == Plugin_Running);
    if (bridge == null || GetPluginStatus(bridge) != Plugin_Running)
    {
        PrintToServer("[RTDProbe] checks=%d failures=%d", g_Checks, g_Failures);
        return Plugin_Stop;
    }
    int before = g_Frames;
    Call_StartFunction(bridge, GetFunctionByName(bridge, "OnGameFrame"));
    Call_Finish();
    Check(g_Frames == before + 1);
    before = g_Entities;
    Call_StartFunction(bridge, GetFunctionByName(bridge, "OnEntityCreated"));
    Call_PushCell(0);
    Call_PushString("probe_dummy");
    Call_Finish();
    Check(g_Entities == before + 1);
    Call_StartFunction(bridge, GetFunctionByName(bridge, "TF2_OnConditionAdded"));
    Call_PushCell(0);
    Call_PushCell(TFCond_CritOnWin);
    Call_Finish();
    Check(g_Added == 1);
    Call_StartFunction(bridge, GetFunctionByName(bridge, "TF2_OnConditionRemoved"));
    Call_PushCell(0);
    Call_PushCell(TFCond_CritOnWin);
    Call_Finish();
    Check(g_Removed == 1);

    int buttons = 5, impulse = 7, weapon = 3;
    float velocity[3] = {1.0, 2.0, 3.0};
    float angles[3] = {4.0, 5.0, 6.0};
    Action result;
    Call_StartFunction(bridge, GetFunctionByName(bridge, "OnPlayerRunCmd"));
    Call_PushCell(0);
    Call_PushCellRef(buttons);
    Call_PushCellRef(impulse);
    Call_PushArrayEx(velocity, 3, SM_PARAM_COPYBACK);
    Call_PushArrayEx(angles, 3, SM_PARAM_COPYBACK);
    Call_PushCellRef(weapon);
    Call_Finish(result);
    Check(result == Plugin_Changed && buttons == 517 && impulse == 27 && weapon == 33);
    Check(velocity[2] == 42.0 && velocity[0] == 1.0 && angles[0] == 15.0 && angles[1] == 5.0);
    bool critical;
    Call_StartFunction(bridge, GetFunctionByName(bridge, "TF2_CalcIsAttackCritical"));
    Call_PushCell(0);
    Call_PushCell(0);
    Call_PushString("probe_weapon");
    Call_PushCellRef(critical);
    Call_Finish(result);
    Check(result == Plugin_Changed && critical);
    ServerCommand("sm plugins unload " ... TEST_BRIDGE);
    CreateTimer(0.2, TestUnloadedBridge);
    return Plugin_Stop;
}

public Action TestUnloadedBridge(Handle timer)
{
    Check(FindPluginByFile(TEST_BRIDGE) == null);
    PrintToServer("[RTDProbe] checks=%d failures=%d", g_Checks, g_Failures);
    return Plugin_Stop;
}

public void OnPluginEnd()
{
    if (FindPluginByFile(TEST_BRIDGE) != null)
    {
        ServerCommand("sm plugins unload " ... TEST_BRIDGE);
    }
}
