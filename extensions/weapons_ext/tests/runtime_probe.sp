/** Console-only isolated-server probe. No database or production configuration. */
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <weapons_ext>
#include <tf2_stocks>

int g_Failures;
int g_Checks;
int g_Bot;
int g_Item = INVALID_ENT_REFERENCE;
int g_Generated;

public Plugin myinfo = {
    name = "Weapons Extension Isolated Probe", author = "Hombre",
    description = "Bounded native feature checks; never use on production", version = "1.0.0"
};

public void OnPluginStart()
{
    RegAdminCmd("sm_weapons_ext_probe", Probe, ADMFLAG_ROOT);
}

void Check(bool result, const char[] label)
{
    g_Checks++;
    if (!result) { g_Failures++; PrintToServer("[WeaponsExtProbe] FAIL: %s", label); }
}

public Action Probe(int client, int args)
{
    if (client != 0) return Plugin_Handled;
    for (int other = 1; other <= MaxClients; other++)
        if (IsClientConnected(other) && !IsFakeClient(other)) {
            PrintToServer("[WeaponsExtProbe] Refusing a server with human clients.");
            return Plugin_Handled;
        }
    if (g_Bot) return Plugin_Handled;
    g_Checks = 0; g_Failures = 0; g_Generated = 0;
    Check(LibraryExists("weapons_ext"), "unified library");
    Check(!LibraryExists("TF2Items") && !LibraryExists("scattergun_pellets"), "no legacy extension libraries");
    g_Bot = CreateFakeClient("WeaponsExt isolated probe");
    if (!g_Bot) { Check(false, "create disposable fake client"); return Plugin_Handled; }
    ChangeClientTeam(g_Bot, 2);
    TF2_SetPlayerClass(g_Bot, TFClass_Soldier);
    TF2_RespawnPlayer(g_Bot);
    CreateTimer(0.2, RunChecks, GetClientUserId(g_Bot), TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Handled;
}

public Action RunChecks(Handle timer, int userid)
{
    for (int other = 1; other <= MaxClients; other++) {
        if (IsClientConnected(other) && !IsFakeClient(other)) {
            Cleanup();
            PrintToServer("[WeaponsExtProbe] Stopped: a human client connected.");
            return Plugin_Stop;
        }
    }
    int bot = GetClientOfUserId(userid);
    if (bot != g_Bot || !bot || !IsClientInGame(bot)) return Plugin_Stop;
    Check(IsPlayerAlive(bot), "TF2Tools respawn");
    TF2_RegeneratePlayer(bot);
    Check(GetPlayerWeaponSlot(bot, 0) > MaxClients, "stock inventory regeneration");
    Check(TF2_GetClass("soldier") == TFClass_Soldier, "TF2Tools class lookup");

    Handle item = TF2Items_CreateItem(OVERRIDE_ALL | FORCE_GENERATION);
    TF2Items_SetClassname(item, "tf_weapon_shotgun_soldier");
    TF2Items_SetItemIndex(item, 10);
    TF2Items_SetQuality(item, 6);
    TF2Items_SetLevel(item, 10);
    TF2Items_SetNumAttributes(item, 1);
    TF2Items_SetAttribute(item, 0, 1, 1.0);
    Check(TF2Items_GetItemIndex(item) == 10 && TF2Items_GetLevel(item) == 10, "item handle properties");
    int weapon = TF2Items_GiveNamedItem(bot, item);
    delete item;
    Check(weapon > MaxClients && IsValidEntity(weapon), "native item generation");
    if (weapon > MaxClients && IsValidEntity(weapon)) {
        g_Item = EntIndexToEntRef(weapon);
        TF2Spread_SetPattern(weapon, TF2Spread_Circular15);
        TF2Spread_SetPattern(weapon, TF2Spread_WideHorizontal20);
        TF2Spread_SetPattern(weapon, TF2Spread_Default);
        TF2Spread_SetAmbassadorAccuracy(weapon, true);
        Check(TF2Spread_IsAmbassadorAccuracyRecovered(weapon), "initial accuracy recovery");
        TF2Spread_SetAmbassadorAccuracy(weapon, false);
        TF2Weapon_SetPunchAngle(weapon, true, 0, true);
        TF2Weapon_SetPunchAngle(weapon, false, 0, false);
        TF2Scatter_SetWeaponPelletCount(weapon, 15);
        Check(!TF2Scatter_IsCurrentShotFull(bot, bot, weapon), "no fabricated pellet completion");
        TF2Scatter_SetWeaponPelletCount(weapon, 0);
    }
    Check(g_Generated > 0, "item generation post forward");
    Handle hat = TF2Items_CreateItem(OVERRIDE_ALL | FORCE_GENERATION);
    TF2Items_SetClassname(hat, "tf_wearable");
    TF2Items_SetItemIndex(hat, 54);
    TF2Items_SetQuality(hat, 6);
    TF2Items_SetLevel(hat, 10);
    TF2Items_SetNumAttributes(hat, 0);
    int wearable = TF2Items_GiveNamedItem(bot, hat);
    delete hat;
    Check(wearable > MaxClients && IsValidEntity(wearable), "native wearable generation");
    if (wearable > MaxClients && IsValidEntity(wearable)) {
        Check(GetEntProp(wearable, Prop_Send, "m_iItemDefinitionIndex") == 54, "wearable econ view");
        RemoveEntity(wearable);
    }
    Check(TF2Scatter_GetLastKillPellets(bot, bot) == 0 && !TF2Scatter_WasLastKillFull(bot, bot), "initial pellet state");

    TF2ConchNoSpeed_AddRegenBuff(bot, 10.0, bot);
    Check(TF2ConchNoSpeed_IsRegenBuffActive(bot), "Conch native state");
    Check(TF2_IsPlayerInCondition(bot, TFCond_RegenBuffed), "Conch regen condition");
    Check(!TF2_IsPlayerInCondition(bot, TFCond_SpeedBuffAlly), "Conch does not grant speed");
    TF2_AddCondition(bot, TFCond_SpeedBuffAlly, 10.0);
    TF2ConchNoSpeed_RemoveRegenBuff(bot);
    Check(TF2_IsPlayerInCondition(bot, TFCond_SpeedBuffAlly), "independent speed survives regen removal");
    Check(!TF2ConchNoSpeed_IsRegenBuffActive(bot), "Conch removal state");
    TF2_RemoveCondition(bot, TFCond_SpeedBuffAlly);

    TF2SentryNewTarget_SetDistance(200.0);
    TF2SentryNewTarget_SetEnabled(true);
    Check(TF2SentryNewTarget_GetRangeOffset() > 0, "sentry range binding");
    TF2SentryNewTarget_SetEnabled(false);

    WhitelistPolicy_BeginPolicy(true);
    WhitelistPolicy_RegisterDefinition(10, 0, true);
    WhitelistPolicy_CommitPolicy();
    int stats[5]; WhitelistPolicy_GetStats(stats);
    Check(stats[0] == 1 && stats[1] > 0, "whitelist policy commit");
    int loadoutStats[6]; WeaponsLoadout_GetStats(loadoutStats);
    Check(loadoutStats[1] == 0, "no production resolver owner");
    PrintToServer("[WeaponsExtProbe] %d checks, %d failures. Feature API calls completed.", g_Checks, g_Failures);
    Cleanup();
    return Plugin_Stop;
}

public int TF2Items_OnGiveNamedItem_Post(int client, char[] classname, int definition, int level, int quality, int entity)
{
    if (client == g_Bot && entity > MaxClients) g_Generated++;
    return 0;
}

public Action TF2_CalcIsAttackCritical(int client, int weapon, char[] classname, bool &critical)
{
    return Plugin_Continue;
}

void Cleanup()
{
    int entity = EntRefToEntIndex(g_Item);
    if (entity > MaxClients && IsValidEntity(entity)) RemoveEntity(entity);
    g_Item = INVALID_ENT_REFERENCE;
    if (g_Bot && IsClientConnected(g_Bot)) KickClient(g_Bot, "isolated extension probe complete");
    g_Bot = 0;
}

public void OnPluginEnd() { Cleanup(); }
