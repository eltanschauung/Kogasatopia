// Ownerless virtual ABI/lifecycle probe. No Weapons reload or player changes.
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <dhooks>
#define WEAPONS_SOUND_MAX_ENTITIES 2049
DynamicHook deployHook, g_WeaponsSoundDeployFinishFrameHook;
Handle deployCall, frameCall;
int g_iWeaponsDeployFrameHook[WEAPONS_SOUND_MAX_ENTITIES];
int g_iWeaponsDeployFinishRef[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
int g_iWeaponsDeployFinishEntity[MAXPLAYERS + 1];
int g_iWeaponsDeployFinishHook[MAXPLAYERS + 1];
int g_iWeaponsDeployFinishClient[WEAPONS_SOUND_MAX_ENTITIES];
int frameId, readyCalls, frameCalls, removedCalls, failedDeploys, checks, failures;
#define WeaponsSound_ItemPostFramePre ProbeReadyPre
#define WeaponsSound_DeployFinishHookRemoved ProbeRemoved
#include "deploy_cleanup_under_test.inc"
#undef WeaponsSound_ItemPostFramePre
#undef WeaponsSound_DeployFinishHookRemoved

void Check(bool ok, const char[] label) {
    checks++;
    if (!ok) { failures++; PrintToServer("[DeployFinishedEngineProbe] FAIL: %s", label); }
}
public MRESReturn ProbeDeployPost(int weapon, DHookReturn result) {
    if (!result.Value) failedDeploys++;
    else {
        frameId = WeaponsSound_AddDeployFinishHook(weapon);
        // Simulated owner; these fields only belong to this isolated probe.
        g_iWeaponsDeployFinishRef[1] = EntIndexToEntRef(weapon);
        g_iWeaponsDeployFinishEntity[1] = weapon;
        g_iWeaponsDeployFinishHook[1] = frameId;
        g_iWeaponsDeployFinishClient[weapon] = 1;
    }
    return MRES_Ignored;
}
public MRESReturn ProbeDeployPre(int weapon, DHookReturn result) {
    #pragma unused weapon
    // Exercise successful post-hook nesting without a player-owned Deploy.
    result.Value = true;
    return MRES_Supercede;
}
public MRESReturn ProbeReadyPre(int weapon) {
    #pragma unused weapon
    frameCalls++;
    if (frameId != INVALID_HOOK_ID) {
        readyCalls++;
        // Native regression: run real cancellation inside its executing hook.
        // The old synchronous removal path crashed at this boundary.
        WeaponsSound_CancelDeployFinish(1);
        frameId = INVALID_HOOK_ID;
    }
    return MRES_Ignored;
}
public void ProbeRemoved(int id) {
    #pragma unused id
    removedCalls++;
}
public void OnPluginStart() {
    RegAdminCmd("sm_deploy_finished_engine_probe", Command_Probe, ADMFLAG_ROOT);
}
public Action Command_Probe(int client, int args) {
    #pragma unused client, args
    checks = 0; failures = 0; readyCalls = 0; frameCalls = 0; removedCalls = 0; failedDeploys = 0;
    GameData data = new GameData("weapons.deploy_finished");
    if (data == null) { PrintToServer("[DeployFinishedEngineProbe] Missing gamedata"); return Plugin_Handled; }
    deployHook = DynamicHook.FromConf(data, "CTFWeaponBase::Deploy");
    g_WeaponsSoundDeployFinishFrameHook = DynamicHook.FromConf(data, "CTFWeaponBase::ItemPostFrame");
    Check(deployHook != null && g_WeaponsSoundDeployFinishFrameHook != null, "both hook configs load");
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetVirtual(data.GetOffset("CTFWeaponBase::Deploy"));
    PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
    deployCall = EndPrepSDKCall();
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetVirtual(data.GetOffset("CTFWeaponBase::ItemPostFrame"));
    frameCall = EndPrepSDKCall();
    delete data;
    Check(deployCall != null && frameCall != null, "both virtual calls prepare");
    if (deployHook == null || g_WeaponsSoundDeployFinishFrameHook == null || deployCall == null || frameCall == null)
        return Plugin_Handled;
    char classes[][] = { "tf_weapon_pistol", "tf_weapon_knife" };
    for (int i = 0; i < sizeof(classes); i++) {
        int weapon = CreateEntityByName(classes[i]);
        Check(weapon > MaxClients, "temporary weapon created");
        if (weapon <= MaxClients) continue;
        int deployId = deployHook.HookEntity(Hook_Post, weapon, ProbeDeployPost);
        Check(deployId != INVALID_HOOK_ID, "Deploy post-hook attaches");
        bool deployed = SDKCall(deployCall, weapon);
        Check(!deployed && failedDeploys == i + 1, "failed Deploy return detected");
        int successId = deployHook.HookEntity(Hook_Pre, weapon, ProbeDeployPre);
        Check(successId != INVALID_HOOK_ID, "safe synthetic successful Deploy pre-hook attaches");
        deployed = SDKCall(deployCall, weapon);
        int id = g_iWeaponsDeployFrameHook[weapon];
        Check(deployed && id != INVALID_HOOK_ID, "successful Deploy post-hook installs lifetime frame hook");
        int before = readyCalls;
        bool sameId = true;
        for (int deployment = 0; deployment < 100; deployment++) {
            deployed = SDKCall(deployCall, weapon);
            if (!deployed) sameId = false;
            if (frameId != id) sameId = false;
            SDKCall(frameCall, weapon);
            SDKCall(frameCall, weapon);
        }
        Check(sameId && readyCalls == before + 100, "100 deployments reuse one hook and consume once each");
        Check(g_iWeaponsDeployFrameHook[weapon] == id && removedCalls == 0,
            "no runtime physical hook removal");
        g_iWeaponsDeployFrameHook[weapon] = INVALID_HOOK_ID;
        RemoveEntity(weapon);
    }
    RequestFrame(ProbeReport);
    return Plugin_Handled;
}
public void ProbeReport(any unused) {
    #pragma unused unused
    Check(removedCalls == 2, "entity destruction removes lifetime frame hooks");
    Check(frameCalls == 400, "all real virtual frame callbacks completed");
    Check(g_iWeaponsDeployFinishHook[1] == INVALID_HOOK_ID
        && g_iWeaponsDeployFinishRef[1] == INVALID_ENT_REFERENCE,
        "production cancellation inside executing hook safely clears pending state");
    delete deployHook; delete g_WeaponsSoundDeployFinishFrameHook;
    delete deployCall; delete frameCall;
    PrintToServer("[DeployFinishedEngineProbe] %d checks; %d failures; 200 deployments; no player changes",
        checks, failures);
}
