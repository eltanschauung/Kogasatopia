#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <tf2utils>
#include <rtd2>

public Plugin myinfo = {
    name = "Plugin error regression probe",
    author = "Kogasatopia",
    description = "Tests production guards and RTD lifecycle without touching players.",
    version = "1.0"
};

methodmap Perk < StringMap {
    public Perk() { return view_as<Perk>(new StringMap()); }
    property int Id {
        public get() { int id; this.GetValue("id", id); return id; }
        public set(int id) { this.SetValue("id", id); }
    }
}
methodmap PerkList < ArrayList {
    public PerkList() { return view_as<PerkList>(new ArrayList()); }
    public Perk Get(int index) { return view_as<Perk>(view_as<ArrayList>(this).Get(index)); }
}
ArrayList g_hPerkTokenMapper;
methodmap PerkContainer < ArrayList {
    public PerkContainer() { return view_as<PerkContainer>(new ArrayList()); }
    public Perk GetFromIdEx(int id) { return view_as<Perk>(this.Get(id)); }
    // PRODUCTION_PERK_LOOKUP
}
PerkContainer g_hPerkContainer;
#include "rollers_under_test.inc"
Rollers g_hRollers;

int cacheCleanups, removals, cooldowns, messages, slotReads, emissions;
enum struct ProbeCache {
    int Cleanups;
    void Cleanup() { this.Cleanups++; cacheCleanups++; }
}
ProbeCache Cache[MAXPLAYERS + 1];
int assertions, failures;
bool inGame, validEntity, realWeapon;
int weaponSlot;
#define Weapons_ATTR_CUSTOM_MELEE_HIT_SOUND "custom melee hit sound"

int ProbeUserId(int userid) { return userid == 1 ? 1 : 0; }
bool ProbeInGame(int client) { return client == 1 && inGame; }
bool ProbeFake(int client) { return false; }
bool ProbeEntity(int entity) { return entity == 1024 && validEntity; }
bool ProbeWeapon(int entity) { return entity == 1024 && realWeapon; }
int ProbeSlot(int entity) { slotReads++; return weaponSlot; }
bool Oblivion_ShouldHide(int target, int author) { return false; }
void ProbeChat(int target, const char[] format, any ...) { messages++; }
void ProbeChatEx(int target, int author, const char[] format, any ...) { messages++; }
bool WeaponsSound_EmitCustomMeleeAttribute(int client, int weapon, const char[] attribute, const char[] context) {
    emissions++;
    return true;
}
void DisplayPerkTimeFrame(int client) {}
void FinishPerkCooldown(int client) { cooldowns++; }
void ManagePerk(int client, Perk perk, bool enabled, RTDRemoveReason reason, const char[] text) {
    removals++;
    g_hRollers.SetInRoll(client, false);
    g_hRollers.SetPerk(client, null);
}

#define GetClientOfUserId ProbeUserId
#define IsClientInGame ProbeInGame
#define IsFakeClient ProbeFake
#define IsValidEntity ProbeEntity
#define TF2Util_IsEntityWeapon ProbeWeapon
#define TF2Util_GetWeaponSlot ProbeSlot
#define CPrintToChat ProbeChat
#define CPrintToChatEx ProbeChatEx
#include "plugin_errors_under_test.inc"

void Check(bool result, const char[] label) {
    assertions++;
    if (!result) {
        failures++;
        PrintToServer("[PluginErrorsProbe] FAIL: %s", label);
    }
}
public Action ProbeIdleTimer(Handle timer) { return Plugin_Continue; }

public void OnPluginStart() {
    g_hPerkTokenMapper = new ArrayList(32);
    g_hPerkContainer = new PerkContainer();
    g_hPerkTokenMapper.PushString("probe");
    Perk perk = new Perk();
    perk.Id = 0;
    g_hPerkContainer.Push(perk);
    g_hRollers = new Rollers();
    Check(g_hRollers.GetPerk(1) == null, "initial state is not perk zero");
    g_hRollers.SetPerk(1, perk);
    Check(g_hRollers.GetPerk(1) == perk, "perk ID resolves to owned definition");
    g_hRollers.SetInRoll(1, true);
    Handle timer = CreateTimer(60.0, ProbeIdleTimer, _, TIMER_REPEAT);
    g_hRollers.SetTimer(1, timer);
    RemovePerk(1);
    Check(!IsValidHandle(timer), "manual removal cancels duration timer");
    Check(g_hRollers.GetTimer(1) == null && removals == 1, "normal removal clears timer ownership");
    g_hRollers.Set(1, 0xa85, 4);
    g_hRollers.SetInRoll(1, true);
    RemovePerk(1);
    Check(cacheCleanups == 1 && cooldowns == 1, "stale ID cleans client state");
    Check(!g_hRollers.GetInRoll(1) && g_hRollers.GetPerk(1) == null, "stale ID cannot survive reset");
    g_hRollers.SetPerk(1, perk);
    delete perk;
    Check(g_hRollers.GetPerk(1) == null, "closed registered handle is never dereferenced");
    g_hRollers.Reset(1);
    Check(g_hRollers.GetPerk(1) == null, "reset invalidates perk ID");

    Check(!IsValidAnnouncerClient(0) && !IsValidAnnouncerClient(MAXPLAYERS + 1), "announcer index bounds");
    Announcer_MessageClient(1, 1, "test");
    Check(!IsHumanAnnouncerClient(1) && messages == 0, "connecting client cannot receive chat");
    inGame = true;
    Announcer_MessageClient(1, 1, "test");
    Check(IsHumanAnnouncerClient(1) && messages == 1, "in-game client still receives chat");

    WeaponsSound_PlayCustomMeleeHit(1, 1024);
    Check(slotReads == 0 && emissions == 0, "invalid entity skips weapon native");
    validEntity = true;
    WeaponsSound_PlayCustomMeleeHit(1, 1024);
    Check(slotReads == 0 && emissions == 0, "valid non-weapon skips weapon native");
    realWeapon = true;
    weaponSlot = TFWeaponSlot_Primary;
    WeaponsSound_PlayCustomMeleeHit(1, 1024);
    Check(slotReads == 1 && emissions == 0, "non-melee weapon remains silent");
    weaponSlot = TFWeaponSlot_Melee;
    WeaponsSound_PlayCustomMeleeHit(1, 1024);
    Check(slotReads == 2 && emissions == 1, "melee weapon still emits hit sound");

    perk = new Perk();
    perk.Id = 0;
    g_hPerkContainer.Set(0, perk);
    g_hRollers.SetPerk(1, perk);
    g_hRollers.SetInRoll(1, true);
    g_hRollers.SetEndRollTime(1, GetTime() - 1);
    timer = CreateTimer(60.0, ProbeIdleTimer, _, TIMER_REPEAT);
    g_hRollers.SetTimer(1, timer);
    Handle staleTimer = CreateTimer(60.0, ProbeIdleTimer, _, TIMER_REPEAT);
    Check(Timer_PerkRunTick(staleTimer, 1) == Plugin_Stop, "previous roll timer cannot expire current roll");
    Check(g_hRollers.GetTimer(1) == timer && removals == 1, "stale callback preserves new roll");
    delete staleTimer;
    g_hRollers.StopTimer(1);
    timer = CreateTimer(0.1, Timer_PerkRunTick, 1);
    g_hRollers.SetTimer(1, timer);
    CreateTimer(0.3, ProbeCheckExpiry);
}

public Action ProbeCheckExpiry(Handle timer) {
    Check(g_hRollers.GetTimer(1) == null && removals == 2, "expiry releases timer before cleanup");
    Check(!g_hRollers.GetInRoll(1), "expiry ends roll");
    PrintToServer("[PluginErrorsProbe] %d assertions, %d failures", assertions, failures);
    Perk perk = g_hPerkContainer.GetFromId(0);
    delete perk;
    delete g_hRollers;
    delete g_hPerkContainer;
    delete g_hPerkTokenMapper;
    return Plugin_Stop;
}
