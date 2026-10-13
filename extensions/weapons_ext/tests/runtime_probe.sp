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
Handle g_GetLoadout;
Handle g_CriticalHelper;
int g_CriticalProbeWeapon = -1;
int g_CriticalCalls;

public Plugin myinfo = {
    name = "Weapons Extension Isolated Probe", author = "Hombre",
    description = "Bounded native feature checks; never use on production", version = "1.0.0"
};

public void OnPluginStart()
{
    RegAdminCmd("sm_weapons_ext_probe", Probe, ADMFLAG_ROOT);
    GameData data = new GameData("tf2.whitelist_policy");
    StartPrepSDKCall(SDKCall_Raw);
    PrepSDKCall_SetFromConf(data, SDKConf_Signature, "GetLoadoutItem");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
    g_GetLoadout = EndPrepSDKCall();
    delete data;
    data = new GameData("sm-tf2.games");
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetVirtual(data.GetOffset("CalcIsAttackCriticalHelper"));
    PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
    g_CriticalHelper = EndPrepSDKCall();
    delete data;
    if (!g_GetLoadout || !g_CriticalHelper) SetFailState("Probe SDK bindings unavailable");
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
    int generatedBefore = g_Generated;
    int weapon = TF2Items_GiveNamedItem(bot, item);
    Check(g_Generated == generatedBefore + 1, "one post forward per native weapon generation");
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
    generatedBefore = g_Generated;
    int wearable = TF2Items_GiveNamedItem(bot, hat);
    Check(g_Generated == generatedBefore + 1, "one post forward per native wearable generation");
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
    if (weapon > MaxClients && IsValidEntity(weapon)) RunLoadoutChecks(bot, weapon);
    int primary = GetPlayerWeaponSlot(bot, 0);
    if (primary > MaxClients && IsValidEntity(primary)) {
        g_CriticalProbeWeapon = primary;
        g_CriticalCalls = 0;
        Check(view_as<bool>(SDKCall(g_CriticalHelper, primary)), "shared critical hook can override helper");
        Check(g_CriticalCalls == 1, "one critical callback per helper invocation");
        g_CriticalProbeWeapon = -1;
    }
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
    if (client == g_Bot && weapon == g_CriticalProbeWeapon) {
        g_CriticalCalls++;
        critical = true;
        return Plugin_Changed;
    }
    return Plugin_Continue;
}

// Demand-driven condition setup must use TF2Tools' own gamedata even though
// the seven components share one CDetour runtime. Calls are no-ops here.
public void TF2_OnConditionAdded(int client, TFCond condition) {}
public void TF2_OnConditionRemoved(int client, TFCond condition) {}

public int ResolveProbeLoadout(int client, int playerClass, int slot)
{
    if (client == g_Bot && playerClass == view_as<int>(TFClass_Soldier) && slot == 1)
        return g_Item;
    return INVALID_ENT_REFERENCE;
}
public void ProbePolicyNotice(int client, WhitelistPolicyReason reason) {}

void RunLoadoutChecks(int bot, int weapon)
{
    WeaponsLoadout_Bind(ResolveProbeLoadout, ProbePolicyNotice);
    bool selected[7];
    selected[1] = true;
    WeaponsLoadout_PublishSelection(bot, view_as<int>(TFClass_Soldier), selected);
    Address expected = GetEntityAddress(weapon) + view_as<Address>(GetEntSendPropOffs(weapon, "m_Item", true));
    int before[6], after[6];
    WeaponsLoadout_GetStats(before);
    WhitelistPolicy_BeginInventory(bot);
    WhitelistPolicy_BeginInventory(bot);
    bool allMatched = true;
    for (int lookup = 0; lookup < 10; lookup++) {
        if (view_as<Address>(SDKCall(g_GetLoadout, GetEntityAddress(bot), TFClass_Soldier, 1, false)) != expected)
            allMatched = false;
    }
    Check(allMatched, "native loadout returns the actual weapon econ view");
    WhitelistPolicy_EndInventory(bot);
    Check(view_as<Address>(SDKCall(g_GetLoadout, GetEntityAddress(bot), TFClass_Soldier, 1, false)) == expected,
          "nested inventory end retains cache");
    WeaponsLoadout_GetStats(after);
    Check(after[3] - before[3] == 1 && after[4] - before[4] == 10, "one resolver call plus ten cache hits");
    WhitelistPolicy_EndInventory(bot);
    WeaponsLoadout_GetStats(before);
    SDKCall(g_GetLoadout, GetEntityAddress(bot), TFClass_Soldier, 1, false);
    SDKCall(g_GetLoadout, GetEntityAddress(bot), TFClass_Soldier, 1, false);
    WeaponsLoadout_GetStats(after);
    Check(after[3] - before[3] == 2, "no cache reuse outside an inventory transaction");
    WhitelistPolicy_BeginInventory(bot);
    WeaponsLoadout_InvalidateClient(bot);
    Check(view_as<Address>(SDKCall(g_GetLoadout, GetEntityAddress(bot), TFClass_Soldier, 1, false)) == expected,
          "explicit invalidation refreshes loadout");
    RemoveEntity(weapon);
    g_Item = INVALID_ENT_REFERENCE;
    Check(view_as<Address>(SDKCall(g_GetLoadout, GetEntityAddress(bot), TFClass_Soldier, 1, false)) != expected,
          "deleted entity is not returned from cache");
    WhitelistPolicy_EndInventory(bot);
    WeaponsLoadout_Unbind();
    WeaponsLoadout_GetStats(after);
    Check(after[1] == 0, "probe resolver ownership released");
}

void Cleanup()
{
    int entity = EntRefToEntIndex(g_Item);
    if (entity > MaxClients && IsValidEntity(entity)) RemoveEntity(entity);
    g_Item = INVALID_ENT_REFERENCE;
    if (g_Bot && IsClientConnected(g_Bot)) KickClient(g_Bot, "isolated extension probe complete");
    g_Bot = 0;
}

public void OnPluginEnd()
{
    WeaponsLoadout_Unbind();
    Cleanup();
    delete g_GetLoadout;
    delete g_CriticalHelper;
}
