// Read-only, optional engine-stage diagnostics. No parameters/results are changed.
// Capture only inside ManageRegularWeapons; map-wide precaching stays unprofiled.
#define WEAPONS_INVENTORY_STAGE_DEPTH 16
enum WeaponsInventoryStage
{
    InventoryStage_ValidateWearables,
    InventoryStage_ValidateWeapons,
    InventoryStage_WeaponGiveTo,
    InventoryStage_WearableGiveTo,
    InventoryStage_EconGiveTo,
    InventoryStage_ExtraWearables,
    InventoryStage_PostInventory,
    InventoryStage_PrecacheModel,
    InventoryStage_Count
}
DynamicDetour g_WeaponsInventoryStages[InventoryStage_Count];
int g_WeaponsInventoryStageDepth[InventoryStage_Count];
int g_WeaponsInventoryStageProfiles[InventoryStage_Count][WEAPONS_INVENTORY_STAGE_DEPTH];
int g_WeaponsInventoryStageClients[InventoryStage_Count][WEAPONS_INVENTORY_STAGE_DEPTH];
char g_WeaponsInventoryStageDetails[InventoryStage_Count][WEAPONS_INVENTORY_STAGE_DEPTH][160];
static const char g_WeaponsInventoryStageNames[][] =
{
    "CTFPlayer::ValidateWearables",
    "CTFPlayer::ValidateWeapons",
    "CBaseCombatWeapon::GiveTo",
    "CEconWearable::GiveTo",
    "CEconEntity::GiveTo",
    "CTFWeaponBase::UpdateExtraWearables",
    "CTFPlayer::PostInventoryApplication",
    "CBaseEntity::PrecacheModel"
};

static void WeaponsInventoryStages_Install(GameData data, WeaponsInventoryStage stage,
    DHookCallback pre, DHookCallback post)
{
    DynamicDetour detour = DynamicDetour.FromConf(data, g_WeaponsInventoryStageNames[stage]);
    if (detour == null)
    {
        LogError("Optional inventory stage unavailable: %s", g_WeaponsInventoryStageNames[stage]);
        return;
    }
    bool preEnabled = detour.Enable(Hook_Pre, pre);
    bool postEnabled = preEnabled && detour.Enable(Hook_Post, post);
    if (!postEnabled)
    {
        if (preEnabled) detour.Disable(Hook_Pre, pre);
        delete detour;
        LogError("Optional inventory stage could not be enabled: %s", g_WeaponsInventoryStageNames[stage]);
        return;
    }
    g_WeaponsInventoryStages[stage] = detour;
}

void WeaponsInventoryStages_Init(GameData data)
{
    if (data == null) return;
    WeaponsInventoryStages_Install(data, InventoryStage_ValidateWearables,
        WeaponsInventoryStage_ValidateWearables_Pre, WeaponsInventoryStage_ValidateWearables_Post);
    WeaponsInventoryStages_Install(data, InventoryStage_ValidateWeapons,
        WeaponsInventoryStage_ValidateWeapons_Pre, WeaponsInventoryStage_ValidateWeapons_Post);
    WeaponsInventoryStages_Install(data, InventoryStage_WeaponGiveTo,
        WeaponsInventoryStage_WeaponGiveTo_Pre, WeaponsInventoryStage_WeaponGiveTo_Post);
    WeaponsInventoryStages_Install(data, InventoryStage_WearableGiveTo,
        WeaponsInventoryStage_WearableGiveTo_Pre, WeaponsInventoryStage_WearableGiveTo_Post);
    WeaponsInventoryStages_Install(data, InventoryStage_EconGiveTo,
        WeaponsInventoryStage_EconGiveTo_Pre, WeaponsInventoryStage_EconGiveTo_Post);
    WeaponsInventoryStages_Install(data, InventoryStage_ExtraWearables,
        WeaponsInventoryStage_ExtraWearables_Pre, WeaponsInventoryStage_ExtraWearables_Post);
    WeaponsInventoryStages_Install(data, InventoryStage_PostInventory,
        WeaponsInventoryStage_PostInventory_Pre, WeaponsInventoryStage_PostInventory_Post);
    WeaponsInventoryStages_Install(data, InventoryStage_PrecacheModel,
        WeaponsInventoryStage_PrecacheModel_Pre, WeaponsInventoryStage_PrecacheModel_Post);
}

static void WeaponsInventoryStages_Remove(WeaponsInventoryStage stage,
    DHookCallback pre, DHookCallback post)
{
    if (g_WeaponsInventoryStages[stage] != null)
    {
        g_WeaponsInventoryStages[stage].Disable(Hook_Pre, pre);
        g_WeaponsInventoryStages[stage].Disable(Hook_Post, post);
        delete g_WeaponsInventoryStages[stage];
        g_WeaponsInventoryStages[stage] = null;
    }
    g_WeaponsInventoryStageDepth[stage] = 0;
}

void WeaponsInventoryStages_Shutdown()
{
    WeaponsInventoryStages_Remove(InventoryStage_ValidateWearables,
        WeaponsInventoryStage_ValidateWearables_Pre, WeaponsInventoryStage_ValidateWearables_Post);
    WeaponsInventoryStages_Remove(InventoryStage_ValidateWeapons,
        WeaponsInventoryStage_ValidateWeapons_Pre, WeaponsInventoryStage_ValidateWeapons_Post);
    WeaponsInventoryStages_Remove(InventoryStage_WeaponGiveTo,
        WeaponsInventoryStage_WeaponGiveTo_Pre, WeaponsInventoryStage_WeaponGiveTo_Post);
    WeaponsInventoryStages_Remove(InventoryStage_WearableGiveTo,
        WeaponsInventoryStage_WearableGiveTo_Pre, WeaponsInventoryStage_WearableGiveTo_Post);
    WeaponsInventoryStages_Remove(InventoryStage_EconGiveTo,
        WeaponsInventoryStage_EconGiveTo_Pre, WeaponsInventoryStage_EconGiveTo_Post);
    WeaponsInventoryStages_Remove(InventoryStage_ExtraWearables,
        WeaponsInventoryStage_ExtraWearables_Pre, WeaponsInventoryStage_ExtraWearables_Post);
    WeaponsInventoryStages_Remove(InventoryStage_PostInventory,
        WeaponsInventoryStage_PostInventory_Pre, WeaponsInventoryStage_PostInventory_Post);
    WeaponsInventoryStages_Remove(InventoryStage_PrecacheModel,
        WeaponsInventoryStage_PrecacheModel_Pre, WeaponsInventoryStage_PrecacheModel_Post);
}

static int WeaponsInventoryStages_Owner(int entity)
{
    return entity > MaxClients && IsValidEntity(entity)
        && HasEntProp(entity, Prop_Send, "m_hOwnerEntity")
        ? GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") : 0;
}

int WeaponsInventoryStages_Begin(WeaponsInventoryStage stage, int client)
{
    int depth = g_WeaponsInventoryStageDepth[stage]++;
    if (depth >= WEAPONS_INVENTORY_STAGE_DEPTH) return -1;
    g_WeaponsInventoryStageClients[stage][depth] = client;
    g_WeaponsInventoryStageDetails[stage][depth][0] = '\0';
    g_WeaponsInventoryStageProfiles[stage][depth] =
        g_WeaponsInventoryDiagnostics != null && g_WeaponsInventoryDiagnostics.BoolValue
        && g_WeaponsInventoryProfileDepth > 0 ? KogasaPerfBegin() : -1;
    return depth;
}

void WeaponsInventoryStages_End(WeaponsInventoryStage stage)
{
    if (g_WeaponsInventoryStageDepth[stage] <= 0) return;
    int depth = --g_WeaponsInventoryStageDepth[stage];
    if (depth >= WEAPONS_INVENTORY_STAGE_DEPTH) return;
    int profile = g_WeaponsInventoryStageProfiles[stage][depth];
    if (profile < 0) return;
    char scope[72];
    FormatEx(scope, sizeof(scope), "Inventory/%s(engine+hooks)", g_WeaponsInventoryStageNames[stage]);
    WeaponsPerf_EndClient(profile, scope, g_WeaponsInventoryStageClients[stage][depth],
        g_WeaponsInventoryStageDetails[stage][depth]);
    g_WeaponsInventoryStageProfiles[stage][depth] = -1;
}

public MRESReturn WeaponsInventoryStage_ValidateWearables_Pre(int entity, DHookParam params)
{
    WeaponsInventoryStages_Begin(InventoryStage_ValidateWearables, entity);
    return MRES_Ignored;
}
public MRESReturn WeaponsInventoryStage_ValidateWearables_Post(int entity, DHookParam params)
{
    WeaponsInventoryStages_End(InventoryStage_ValidateWearables);
    return MRES_Ignored;
}

public MRESReturn WeaponsInventoryStage_ValidateWeapons_Pre(int entity, DHookParam params)
{
    WeaponsInventoryStages_Begin(InventoryStage_ValidateWeapons, entity);
    return MRES_Ignored;
}
public MRESReturn WeaponsInventoryStage_ValidateWeapons_Post(int entity, DHookParam params)
{
    WeaponsInventoryStages_End(InventoryStage_ValidateWeapons);
    return MRES_Ignored;
}

public MRESReturn WeaponsInventoryStage_WeaponGiveTo_Pre(int entity, DHookParam params)
{
    WeaponsInventoryStages_Begin(InventoryStage_WeaponGiveTo, params.Get(1));
    return MRES_Ignored;
}
public MRESReturn WeaponsInventoryStage_WeaponGiveTo_Post(int entity, DHookParam params)
{
    WeaponsInventoryStages_End(InventoryStage_WeaponGiveTo);
    return MRES_Ignored;
}

public MRESReturn WeaponsInventoryStage_WearableGiveTo_Pre(int entity, DHookParam params)
{
    WeaponsInventoryStages_Begin(InventoryStage_WearableGiveTo, params.Get(1));
    return MRES_Ignored;
}
public MRESReturn WeaponsInventoryStage_WearableGiveTo_Post(int entity, DHookParam params)
{
    WeaponsInventoryStages_End(InventoryStage_WearableGiveTo);
    return MRES_Ignored;
}

public MRESReturn WeaponsInventoryStage_EconGiveTo_Pre(int entity, DHookParam params)
{
    WeaponsInventoryStages_Begin(InventoryStage_EconGiveTo, params.Get(1));
    return MRES_Ignored;
}
public MRESReturn WeaponsInventoryStage_EconGiveTo_Post(int entity, DHookParam params)
{
    WeaponsInventoryStages_End(InventoryStage_EconGiveTo);
    return MRES_Ignored;
}

public MRESReturn WeaponsInventoryStage_ExtraWearables_Pre(int entity)
{
    WeaponsInventoryStages_Begin(InventoryStage_ExtraWearables, WeaponsInventoryStages_Owner(entity));
    return MRES_Ignored;
}
public MRESReturn WeaponsInventoryStage_ExtraWearables_Post(int entity)
{
    WeaponsInventoryStages_End(InventoryStage_ExtraWearables);
    return MRES_Ignored;
}

public MRESReturn WeaponsInventoryStage_PostInventory_Pre(int entity)
{
    WeaponsInventoryStages_Begin(InventoryStage_PostInventory, entity);
    return MRES_Ignored;
}
public MRESReturn WeaponsInventoryStage_PostInventory_Post(int entity)
{
    WeaponsInventoryStages_End(InventoryStage_PostInventory);
    return MRES_Ignored;
}

public MRESReturn WeaponsInventoryStage_PrecacheModel_Pre(DHookReturn result, DHookParam params)
{
    int depth = WeaponsInventoryStages_Begin(InventoryStage_PrecacheModel, 0);
    if (depth >= 0 && g_WeaponsInventoryStageProfiles[InventoryStage_PrecacheModel][depth] >= 0
        && !params.IsNull(1))
        params.GetString(1, g_WeaponsInventoryStageDetails[InventoryStage_PrecacheModel][depth], 160);
    return MRES_Ignored;
}
public MRESReturn WeaponsInventoryStage_PrecacheModel_Post(DHookReturn result, DHookParam params)
{
    WeaponsInventoryStages_End(InventoryStage_PrecacheModel);
    return MRES_Ignored;
}
