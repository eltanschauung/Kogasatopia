#define DISABLE_ENGINEER_BUILDINGS_ATTRIBUTE "disable engineer buildings"

/**
 * One client-scoped inventory policy owns prediction, spawn suppression and
 * deferred reconciliation. Never detach tools inside engine/custom equip hooks.
 */
enum struct EngineerBuildingPolicy
{
    bool restricted;
    bool prepared;
    bool suppressTools;
    bool inventoryApplied;
    bool reconciling;
    int inventoryDepth;
    int blockedSpawns;
    int skippedCustomTools;
    int failedPlanRevision;
    DataPack request;
}

EngineerBuildingPolicy g_EngineerBuildingPolicy[MAXPLAYERS + 1];

void WeaponsBuildings_OnPluginStart()
{
    WeaponsBuildings_ResetAll();
    HookEvent("post_inventory_application", WeaponsBuildings_OnInventoryApplied, EventHookMode_Post);
    HookEvent("player_builtobject", WeaponsBuildings_OnInventoryApplied, EventHookMode_Post);
    AddCommandListener(WeaponsBuildings_OnBuildCommand, "build");
}

bool WeaponsBuildings_IsToolClass(const char[] classname)
{
    return StrEqual(classname, "tf_weapon_pda_engineer_build")
        || StrEqual(classname, "tf_weapon_pda_engineer_destroy")
        || StrEqual(classname, "tf_weapon_builder");
}

void WeaponsBuildings_ResetClient(int client)
{
    // A queued callback owns its pack until it runs. Invalidate ownership only;
    // it must not touch a new map/session/request even if the client slot survives.
    g_EngineerBuildingPolicy[client].request = null;
    g_EngineerBuildingPolicy[client].restricted = false;
    g_EngineerBuildingPolicy[client].prepared = false;
    g_EngineerBuildingPolicy[client].suppressTools = false;
    g_EngineerBuildingPolicy[client].inventoryApplied = false;
    g_EngineerBuildingPolicy[client].reconciling = false;
    g_EngineerBuildingPolicy[client].inventoryDepth = 0;
    g_EngineerBuildingPolicy[client].blockedSpawns = 0;
    g_EngineerBuildingPolicy[client].skippedCustomTools = 0;
    g_EngineerBuildingPolicy[client].failedPlanRevision = -1;
}

void WeaponsBuildings_ResetAll()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        WeaponsBuildings_ResetClient(client);
    }
}

static bool WeaponsBuildings_CheckRestriction(int client, bool incomingInventory = false)
{
    if (!Weapons_IsValidClient(client) || TF2_GetPlayerClass(client) != TFClass_Engineer)
    {
        return false;
    }

    int count = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
    for (int slot = 0; slot < count; slot++)
    {
        int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", slot);
        if (weapon <= MaxClients || !IsValidEntity(weapon)
            || (GetEntityFlags(weapon) & FL_KILLME)
            || GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity") != client)
        {
            continue;
        }
        // Engine regeneration replaces custom items from the selected loadout.
        // Do not let an outgoing Super Gunslinger suppress the restored tools.
        // Ordinary externally attributed weapons still retain their restriction.
        if (incomingInventory && TF2Attrib_GetByName(weapon, ATTRIB_NAME_CUSTOM_UID))
        {
            continue;
        }
        if (TF2CustAttr_GetInt(weapon, DISABLE_ENGINEER_BUILDINGS_ATTRIBUTE, 0) != 0)
        {
            return true;
        }
    }
    return false;
}

static bool WeaponsBuildings_HasRestriction(int client)
{
    int profile = KogasaPerfBegin();
    bool restricted = WeaponsBuildings_CheckRestriction(client);
    char detail[32];
    FormatEx(detail, sizeof(detail), "restricted=%d", restricted);
    WeaponsPerf_EndClient(profile, "EngineerBuildings/check", client, detail);
    return restricted;
}

static bool WeaponsBuildings_LoadoutWillRestrict(int client)
{
    if (sm_weapons_enable_loadout == null || !sm_weapons_enable_loadout.BoolValue
        || g_EngineerBuildingPolicy[client].failedPlanRevision == Weapons_GetLoadoutRevision(client))
    {
        return false;
    }

    for (int slot = 0; slot < NUM_ITEMS; slot++)
    {
        CustomItemDefinition item;
        if (g_CurrentLoadout[client][TFClass_Engineer][slot].IsEmpty()
            || !g_CurrentLoadout[client][TFClass_Engineer][slot].GetItemDefinition(item)
            || item.customAttributes == null)
        {
            continue;
        }

        item.customAttributes.Rewind();
        if (item.customAttributes.GetNum(DISABLE_ENGINEER_BUILDINGS_ATTRIBUTE, 0) != 0
            && CanPlayerEquipItem(client, item) && Weapons_IsCustomItemAllowed(client, item))
        {
            return true;
        }
    }
    return false;
}

static void WeaponsBuildings_Prepare(int client, bool incomingInventory)
{
    if (!Weapons_IsValidClient(client)) return;
    int profile = KogasaPerfBegin();
    bool engineer = TF2_GetPlayerClass(client) == TFClass_Engineer;
    bool restricted = engineer
        && (WeaponsBuildings_LoadoutWillRestrict(client)
            || WeaponsBuildings_CheckRestriction(client, incomingInventory));
    g_EngineerBuildingPolicy[client].prepared = engineer;
    g_EngineerBuildingPolicy[client].suppressTools = restricted;
    char detail[48];
    FormatEx(detail, sizeof(detail), "inventory=%d;suppress=%d", incomingInventory, restricted);
    WeaponsPerf_EndClient(profile, "EngineerBuildings/prepare", client, detail);
}

void WeaponsBuildings_BeginInventory(int client)
{
    if (!Weapons_IsValidClient(client)) return;
    if (g_EngineerBuildingPolicy[client].inventoryDepth++ == 0)
    {
        WeaponsBuildings_Prepare(client, true);
    }
}

void WeaponsBuildings_EndInventory(int client)
{
    if (!Weapons_IsValidClient(client) || g_EngineerBuildingPolicy[client].inventoryDepth <= 0) return;
    if (--g_EngineerBuildingPolicy[client].inventoryDepth == 0)
    {
        // ManageBuilderWeapons follows ManageRegularWeapons: keep the prepared
        // suppression policy alive until the complete inventory has settled.
        WeaponsBuildings_RequestReconcile(client, true);
    }
}

void WeaponsBuildings_PrepareCustomLoadout(int client)
{
    if (!Weapons_IsValidClient(client)) return;
    if (g_EngineerBuildingPolicy[client].inventoryDepth == 0)
    {
        WeaponsBuildings_Prepare(client, false);
    }
}

bool WeaponsBuildings_ShouldBlockTool(int client, const char[] classname)
{
    if (!WeaponsBuildings_IsToolClass(classname) || !Weapons_IsValidClient(client)
        || TF2_GetPlayerClass(client) != TFClass_Engineer)
    {
        return false;
    }

    if (g_EngineerBuildingPolicy[client].prepared)
    {
        return g_EngineerBuildingPolicy[client].suppressTools;
    }
    return WeaponsBuildings_CheckRestriction(client);
}

bool WeaponsBuildings_ShouldBlockCustomItem(int client, const CustomItemDefinition item)
{
    return WeaponsBuildings_ShouldBlockTool(client, item.className);
}

void WeaponsBuildings_NoteSkippedCustomTool(int client)
{
    g_EngineerBuildingPolicy[client].skippedCustomTools++;
}

void WeaponsBuildings_OnItemRuntimeStateReady(int client, int entity)
{
    if (!Weapons_IsValidClient(client) || entity <= MaxClients || !IsValidEntity(entity)) return;
    if (TF2_GetPlayerClass(client) == TFClass_Engineer
        && TF2CustAttr_GetInt(entity, DISABLE_ENGINEER_BUILDINGS_ATTRIBUTE, 0) != 0)
    {
        // Covers direct/native equips too, without deleting their inventory.
        g_EngineerBuildingPolicy[client].prepared = true;
        g_EngineerBuildingPolicy[client].suppressTools = true;
        g_EngineerBuildingPolicy[client].failedPlanRevision = -1;
    }
    WeaponsBuildings_RequestReconcile(client);
}

public Action TF2Items_OnGiveNamedItem(int client, char[] classname, int itemDefinitionIndex, Handle &item)
{
    // TF2Items documents Plugin_Handled as preventing item creation. Leave the
    // override handle and unrelated weapons (including Spy sappers) untouched.
    if (!WeaponsBuildings_ShouldBlockTool(client, classname)) return Plugin_Continue;
    g_EngineerBuildingPolicy[client].blockedSpawns++;
    WeaponsBuildings_RequestReconcile(client);
    return Plugin_Handled;
}

public Action WeaponsBuildings_OnBuildCommand(int client, const char[] command, int argc)
{
    if (!Weapons_IsValidClient(client) || !WeaponsBuildings_HasRestriction(client)) return Plugin_Continue;
    WeaponsBuildings_RequestReconcile(client);
    return Plugin_Handled;
}

void WeaponsBuildings_RequestReconcile(int client, bool inventoryApplied = false)
{
    if (!Weapons_IsValidClient(client)) return;
    if (TF2_GetPlayerClass(client) != TFClass_Engineer
        && !g_EngineerBuildingPolicy[client].restricted && !g_EngineerBuildingPolicy[client].prepared)
    {
        return;
    }

    g_EngineerBuildingPolicy[client].inventoryApplied =
        g_EngineerBuildingPolicy[client].inventoryApplied || inventoryApplied;
    if (g_EngineerBuildingPolicy[client].request != null) return;

    DataPack request = new DataPack();
    request.WriteCell(GetClientSerial(client));
    g_EngineerBuildingPolicy[client].request = request;
    RequestFrame(WeaponsBuildings_FrameReconcile, request);
}

public void WeaponsBuildings_FrameReconcile(any data)
{
    DataPack request = view_as<DataPack>(data);
    request.Reset();
    int serial = request.ReadCell();
    int client = GetClientFromSerial(serial);
    bool ownsRequest = client > 0 && client <= MaxClients
        && g_EngineerBuildingPolicy[client].request == request;
    if (!ownsRequest || !Weapons_IsValidClient(client))
    {
        if (ownsRequest) g_EngineerBuildingPolicy[client].request = null;
        delete request;
        return;
    }

    if (g_EngineerBuildingPolicy[client].inventoryDepth > 0 || Weapons_IsApplyingLoadout(client)
        || g_EngineerBuildingPolicy[client].reconciling)
    {
        RequestFrame(WeaponsBuildings_FrameReconcile, request);
        return;
    }

    g_EngineerBuildingPolicy[client].request = null;
    delete request;
    bool inventoryApplied = g_EngineerBuildingPolicy[client].inventoryApplied;
    g_EngineerBuildingPolicy[client].inventoryApplied = false;
    g_EngineerBuildingPolicy[client].reconciling = true;
    WeaponsBuildings_ReconcileNow(client, inventoryApplied);
    if (GetClientFromSerial(serial) == client)
    {
        g_EngineerBuildingPolicy[client].reconciling = false;
    }
}

static int WeaponsBuildings_DestroyOwned(int client, bool inventoryApplied)
{
    int profile = KogasaPerfBegin();
    int removed;
    bool nativeAvailable = GetFeatureStatus(FeatureType_Native, "Amplifier_DestroyOwnedBuildings")
        == FeatureStatus_Available;
    if (nativeAvailable)
    {
        removed = Amplifier_DestroyOwnedBuildings(client);
    }
    else
    {
        int building = -1;
        while ((building = FindEntityByClassname(building, "obj_*")) != -1)
        {
            if (HasEntProp(building, Prop_Send, "m_hBuilder")
                && GetEntPropEnt(building, Prop_Send, "m_hBuilder") == client)
            {
                AcceptEntityInput(building, "Kill");
                removed++;
            }
        }
    }
    char detail[64];
    FormatEx(detail, sizeof(detail), "native=%d;removed=%d;inventory=%d", nativeAvailable, removed, inventoryApplied);
    WeaponsPerf_EndClient(profile, "EngineerBuildings/destroy_owned", client, detail);
    return removed;
}

static int WeaponsBuildings_StripTools(int client)
{
    int profile = KogasaPerfBegin();
    int removed;
    int serial = GetClientSerial(client);
    int count = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
    for (int slot = count - 1; slot >= 0; slot--)
    {
        if (GetClientFromSerial(serial) != client || !Weapons_IsValidClient(client)) break;
        int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", slot);
        if (weapon <= MaxClients || !IsValidEntity(weapon) || (GetEntityFlags(weapon) & FL_KILLME)
            || GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity") != client)
        {
            continue;
        }
        char classname[64];
        GetEntityClassname(weapon, classname, sizeof(classname));
        if (!WeaponsBuildings_IsToolClass(classname)) continue;

        int ref = EntIndexToEntRef(weapon);
        int detachProfile = KogasaPerfBegin();
        bool detached = RemovePlayerItem(client, weapon);
        WeaponsPerf_EndClient(detachProfile, "EngineerBuildings/detach_tool", client, classname);
        if (detached && GetClientFromSerial(serial) == client
            && EntRefToEntIndex(ref) == weapon && IsValidEntity(weapon))
        {
            int removeProfile = KogasaPerfBegin();
            RemoveEntity(weapon);
            WeaponsPerf_EndClient(removeProfile, "EngineerBuildings/remove_tool", client, classname);
            removed++;
        }
    }
    char detail[32];
    FormatEx(detail, sizeof(detail), "removed=%d", removed);
    WeaponsPerf_EndClient(profile, "EngineerBuildings/strip_tools", client, detail);
    return removed;
}

static void WeaponsBuildings_ReconcileNow(int client, bool inventoryApplied)
{
    int serial = GetClientSerial(client);
    int profile = KogasaPerfBegin();
    bool before = g_EngineerBuildingPolicy[client].restricted;
    bool suppressed = g_EngineerBuildingPolicy[client].suppressTools;
    int blocked = g_EngineerBuildingPolicy[client].blockedSpawns;
    int skipped = g_EngineerBuildingPolicy[client].skippedCustomTools;
    g_EngineerBuildingPolicy[client].blockedSpawns = 0;
    g_EngineerBuildingPolicy[client].skippedCustomTools = 0;
    bool restricted = WeaponsBuildings_HasRestriction(client);
    g_EngineerBuildingPolicy[client].restricted = restricted;
    g_EngineerBuildingPolicy[client].prepared = false;
    g_EngineerBuildingPolicy[client].suppressTools = restricted;

    if (restricted)
    {
        g_EngineerBuildingPolicy[client].failedPlanRevision = -1;
        if (!before || inventoryApplied) WeaponsBuildings_DestroyOwned(client, inventoryApplied);
        if (GetClientFromSerial(serial) == client && Weapons_IsValidClient(client)
            && TF2_GetPlayerClass(client) == TFClass_Engineer)
        {
            WeaponsBuildings_StripTools(client);
        }
    }
    else if (suppressed && (blocked > 0 || skipped > 0)
        && TF2_GetPlayerClass(client) == TFClass_Engineer)
    {
        // A planned restriction failed to equip. Restore tools once, without an
        // endless regeneration loop retrying the same failed loadout revision.
        g_EngineerBuildingPolicy[client].failedPlanRevision = Weapons_GetLoadoutRevision(client);
        if (IsPlayerAlive(client)) TF2_RegeneratePlayer(client);
    }

    char detail[96];
    FormatEx(detail, sizeof(detail), "inventory=%d;before=%d;after=%d;blocked=%d;custom_skips=%d",
        inventoryApplied, before, restricted, blocked, skipped);
    WeaponsPerf_EndClient(profile, "EngineerBuildings/reconcile", client, detail);
}

public void WeaponsBuildings_OnInventoryApplied(Event event, const char[] name, bool dontBroadcast)
{
    WeaponsBuildings_RequestReconcile(GetClientOfUserId(event.GetInt("userid")), true);
}
