// Virtual hooks cover subclass overrides such as CTFKnife. Once installed,
// ItemPostFrame hooks live until entity destruction/plugin unload. Completion,
// cancellation and re-deploy only update state: never remove an executing hook.
DynamicHook g_WeaponsSoundDeployHook;
DynamicHook g_WeaponsSoundDeployFinishFrameHook;
int g_iWeaponsDeployFinishRef[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
int g_iWeaponsDeployFinishEntity[MAXPLAYERS + 1];
int g_iWeaponsDeployFinishHook[MAXPLAYERS + 1];
int g_iWeaponsDeployFinishClient[WEAPONS_SOUND_MAX_ENTITIES];
int g_iWeaponsDeployFrameHook[WEAPONS_SOUND_MAX_ENTITIES];

void WeaponsSound_InitDeployFinishedHooks()
{
    GameData data = new GameData("weapons.deploy_finished");
    if (data == null)
    {
        SetFailState("Missing weapons.deploy_finished gamedata");
        return;
    }
    g_WeaponsSoundDeployHook = DynamicHook.FromConf(data, "CTFWeaponBase::Deploy");
    g_WeaponsSoundDeployFinishFrameHook =
        DynamicHook.FromConf(data, "CTFWeaponBase::ItemPostFrame");
    delete data;
    if (g_WeaponsSoundDeployHook == null || g_WeaponsSoundDeployFinishFrameHook == null)
        SetFailState("Failed to create deploy-finished weapon hooks");
}

void WeaponsSound_ShutdownDeployFinishedHooks()
{
    for (int client = 1; client <= MaxClients; client++)
        WeaponsSound_CancelDeployFinish(client);
    // DHooks owns hook removal at entity destruction/plugin unload.
    delete g_WeaponsSoundDeployHook;
    g_WeaponsSoundDeployHook = null;
    delete g_WeaponsSoundDeployFinishFrameHook;
    g_WeaponsSoundDeployFinishFrameHook = null;
}

void WeaponsSound_HookDeployFinishedWeapon(int weapon)
{
    if (g_WeaponsSoundDeployHook != null && weapon < WEAPONS_SOUND_MAX_ENTITIES)
        g_WeaponsSoundDeployHook.HookEntity(Hook_Post, weapon, WeaponsSound_DeployPost);
}

public MRESReturn WeaponsSound_DeployPost(int weapon, DHookReturn result)
{
    if (result.Value && Weapons_IsValidWeaponEntity(weapon))
        WeaponsSound_TrackDeployFinish(GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity"), weapon);
    return MRES_Ignored;
}

void WeaponsSound_TrackDeployFinish(int client, int weapon)
{
    if (client < 1 || client > MaxClients)
        return;
    WeaponsSound_CancelDeployFinish(client);
    if (!Weapons_IsValidClient(client) || !IsPlayerAlive(client)
        || !Weapons_IsValidWeaponEntity(weapon) || weapon >= WEAPONS_SOUND_MAX_ENTITIES)
        return;

    int previousClient = g_iWeaponsDeployFinishClient[weapon];
    if (previousClient != 0 && previousClient != client)
        WeaponsSound_CancelDeployFinish(previousClient);

    g_iWeaponsDeployFinishRef[client] = EntIndexToEntRef(weapon);
    g_iWeaponsDeployFinishEntity[client] = weapon;
    g_iWeaponsDeployFinishClient[weapon] = client;
    g_iWeaponsDeployFinishHook[client] = WeaponsSound_AddDeployFinishHook(weapon);
    if (g_iWeaponsDeployFinishHook[client] == INVALID_HOOK_ID)
    {
        WeaponsSound_ClearDeployFinishState(client);
        LogError("Failed to hook deploy-finished ItemPostFrame on weapon %d", weapon);
    }
}

static int WeaponsSound_AddDeployFinishHook(int weapon)
{
    if (g_iWeaponsDeployFrameHook[weapon] == INVALID_HOOK_ID)
    {
        g_iWeaponsDeployFrameHook[weapon] = g_WeaponsSoundDeployFinishFrameHook.HookEntity(
            Hook_Pre, weapon, WeaponsSound_ItemPostFramePre, WeaponsSound_DeployFinishHookRemoved);
    }
    return g_iWeaponsDeployFrameHook[weapon];
}

static void WeaponsSound_ClearDeployFinishState(int client)
{
    int weapon = g_iWeaponsDeployFinishEntity[client];
    if (weapon > 0 && weapon < WEAPONS_SOUND_MAX_ENTITIES
        && g_iWeaponsDeployFinishClient[weapon] == client)
        g_iWeaponsDeployFinishClient[weapon] = 0;
    g_iWeaponsDeployFinishRef[client] = INVALID_ENT_REFERENCE;
    g_iWeaponsDeployFinishEntity[client] = 0;
    g_iWeaponsDeployFinishHook[client] = INVALID_HOOK_ID;
}

void WeaponsSound_CancelDeployFinish(int client)
{
    if (client >= 1 && client <= MaxClients)
        WeaponsSound_ClearDeployFinishState(client);
}

void WeaponsSound_CancelOtherDeploy(int client, int weapon)
{
    if (client >= 1 && client <= MaxClients
        && g_iWeaponsDeployFinishRef[client] != INVALID_ENT_REFERENCE
        && (!Weapons_IsValidWeaponEntity(weapon)
            || g_iWeaponsDeployFinishRef[client] != EntIndexToEntRef(weapon)))
        WeaponsSound_CancelDeployFinish(client);
}

void WeaponsSound_DeployFinishEntityDestroyed(int weapon)
{
    if (weapon <= MaxClients || weapon >= WEAPONS_SOUND_MAX_ENTITIES)
        return;
    int client = g_iWeaponsDeployFinishClient[weapon];
    if (client >= 1 && client <= MaxClients)
        WeaponsSound_CancelDeployFinish(client);
    g_iWeaponsDeployFrameHook[weapon] = INVALID_HOOK_ID;
}

public void WeaponsSound_DeployFinishHookRemoved(int hookId)
{
    // Fallback cleanup if DHooks removes a pending hook independently.
    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_iWeaponsDeployFinishHook[client] == hookId)
        {
            WeaponsSound_ClearDeployFinishState(client);
            break;
        }
    }
}

public MRESReturn WeaponsSound_ItemPostFramePre(int weapon)
{
    if (weapon <= MaxClients || weapon >= WEAPONS_SOUND_MAX_ENTITIES)
        return MRES_Ignored;
    int client = g_iWeaponsDeployFinishClient[weapon];
    if (client < 1 || client > MaxClients)
        return MRES_Ignored;

    bool ready = Weapons_IsValidClient(client) && IsPlayerAlive(client)
        && Weapons_IsValidWeaponEntity(weapon)
        && EntRefToEntIndex(g_iWeaponsDeployFinishRef[client]) == weapon
        && GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity") == client
        && GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") == weapon;
    WeaponsSound_CancelDeployFinish(client);
    if (ready)
        WeaponsSound_OnWeaponFinishedDeploy(client, weapon);
    return MRES_Ignored;
}
