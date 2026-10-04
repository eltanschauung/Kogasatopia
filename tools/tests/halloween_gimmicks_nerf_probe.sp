#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>

public Plugin myinfo =
{
    name = "Halloween module integration probe",
    author = "Kogasatopia",
    description = "Checks merged Halloween rules on an empty test server.",
    version = "1.0"
};

ConVar g_DisableSpells;
ConVar g_Halloween;
bool g_OriginalDisableSpells;
bool g_OriginalHalloween;
bool g_Running;
int g_Failures;
int g_SpellRef = INVALID_ENT_REFERENCE;

public void OnPluginStart()
{
    RegServerCmd("sm_halloween_module_probe", RunProbe);
}

public void OnPluginEnd()
{
    RestoreSettings();
}

public Action RunProbe(int args)
{
    if (g_Running)
        return Plugin_Handled;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && !IsFakeClient(client))
        {
            PrintToServer("[HalloweenProbe] Refusing to run with human clients.");
            return Plugin_Handled;
        }
    }

    g_DisableSpells = FindConVar("sm_nospells");
    g_Halloween = FindConVar("sm_halloween");
    if (g_DisableSpells == null || g_Halloween == null)
        SetFailState("Merged Halloween convars are missing.");

    g_OriginalDisableSpells = g_DisableSpells.BoolValue;
    g_OriginalHalloween = g_Halloween.BoolValue;
    g_Running = true;
    g_Failures = 0;
    g_Halloween.BoolValue = false;
    g_DisableSpells.BoolValue = true;
    SpawnSpell();
    CreateTimer(0.1, CheckPhase, 0, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Handled;
}

void SpawnSpell()
{
    int entity = CreateEntityByName("tf_spell_pickup");
    if (entity == -1)
        SetFailState("Cannot create tf_spell_pickup.");
    DispatchSpawn(entity);
    g_SpellRef = EntIndexToEntRef(entity);
}

public Action CheckPhase(Handle timer, any phase)
{
    switch (phase)
    {
        case 0: CheckDisabled();
        case 1: CheckEnabled();
        case 2: CheckChanged();
    }
    return Plugin_Stop;
}

void CheckDisabled()
{
    Check(EntRefToEntIndex(g_SpellRef) == INVALID_ENT_REFERENCE,
        "spell removed without Halloween markers");
    g_DisableSpells.BoolValue = false;
    SpawnSpell();
    CreateTimer(0.1, CheckPhase, 1, TIMER_FLAG_NO_MAPCHANGE);
}

void CheckEnabled()
{
    Check(EntRefToEntIndex(g_SpellRef) != INVALID_ENT_REFERENCE,
        "spell allowed with sm_nospells 0");
    g_DisableSpells.BoolValue = true;
    CreateTimer(0.1, CheckPhase, 2, TIMER_FLAG_NO_MAPCHANGE);
}

void CheckChanged()
{
    Check(EntRefToEntIndex(g_SpellRef) == INVALID_ENT_REFERENCE,
        "existing spell removed after convar change");

    int bot = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && IsFakeClient(client)
            && !IsClientSourceTV(client) && IsPlayerAlive(client))
        {
            bot = client;
            break;
        }
    }

    if (bot != 0 && FindConVar("sm_minicrumps").BoolValue)
    {
        g_Halloween.BoolValue = true;
        TF2_AddCondition(bot, TFCond_HalloweenCritCandy, 4.0);
        Check(!TF2_IsPlayerInCondition(bot, TFCond_HalloweenCritCandy)
            && TF2_IsPlayerInCondition(bot, TFCond_CritCola),
            "crit pumpkin converted to mini-crit condition");
        TF2_RemoveCondition(bot, TFCond_CritCola);
    }
    else
    {
        PrintToServer("[HalloweenProbe] SKIP pumpkin condition: no live bot or feature disabled.");
    }

    RestoreSettings();
    PrintToServer("[HalloweenProbe] Finished with %d failures.", g_Failures);
}

void Check(bool passed, const char[] name)
{
    if (!passed)
        g_Failures++;
    PrintToServer("[HalloweenProbe] %s: %s", passed ? "PASS" : "FAIL", name);
}

void RestoreSettings()
{
    if (!g_Running)
        return;
    int spell = EntRefToEntIndex(g_SpellRef);
    if (spell != INVALID_ENT_REFERENCE)
        RemoveEntity(spell);
    g_SpellRef = INVALID_ENT_REFERENCE;
    g_DisableSpells.BoolValue = g_OriginalDisableSpells;
    g_Halloween.BoolValue = g_OriginalHalloween;
    g_Running = false;
}
