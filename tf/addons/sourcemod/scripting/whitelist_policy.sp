// SPDX-License-Identifier: GPL-3.0-or-later
// Inspired by Sappykun's whitelist enabler plugin.
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <tf_econ_data>
#include <whitelist_policy>
public Plugin myinfo = {
    name = "TF2 Whitelist Policy",
    author = "Hombre",
    description = "Cached native whitelist enforcement without tournament-mode toggles",
    version = "1.0.0",
    url = ""
};
ConVar g_WhitelistPath;
bool g_PolicyLoaded;
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int maxlength) {
    RegPluginLibrary("whitelist_policy");
    return APLRes_Success;
}
public void OnPluginStart() {
    CreateConVar("sm_enablewhitelist_version", "2.0.0", "Native whitelist policy version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_WhitelistPath = FindConVar("mp_tournament_whitelist");
    if (g_WhitelistPath == null) SetFailState("mp_tournament_whitelist is unavailable");
    g_WhitelistPath.AddChangeHook(OnWhitelistPathChanged);
    RegAdminCmd("sm_whitelist_reload", Command_Reload, ADMFLAG_ROOT, "Reload whitelist policy and schema classifications.");
    RegAdminCmd("sm_whitelist_status", Command_Status, ADMFLAG_GENERIC, "Inspect native whitelist counters.");
    ReloadPolicy();
}
public void OnMapStart() {
    WhitelistPolicy_ResetTransactions();
    ReloadPolicy();
}
public void OnConfigsExecuted() { ReloadPolicy(); }
public void OnWhitelistPathChanged(ConVar convar, const char[] oldValue, const char[] newValue) { ReloadPolicy(); }

bool ReloadPolicy() {
    char relative[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
    g_WhitelistPath.GetString(relative, sizeof(relative));
    if (relative[0] == '/' || StrContains(relative, "..") != -1) {
        LogError("Refusing whitelist path outside the TF2 game directory");
        if (!g_PolicyLoaded) SetFailState("Whitelist path must be game-relative");
        return false;
    }
    BuildPath(Path_SM, path, sizeof(path), "../../%s", relative);
    KeyValues whitelist = new KeyValues("item_whitelist");
    bool imported = relative[0] != '\0' && whitelist.ImportFromFile(path);
    if (!imported && relative[0] != '\0') {
        if (FileExists(path)) {
            delete whitelist;
            if (!g_PolicyLoaded) SetFailState("Could not parse item whitelist");
            LogError("Could not parse item whitelist; keeping previous policy");
            return false;
        }
        LogMessage("Whitelist file is missing; using Valve's allow-all fallback");
    }
    ArrayList definitions = TF2Econ_GetItemList();
    if (definitions == null || definitions.Length == 0) {
        delete definitions; delete whitelist;
        SetFailState("Item schema is unavailable");
        return false;
    }
    bool defaultAllowed = !imported || whitelist.GetNum("unlisted_items_default_to", 0) != 0;
    WhitelistPolicy_BeginPolicy(defaultAllowed);
    char name[256], entityClass[128];
    int count = definitions.Length;
    for (int i = 0; i < count; i++) {
        int index = definitions.Get(i);
        if (!TF2Econ_GetItemName(index, name, sizeof(name))) continue;
        entityClass[0] = '\0';
        TF2Econ_GetItemClassName(index, entityClass, sizeof(entityClass));
        int classification;
        if (StrEqual(entityClass, "tf_wearable") || StrEqual(entityClass, "tf_weapon_wearable"))
            classification = WHITELIST_CLASS_WEARABLE;
        else if (StrEqual(entityClass, "tf_wearable_demoshield")) classification = WHITELIST_CLASS_SHIELD;
        else if (StrEqual(entityClass, "tf_weapon_sword") || StrEqual(entityClass, "tf_weapon_katana"))
            classification = WHITELIST_CLASS_SWORD;
        bool allowed = imported ? whitelist.GetNum(name, defaultAllowed ? 1 : 0) != 0 : true;
        WhitelistPolicy_RegisterDefinition(index, classification, allowed);
    }
    WhitelistPolicy_CommitPolicy();
    g_PolicyLoaded = true;
    delete definitions; delete whitelist;
    LogMessage("Whitelist policy rebuilt: schema=%d default_allowed=%d", count, defaultAllowed);
    return true;
}
public Action Command_Reload(int client, int args) {
    if (ReloadPolicy())
        ReplyToCommand(client, "[Whitelist] Policy reload complete.");
    else
        ReplyToCommand(client, "[Whitelist] Reload failed; previous policy retained. Check the error log.");
    return Plugin_Handled;
}
public Action Command_Status(int client, int args) {
    int stats[5]; WhitelistPolicy_GetStats(stats);
    ReplyToCommand(client, "[Whitelist] ready=%d generation=%d checks=%d combo_scans=%d denials=%d; tournament convar untouched",
        stats[0], stats[1], stats[2], stats[3], stats[4]);
    return Plugin_Handled;
}
