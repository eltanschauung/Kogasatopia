#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <tf2_stocks>

#define NUM_ITEMS 7
#define NUM_PLAYER_CLASSES 10
#define ATTRIB_NAME_CUSTOM_UID "test custom uid"
#define PROBE_CLIENTS 2
#define PROBE_ENTITIES 128

public Plugin myinfo = {
    name = "Engineer building policy regression probe",
    author = "Kogasatopia",
    description = "Real policy module, simulated inventory; never changes player inventories.",
    version = "1.0"
};

enum struct CustomItemDefinition {
    char className[64];
    KeyValues customAttributes;
    bool accessible;
    bool allowed;
}
enum struct ProbeLoadoutEntry {
    int definition;
    bool IsEmpty() { return this.definition == 0; }
    bool GetItemDefinition(CustomItemDefinition item) {
        return ProbeDefinition(this.definition, item);
    }
}
ProbeLoadoutEntry g_CurrentLoadout[MAXPLAYERS + 1][NUM_PLAYER_CLASSES][NUM_ITEMS];
CustomItemDefinition definitions[4];
ConVar sm_weapons_enable_loadout;
KeyValues restrictedAttributes;
bool connected[MAXPLAYERS + 1];
bool applying[MAXPLAYERS + 1];
int serials[MAXPLAYERS + 1], revisions[MAXPLAYERS + 1];
TFClassType classes[MAXPLAYERS + 1];
int weapons[MAXPLAYERS + 1][8];
bool valid[PROBE_ENTITIES], custom[PROBE_ENTITIES], restrictedWeapon[PROBE_ENTITIES];
int owners[PROBE_ENTITIES], flags[PROBE_ENTITIES];
char classnames[PROBE_ENTITIES][64];
ArrayList pending;
bool probeNativeAvailable;
bool resetDuringDestroy;
int destroyed, probeDetached, probeRemoved, regenerated, checks, failures;

bool ProbeDefinition(int index, CustomItemDefinition item) {
    if (index < 1 || index >= sizeof(definitions)) return false;
    item = definitions[index];
    return true;
}
bool Weapons_IsValidClient(int client) {
    return client > 0 && client <= PROBE_CLIENTS && connected[client];
}
bool Weapons_IsApplyingLoadout(int client) { return applying[client]; }
int Weapons_GetLoadoutRevision(int client) { return revisions[client]; }
bool CanPlayerEquipItem(int client, const CustomItemDefinition item) {
    #pragma unused client
    return item.accessible;
}
bool Weapons_IsCustomItemAllowed(int client, const CustomItemDefinition item) {
    #pragma unused client
    return item.allowed;
}
int KogasaPerfBegin() { return -1; }
void WeaponsPerf_EndClient(int profile, const char[] scope, int client, const char[] detail = "") {
    #pragma unused profile
    #pragma unused scope
    #pragma unused client
    #pragma unused detail
}
TFClassType ProbeClass(int client) { return classes[client]; }
int ProbeSerial(int client) { return serials[client]; }
int ProbeFromSerial(int serial) {
    for (int client = 1; client <= PROBE_CLIENTS; client++)
        if (connected[client] && serials[client] == serial) return client;
    return 0;
}
int ProbeArraySize(int entity, PropType type, const char[] name) {
    #pragma unused entity
    #pragma unused type
    #pragma unused name
    return 8;
}
int ProbePropEnt(int entity, PropType type, const char[] name, int element = 0) {
    #pragma unused type
    #pragma unused name
    return entity <= PROBE_CLIENTS ? weapons[entity][element] : owners[entity];
}
bool ProbeValidEntity(int entity) { return entity > PROBE_CLIENTS && entity < PROBE_ENTITIES && valid[entity]; }
int ProbeFlags(int entity) { return flags[entity]; }
Address ProbeCustomUid(int entity, const char[] name) {
    #pragma unused name
    return custom[entity] ? view_as<Address>(1) : Address_Null;
}
int ProbeAttribute(int entity, const char[] name, int fallback) {
    #pragma unused name
    #pragma unused fallback
    return restrictedWeapon[entity] ? 1 : 0;
}
void ProbeRequestFrame(RequestFrameCallback callback, any data = 0) {
    #pragma unused callback
    pending.Push(data);
}
void ProbeHookEvent(const char[] name, EventHook callback, EventHookMode mode) {
    #pragma unused name
    #pragma unused callback
    #pragma unused mode
}
bool ProbeAddListener(CommandListener callback, const char[] command) {
    #pragma unused callback
    #pragma unused command
    return true;
}
FeatureStatus ProbeFeature(FeatureType type, const char[] name) {
    #pragma unused type
    #pragma unused name
    return probeNativeAvailable ? FeatureStatus_Available : FeatureStatus_Unavailable;
}
int ProbeDestroyOwned(int client) {
    destroyed++;
    if (resetDuringDestroy) {
        WeaponsBuildings_ResetClient(client);
        serials[client]++;
    }
    return 0;
}
int ProbeFindBuilding(int start, const char[] name) {
    #pragma unused name
    for (int entity = start + 1; entity < PROBE_ENTITIES; entity++)
        if (valid[entity] && StrEqual(classnames[entity], "obj_dispenser")) return entity;
    return -1;
}
bool ProbeHasProp(int entity, PropType type, const char[] name) {
    #pragma unused entity
    #pragma unused type
    #pragma unused name
    return true;
}
bool ProbeKill(int entity, const char[] input) {
    #pragma unused input
    destroyed++;
    valid[entity] = false;
    return true;
}
bool ProbeDetach(int client, int entity) {
    probeDetached++;
    for (int slot = 0; slot < 8; slot++)
        if (weapons[client][slot] == entity) weapons[client][slot] = -1;
    return true;
}
int ProbeRef(int entity) { return entity; }
int ProbeFromRef(int ref) { return ProbeValidEntity(ref) ? ref : -1; }
bool ProbeClassname(int entity, char[] output, int size) {
    strcopy(output, size, classnames[entity]);
    return true;
}
void ProbeRemove(int entity) { probeRemoved++; valid[entity] = false; }
bool ProbeAlive(int client) {
    #pragma unused client
    return true;
}
void ProbeRegenerate(int client) {
    regenerated++;
    // Simulate a full nested engine inventory cycle, without a real player.
    WeaponsBuildings_BeginInventory(client);
    WeaponsBuildings_EndInventory(client);
}

#define MaxClients PROBE_CLIENTS
#define TF2_GetPlayerClass ProbeClass
#define GetClientSerial ProbeSerial
#define GetClientFromSerial ProbeFromSerial
#define GetEntPropArraySize ProbeArraySize
#define GetEntPropEnt ProbePropEnt
#define IsValidEntity ProbeValidEntity
#define GetEntityFlags ProbeFlags
#define TF2Attrib_GetByName ProbeCustomUid
#define TF2CustAttr_GetInt ProbeAttribute
#define RequestFrame ProbeRequestFrame
#define HookEvent ProbeHookEvent
#define AddCommandListener ProbeAddListener
#define GetFeatureStatus ProbeFeature
#define Amplifier_DestroyOwnedBuildings ProbeDestroyOwned
#define FindEntityByClassname ProbeFindBuilding
#define HasEntProp ProbeHasProp
#define AcceptEntityInput ProbeKill
#define RemovePlayerItem ProbeDetach
#define EntIndexToEntRef ProbeRef
#define EntRefToEntIndex ProbeFromRef
#define GetEntityClassname ProbeClassname
#define RemoveEntity ProbeRemove
#define IsPlayerAlive ProbeAlive
#define TF2_RegeneratePlayer ProbeRegenerate
// Do not expose the production TF2Items forward from this test plugin.
#define TF2Items_OnGiveNamedItem ProbeOnGiveNamedItem
#include "weapons/building_restrictions.sp"

void Check(bool condition, const char[] label) {
    checks++;
    if (!condition) { failures++; PrintToServer("[BuildingsProbe] FAIL: %s", label); }
}
void Frame() {
    int count = pending.Length;
    for (int i = 0; i < count; i++) {
        any data = pending.Get(0);
        pending.Erase(0);
        WeaponsBuildings_FrameReconcile(data);
    }
}
void Reset() {
    WeaponsBuildings_ResetAll();
    while (pending.Length > 0) Frame();
    for (int entity = 0; entity < PROBE_ENTITIES; entity++) {
        valid[entity] = custom[entity] = restrictedWeapon[entity] = false;
        owners[entity] = flags[entity] = 0;
        classnames[entity][0] = '\0';
    }
    for (int client = 1; client <= PROBE_CLIENTS; client++) {
        connected[client] = true;
        serials[client] = 1000 + client;
        revisions[client] = 1;
        classes[client] = TFClass_Engineer;
        applying[client] = false;
        for (int slot = 0; slot < 8; slot++) weapons[client][slot] = -1;
        for (int playerClass = 0; playerClass < NUM_PLAYER_CLASSES; playerClass++)
            for (int slot = 0; slot < NUM_ITEMS; slot++)
                g_CurrentLoadout[client][playerClass][slot].definition = 0;
    }
    probeNativeAvailable = true;
    resetDuringDestroy = false;
    destroyed = probeDetached = probeRemoved = regenerated = 0;
    definitions[1].accessible = definitions[1].allowed = true;
    sm_weapons_enable_loadout.BoolValue = true;
}
void Weapon(int entity, int client, int slot, const char[] classname, bool restriction = false, bool customItem = false) {
    valid[entity] = true;
    owners[entity] = client;
    restrictedWeapon[entity] = restriction;
    custom[entity] = customItem;
    strcopy(classnames[entity], sizeof(classnames[]), classname);
    weapons[client][slot] = entity;
}
void Plan() {
    g_CurrentLoadout[1][TFClass_Engineer][2].definition = 1;
    g_CurrentLoadout[1][TFClass_Engineer][4].definition = 2;
}

public void OnPluginStart() {
    pending = new ArrayList();
    restrictedAttributes = new KeyValues("attributes_custom");
    restrictedAttributes.SetNum(DISABLE_ENGINEER_BUILDINGS_ATTRIBUTE, 1);
    definitions[1].customAttributes = restrictedAttributes;
    strcopy(definitions[1].className, sizeof(definitions[].className), "tf_weapon_robot_arm");
    strcopy(definitions[2].className, sizeof(definitions[].className), "tf_weapon_pda_engineer_destroy");
    sm_weapons_enable_loadout = CreateConVar("sm_buildings_probe_enable", "1", "Isolated regression probe setting");
    WeaponsBuildings_OnPluginStart();
    RegAdminCmd("sm_buildings_probe", Run, ADMFLAG_ROOT);
}

public Action Run(int client, int args) {
    #pragma unused client, args
    checks = failures = 0;
    Reset();
    Plan();
    WeaponsBuildings_BeginInventory(1);
    Check(WeaponsBuildings_ShouldBlockCustomItem(1, definitions[2]), "planned restriction skips custom PDA");
    Check(!WeaponsBuildings_ShouldBlockCustomItem(1, definitions[1]), "restriction weapon itself still equips");
    char builder[] = "tf_weapon_builder";
    Handle overrideItem = null;
    Check(TF2Items_OnGiveNamedItem(1, builder, 28, overrideItem) == Plugin_Handled, "TF2Items rejects stock builder before creation");
    Check(overrideItem == null, "TF2Items override handle is untouched");
    WeaponsBuildings_EndInventory(1);
    Check(WeaponsBuildings_ShouldBlockTool(1, builder), "policy survives through ManageBuilderWeapons");
    Weapon(40, 1, 2, "tf_weapon_robot_arm", true, true);
    Weapon(41, 1, 3, "tf_weapon_pda_engineer_build");
    Weapon(42, 1, 4, "tf_weapon_pda_engineer_destroy");
    Weapon(43, 1, 5, "tf_weapon_builder");
    Weapon(44, 1, 0, "tf_weapon_shotgun_primary");
    for (int i = 0; i < 100; i++) WeaponsBuildings_OnItemRuntimeStateReady(1, 40);
    Check(pending.Length == 1, "100 notifications coalesce into one request");
    Check(probeDetached == 0 && destroyed == 0, "equip hooks never synchronously remove inventory/buildings");
    applying[1] = true;
    Frame();
    Check(probeDetached == 0 && pending.Length == 1, "custom loadout must settle before cleanup");
    applying[1] = false;
    WeaponsBuildings_BeginInventory(1);
    Frame();
    Check(probeDetached == 0 && pending.Length == 1, "engine inventory must settle before cleanup");
    WeaponsBuildings_EndInventory(1);
    Frame();
    Check(probeDetached == 3 && probeRemoved == 3 && destroyed == 1, "one cleanup strips all three tools and uses owned-building helper once");
    Check(valid[40] && valid[44], "cleanup preserves ordinary weapons");
    Check(g_CurrentLoadout[1][TFClass_Engineer][4].definition == 2, "saved custom PDA selection survives restriction");
    for (int i = 0; i < 100; i++) WeaponsBuildings_OnItemRuntimeStateReady(1, 40);
    Frame();
    Check(probeDetached == 3 && destroyed == 1, "stable restriction does not repeat destruction/removal");
    WeaponsBuildings_RequestReconcile(1, true);
    WeaponsBuildings_RequestReconcile(1, true);
    Frame();
    Check(destroyed == 2, "settled inventory events collapse to one cleanup");

    // Incoming inventory ignores an outgoing custom restriction after deselecting it.
    g_CurrentLoadout[1][TFClass_Engineer][2].definition = 0;
    revisions[1]++;
    WeaponsBuildings_BeginInventory(1);
    Check(!WeaponsBuildings_ShouldBlockTool(1, builder), "deselecting restriction restores engine tool creation");
    restrictedWeapon[40] = false;
    WeaponsBuildings_EndInventory(1);
    Frame();
    Check(!WeaponsBuildings_ShouldBlockCustomItem(1, definitions[2]), "saved custom PDA can equip again");
    Check(regenerated == 0, "normal removal needs no extra regeneration");

    Reset();
    Plan();
    WeaponsBuildings_BeginInventory(1);
    WeaponsBuildings_NoteSkippedCustomTool(1);
    WeaponsBuildings_EndInventory(1);
    Frame();
    Check(regenerated == 1, "failed restriction equip restores missing tools once");
    Check(!WeaponsBuildings_ShouldBlockTool(1, builder), "failed plan bypasses spawn suppression");
    Frame();
    Check(regenerated == 1 && pending.Length == 0, "failed plan cannot cause endless regeneration");
    revisions[1]++;
    WeaponsBuildings_PrepareCustomLoadout(1);
    Check(WeaponsBuildings_ShouldBlockTool(1, builder), "new loadout revision retries a previously failed plan");

    Reset();
    Plan();
    definitions[1].accessible = false;
    WeaponsBuildings_PrepareCustomLoadout(1);
    Check(!WeaponsBuildings_ShouldBlockTool(1, builder), "inaccessible restriction does not suppress tools");
    definitions[1].accessible = true;
    definitions[1].allowed = false;
    WeaponsBuildings_PrepareCustomLoadout(1);
    Check(!WeaponsBuildings_ShouldBlockTool(1, builder), "game-mode-ineligible restriction does not suppress tools");
    definitions[1].allowed = true;
    sm_weapons_enable_loadout.BoolValue = false;
    WeaponsBuildings_PrepareCustomLoadout(1);
    Check(!WeaponsBuildings_ShouldBlockTool(1, builder), "disabled custom loadouts do not predict restrictions");
    sm_weapons_enable_loadout.BoolValue = true;
    Weapon(40, 1, 2, "tf_weapon_robot_arm", true);
    WeaponsBuildings_BeginInventory(1);
    Check(WeaponsBuildings_ShouldBlockTool(1, builder), "external owned restriction is honored");
    Check(!WeaponsBuildings_ShouldBlockTool(1, "tf_weapon_pistol"), "ordinary weapon spawn remains allowed");
    classes[2] = TFClass_Spy;
    Weapon(50, 2, 0, builder, true);
    Check(!WeaponsBuildings_ShouldBlockTool(2, builder), "Spy sapper is not suppressed");
    Check(!WeaponsBuildings_ShouldBlockTool(0, builder), "invalid client is harmless");
    classes[1] = TFClass_Scout;
    WeaponsBuildings_ResetClient(1);
    WeaponsBuildings_BeginInventory(1);
    WeaponsBuildings_EndInventory(1);
    Check(pending.Length == 0, "unrestricted other classes allocate no reconciliation request");

    Reset();
    Weapon(40, 1, 2, "tf_weapon_robot_arm", true);
    Weapon(41, 1, 3, builder);
    WeaponsBuildings_RequestReconcile(1);
    connected[1] = false;
    Frame();
    Check(probeDetached == 0 && destroyed == 0, "disconnect discards old request safely");
    connected[1] = true;
    serials[1]++;
    WeaponsBuildings_ResetClient(1);
    WeaponsBuildings_RequestReconcile(1);
    WeaponsBuildings_ResetAll();
    WeaponsBuildings_RequestReconcile(1);
    Check(pending.Length == 2, "map reset invalidates old request ownership");
    Frame();
    Check(destroyed == 1 && probeRemoved == 1, "stale request cannot consume a replacement request");

    Reset();
    probeNativeAvailable = false;
    Weapon(40, 1, 2, "tf_weapon_robot_arm", true);
    valid[70] = valid[71] = true;
    owners[70] = 1; owners[71] = 2;
    strcopy(classnames[70], sizeof(classnames[]), "obj_dispenser");
    strcopy(classnames[71], sizeof(classnames[]), "obj_dispenser");
    WeaponsBuildings_RequestReconcile(1);
    Frame();
    Check(destroyed == 1 && !valid[70] && valid[71], "fallback destruction respects building ownership");

    Reset();
    Weapon(40, 1, 2, "tf_weapon_robot_arm", true);
    Weapon(41, 1, 3, builder);
    resetDuringDestroy = true;
    WeaponsBuildings_RequestReconcile(1);
    Frame();
    Check(probeRemoved == 0 && !g_EngineerBuildingPolicy[1].reconciling, "reentrant session reset cannot strip new session inventory");
    Reset();
    PrintToServer("[BuildingsProbe] %d checks; %d failures", checks, failures);
    return Plugin_Handled;
}

public void OnPluginEnd() {
    WeaponsBuildings_ResetAll();
    while (pending.Length > 0) Frame();
    delete pending;
    delete restrictedAttributes;
}
