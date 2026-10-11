// Runs the production module against simulated players and weapon references.
// Does not hook attacks, emit events, or touch any real player's health.
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <dhooks>

public Plugin myinfo = {
    name = "Kunai nerf regression probe",
    author = "Hombre",
    version = "1.0.0"
};

bool enabled, connected[3], alive[3], attributed[2], valid[2];
int health[3], serials[3], owners[2], refs[2], writes, checks, failures;
TFClassType classes[3];

bool WeaponsGameplay_IsEnabled() { return enabled; }
bool Weapons_IsClientInGame(int client) {
    return client > 0 && client < sizeof(connected) && connected[client];
}
bool Weapons_IsValidWeaponEntity(int weapon) {
    return weapon >= 100 && weapon < 102 && valid[weapon - 100];
}
int ProbeAttribute(int weapon, const char[] name, int fallback) {
    #pragma unused name
    return attributed[weapon - 100] ? 1 : fallback;
}
int ProbeOwner(int weapon, PropType type, const char[] name) {
    #pragma unused type
    #pragma unused name
    return owners[weapon - 100];
}
int ProbeRef(int weapon) { return refs[weapon - 100]; }
int ProbeFromRef(int ref) {
    for (int i = 0; i < sizeof(refs); i++)
        if (valid[i] && refs[i] == ref) return 100 + i;
    return -1;
}
bool ProbeAlive(int client) { return alive[client]; }
TFClassType ProbeClass(int client) { return classes[client]; }
int ProbeSerial(int client) { return serials[client]; }
int ProbeFromSerial(int serial) {
    for (int client = 1; client < sizeof(connected); client++)
        if (connected[client] && serials[client] == serial) return client;
    return 0;
}
int ProbeHealth(int client) { return health[client]; }
void ProbeSetHealth(int client, int value) { health[client] = value; writes++; }

#define TF2CustAttr_GetInt ProbeAttribute
#define GetEntPropEnt ProbeOwner
#define EntIndexToEntRef ProbeRef
#define EntRefToEntIndex ProbeFromRef
#define IsPlayerAlive ProbeAlive
#define TF2_GetPlayerClass ProbeClass
#define GetClientSerial ProbeSerial
#define GetClientFromSerial ProbeFromSerial
#define GetClientHealth ProbeHealth
#define SetEntityHealth ProbeSetHealth
#include "weapons/kunai_nerf.sp"
#undef TF2CustAttr_GetInt
#undef GetEntPropEnt
#undef EntIndexToEntRef
#undef EntRefToEntIndex
#undef IsPlayerAlive
#undef TF2_GetPlayerClass
#undef GetClientSerial
#undef GetClientFromSerial
#undef GetClientHealth
#undef SetEntityHealth

void Check(bool condition, const char[] label) {
    checks++;
    if (!condition) {
        failures++;
        PrintToServer("[KunaiProbe] FAIL: %s", label);
    }
}
void Reset() {
    enabled = true; writes = 0; g_KunaiNerfAttackDepth = 0;
    for (int client = 1; client < sizeof(connected); client++) {
        connected[client] = true; alive[client] = true; health[client] = 70;
        serials[client] = client; classes[client] = TFClass_Spy;
        int index = client - 1;
        attributed[index] = true; valid[index] = true;
        owners[index] = client; refs[index] = 100 + index;
    }
}
void Mark(int attacker = 1, int weapon = 100,
    int customKill = TF_CUSTOM_BACKSTAB, int flags = 0) {
    Event event = CreateEvent("player_death", true);
    event.SetInt("customkill", customKill); event.SetInt("death_flags", flags);
    KunaiNerf_RecordBackstab(event, attacker, weapon);
    delete event;
}
void Stab(int before, int after, int expected) {
    Reset(); health[1] = before;
    KunaiNerf_PrimaryAttack_Pre(100); Mark(); health[1] = after;
    KunaiNerf_PrimaryAttack_Post(100);
    Check(health[1] == expected, "health cap");
    Check(writes == (after != expected ? 1 : 0), "only write when necessary");
    Check(g_KunaiNerfAttackDepth == 0, "balanced invocation");
}
public void OnPluginStart() {
    RegAdminCmd("sm_kunai_probe", Command_Probe, ADMFLAG_ROOT);
}
public Action Command_Probe(int client, int args) {
    #pragma unused args
    checks = 0; failures = 0;
    Stab(70, 210, 185); Stab(150, 190, 185); Stab(70, 145, 145);
    Stab(185, 210, 185); Stab(190, 210, 190); Stab(250, 250, 250);
    Stab(190, 180, 180); Stab(70, 70, 70);

    Reset(); attributed[0] = false;
    KunaiNerf_PrimaryAttack_Pre(100); Mark(); health[1] = 210;
    KunaiNerf_PrimaryAttack_Post(100);
    Check(health[1] == 210 && writes == 0, "unattributed Kunai unchanged");

    Reset(); KunaiNerf_PrimaryAttack_Pre(100); health[1] = 210;
    KunaiNerf_PrimaryAttack_Post(100);
    Check(health[1] == 210 && writes == 0, "miss or unrelated heal unchanged");

    Reset(); KunaiNerf_PrimaryAttack_Pre(100); Mark(1, 100, 0); health[1] = 210;
    KunaiNerf_PrimaryAttack_Post(100);
    Check(health[1] == 210 && writes == 0, "non-backstab unchanged");

    Reset(); KunaiNerf_PrimaryAttack_Pre(100);
    Mark(1, 100, TF_CUSTOM_BACKSTAB, TF_DEATHFLAG_DEADRINGER); health[1] = 210;
    KunaiNerf_PrimaryAttack_Post(100);
    Check(health[1] == 210 && writes == 0, "feigned death unchanged");

    Reset(); KunaiNerf_PrimaryAttack_Pre(100); Mark(2, 101); health[1] = 210;
    KunaiNerf_PrimaryAttack_Post(100);
    Check(health[1] == 210 && writes == 0, "unrelated attacker and weapon");

    Reset(); KunaiNerf_PrimaryAttack_Pre(100); Mark(1, 101); health[1] = 210;
    KunaiNerf_PrimaryAttack_Post(100);
    Check(health[1] == 210 && writes == 0, "wrong inflicting weapon");

    Reset(); KunaiNerf_PrimaryAttack_Pre(100); Mark(2, 100); health[1] = 210;
    KunaiNerf_PrimaryAttack_Post(100);
    Check(health[1] == 210 && writes == 0, "wrong attacking client");

    Reset(); KunaiNerf_PrimaryAttack_Pre(100); Mark(); health[1] = 210;
    serials[1]++; KunaiNerf_PrimaryAttack_Post(100);
    Check(health[1] == 210 && writes == 0, "replaced client session");

    Reset(); KunaiNerf_PrimaryAttack_Pre(100); Mark(); health[1] = 210;
    owners[0] = 2; KunaiNerf_PrimaryAttack_Post(100);
    Check(health[1] == 210 && writes == 0, "owner changed");

    Reset(); KunaiNerf_PrimaryAttack_Pre(100); Mark(); health[1] = 210;
    refs[0]++; KunaiNerf_PrimaryAttack_Post(100);
    Check(health[1] == 210 && writes == 0, "replaced weapon entity");

    Reset(); KunaiNerf_PrimaryAttack_Pre(100); Mark(); health[1] = 210;
    alive[1] = false; KunaiNerf_PrimaryAttack_Post(100);
    Check(writes == 0, "dead attacker not revived");

    Reset(); classes[1] = TFClass_Scout;
    KunaiNerf_PrimaryAttack_Pre(100); Mark(); health[1] = 210;
    KunaiNerf_PrimaryAttack_Post(100);
    Check(writes == 0, "Spy-only");

    Reset(); enabled = false;
    KunaiNerf_PrimaryAttack_Pre(100); Mark(); health[1] = 210;
    KunaiNerf_PrimaryAttack_Post(100);
    Check(writes == 0, "gameplay disabled");

    Reset(); KunaiNerf_PrimaryAttack_Pre(100); Mark();
    KunaiNerf_PrimaryAttack_Pre(101); Mark(2, 101);
    health[2] = 210; KunaiNerf_PrimaryAttack_Post(101);
    health[1] = 210; KunaiNerf_PrimaryAttack_Post(100);
    Check(health[1] == 185 && health[2] == 185 && writes == 2,
        "nested attacks have independent snapshots");
    Check(g_KunaiNerfAttackDepth == 0, "nested stack balanced");

    Reset(); KunaiNerf_PrimaryAttack_Pre(100); Mark();
    for (int i = 0; i < KUNAI_NERF_MAX_ATTACK_DEPTH; i++)
        KunaiNerf_PrimaryAttack_Pre(101);
    Mark(2, 101); health[2] = 210;
    for (int i = 0; i < KUNAI_NERF_MAX_ATTACK_DEPTH; i++)
        KunaiNerf_PrimaryAttack_Post(101);
    health[1] = 210; KunaiNerf_PrimaryAttack_Post(100);
    Check(health[1] == 185 && health[2] == 210 && writes == 1,
        "overflow ignored without corrupting outer snapshot");
    Check(g_KunaiNerfAttackDepth == 0, "overflow stack balanced");
    KunaiNerf_PrimaryAttack_Post(100);
    Check(g_KunaiNerfAttackDepth == 0, "unpaired post ignored");

    ReplyToCommand(client, "[KunaiProbe] %d checks; %d failures; real players untouched",
        checks, failures);
    return Plugin_Handled;
}
