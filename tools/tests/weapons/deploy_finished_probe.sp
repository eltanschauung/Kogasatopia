// Simulated engine/audio: exercises extracted production state and cooldowns.
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <dhooks>
#define WEAPONS_SOUND_MAX_ENTITIES 2049
#define WEAPONS_DEPLOY_COOLDOWN_SLOT_COUNT 7
#define WEAPONS_LAST_WEAPON_SLOT 5
#define WEAPONS_DEPLOY_COOLDOWN_UNKNOWN_SLOT 6
#define WEAPONS_CUSTOM_DEPLOY_SOUND_COOLDOWN 1.5
#define Weapons_ATTR_CUSTOM_DEPLOY_SOUND "custom deploy sound"
#define Weapons_ATTR_CUSTOM_DEPLOY_FINISHED_SOUND "custom deploy finished sound"
int g_iWeaponsDeployFinishRef[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
int g_iWeaponsDeployFinishEntity[MAXPLAYERS + 1], g_iWeaponsDeployFinishHook[MAXPLAYERS + 1];
int g_iWeaponsDeployFinishClient[WEAPONS_SOUND_MAX_ENTITIES];
int g_iWeaponsDeployFrameHook[WEAPONS_SOUND_MAX_ENTITIES];
int g_iWeaponsSoundWeaponRef[MAXPLAYERS + 1];
char g_sWeaponsSoundGroup[MAXPLAYERS + 1][64];
float g_flWeaponsNextDeploySoundTime[MAXPLAYERS + 1][WEAPONS_DEPLOY_COOLDOWN_SLOT_COUNT];
float g_flWeaponsNextDeployFinishedSoundTime[MAXPLAYERS + 1][WEAPONS_DEPLOY_COOLDOWN_SLOT_COUNT];
bool connected[3], alive[3], cloaked[3], valid[2], failHook;
int owners[2], active[3], refs[2], slots[2], hookSerial, removed, emissions, checks, failures;
float clockTime;
char lastAttribute[64];
bool Weapons_IsValidClient(int client) { return client >= 1 && client <= 2 && connected[client]; }
bool Weapons_IsValidWeaponEntity(int weapon) { return weapon >= 1900 && weapon <= 1901 && valid[weapon - 1900]; }
bool TF2Util_IsEntityWeapon(int weapon) { return Weapons_IsValidWeaponEntity(weapon); }
int TF2Util_GetWeaponSlot(int weapon) { return slots[weapon - 1900]; }
int ProbeRef(int weapon) { return refs[weapon - 1900]; }
int ProbeFromRef(int ref) {
    for (int i = 0; i < 2; i++) if (valid[i] && refs[i] == ref) return 1900 + i;
    return -1;
}
int ProbeProp(int entity, PropType type, const char[] name) {
    #pragma unused type
    if (StrEqual(name, "m_hOwnerEntity")) return owners[entity - 1900];
    return active[entity];
}
bool ProbeAlive(int client) { return alive[client]; }
TFClassType ProbeClass(int client) { return cloaked[client] ? TFClass_Spy : TFClass_Engineer; }
bool ProbeCondition(int client, TFCond condition) {
    return condition == TFCond_Cloaked && cloaked[client];
}
float ProbeTime() { return clockTime; }
int WeaponsSound_AddDeployFinishHook(int weapon) {
    return failHook || !Weapons_IsValidWeaponEntity(weapon) ? INVALID_HOOK_ID : ++hookSerial;
}
public bool ProbeRemove(int id) { removed++; WeaponsSound_DeployFinishHookRemoved(id); return true; }
bool WeaponsSound_EmitCustomAttribute(int client, int weapon, const char[] attribute, const char[] context) {
    #pragma unused context
    if (!Weapons_IsValidClient(client) || !Weapons_IsValidWeaponEntity(weapon)) return false;
    emissions++; strcopy(lastAttribute, sizeof(lastAttribute), attribute); return true;
}
#define EntIndexToEntRef ProbeRef
#define EntRefToEntIndex ProbeFromRef
#define GetEntPropEnt ProbeProp
#define IsPlayerAlive ProbeAlive
#define TF2_GetPlayerClass ProbeClass
#define TF2_IsPlayerInCondition ProbeCondition
#define GetGameTime ProbeTime
#define DHookRemoveHookID ProbeRemove
#include "deploy_under_test.inc"
#undef EntIndexToEntRef
#undef EntRefToEntIndex
#undef GetEntPropEnt
#undef IsPlayerAlive
#undef TF2_GetPlayerClass
#undef TF2_IsPlayerInCondition
#undef GetGameTime
#undef DHookRemoveHookID

void Check(bool ok, const char[] label) {
    checks++;
    if (!ok) { failures++; PrintToServer("[DeployFinishedProbe] FAIL: %s", label); }
}
void Reset() {
    WeaponsSound_ResetClients();
    for (int client = 1; client <= 2; client++) {
        connected[client] = true; alive[client] = true; cloaked[client] = false;
        active[client] = 1900;
    }
    for (int i = 0; i < 2; i++) {
        valid[i] = true; refs[i] = 10000 + i; owners[i] = 1; slots[i] = i;
    }
    failHook = false; emissions = 0; removed = 0; clockTime = 100.0;
}
public void OnPluginStart() {
    RegAdminCmd("sm_deploy_finished_probe", Command_Probe, ADMFLAG_ROOT);
}
public Action Command_Probe(int client, int args) {
    #pragma unused args
    checks = 0; failures = 0;
    Reset(); WeaponsSound_TrackDeployFinish(1, 1900);
    Check(g_iWeaponsDeployFinishRef[1] == 10000 && emissions == 0, "successful deploy arms without sound");
    WeaponsSound_CancelOtherDeploy(1, 1900);
    Check(g_iWeaponsDeployFinishHook[1] != 0, "switch-post preserves newly deployed weapon");
    WeaponsSound_ResetClient(1);
    Check(g_iWeaponsDeployFinishHook[1] != 0, "sound-group refresh preserves pending deployment");
    WeaponsSound_ItemPostFramePre(1900);
    Check(emissions == 1 && StrEqual(lastAttribute, Weapons_ATTR_CUSTOM_DEPLOY_FINISHED_SOUND), "first ready frame emits finished attribute");
    Check(g_iWeaponsDeployFinishRef[1] == INVALID_ENT_REFERENCE && g_iWeaponsDeployFinishHook[1] == 0
        && g_iWeaponsDeployFinishClient[1900] == 0 && removed == 0, "ready clears state without removing hooks");
    WeaponsSound_ItemPostFramePre(1900);
    Check(emissions == 1, "later frames never emit again");

    Reset(); WeaponsSound_TrackDeployFinish(1, 1900); active[1] = 1901;
    WeaponsSound_ItemPostFramePre(1900);
    Check(emissions == 0 && removed == 0, "inactive weapon cancels without removing hooks");
    Reset(); WeaponsSound_TrackDeployFinish(1, 1900);
    WeaponsSound_CancelOtherDeploy(1, 1901); WeaponsSound_ItemPostFramePre(1900);
    Check(emissions == 0 && removed == 0, "later weapon switch clears old pending state");
    Reset(); WeaponsSound_TrackDeployFinish(1, 1900); WeaponsSound_TrackDeployFinish(1, 1901);
    active[1] = 1901; WeaponsSound_ItemPostFramePre(1900);
    Check(emissions == 0 && g_iWeaponsDeployFinishRef[1] == 10001, "new deploy replaces old");
    WeaponsSound_ItemPostFramePre(1901);
    Check(emissions == 1 && removed == 0, "replacement deploy completes once");
    Reset(); WeaponsSound_TrackDeployFinish(1, 1900); refs[0]++;
    WeaponsSound_ItemPostFramePre(1900);
    Check(emissions == 0 && removed == 0, "recycled entity cannot satisfy EntRef");
    Reset(); WeaponsSound_TrackDeployFinish(1, 1900); owners[0] = 2;
    WeaponsSound_ItemPostFramePre(1900);
    Check(emissions == 0 && removed == 0, "owner transfer cancels original client");
    Reset(); WeaponsSound_TrackDeployFinish(1, 1900); owners[0] = 2;
    WeaponsSound_TrackDeployFinish(2, 1900);
    Check(g_iWeaponsDeployFinishHook[1] == 0 && removed == 0,
        "new owner deploy cancels previous owner's pending hook");
    WeaponsSound_ItemPostFramePre(1900);
    Check(emissions == 1 && removed == 0 && g_iWeaponsDeployFinishHook[2] == 0,
        "transferred weapon completes once for new owner");
    Reset(); WeaponsSound_TrackDeployFinish(1, 1900); alive[1] = false;
    WeaponsSound_ItemPostFramePre(1900);
    Check(emissions == 0 && removed == 0, "dead client cannot emit");
    Reset(); WeaponsSound_TrackDeployFinish(1, 1900); connected[1] = false;
    WeaponsSound_ResetClient(1, true);
    Check(g_iWeaponsDeployFinishHook[1] == 0 && removed == 0, "disconnect cleanup does not need in-game client");
    Reset(); WeaponsSound_TrackDeployFinish(1, 1900); valid[0] = false;
    WeaponsSound_DeployFinishHookRemoved(g_iWeaponsDeployFinishHook[1]);
    Check(g_iWeaponsDeployFinishRef[1] == INVALID_ENT_REFERENCE && g_iWeaponsDeployFinishClient[1900] == 0,
        "DHooks destruction removal clears stale EntRef and reverse lookup");
    Reset(); WeaponsSound_TrackDeployFinish(1, 1900);
    g_iWeaponsDeployFrameHook[1900] = 123;
    WeaponsSound_DeployFinishEntityDestroyed(1900);
    Check(g_iWeaponsDeployFinishRef[1] == INVALID_ENT_REFERENCE && g_iWeaponsDeployFrameHook[1900] == 0,
        "entity destruction clears pending state and lifetime hook cache");
    WeaponsSound_DeployFinishEntityDestroyed(0);
    Check(g_iWeaponsDeployFinishClient[1900] == 0, "invalid destroyed entity ignored");
    Reset(); WeaponsSound_TrackDeployFinish(1, 1900);
    WeaponsSound_ResetClients();
    Check(g_iWeaponsDeployFinishHook[1] == 0 && removed == 0, "map/reset clears pending state without hook removal");
    Reset(); alive[1] = false; WeaponsSound_TrackDeployFinish(1, 1900);
    Check(g_iWeaponsDeployFinishHook[1] == 0, "dead client cannot arm");
    Reset(); WeaponsSound_TrackDeployFinish(0, 1900);
    Check(g_iWeaponsDeployFinishClient[1900] == 0, "invalid owner cannot arm");

    Reset(); WeaponsSound_PlayCustomDeploySound(1, 1900);
    Check(emissions == 1 && StrEqual(lastAttribute, Weapons_ATTR_CUSTOM_DEPLOY_SOUND), "start attribute unchanged");
    WeaponsSound_TrackDeployFinish(1, 1900); WeaponsSound_ItemPostFramePre(1900);
    Check(emissions == 2, "start cooldown does not suppress finished sound");
    WeaponsSound_TrackDeployFinish(1, 1900); WeaponsSound_ItemPostFramePre(1900);
    Check(emissions == 2, "finished sound has 1.5-second cooldown");
    clockTime += 1.5; WeaponsSound_TrackDeployFinish(1, 1900); WeaponsSound_ItemPostFramePre(1900);
    Check(emissions == 3, "finished cooldown expires");
    active[1] = 1901; WeaponsSound_TrackDeployFinish(1, 1901); WeaponsSound_ItemPostFramePre(1901);
    Check(emissions == 4, "another slot has independent finished cooldown");
    owners[0] = 2; active[2] = 1900;
    WeaponsSound_TrackDeployFinish(2, 1900); WeaponsSound_ItemPostFramePre(1900);
    Check(emissions == 5, "another client has independent cooldown");
    Reset(); cloaked[1] = true; WeaponsSound_TrackDeployFinish(1, 1900); WeaponsSound_ItemPostFramePre(1900);
    Check(emissions == 0 && g_iWeaponsDeployFinishHook[1] == 0, "cloak suppresses sound but consumes transition");
    ReplyToCommand(client, "[DeployFinishedProbe] %d checks; %d failures; no real players or audio touched", checks, failures);
    return Plugin_Handled;
}
