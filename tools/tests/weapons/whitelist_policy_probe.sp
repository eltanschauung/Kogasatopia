// Read-only ABI/inventory probe: never equips, respawns, changes a convar or schema.
// Console-only "bot" argument creates and immediately removes a disposable client.
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <tf_econ_data>
#include <whitelist_policy>
public Plugin myinfo = { name = "Whitelist read-only regression probe", author = "Hombre", version = "1.0.0" };
Handle getSelected, getBase, getIndex;
Address manager;
int inventoryOffset, qualityOffset, initializedOffset, checks, failures;
public void OnPluginStart() {
    GameData config = new GameData("tf2.whitelist_policy");
    inventoryOffset = config.GetOffset("Inventory");
    getSelected = Prepare(config, SDKCall_Raw, "GetItemInLoadout", 2);
    getBase = Prepare(config, SDKCall_Raw, "GetBaseItemForClass", 2);
    getIndex = Prepare(config, SDKCall_Raw, "GetItemDefIndex", 0);
    Handle getManager = Prepare(config, SDKCall_Static, "TFInventoryManager", 0);
    manager = SDKCall(getManager);
    delete getManager; delete config;
    qualityOffset = FindSendPropInfo("CEconEntity", "m_iEntityQuality") - FindSendPropInfo("CEconEntity", "m_Item");
    initializedOffset = FindSendPropInfo("CEconEntity", "m_bInitialized") - FindSendPropInfo("CEconEntity", "m_Item");
    RegAdminCmd("sm_whitelist_probe", Command_Probe, ADMFLAG_ROOT);
}
Handle Prepare(GameData config, SDKCallType kind, const char[] name, int count) {
    StartPrepSDKCall(kind);
    PrepSDKCall_SetFromConf(config, SDKConf_Signature, name);
    for (int i = 0; i < count; i++) PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
    Handle call = EndPrepSDKCall();
    if (call == null) SetFailState("Probe SDK binding failed");
    return call;
}
int Classification(Address selected) {
    char entityClass[128];
    if (selected == Address_Null) return 0;
    int index = SDKCall(getIndex, selected);
    TF2Econ_GetItemClassName(index, entityClass, sizeof(entityClass));
    if (StrEqual(entityClass, "tf_wearable") || StrEqual(entityClass, "tf_weapon_wearable"))
        return WHITELIST_CLASS_WEARABLE;
    if (StrEqual(entityClass, "tf_wearable_demoshield")) return WHITELIST_CLASS_SHIELD;
    if (StrEqual(entityClass, "tf_weapon_sword") || StrEqual(entityClass, "tf_weapon_katana"))
        return WHITELIST_CLASS_SWORD;
    return 0;
}
void Check(bool result) { checks++; if (!result) failures++; }
public Action Command_Probe(int client, int args) {
    checks = 0; failures = 0;
    int temporaryClient;
    if (client == 0 && args == 1) {
        char argument[16]; GetCmdArg(1, argument, sizeof(argument));
        if (StrEqual(argument, "bot")) {
            temporaryClient = CreateFakeClient("WhitelistPolicyProbe");
            Check(temporaryClient > 0);
        }
    }
    int stats[5]; WhitelistPolicy_GetStats(stats); Check(stats[0] != 0);
    Address replacement = view_as<Address>(1);
    Check(WhitelistPolicy_Evaluate(0, 4, 0, replacement) == WhitelistPolicy_Allowed);
    Check(replacement == Address_Null);
    for (int playerClass = 1; playerClass <= 9; playerClass++) {
        for (int slot = 0; slot < 3; slot++) {
            Address base = SDKCall(getBase, manager, playerClass, slot);
            if (playerClass == 8 && slot == 0) continue;
            Check(base != Address_Null);
            Check(LoadFromAddress(base + view_as<Address>(initializedOffset), NumberType_Int8) != 0);
            Check(LoadFromAddress(base + view_as<Address>(qualityOffset), NumberType_Int32) == 0);
        }
    }
    int testedClients;
    for (int target = 1; target <= MaxClients; target++) {
        if (!IsClientInGame(target) || IsClientSourceTV(target) || IsClientReplay(target)) continue;
        testedClients++;
        Address inventory = GetEntityAddress(target) + view_as<Address>(inventoryOffset);
        bool forbidden = (Classification(SDKCall(getSelected, inventory, 4, 0)) & WHITELIST_CLASS_WEARABLE) != 0
            && (Classification(SDKCall(getSelected, inventory, 4, 1)) & WHITELIST_CLASS_SHIELD) != 0
            && (Classification(SDKCall(getSelected, inventory, 4, 2)) & WHITELIST_CLASS_SWORD) != 0;
        WhitelistPolicy_BeginInventory(target);
        WhitelistPolicy_BeginInventory(target);
        for (int playerClass = 1; playerClass <= 9; playerClass++) {
            for (int slot = 0; slot < 7; slot++) {
                WhitelistPolicyReason actual = WhitelistPolicy_Evaluate(target, playerClass, slot, replacement);
                // Live whitelist is allow-all. Combo restriction still has priority.
                WhitelistPolicyReason expected = playerClass == 4 && slot <= 2 && forbidden
                    ? WhitelistPolicy_DemoCombination : WhitelistPolicy_Allowed;
                Check(actual == expected);
                if (actual != WhitelistPolicy_Allowed)
                    Check(replacement == view_as<Address>(SDKCall(getBase, manager, playerClass, slot)));
            }
        }
        WhitelistPolicy_EndInventory(target);
        WhitelistPolicy_EndInventory(target);
    }
    ReplyToCommand(client, "[WhitelistProbe] checks=%d failures=%d clients=%d; inventories untouched", checks, failures, testedClients);
    if (temporaryClient > 0 && IsClientConnected(temporaryClient))
        KickClientEx(temporaryClient, "Whitelist validation complete");
    return Plugin_Handled;
}
