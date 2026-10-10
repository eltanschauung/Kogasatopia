// Bounded console-only probe. No cookies, purchases, schemas or live clients
// are changed. The optional disposable fake client is removed immediately.
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <profiler>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <weapons>
#include <whitelist_policy>
public Plugin myinfo = { name = "Weapons native loadout probe", author = "Hombre", version = "1.0.0" };
Handle g_GetLoadout;
int g_Checks, g_Failures;
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int size) {
    MarkNativeAsOptional("WeaponsLoadout_GetStats");
    return APLRes_Success;
}
public void OnPluginStart() {
    GameData data = new GameData("tf2.whitelist_policy");
    StartPrepSDKCall(SDKCall_Raw);
    PrepSDKCall_SetFromConf(data, SDKConf_Signature, "GetLoadoutItem");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
    g_GetLoadout = EndPrepSDKCall();
    delete data;
    if (!g_GetLoadout) SetFailState("GetLoadoutItem SDK binding failed");
    RegAdminCmd("sm_loadout_native_probe", Probe, ADMFLAG_ROOT);
}
void Check(bool condition) {
    g_Checks++;
    if (!condition) { g_Failures++; PrintToServer("[LoadoutProbe] failed_check=%d", g_Checks); }
}
float Benchmark(int target, int playerClass, int slot, int count) {
    Profiler profiler = new Profiler();
    profiler.Start();
    for (int i = 0; i < count; i++) SDKCall(g_GetLoadout, GetEntityAddress(target), playerClass, slot, false);
    profiler.Stop();
    float microseconds = profiler.Time * 1000000.0 / float(count);
    delete profiler;
    return microseconds;
}
public Action Probe(int client, int args) {
    if (client != 0) return Plugin_Handled;
    for (int target = 1; target <= MaxClients; target++) {
        if (IsClientInGame(target) && !IsFakeClient(target)) {
            PrintToServer("[LoadoutProbe] Refusing fake-client tests while humans are connected.");
            return Plugin_Handled;
        }
    }
    int bot = CreateFakeClient("WeaponsLoadoutProbe");
    if (bot <= 0) { PrintToServer("[LoadoutProbe] Could not create disposable fake client."); return Plugin_Handled; }
    g_Checks = 0; g_Failures = 0;
    bool nativeHook = GetFeatureStatus(FeatureType_Native, "WeaponsLoadout_GetStats") == FeatureStatus_Available;
    int stats[6], before[6];
    if (nativeHook) { WeaponsLoadout_GetStats(stats); Check(stats[0] && stats[1]); }
    Address stockView = SDKCall(g_GetLoadout, GetEntityAddress(bot), 1, 0, false);
    Check(stockView != Address_Null);
    // Three small samples include equal SDKCall overhead in baseline and native.
    for (int sample = 0; sample < 3; sample++) {
        float us = Benchmark(bot, 1, 0, 1000);
        PrintToServer("[LoadoutProbe] native=%d stock sample=%d lookup_us=%.3f count=1000", nativeHook, sample, us);
    }
    Check(Weapons_SetPlayerLoadoutItem(bot, TFClass_Sniper, "haloce_sniperrifle", 0));
    WhitelistPolicy_BeginInventory(bot);
    WhitelistPolicy_BeginInventory(bot);
    if (nativeHook) WeaponsLoadout_GetStats(before);
    Address custom = SDKCall(g_GetLoadout, GetEntityAddress(bot), 2, 0, false);
    Check(custom != Address_Null);
    for (int sample = 0; sample < 3; sample++) {
        float us = Benchmark(bot, 2, 0, 1000);
        PrintToServer("[LoadoutProbe] native=%d custom sample=%d lookup_us=%.3f count=1000", nativeHook, sample, us);
    }
    WhitelistPolicy_EndInventory(bot); // A nested end must not expire the cache.
    Check(custom == view_as<Address>(SDKCall(g_GetLoadout, GetEntityAddress(bot), 2, 0, false)));
    if (nativeHook) {
        WeaponsLoadout_GetStats(stats);
        Check(stats[3] - before[3] == 1);
        Check(stats[4] - before[4] == 3001);
        PrintToServer("[LoadoutProbe] custom lookups=%d resolver_calls=%d cache_hits=%d", stats[2] - before[2], stats[3] - before[3], stats[4] - before[4]);
    }
    Weapons_RemovePlayerLoadoutItem(bot, TFClass_Sniper, 0, 0);
    Check(custom != view_as<Address>(SDKCall(g_GetLoadout, GetEntityAddress(bot), 2, 0, false)));
    WhitelistPolicy_EndInventory(bot);
    if (nativeHook) WeaponsLoadout_GetStats(before);
    Check(Weapons_SetPlayerLoadoutItem(bot, TFClass_Sniper, "haloce_sniperrifle", 0));
    SDKCall(g_GetLoadout, GetEntityAddress(bot), 2, 0, false);
    SDKCall(g_GetLoadout, GetEntityAddress(bot), 2, 0, false);
    if (nativeHook) { WeaponsLoadout_GetStats(stats); Check(stats[3] - before[3] == 2); }
    // Verify the native m_Item address matches SourceMod's sendprop-derived
    // address, not merely that the returned pointer is non-null.
    Address placeholder = SDKCall(g_GetLoadout, GetEntityAddress(bot), 2, 0, false);
    bool foundPlaceholder;
    int wearable = -1;
    while ((wearable = FindEntityByClassname(wearable, "tf_wearable")) != -1) {
        Address view = GetEntityAddress(wearable) + view_as<Address>(GetEntSendPropOffs(wearable, "m_Item", true));
        if (view == placeholder) { foundPlaceholder = true; break; }
    }
    Check(foundPlaceholder);
    // One real inventory generation verifies an attached custom weapon too.
    // Only the disposable fake client's transient inventory is touched.
    ChangeClientTeam(bot, 2);
    TF2_SetPlayerClass(bot, TFClass_Sniper);
    TF2_RespawnPlayer(bot);
    // Fake clients have no Steam cookies or real outbound HUD messages. Send
    // the existing inventory notification explicitly to exercise Weapons'
    // normal PlayerLoadoutUpdated control plane without changing any human.
    BfWrite inventoryUpdated = UserMessageToBfWrite(StartMessageOne("PlayerLoadoutUpdated", bot));
    inventoryUpdated.WriteByte(bot);
    EndMessage();
    PrintToServer("[LoadoutProbe] inventory in_game=%d alive=%d team=%d class=%d", IsClientInGame(bot), IsPlayerAlive(bot), GetClientTeam(bot), TF2_GetPlayerClass(bot));
    int weapon = GetPlayerWeaponSlot(bot, 0);
    Check(weapon > MaxClients && IsValidEntity(weapon));
    if (weapon > MaxClients && IsValidEntity(weapon)) {
        char uid[64];
        Check(Weapons_GetItemUIDFromEntity(weapon, uid, sizeof(uid)) && StrEqual(uid, "haloce_sniperrifle"));
        Address expected = GetEntityAddress(weapon) + view_as<Address>(GetEntSendPropOffs(weapon, "m_Item", true));
        Check(expected == view_as<Address>(SDKCall(g_GetLoadout, GetEntityAddress(bot), 2, 0, false)));
    }
    Weapons_RemovePlayerLoadoutItem(bot, TFClass_Sniper, 0, 0);
    KickClientEx(bot, "Loadout probe complete");
    PrintToServer("[LoadoutProbe] checks=%d failures=%d native=%d; disposable client removed", g_Checks, g_Failures, nativeHook);
    return Plugin_Handled;
}
