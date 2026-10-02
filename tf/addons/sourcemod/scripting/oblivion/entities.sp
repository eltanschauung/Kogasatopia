static const char g_OwnerNames[][] = { "m_hBuilder", "m_hThrower", "m_hOwnerEntity", "moveparent", "m_hLauncher", "m_hOriginalLauncher", "m_hPlayer" };

int RememberActor(int entity, int actor)
{
    if (actor > 0)
    {
        g_Actor[entity] = actor;
        g_ActorSerial[entity] = GetClientSerial(actor);
        if (g_Auth[actor][0]) strcopy(g_EntityAuth[entity], AUTH_LEN, g_Auth[actor]);
    }
    return actor;
}

int Actor(int entity, int depth = 0)
{
    if (entity > 0 && entity <= MaxClients) return IsClientConnected(entity) ? entity : 0;
    if (entity <= MaxClients || entity >= ENTITY_LIMIT || depth >= 8 || !IsValidEntity(entity)) return 0;
    // Some TF2 entities (notably death ragdolls) are initialized without a
    // DispatchSpawn call, so a SpawnPost hook alone never discovers their data.
    // The first ownership query after construction initializes them too.
    if (!g_EntityHooked[entity]) HookEntity(entity);
    if ((g_Ragdoll[entity] || g_DroppedWeapon[entity]) && g_ActorSerial[entity])
        return GetClientFromSerial(g_ActorSerial[entity]);
    if (g_DroppedWeapon[entity])
    {
        int player = GetEntDataEnt2(entity, g_DroppedOwnerOffset);
        if (player > 0 && player <= MaxClients && IsClientConnected(player)) return RememberActor(entity, player);
    }
    for (int i = 0; i < sizeof(g_OwnerNames); i++)
    {
        if (!(g_OwnerProps[entity] & (1 << i))) continue;
        int owner = GetEntPropEnt(entity, Prop_Send, g_OwnerNames[i]);
        if (owner > 0 && owner != entity)
        {
            int actor = Actor(owner, depth + 1);
            if (actor > 0) return RememberActor(entity, actor);
        }
    }
    if (g_Actor[entity] > 0 && g_ActorSerial[entity] != 0)
    {
        int player = GetClientFromSerial(g_ActorSerial[entity]);
        if (player == g_Actor[entity]) return player;
    }
    return 0;
}

bool EntityIdentity(int entity, char[] identity, int size)
{
    int actor = Actor(entity);
    if (actor > 0 && g_Auth[actor][0]) { strcopy(identity, size, g_Auth[actor]); return true; }
    if (entity > MaxClients && entity < ENTITY_LIMIT && g_EntityAuth[entity][0])
    {
        strcopy(identity, size, g_EntityAuth[entity]);
        return true;
    }
    identity[0] = '\0';
    return false;
}

bool HiddenEntity(int viewer, int entity)
{
    if (viewer < 1 || viewer > MaxClients || !g_HasRules[viewer]) return false;
    int actor = Actor(entity);
    if (actor > 0) return Hidden(viewer, actor);
    return entity > MaxClients && entity < ENTITY_LIMIT && g_EntityAuth[entity][0]
        && HiddenAuth(viewer, g_EntityAuth[entity]);
}

bool EntitiesBlocked(int first, int second)
{
    int a = Actor(first), b = Actor(second);
    if (a > 0 && b > 0) return Blocked(a, b);
    char firstId[AUTH_LEN], secondId[AUTH_LEN];
    if (!EntityIdentity(first, firstId, sizeof(firstId)) || !EntityIdentity(second, secondId, sizeof(secondId))) return false;
    return PairIndex(firstId, secondId) >= 0 || PairIndex(secondId, firstId) >= 0;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (entity <= MaxClients || entity >= ENTITY_LIMIT) return;
    g_EntityHooked[entity] = false;
    g_Actor[entity] = 0;
    g_ActorSerial[entity] = 0;
    g_EntityAuth[entity][0] = '\0';
    g_OwnerProps[entity] = 0;
    g_Ragdoll[entity] = false;
    g_DroppedWeapon[entity] = false;
    g_IsTeam[entity] = false;
    g_TeamOwnerSerial[entity] = 0;
    SDKHook(entity, SDKHook_SpawnPost, EntitySpawned);
    RequestFrame(CacheEntityOwner, EntIndexToEntRef(entity));
}

public void EntitySpawned(int entity)
{
    HookEntity(entity);
    RequestFrame(CacheEntityOwner, EntIndexToEntRef(entity));
}

public void CacheEntityOwner(int reference)
{
    int entity = EntRefToEntIndex(reference);
    if (entity > MaxClients && entity < ENTITY_LIMIT && IsValidEntity(entity)) Actor(entity);
}

void HookEntity(int entity)
{
    if (entity <= MaxClients || entity >= ENTITY_LIMIT || !IsValidEntity(entity) || g_EntityHooked[entity]) return;
    char classname[64];
    GetEntityClassname(entity, classname, sizeof(classname));
    if (StrEqual(classname, "tf_player_manager")) return;
    if (StrEqual(classname, "tf_team")) { g_IsTeam[entity] = true; return; }
    g_EntityHooked[entity] = true;
    for (int i = 0; i < sizeof(g_OwnerNames); i++)
        if (HasEntProp(entity, Prop_Send, g_OwnerNames[i])) g_OwnerProps[entity] |= 1 << i;
    g_Ragdoll[entity] = StrEqual(classname, "tf_ragdoll") && HasEntProp(entity, Prop_Send, "m_hPlayer");
    g_DroppedWeapon[entity] = StrEqual(classname, "tf_dropped_weapon");
    if (StrContains(classname, "obj_") == 0)
    {
        SDKHook(entity, SDKHook_OnTakeDamage, FilterDamage);
        Interactions_HookEntity(entity);
    }
    if (StrContains(classname, "tf_projectile_") == 0 || StrContains(classname, "obj_") == 0)
        Effects_HookEntity(entity);
    if (StrContains(classname, "tf_projectile_") == 0 || StrContains(classname, "obj_") == 0
        || StrContains(classname, "item_") == 0 || StrEqual(classname, "tf_dropped_weapon") || StrEqual(classname, "tf_ammo_pack"))
    {
        SDKHook(entity, SDKHook_StartTouch, FilterTouch);
        SDKHook(entity, SDKHook_Touch, FilterTouch);
    }
    int actor = Actor(entity);
    if (actor > 0)
    {
        g_Actor[entity] = actor;
        g_ActorSerial[entity] = GetClientSerial(actor);
    }
}

public void OnEntityDestroyed(int entity)
{
    ForgetEffectScopes(entity);
    if (entity > 0 && entity < ENTITY_LIMIT)
    {
        g_EntityHooked[entity] = false;
        g_Actor[entity] = 0;
        g_ActorSerial[entity] = 0;
        g_EntityAuth[entity][0] = '\0';
        g_OwnerProps[entity] = 0;
        g_Ragdoll[entity] = false;
        g_DroppedWeapon[entity] = false;
        g_IsResource[entity] = false;
        if (g_IsTeam[entity]) OblivionNet_TeamForget(entity);
        g_IsTeam[entity] = false;
        g_TeamOwnerSerial[entity] = 0;
    }
}

public Action FilterTransmit(int entity, int viewer)
{
    return HiddenEntity(viewer, entity) ? Plugin_Handled : Plugin_Continue;
}

public void OblivionNet_CheckTransmit(int viewer, const int[] entities, int count, bool[] blocked)
{
    // Called AFTER the game's complete CheckTransmit, including FL_EDICT_ALWAYS
    // and dependency/parent shortcuts which never call SDKHook_SetTransmit.
    if (!g_Ready || !g_MapActive || viewer < 1 || viewer > MaxClients) return;
    for (int i = 0; i < count; i++)
    {
        int entity = entities[i];
        if (entity <= 0 || entity >= ENTITY_LIMIT || entity == viewer) continue;
        if (g_IsResource[entity]) blocked[i] = Roster_Transmit(entity, viewer) == Plugin_Handled;
        else if (g_IsTeam[entity]) blocked[i] = Teams_Blocked(entity, viewer);
        else if (g_HasRules[viewer]) blocked[i] = HiddenEntity(viewer, entity);
    }
}

public Action FilterDamage(int victim, int &attacker, int &inflictor, float &damage,
    int &damageType, int &weapon, float force[3], float position[3], int damageCustom)
{
    if (!EntitiesBlocked(victim, attacker) && !EntitiesBlocked(victim, inflictor)) return Plugin_Continue;
    damage = 0.0;
    force[0] = 0.0; force[1] = 0.0; force[2] = 0.0;
    return Plugin_Handled;
}

public Action FilterTraceAttack(int victim, int &attacker, int &inflictor, float &damage,
    int &damageType, int &ammoType, int hitbox, int hitgroup)
{
    return EntitiesBlocked(victim, attacker) ? Plugin_Handled : Plugin_Continue;
}

public Action FilterTouch(int first, int second)
{
    return EntitiesBlocked(first, second) ? Plugin_Handled : Plugin_Continue;
}

public Action CH_PassFilter(int first, int second, bool &result)
{
    if (!EntitiesBlocked(first, second)) return Plugin_Continue;
    result = false;
    return Plugin_Handled;
}

public Action CH_ShouldCollide(int first, int second, bool &result)
{
    return CH_PassFilter(first, second, result);
}

public Action FilterSound(int clients[MAXPLAYERS], int &count, char sample[PLATFORM_MAX_PATH],
    int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
    char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
    if (flags & (SND_STOP | SND_STOPLOOPING)) return Plugin_Continue;
    int source = EffectSource();
    int kept;
    for (int i = 0; i < count; i++)
        if (!HiddenEntity(clients[i], entity) && !HiddenEntity(clients[i], source)) clients[kept++] = clients[i];
    if (kept == count) return Plugin_Continue;
    count = kept;
    return kept ? Plugin_Changed : Plugin_Handled;
}

public void TF2_OnConditionAdded(int client, TFCond condition)
{
    if (GetFeatureStatus(FeatureType_Native, "TF2Util_GetPlayerConditionProvider") != FeatureStatus_Available) return;
    int source = Actor(TF2Util_GetPlayerConditionProvider(client, condition));
    if (Blocked(client, source)) TF2_RemoveCondition(client, condition);
}
