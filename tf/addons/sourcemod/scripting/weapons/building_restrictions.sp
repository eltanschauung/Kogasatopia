#define DISABLE_ENGINEER_BUILDINGS_ATTRIBUTE "disable engineer buildings"

bool g_bEngineerBuildingsDisabled[MAXPLAYERS + 1];

void WeaponsBuildings_OnPluginStart()
{
    HookEvent("post_inventory_application", WeaponsBuildings_OnInventoryApplied, EventHookMode_Post);
    HookEvent("player_builtobject", WeaponsBuildings_OnInventoryApplied, EventHookMode_Post);
    AddCommandListener(WeaponsBuildings_OnBuildCommand, "build");
}

public Action WeaponsBuildings_OnBuildCommand(int client, const char[] command, int argc)
{
    if (!Weapons_IsValidClient(client) || !WeaponsBuildings_HasRestriction(client)) return Plugin_Continue;
    WeaponsBuildings_Reconcile(client);
    return Plugin_Handled;
}

void WeaponsBuildings_ResetClient(int client)
{
    g_bEngineerBuildingsDisabled[client] = false;
}

void WeaponsBuildings_ResetAll()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        WeaponsBuildings_ResetClient(client);
    }
}

static bool WeaponsBuildings_HasRestriction(int client)
{
    if (TF2_GetPlayerClass(client) != TFClass_Engineer) return false;
    int profile = KogasaPerfBegin();
    bool restricted = WeaponsBuildings_CheckRestriction(client);
    char detail[32];
    FormatEx(detail, sizeof(detail), "restricted=%d", restricted);
    WeaponsPerf_EndClient(profile, "EngineerBuildings/check", client, detail);
    return restricted;
}

static bool WeaponsBuildings_CheckRestriction(int client)
{
    if (TF2_GetPlayerClass(client) != TFClass_Engineer)
    {
        return false;
    }

    int count = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
    for (int slot = 0; slot < count; slot++)
    {
        int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", slot);
        if (weapon <= MaxClients || !IsValidEntity(weapon)
            || GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity") != client)
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

static void WeaponsBuildings_StripTools(int client)
{
    int profile = KogasaPerfBegin();
    int removed = WeaponsBuildings_StripToolsImpl(client);
    char detail[32];
    FormatEx(detail, sizeof(detail), "removed=%d", removed);
    WeaponsPerf_EndClient(profile, "EngineerBuildings/strip_tools", client, detail);
}

static int WeaponsBuildings_StripToolsImpl(int client)
{
    int removed;
    int count = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
    for (int slot = count - 1; slot >= 0; slot--)
    {
        int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", slot);
        if (weapon <= MaxClients || !IsValidEntity(weapon))
        {
            continue;
        }
        char classname[64];
        GetEntityClassname(weapon, classname, sizeof(classname));
        if (!StrEqual(classname, "tf_weapon_pda_engineer_build")
            && !StrEqual(classname, "tf_weapon_pda_engineer_destroy")
            && !StrEqual(classname, "tf_weapon_builder"))
        {
            continue;
        }
        int ref = EntIndexToEntRef(weapon);
        if (RemovePlayerItem(client, weapon) && EntRefToEntIndex(ref) == weapon)
        {
            RemoveEntity(weapon);
            removed++;
        }
    }
    return removed;
}

void WeaponsBuildings_Reconcile(int client, bool inventoryApplied = false)
{
    if (!Weapons_IsValidClient(client)) return;
    bool before = g_bEngineerBuildingsDisabled[client];
    int profile = KogasaPerfBegin();
    WeaponsBuildings_ReconcileImpl(client, inventoryApplied);
    char detail[80];
    FormatEx(detail, sizeof(detail), "inventory=%d;cached_before=%d;cached_after=%d",
        inventoryApplied, before, g_bEngineerBuildingsDisabled[client]);
    WeaponsPerf_EndClient(profile, "EngineerBuildings/reconcile", client, detail);
}

static void WeaponsBuildings_ReconcileImpl(int client, bool inventoryApplied)
{
    if (!Weapons_IsValidClient(client))
    {
        return;
    }
    bool restricted = WeaponsBuildings_HasRestriction(client);
    if (!restricted)
    {
        // A later ordinary inventory regeneration restores the stock tools.
        g_bEngineerBuildingsDisabled[client] = false;
        return;
    }

    if (!g_bEngineerBuildingsDisabled[client] || inventoryApplied)
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
            // The optional custom-building plugin must not disable this attribute.
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
    }
    g_bEngineerBuildingsDisabled[client] = true;
    WeaponsBuildings_StripTools(client);
}

public void WeaponsBuildings_OnInventoryApplied(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        RequestFrame(WeaponsBuildings_ReconcileAfterInventory, GetClientSerial(client));
    }
}

public void WeaponsBuildings_ReconcileAfterInventory(any serial)
{
    int client = GetClientFromSerial(serial);
    if (client > 0)
    {
        WeaponsBuildings_Reconcile(client, true);
    }
}
