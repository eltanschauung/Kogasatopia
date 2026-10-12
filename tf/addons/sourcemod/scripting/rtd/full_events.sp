#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <tf2>

// Optional implementation detail of rtd.smx, not an independently enabled perk
// plugin. It lives in plugins/disabled and is loaded only for full RTD maps.
native Handle RTD2_GetRuntimeOwner();

Handle g_Core;
Function g_Frame = INVALID_FUNCTION;
Function g_Entity = INVALID_FUNCTION;
Function g_ConditionAdded = INVALID_FUNCTION;
Function g_ConditionRemoved = INVALID_FUNCTION;
Function g_RunCmd = INVALID_FUNCTION;
Function g_Critical = INVALID_FUNCTION;

public Plugin myinfo =
{
	name = "RTD Full Event Bridge",
	author = "Hombre",
	description = "Automatic engine forwards for full RTD; absent in firework-only mode.",
	version = "1.0.0"
};

Function Bind(const char[] name)
{
	Function callback = GetFunctionByName(g_Core, name);
	if (callback == INVALID_FUNCTION)
		SetFailState("RTD is missing internal callback %s", name);
	return callback;
}

public void OnPluginStart()
{
	g_Core = RTD2_GetRuntimeOwner();
	Function enabled = Bind("RTD_Full_IsEnabled");
	bool fullEnabled;
	Call_StartFunction(g_Core, enabled);
	Call_Finish(fullEnabled);
	if (!fullEnabled)
		SetFailState("This bridge must not be loaded in firework-only mode.");
	g_Frame = Bind("RTD_Full_GameFrame");
	g_Entity = Bind("RTD_Full_EntityCreated");
	g_ConditionAdded = Bind("RTD_Full_ConditionAdded");
	g_ConditionRemoved = Bind("RTD_Full_ConditionRemoved");
	g_RunCmd = Bind("RTD_Full_PlayerRunCmd");
	g_Critical = Bind("RTD_Full_AttackCritical");
}

public void OnGameFrame()
{
	Call_StartFunction(g_Core, g_Frame);
	Call_Finish();
}

public void OnEntityCreated(int entity, const char[] classname)
{
	// SDKHooks may send entity creation during this plugin's startup catch-up.
	if (g_Entity == INVALID_FUNCTION || g_Core == null)
		return;
	Call_StartFunction(g_Core, g_Entity);
	Call_PushCell(entity);
	Call_PushString(classname);
	Call_Finish();
}

void DispatchCondition(Function callback, int client, TFCond condition)
{
	Call_StartFunction(g_Core, callback);
	Call_PushCell(client);
	Call_PushCell(condition);
	Call_Finish();
}

public void TF2_OnConditionAdded(int client, TFCond condition)
{
	DispatchCondition(g_ConditionAdded, client, condition);
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
	DispatchCondition(g_ConditionRemoved, client, condition);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse,
	float velocity[3], float angles[3], int &weapon)
{
	Action result = Plugin_Continue;
	Call_StartFunction(g_Core, g_RunCmd);
	Call_PushCell(client);
	Call_PushCellRef(buttons);
	Call_PushCellRef(impulse);
	Call_PushArrayEx(velocity, sizeof(velocity), SM_PARAM_COPYBACK);
	Call_PushArrayEx(angles, sizeof(angles), SM_PARAM_COPYBACK);
	Call_PushCellRef(weapon);
	Call_Finish(result);
	return result;
}

public Action TF2_CalcIsAttackCritical(int client, int weapon,
	char[] weaponName, bool &critical)
{
	Action result = Plugin_Continue;
	Call_StartFunction(g_Core, g_Critical);
	Call_PushCell(client);
	Call_PushCell(weapon);
	Call_PushString(weaponName);
	Call_PushCellRef(critical);
	Call_Finish(result);
	return result;
}
