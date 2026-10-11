// Console-only smoke test, refusing to run if any human is connected.
// Creates one disposable bot, exercises stock item lookup/creation, removes it.
// Does not respawn: MGE may deliberately keep unassigned clients spectating.
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
public Plugin myinfo = { name = "Inventory diagnostic ABI probe", author = "Hombre", version = "1.0.0" };
int probeClient;
Handle getLoadout, giveItem;
public void OnPluginStart() {
    GameData loadoutData = new GameData("weapons");
    StartPrepSDKCall(SDKCall_Player);
    PrepSDKCall_SetFromConf(loadoutData, SDKConf_Signature, "CTFPlayer::GetLoadoutItem()");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
    getLoadout = EndPrepSDKCall();
    delete loadoutData;
    GameData itemData = new GameData("weapons.inventory_diagnostics");
    StartPrepSDKCall(SDKCall_Player);
    PrepSDKCall_SetFromConf(itemData, SDKConf_Signature, "CTFPlayer::GiveNamedItem");
    PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
    PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
    giveItem = EndPrepSDKCall();
    delete itemData;
    if (getLoadout == null || giveItem == null) SetFailState("Diagnostic SDK bindings unavailable");
    RegAdminCmd("sm_inventory_diagnostics_probe", Command_Probe, ADMFLAG_ROOT);
}
public void OnPluginEnd() { Cleanup(); delete getLoadout; delete giveItem; }
void Cleanup() {
    if (probeClient > 0 && IsClientConnected(probeClient))
        KickClientEx(probeClient, "Inventory diagnostics complete");
    probeClient = 0;
}
public Action Command_Probe(int client, int args) {
    #pragma unused args
    if (client != 0) return Plugin_Handled;
    for (int target = 1; target <= MaxClients; target++)
        if (IsClientInGame(target) && !IsFakeClient(target)) {
            PrintToServer("[InventoryProbe] Refused: human clients connected.");
            return Plugin_Handled;
        }
    probeClient = CreateFakeClient("InventoryDiagnosticsProbe");
    if (probeClient <= 0) {
        PrintToServer("[InventoryProbe] Could not create disposable bot.");
        return Plugin_Handled;
    }
    ChangeClientTeam(probeClient, 3);
    TFClassType testClasses[] = {TFClass_Heavy, TFClass_Soldier, TFClass_Engineer, TFClass_Spy};
    char itemClasses[][][] = {
        {"tf_weapon_minigun", "tf_weapon_shotgun", "tf_weapon_fists"},
        {"tf_weapon_rocketlauncher", "tf_weapon_shotgun", "tf_weapon_shovel"},
        {"tf_weapon_shotgun", "tf_weapon_pistol", "tf_weapon_wrench"},
        {"tf_weapon_revolver", "tf_weapon_builder", "tf_weapon_knife"}
    };
    int checks, failures;
    for (int i = 0; i < sizeof(testClasses); i++) {
        TF2_SetPlayerClass(probeClient, testClasses[i], false, true);
        checks++;
        if (TF2_GetPlayerClass(probeClient) != testClasses[i]) failures++;
        for (int slot = 0; slot <= 2; slot++) {
            checks++;
            Address item = view_as<Address>(SDKCall(getLoadout, probeClient, testClasses[i], slot, false));
            if (item == Address_Null) { failures++; continue; }
            int weapon = SDKCall(giveItem, probeClient, itemClasses[i][slot], 0, item, false);
            if (weapon <= MaxClients || !IsValidEntity(weapon)) failures++;
            else RemoveEntity(weapon);
        }
    }
    Cleanup();
    PrintToServer("[InventoryProbe] %d checks; %d failures; disposable bot removed", checks, failures);
    return Plugin_Handled;
}
