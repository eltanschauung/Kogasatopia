#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <tf2utils>
#include <tf_custom_attributes>

native bool WeaponsDebug_SoundState(int weapon, int state[7]);
public Plugin myinfo = {name="Weapons Sound Hook Regression", author="Hombre", version="1.0.0"};
int g_BotSerial, g_Step, g_Failures, g_Checks, g_Swings, g_Finishes;
int g_MeleeRef, g_PrimaryRef, g_Before[7];
int g_CritCalls, g_CritCallsBefore;
bool g_Preparing, g_Attack;
bool g_CompletionCleared;
int g_PreviousBotStop;
char g_PreviousForceClass[32];
Handle g_Timer;
#define SAMPLE "tools/ifm/beep.wav"

public void OnPluginStart()
{
    RegAdminCmd("sm_soundhookprobe", StartProbe, ADMFLAG_ROOT);
    AddNormalSoundHook(SoundEmitted);
    HookEvent("post_inventory_application", ProbeInventory);
    HookEvent("player_death", ProbeDeath);
}
bool Bot(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client)
        && IsFakeClient(client) && !IsClientSourceTV(client) && !IsClientReplay(client);
}
public void OnClientPutInServer(int client)
{
    if (g_Preparing && Bot(client) && !g_BotSerial)
    {
        g_BotSerial = GetClientSerial(client);
        g_Preparing = false;
        g_Timer = CreateTimer(1.0, ProbeStep, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}
public Action StartProbe(int client, int args)
{
    bool populated;
    for (int target = 1; target <= MaxClients; target++)
        if (IsClientConnected(target) && (!IsFakeClient(target) || Bot(target))) populated = true;
    if (g_Preparing || g_Timer != null || populated)
    {
        ReplyToCommand(client, "[SoundProbe] Refused: server must be empty.");
        return Plugin_Handled;
    }
    g_Preparing = true;
    g_BotSerial = 0; g_Step = 0; g_Checks = 0; g_Failures = 0;
    g_Swings = 0; g_Finishes = 0;
    g_CritCalls = 0;
    g_CompletionCleared = false;
    g_PreviousBotStop = FindConVar("nb_stop").IntValue;
    // Unlike inventory-only stress, the probe needs real ItemPostFrame/input
    // processing. nb_stop suppresses bot commands and would invalidate it.
    FindConVar("nb_stop").IntValue = 0;
    FindConVar("tf_bot_force_class").GetString(g_PreviousForceClass, sizeof(g_PreviousForceClass));
    FindConVar("tf_bot_force_class").SetString("soldier");
    PrecacheSound(SAMPLE, true);
    int trigger = -1;
    while ((trigger = FindEntityByClassname(trigger, "trigger_regenerate")) != -1)
    {
        SDKHook(trigger, SDKHook_StartTouch, IgnoreProbeResupply);
        SDKHook(trigger, SDKHook_Touch, IgnoreProbeResupply);
    }
    ServerCommand("tf_bot_add 1 soldier red easy noquota SoundHookProbe");
    return Plugin_Handled;
}
void Check(bool condition, const char[] label)
{
    g_Checks++;
    if (!condition) g_Failures++;
    PrintToServer("[SoundProbe] %s %s", condition ? "PASS" : "FAIL", label);
    LogMessage("[SoundProbe] %s %s", condition ? "PASS" : "FAIL", label);
}
public Action ProbeStep(Handle timer)
{
    int bot = GetClientFromSerial(g_BotSerial);
    if (!Bot(bot)) { FinishProbe(bot, "bot_missing"); g_Timer = null; return Plugin_Stop; }
    // Never continue the experiment when an ordinary human arrives.
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientConnected(client) && !IsFakeClient(client))
        { FinishProbe(bot, "human_joined"); g_Timer = null; return Plugin_Stop; }
    int melee = EntRefToEntIndex(g_MeleeRef), primary = EntRefToEntIndex(g_PrimaryRef);
    LogMessage("[SoundProbe] state step=%d alive=%d class=%d melee_valid=%d primary_valid=%d",
        g_Step, IsPlayerAlive(bot), TF2_GetPlayerClass(bot), melee > MaxClients, primary > MaxClients);
    int state[7];
    switch (g_Step++)
    {
        case 0:
        {
            TF2_SetPlayerClass(bot, TFClass_Soldier);
            TF2_RespawnPlayer(bot);
            TF2_RegeneratePlayer(bot);
            SetEntityMoveType(bot, MOVETYPE_NONE);
        }
        case 1:
        {
            // Let asynchronous spawn/inventory initialization settle before
            // retaining entity references for the lifecycle assertions.
            melee = GetPlayerWeaponSlot(bot, TFWeaponSlot_Melee);
            primary = GetPlayerWeaponSlot(bot, TFWeaponSlot_Primary);
            Check(melee > MaxClients && primary > MaxClients, "stock inventory exists");
            if (melee <= MaxClients || primary <= MaxClients)
            { FinishProbe(bot, "missing_inventory"); g_Timer = null; return Plugin_Stop; }
            g_MeleeRef = EntIndexToEntRef(melee); g_PrimaryRef = EntIndexToEntRef(primary);
            WeaponsDebug_SoundState(primary, state);
            Check(state[0] == 0 && state[1] == 0 && state[2] == 0 && state[3] == 0 && state[4] == 0,
                "unfeatured stock weapon has zero sound/deploy hooks");
            TF2CustAttr_SetString(melee, "custom melee swing sound", SAMPLE);
            WeaponsDebug_SoundState(melee, state);
            Check(state[0] == 1 && state[1] != 0 && state[2] != 0 && state[3] == 0 && state[4] == 0,
                "late melee attribute installs only swing hooks");
            for (int i = 0; i < 7; i++) g_Before[i] = state[i];
            TF2CustAttr_SetString(primary, "custom melee swing sound", SAMPLE);
            WeaponsDebug_SoundState(primary, state);
            Check(state[0] == 0 && state[1] == 0 && state[2] == 0,
                "ranged weapon does not receive melee hooks");
            Check(TF2Util_SetPlayerActiveWeapon(bot, melee), "normal switch to melee succeeds");
        }
        case 2: { g_Attack = true; }
        case 3:
        {
            g_Attack = false;
            Check(g_Swings > 0, "melee attacks emit custom swing sample");
            Check(g_CritCalls > 0, "critical-hit forward still executes for melee");
            for (int i = 0; i < 20; i++) TF2CustAttr_SetString(melee, "custom melee swing sound", SAMPLE);
            WeaponsDebug_SoundState(melee, state);
            Check(state[1] == g_Before[1] && state[2] == g_Before[2],
                "repeated assignment reuses identical hooks");
            TF2CustAttr_SetString(melee, "custom melee swing sound", "");
            WeaponsDebug_SoundState(melee, state);
            Check(state[0] == 0 && state[1] == g_Before[1] && state[2] == g_Before[2],
                "attribute removal makes retained hooks inert");
            g_Swings = 0; g_Attack = true;
        }
        case 4:
        {
            g_Attack = false;
            Check(g_Swings == 0, "removed melee attribute emits nothing");
            // Assign after a successful Deploy: first ItemPostFrame must still
            // be observed, without treating Deploy itself as completion.
            Check(TF2Util_SetPlayerActiveWeapon(bot, primary), "normal primary switch succeeds");
            TF2CustAttr_SetString(primary, "custom deploy finished sound", SAMPLE);
            WeaponsDebug_SoundState(primary, state);
            Check(state[0] == 2 && state[1] == 0 && state[2] == 0 && state[3] != 0 && state[4] != 0,
                "mid-deploy assignment installs only deploy hooks");
            Check(state[5] == bot, "mid-deploy assignment arms completion");
            for (int i = 0; i < 7; i++) g_Before[i] = state[i];
            Check(g_Finishes == 0, "finished sound not emitted at switch start");
        }
        case 5:
        {
            Check(g_Finishes == 1, "one finished sound on first operational frame");
            WeaponsDebug_SoundState(primary, state);
            Check(g_CompletionCleared, "completion clears pending owner before emission");
            KeyValues empty = new KeyValues("CustomAttributes");
            Check(TF2CustAttr_UseKeyValues(primary, empty), "full KeyValues replacement succeeds");
            delete empty;
            TF2CustAttr_SetString(primary, "custom deploy finished sound", SAMPLE);
            WeaponsDebug_SoundState(primary, state);
            Check(state[3] == g_Before[3] && state[4] == g_Before[4] && state[5] == 0,
                "ready-weapon assignment retains hooks and does not re-arm");
            TF2Util_SetPlayerActiveWeapon(bot, melee);
        }
        case 6:
        {
            TF2Util_SetPlayerActiveWeapon(bot, primary);
            TF2Util_SetPlayerActiveWeapon(bot, melee);
            WeaponsDebug_SoundState(primary, state);
            Check(state[5] == 0, "switch away cancels pending completion");
        }
        case 7:
        {
            Check(g_Finishes == 1, "cancelled switch emits no finished sound");
            TF2Util_SetPlayerActiveWeapon(bot, primary);
            ForcePlayerSuicide(bot);
            WeaponsDebug_SoundState(primary, state);
            Check(state[5] == 0, "death cancels pending completion");
        }
        case 8:
        {
            Check(g_Finishes == 1, "death emits no finished sound");
            FindConVar("tf_bot_force_class").SetString("scout");
            TF2_SetPlayerClass(bot, TFClass_Scout);
            TF2_RespawnPlayer(bot);
        }
        case 9:
        {
            // Respawn can replace inventory on the following frame. Resolve
            // the new slot only after that work has completed, not immediately
            // after TF2_RespawnPlayer while the old entity is still present.
            Check(EntRefToEntIndex(g_PrimaryRef) == INVALID_ENT_REFERENCE,
                "class change invalidates old weapon reference after deferred cleanup");
            primary = GetPlayerWeaponSlot(bot, TFWeaponSlot_Primary);
            if (primary <= MaxClients)
            { FinishProbe(bot, "missing_scout_inventory"); g_Timer = null; return Plugin_Stop; }
            WeaponsDebug_SoundState(primary, state);
            Check(state[0] == 0 && state[1] == 0 && state[2] == 0 && state[3] == 0 && state[4] == 0,
                "new entity generation has no stale sound hooks");
            g_CritCallsBefore = g_CritCalls;
            TF2Util_SetPlayerActiveWeapon(bot, primary);
            g_Attack = true;
        }
        case 10:
        {
            Check(g_CritCalls > g_CritCallsBefore, "critical-hit forward survives class/entity changes");
            FinishProbe(bot, "complete"); g_Timer = null; return Plugin_Stop;
        }
    }
    return Plugin_Continue;
}
public void ProbeInventory(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && g_BotSerial && GetClientSerial(client) == g_BotSerial)
        LogMessage("[SoundProbe] inventory event at step=%d", g_Step);
}
public Action IgnoreProbeResupply(int trigger, int client)
{
    return client > 0 && client <= MaxClients && g_BotSerial
        && GetClientSerial(client) == g_BotSerial ? Plugin_Handled : Plugin_Continue;
}
public Action TF2_CalcIsAttackCritical(int client, int weapon, char[] weaponname, bool &result)
{
    if (client > 0 && g_BotSerial && GetClientSerial(client) == g_BotSerial)
    {
        g_CritCalls++;
        if (g_Attack) { result = true; return Plugin_Changed; }
    }
    return Plugin_Continue;
}
public void ProbeDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && g_BotSerial && GetClientSerial(client) == g_BotSerial)
        LogMessage("[SoundProbe] death event at step=%d customkill=%d", g_Step, event.GetInt("customkill"));
}
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse,
    float velocity[3], float angles[3], int &weapon)
{
    if (g_BotSerial && GetClientSerial(client) == g_BotSerial)
    {
        buttons = g_Attack ? IN_ATTACK : 0;
        weapon = 0;
        impulse = 0;
        velocity[0] = 0.0; velocity[1] = 0.0; velocity[2] = 0.0;
    }
    return Plugin_Continue;
}
public Action SoundEmitted(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH],
    int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
    char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
    if (entity == GetClientFromSerial(g_BotSerial) && StrEqual(sample, SAMPLE))
    {
        if (g_Step <= 4) g_Swings++;
        else
        {
            g_Finishes++;
            int weapon = GetEntPropEnt(entity, Prop_Send, "m_hActiveWeapon");
            int state[7]; WeaponsDebug_SoundState(weapon, state);
            g_CompletionCleared = state[5] == 0;
        }
    }
    return Plugin_Continue;
}
void FinishProbe(int bot, const char[] reason)
{
    if (g_BotSerial || g_Preparing)
    {
        FindConVar("nb_stop").IntValue = g_PreviousBotStop;
        FindConVar("tf_bot_force_class").SetString(g_PreviousForceClass);
    }
    g_Attack = false; g_Preparing = false;
    PrintToServer("[SoundProbe] END reason=%s checks=%d failures=%d", reason, g_Checks, g_Failures);
    LogMessage("[SoundProbe] END reason=%s checks=%d failures=%d", reason, g_Checks, g_Failures);
    if (Bot(bot)) KickClient(bot, "Sound hook test complete");
    g_BotSerial = 0;
}
public void OnMapEnd() { delete g_Timer; FinishProbe(GetClientFromSerial(g_BotSerial), "map_end"); }
public void OnPluginEnd() { delete g_Timer; FinishProbe(GetClientFromSerial(g_BotSerial), "plugin_end"); }
