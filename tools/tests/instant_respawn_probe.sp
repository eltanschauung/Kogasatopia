#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>

#define MaxClients 2
#define TFTeam_Spectator 1
#define TFClass_Heavy 6
#define DGM_RESPAWN_DISABLED_TIME 30.0
#define DGM_RESPAWN_REMINDER_INTERVAL 60.0
float values[16];
methodmap TestConVar < Handle
{
    property bool BoolValue
    {
        public get() { return values[view_as<int>(this)] != 0.0; }
    }
    property float FloatValue
    {
        public get() { return values[view_as<int>(this)]; }
    }
}
TestConVar g_cvInstantRespawn = view_as<TestConVar>(1);
TestConVar g_cvRespawnTime = view_as<TestConVar>(2);
TestConVar g_cvTimeOverride = view_as<TestConVar>(3);
TestConVar g_cvRedTime = view_as<TestConVar>(4);
TestConVar g_cvBluTime = view_as<TestConVar>(5);
TestConVar g_cvHeavyInstantRespawnImmunity = view_as<TestConVar>(6);
TestConVar g_cvPopulationRespawns = view_as<TestConVar>(7);
TestConVar g_cvHalveRespawnWaves = view_as<TestConVar>(8);
TestConVar g_cvMpDisableRespawnTimes = view_as<TestConVar>(9);
bool g_InternalOverride, inGame = true, alive, smallMode, nativeWaves, heavy;
int team = 2, serial = 100, respawns, checks, failures;
float lastDelay;
Handle g_hRespawnTimers[MAXPLAYERS + 1], g_hRespawnReminderTimers[MAXPLAYERS + 1];
stock bool Client_IsInGame(int client) { return client == 1 && inGame; }
stock bool TestInGame(int client) { return Client_IsInGame(client); }
stock bool TestAlive(int client) { return client == 1 && alive; }
stock int TestTeam(int client) { return client == 1 ? team : 0; }
stock int TestSerial(int client) { return client == 1 ? serial : 0; }
stock int TestFromSerial(int value) { return inGame && value == serial ? 1 : 0; }
stock int TestFromUserId(int value) { return TestFromSerial(value); }
stock int TF2Classes_GetCurrentOrDesired(int client) { return client == 1 && heavy ? 6 : 1; }
stock bool DGM_ShouldDisableInstantRespawn() { return smallMode; }
stock bool DGM_NativeWavesActive() { return nativeWaves; }
stock void TestRespawn(int client) { if (client != 1) failures++; respawns++; alive = true; }
stock Handle TestTimer(float delay, Timer callback, any data, int flags)
{
    #pragma unused callback
    #pragma unused data
    #pragma unused flags
    lastDelay = delay;
    return CreateDataPack();
}
stock void TestSetConVarBool(TestConVar convar, bool value) { values[view_as<int>(convar)] = value ? 1.0 : 0.0; }
stock void CPrintToChat(int client, const char[] format, any ...)
{
    #pragma unused client
    #pragma unused format
}
stock void DGM_NativeWavesSync()
{
    nativeWaves = !g_cvInstantRespawn.BoolValue && g_cvHalveRespawnWaves.BoolValue
        && !DGM_AreRespawnTimesForcedOn() && !g_InternalOverride && !smallMode;
}
#define ConVar TestConVar
#define IsClientInGame TestInGame
#define IsPlayerAlive TestAlive
#define GetClientTeam TestTeam
#define GetClientSerial TestSerial
#define GetClientFromSerial TestFromSerial
#define GetClientOfUserId TestFromUserId
#define TF2_RespawnPlayer TestRespawn
#define CreateTimer TestTimer
#define SetConVarBool TestSetConVarBool
#include "instant_visual_under_test.inc"
#include "respawn_timers.sp"

void Check(bool pass, const char[] name)
{
    checks++;
    if (!pass) { failures++; PrintToServer("[InstantRespawnProbe] FAIL: %s", name); }
}
void Reset()
{
    DGM_ClearAllRespawnTimers();
    inGame = true; alive = false; smallMode = nativeWaves = heavy = g_InternalOverride = false;
    team = 2; respawns = 0;
    for (int i = 0; i < sizeof(values); i++) values[i] = 0.0;
    values[2] = values[4] = values[5] = 3.0;
}
void Complete(int token = -1)
{
    Handle timer = g_hRespawnTimers[1];
    Timer_RespawnClient(timer, token == -1 ? serial : token);
    if (g_hRespawnTimers[1] == timer) DGM_ClearRespawnTimer(1);
    else delete timer;
}
void Change(bool enabled)
{
    values[1] = enabled ? 1.0 : 0.0;
    DGM_ConVarChangeInstantRespawn(g_cvInstantRespawn, enabled ? "0" : "1", enabled ? "1" : "0");
}
public void OnPluginStart()
{
    Reset();
    DGM_ScheduleDeathRespawn(1);
    Check(g_hRespawnTimers[1] != null && lastDelay == 3.0, "default retains legacy delay");
    Complete(); Check(respawns == 1, "legacy timer still respawns");

    Reset(); values[1] = 1.0; values[2] = 30.0; values[3] = 20.0;
    values[4] = 15.0; values[5] = 12.0; values[6] = 1.0;
    g_InternalOverride = smallMode = nativeWaves = heavy = true;
    Event event = CreateEvent("player_death", true); event.SetInt("userid", serial);
    DGM_Event_PlayerDeath(event, "player_death", false); delete event;
    Check(g_hRespawnTimers[1] != null && lastDelay == 0.0 && respawns == 0,
        "forced mode queues zero delay over all policies without synchronous respawn");
    Complete(); Check(respawns == 1, "forced timer bypasses native, internal, Heavy and gamemode restrictions");
    Check(values[2] == 30.0 && values[3] == 20.0 && values[4] == 15.0 && values[5] == 12.0,
        "forced mode preserves configured delays");

    Reset(); values[1] = 1.0; team = 1; DGM_ScheduleDeathRespawn(1);
    Check(g_hRespawnTimers[1] == null, "spectator cannot receive instant respawn");
    team = 2; DGM_ScheduleDeathRespawn(1); alive = true; Complete();
    Check(respawns == 0, "already-alive client cannot respawn twice");
    alive = false; DGM_ScheduleDeathRespawn(1); team = 3; Complete();
    Check(respawns == 0, "team change invalidates instant timer");
    team = 2; DGM_ScheduleDeathRespawn(1); Complete(serial + 1);
    Check(respawns == 0, "reused client session cannot satisfy timer");
    DGM_ScheduleDeathRespawn(1); inGame = false; Complete();
    Check(respawns == 0, "disconnected client cannot respawn");

    Reset(); values[8] = 1.0; nativeWaves = true;
    Change(true);
    Check(!nativeWaves && lastDelay == 0.0 && g_hRespawnTimers[1] != null,
        "enabling suspends native waves and reconciles already-dead clients");
    Check(values[9] == 1.0, "instant mode enables instant visual state");
    Change(false);
    Check(nativeWaves && g_hRespawnTimers[1] == null && values[9] == 0.0,
        "disabling cancels instant timer and restores native waves and HUD");
    Check(values[2] == 3.0 && values[8] == 1.0, "native policy selector unchanged across toggle");

    Reset(); Change(true); Change(false);
    Check(g_hRespawnTimers[1] != null && lastDelay == 3.0,
        "disabling with legacy mode rearms configured delay");
    Complete(); Check(respawns == 1, "restored legacy timer operates normally");
    Reset(); values[2] = 30.0; g_InternalOverride = true;
    Change(true); Change(false);
    Check(g_hRespawnTimers[1] == null && values[9] == 0.0,
        "disabling restores explicitly normal respawns");
    Reset(); values[6] = 1.0; heavy = true; Change(true); Change(false);
    Check(g_hRespawnTimers[1] == null && DGM_HasInstantRespawnImmunity(1),
        "Heavy immunity returns when force mode turns off");
    Reset(); values[3] = 8.0; DGM_ScheduleDeathRespawn(1);
    Check(lastDelay == 8.0, "legacy override delay unchanged when disabled");
    DGM_ClearAllRespawnTimers();
    PrintToServer("[InstantRespawnProbe] %d checks, %d failures", checks, failures);
}
