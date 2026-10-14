// Production melee classification/config routing with simulated engine/audio.
// Does not install damage hooks, dispatch game events, or emit any sounds.
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>
#include <textparse>
#include "include/strings.inc"

#define ANNOUNCER_MAX_COMMAND_NAME 64
#define WEAPONS_DMG_MELEE DMG_BLAST_SURFACE
#include "announcer_enum_under_test.inc"
GlobalForward g_OnMeleeKill;
int gFired, gFailures, gChecks, gLastWeapon, gLastAttacker, gLastVictim;
int gTeams[3] = { 0, 2, 3 };
bool gConnected[3] = { false, true, true };
bool gWeaponValid = true, gWeaponType = true, gAudioAvailable = true;
int gWeaponSlot = TFWeaponSlot_Melee;
int gDeliveryCount;
char gDelivered[64];

bool Weapons_IsClientInGame(int client) {
    return client >= 1 && client <= 2 && gConnected[client];
}
bool Weapons_IsValidWeaponEntity(int weapon) { return weapon == 100 && gWeaponValid; }
bool TF2Util_IsEntityWeapon(int weapon) { return weapon == 100 && gWeaponType; }
int TF2Util_GetWeaponSlot(int weapon) { return weapon == 100 ? gWeaponSlot : -1; }
int ProbeTeam(int client) { return gTeams[client]; }
#define GetClientTeam ProbeTeam
#include "melee_under_test.inc"
#undef GetClientTeam

public void MeleeKillProbe_Confirmed(int attacker, int victim, int weapon) {
    gFired++;
    gLastWeapon = weapon; gLastAttacker = attacker; gLastVictim = victim;
}

StringMap g_KillstreakSoundMap, g_MultikillSoundMap, g_ShutdownSoundMap;
StringMap g_ShutdownTheirsSoundMap, g_MedicDropSoundMap, g_AirshotSoundMap;
StringMap g_MeleeKillSoundMap, g_UberSoundMaps[3];
int g_ConfigDepth, g_ConfigLevel;
AnnouncerConfigMode g_ConfigMode;
bool IsValidAnnouncerClient(int client) { return client >= 1 && client <= 2; }
bool IsHumanAnnouncerClient(int client) { return client >= 1 && client <= 2; }
bool gHideVictim;
bool Oblivion_ShouldHide(int viewer, int source) {
    return gHideVictim && viewer == 2 && source == 2;
}
bool Announcer_ShouldPlaySound(bool enabled) { return enabled && gAudioAvailable; }
bool GetAnnouncerSoundCommand(StringMap map, int level, const char[] fallback,
    int source, char[] output, int length) {
    if (!IsValidAnnouncerClient(source)) return false;
    ArrayList commands = GetAnnouncerSoundCommandList(map, level);
    if (commands == null || commands.Length == 0) {
        strcopy(output, length, fallback);
        return output[0] != '\0';
    }
    commands.GetString(0, output, length);
    return true;
}
bool Announcer_PlaySound(int viewer, int source, const char[] command, StringMap choices) {
    if (!IsHumanAnnouncerClient(viewer) || !IsValidAnnouncerClient(source) || choices == null)
        return false;
    gDeliveryCount++;
    strcopy(gDelivered, sizeof(gDelivered), command);
    return true;
}
// Rename the production consumer so the temporary probe cannot subscribe to
// live Weapons_OnMeleeKill announcements.
#define Weapons_OnMeleeKill Probe_OnMeleeKill
#include "announcer_under_test.inc"
#undef Weapons_OnMeleeKill

void Check(bool ok, const char[] label) {
    gChecks++;
    if (!ok) {
        gFailures++;
        PrintToServer("[MeleeKillProbe] FAIL: %s", label);
    }
}
void CheckKill(int bits, int flags, int attacker, int victim, int weapon,
    bool expected, const char[] label, int custom = 0) {
    int before = gFired;
    Event event = CreateEvent("player_death", true);
    event.SetInt("damagebits", bits);
    event.SetInt("death_flags", flags);
    event.SetInt("customkill", custom);
    TryFireMeleeKill(event, attacker, victim, weapon);
    delete event;
    Check(gFired == before + (expected ? 1 : 0), label);
    if (expected)
        Check(gLastWeapon == weapon && gLastAttacker == attacker && gLastVictim == victim,
            "forward passes actual weapon/attacker/victim exactly once");
}
public void OnPluginStart() {
    g_OnMeleeKill = new GlobalForward("MeleeKillProbe_Confirmed", ET_Ignore,
        Param_Cell, Param_Cell, Param_Cell);
    g_KillstreakSoundMap = new StringMap(); g_MultikillSoundMap = new StringMap();
    g_ShutdownSoundMap = new StringMap(); g_ShutdownTheirsSoundMap = new StringMap();
    g_MedicDropSoundMap = new StringMap(); g_AirshotSoundMap = new StringMap();
    g_MeleeKillSoundMap = new StringMap();
    for (int i = 0; i < sizeof(g_UberSoundMaps); i++) g_UberSoundMaps[i] = new StringMap();
    RegAdminCmd("sm_melee_kill_probe", Command_Probe, ADMFLAG_ROOT);
}
public Action Command_Probe(int client, int args) {
    gChecks = 0; gFailures = 0; gFired = 0;
    int melee = DMG_CLUB | WEAPONS_DMG_MELEE;
    CheckKill(melee, 0, 1, 2, 100, true, "normal melee contact");
    CheckKill(melee | DMG_CRIT, 0, 1, 2, 100, true, "critical melee");
    CheckKill(melee | DMG_CRIT, 0, 1, 2, 100, true, "knife backstab", TF_CUSTOM_BACKSTAB);
    CheckKill(melee, TF_DEATHFLAG_DEADRINGER, 1, 2, 100, false, "Dead Ringer excluded");
    CheckKill(DMG_CLUB, 0, 1, 2, 100, false, "Sandman/Wrap Assassin projectile excluded");
    CheckKill(DMG_BURN, 0, 1, 2, 100, false, "melee-source afterburn excluded");
    CheckKill(DMG_BLAST, 0, 1, 2, 100, false, "Caber explosion excluded");
    CheckKill(DMG_BULLET, 0, 1, 2, 100, false, "shot after switching to melee excluded");
    CheckKill(melee, 0, 1, 1, 100, false, "suicide excluded");
    CheckKill(melee, 0, 0, 2, 100, false, "environmental attacker excluded");
    CheckKill(melee, 0, 1, 0, 100, false, "invalid victim excluded");
    gTeams[2] = 2;
    CheckKill(melee, 0, 1, 2, 100, false, "teammate excluded");
    gTeams[2] = 1;
    CheckKill(melee, 0, 1, 2, 100, false, "spectator excluded");
    gTeams[2] = 3; gConnected[1] = false;
    CheckKill(melee, 0, 1, 2, 100, false, "disconnected attacker excluded");
    gConnected[1] = true; gConnected[2] = false;
    CheckKill(melee, 0, 1, 2, 100, false, "disconnected victim excluded");
    gConnected[2] = true;
    CheckKill(melee, 0, 1, 2, -1, false, "missing actual damage weapon excluded");
    gWeaponValid = false;
    CheckKill(melee, 0, 1, 2, 100, false, "removed weapon excluded");
    gWeaponValid = true; gWeaponType = false;
    CheckKill(melee, 0, 1, 2, 100, false, "non-weapon entity excluded");
    gWeaponType = true; gWeaponSlot = TFWeaponSlot_Primary;
    CheckKill(melee, 0, 1, 2, 100, false, "ranged weapon with melee bit excluded");
    gWeaponSlot = TFWeaponSlot_Melee;

    // Exercise the actual SMC parser with an in-memory fixture, not live config.
    ClearSoundMap(g_MeleeKillSoundMap); ClearSoundMap(g_AirshotSoundMap);
    g_ConfigDepth = 0; g_ConfigLevel = 0; g_ConfigMode = AnnouncerConfig_None;
    SMCParser parser = new SMCParser();
    parser.OnEnterSection = AnnouncerConfig_EnterSection;
    parser.OnLeaveSection = AnnouncerConfig_LeaveSection;
    parser.OnKeyValue = AnnouncerConfig_KeyValue;
    char config[] = "\"Announcers\"\n{\n\"melee_kill\"\n{\n\"swing_test\" \"\"\n\"stab_test\" \"\"\n}\n\"airshot_kill\"\n{\n\"air_test\" \"\"\n}\n\"unknown\"\n{\n\"ignored\" \"\"\n}\n}\n";
    Check(parser.ParseString(config) == SMCError_Okay, "melee_kill parses");
    delete parser;
    ArrayList commands = GetAnnouncerSoundCommandList(g_MeleeKillSoundMap, 0);
    Check(commands != null && commands.Length == 2, "flat melee command pool");
    Check(commands != null && commands.FindString("stab_test") == 1, "second command preserved");
    Check(FindAnnouncerSoundCommandList("swing_test") == commands, "melee pool in listener lookup");
    Check(FindAnnouncerSoundCommandList("ignored") == null, "unknown section ignored");
    Check(g_ConfigDepth == 0 && g_ConfigMode == AnnouncerConfig_None, "parser state reset");

    gDeliveryCount = 0;
    Probe_OnMeleeKill(1, 2, 100);
    Check(gDeliveryCount == 2 && StrEqual(gDelivered, "swing_test"), "melee consumer routes configured pool");
    gDeliveryCount = 0; gHideVictim = true;
    Probe_OnMeleeKill(1, 2, 100);
    Check(gDeliveryCount == 1, "Oblivion visibility preserved");
    gHideVictim = false;
    gDeliveryCount = 0;
    Check(PlayAnnouncerKillSound(g_AirshotSoundMap, 1, 2)
        && gDeliveryCount == 2 && StrEqual(gDelivered, "air_test"), "airshot routing unchanged");
    gDeliveryCount = 0; gAudioAvailable = false;
    Probe_OnMeleeKill(1, 2, 100);
    Check(gDeliveryCount == 0, "unavailable Saysounds emits nothing");
    gAudioAvailable = true;
    ClearSoundMap(g_MeleeKillSoundMap);
    Probe_OnMeleeKill(1, 2, 100);
    Check(gDeliveryCount == 0, "missing melee config emits nothing");
    Check(!PlayAnnouncerKillSound(g_AirshotSoundMap, 0, 2), "invalid sound source rejected");
    ReplyToCommand(client, "[MeleeKillProbe] %d checks; %d failures; no real players or audio touched",
        gChecks, gFailures);
    return Plugin_Handled;
}
public void OnPluginEnd() {
    ClearSoundMap(g_KillstreakSoundMap); delete g_KillstreakSoundMap;
    ClearSoundMap(g_MultikillSoundMap); delete g_MultikillSoundMap;
    ClearSoundMap(g_ShutdownSoundMap); delete g_ShutdownSoundMap;
    ClearSoundMap(g_ShutdownTheirsSoundMap); delete g_ShutdownTheirsSoundMap;
    ClearSoundMap(g_MedicDropSoundMap); delete g_MedicDropSoundMap;
    ClearSoundMap(g_AirshotSoundMap); delete g_AirshotSoundMap;
    ClearSoundMap(g_MeleeKillSoundMap); delete g_MeleeKillSoundMap;
    for (int i = 0; i < sizeof(g_UberSoundMaps); i++) {
        ClearSoundMap(g_UberSoundMaps[i]); delete g_UberSoundMaps[i];
    }
    delete g_OnMeleeKill;
}
