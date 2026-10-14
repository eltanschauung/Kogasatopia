/**
 * Weapons view preferences. FOV command/cookie behavior derived from TF-FOV
 * Copyright (C) 2019-2024 AndrewBetson, AGPL-3.0-or-later.
 * Center Projectiles: Copyright 2020 rtldg; permission to copy/distribute with
 * or without modification, without royalty, provided this notice is retained.
 * No warranty. Engine hooks and Hunting Revolver integration live in weapons_ext.
 */
ConVar g_ViewFOVMin, g_ViewFOVMax;
Cookie g_ViewFOVCookie, g_ViewCenterCookie;
int g_ViewFOV[MAXPLAYERS + 1] = {-1, ...};
bool g_ViewCentered[MAXPLAYERS + 1];

void WeaponsView_OnPluginStart()
{
    LoadTranslations("fov.phrases");
    g_ViewFOVMin = CreateConVar("sv_fov_min", "20.0", "Minimum FOV players can set", FCVAR_NOTIFY, true, 10.0, true, 998.0);
    g_ViewFOVMax = CreateConVar("sv_fov_max", "160.0", "Maximum FOV players can set", FCVAR_NOTIFY, true, 11.0, true, 999.0);
    g_ViewFOVMin.AddChangeHook(WeaponsView_OnLimitsChanged);
    g_ViewFOVMax.AddChangeHook(WeaponsView_OnLimitsChanged);
    g_ViewFOVCookie = new Cookie("fov_override", "Your FOV preference", CookieAccess_Public);
    g_ViewCenterCookie = new Cookie("tf2centerprojectiles", "TF2 Center Projectiles thing", CookieAccess_Protected);
    RegConsoleCmd("sm_fov", WeaponsView_CommandFOV, "Set your field of view");
    RegConsoleCmd("sm_fov_clear", WeaponsView_CommandClearFOV, "Clear your FOV preference");
    RegConsoleCmd("sm_centerprojectiles", WeaponsView_CommandCenter, "Toggle centered projectiles, or set [0|1]");
    AutoExecConfig(true, "fov");
    WeaponsView_PublishLimits();
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client) && AreClientCookiesCached(client)) WeaponsView_OnCookiesCached(client);
}

void WeaponsView_PublishLimits()
{
    int minimum = g_ViewFOVMin.IntValue, maximum = g_ViewFOVMax.IntValue;
    if (minimum >= maximum)
    {
        LogError("FOV minimum must be below maximum; retaining previous native limits");
        return;
    }
    WeaponsView_SetLimits(minimum, maximum);
}

public void WeaponsView_OnLimitsChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    WeaponsView_PublishLimits();
}

void WeaponsView_OnCookiesCached(int client)
{
    char value[16];
    g_ViewFOVCookie.Get(client, value, sizeof(value));
    g_ViewFOV[client] = value[0] ? StringToInt(value) : -1;
    g_ViewCenterCookie.Get(client, value, sizeof(value));
    g_ViewCentered[client] = value[0] == '1';
    WeaponsView_SetPreference(client, g_ViewFOV[client]);
    WeaponsView_SetCentered(client, g_ViewCentered[client]);
}

void WeaponsView_OnDisconnect(int client)
{
    g_ViewFOV[client] = -1;
    g_ViewCentered[client] = false;
}

public Action WeaponsView_CommandFOV(int client, int args)
{
    if (client < 1 || !IsClientInGame(client) || IsFakeClient(client)) return Plugin_Handled;
    if (args == 0)
    {
        if (g_ViewFOV[client] != -1)
            CPrintToChat(client, "{gold}[FOV]{default} Your current FOV is set to {green}%d", g_ViewFOV[client]);
        else ReplyToCommand(client, "[FOV] Usage: sm_fov <number>");
        return Plugin_Handled;
    }
    char value[16];
    GetCmdArg(1, value, sizeof(value));
    int fov;
    if (!StringToIntEx(value, fov) || fov < g_ViewFOVMin.IntValue || fov > g_ViewFOVMax.IntValue)
    {
        ReplyToCommand(client, "[FOV] Choose a value between %d and %d.", g_ViewFOVMin.IntValue, g_ViewFOVMax.IntValue);
        return Plugin_Handled;
    }
    g_ViewFOV[client] = fov;
    IntToString(fov, value, sizeof(value));
    g_ViewFOVCookie.Set(client, value);
    WeaponsView_SetPreference(client, fov);
    CPrintToChat(client, "{gold}[FOV]{default} Your FOV has been set to {green}%d", fov);
    return Plugin_Handled;
}

public Action WeaponsView_CommandClearFOV(int client, int args)
{
    if (client < 1 || !IsClientInGame(client)) return Plugin_Handled;
    g_ViewFOV[client] = -1;
    g_ViewFOVCookie.Set(client, "");
    WeaponsView_SetPreference(client, -1);
    ReplyToCommand(client, "[FOV] Cleared your FOV preference.");
    return Plugin_Handled;
}

public Action WeaponsView_CommandCenter(int client, int args)
{
    if (client < 1 || !IsClientInGame(client) || IsFakeClient(client)) return Plugin_Handled;
    bool centered = !g_ViewCentered[client];
    if (args)
    {
        char value[16];
        GetCmdArg(1, value, sizeof(value));
        centered = StringToInt(value) != 0;
    }
    g_ViewCentered[client] = centered;
    g_ViewCenterCookie.Set(client, centered ? "1" : "0");
    WeaponsView_SetCentered(client, centered);
    PrintToChat(client, "[TF2 Center Projectiles] %s", centered ? "Enabled" : "Disabled");
    return Plugin_Handled;
}
