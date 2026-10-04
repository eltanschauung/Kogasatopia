// Halloween map rules, formerly nerfhalloweengimmicks by Hombre.
#define HALLOWEEN_CLEANUP_STUNS 0
#define HALLOWEEN_CLEANUP_PUMPKINS 1
#define HALLOWEEN_CLEANUP_COUNT 2

static const char g_HalloweenCleanupClassnames[][] =
{
    "trigger_stun",
    "tf_pumpkin_bomb"
};

ConVar g_cvHalloweenDisableStuns;
ConVar g_cvHalloweenDisableSpells;
ConVar g_cvHalloweenMiniCrump;
ConVar g_cvHalloweenNerfBosses;
ConVar g_cvHalloweenBossNerfScale;
ConVar g_cvHalloweenBetterPumpkins;
ConVar g_cvHalloweenNoPumpkins;
ConVar g_cvHalloweenStatus;
bool g_HalloweenSpellCleanupQueued;

void HalloweenGimmicksNerf_OnPluginStart()
{
    g_cvHalloweenDisableSpells = CreateConVar("sm_nospells", "1", "Disable spells", _, true, 0.0, true, 1.0);
    g_cvHalloweenDisableSpells.AddChangeHook(HalloweenGimmicksNerf_OnSpellSettingChanged);
    g_cvHalloweenDisableStuns = CreateConVar("sm_noghoststuns", "1", "Attempt to disable trigger_stuns (halloween ghost stun), doesn't work on Viaduct Event", _, true, 0.0, true, 1.0);
    g_cvHalloweenMiniCrump = CreateConVar("sm_minicrumps", "1", "Replace crit pumpkin boost with mini crits", _, true, 0.0, true, 1.0);
    g_cvHalloweenBetterPumpkins = CreateConVar("sm_betterpumpkins", "1", "Limit pumpkin bomb damage while maintaining launch velocity", _, true, 0.0, true, 1.0);
    g_cvHalloweenNoPumpkins = CreateConVar("sm_nopumpkins", "0", "Disable exploding pumpkins", _, true, 0.0, true, 1.0);
    g_cvHalloweenNerfBosses = CreateConVar("sm_nerfbosses", "1", "Scale damage to Halloween bosses", _, true, 0.0, true, 1.0);
    g_cvHalloweenBossNerfScale = CreateConVar("sm_bossnerfscale", "4", "Multiply damage to Monoculus/Horsemann/Merasmus by this value", _, true, 0.0, true, 10.0);
    g_cvHalloweenStatus = CreateConVar("sm_halloween", "0", "Reference for other plugins to check halloween status", _, true, 0.0, true, 1.0);
    AutoExecConfig(true, "nerfhalloweengimmicks");
    HalloweenGimmicksNerf_CheckHalloweenStatus();
    HalloweenGimmicksNerf_QueueSpellPickupCleanup();

    // Reloads must also cover clients and bosses already in the current map.
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
            HalloweenGimmicksNerf_OnClientPutInServer(client);
    }

    for (int entity = MaxClients + 1; entity < GetMaxEntities(); entity++)
    {
        if (HalloweenGimmicksNerf_IsHalloweenBoss(entity))
            SDKHook(entity, SDKHook_OnTakeDamage, HalloweenGimmicksNerf_OnTakeDamage);
    }
}

void HalloweenGimmicksNerf_OnMapStart()
{
    g_HalloweenSpellCleanupQueued = false;
    HalloweenGimmicksNerf_CheckHalloweenStatus();
    HalloweenGimmicksNerf_QueueSpellPickupCleanup();
}

void HalloweenGimmicksNerf_OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, HalloweenGimmicksNerf_OnTakeDamage);
}

void HalloweenGimmicksNerf_OnConfigsExecuted()
{
    HalloweenGimmicksNerf_CheckHalloweenStatus();
    HalloweenGimmicksNerf_QueueSpellPickupCleanup();
}

// Entity creation checks

void HalloweenGimmicksNerf_OnEntityCreated(int entity, const char[] classname)
{
    if (g_cvHalloweenDisableSpells == null || !IsValidEntity(entity)) return;

    // Spell drops can exist on ordinary maps without Halloween marker entities.
    if (StrEqual(classname, "tf_spell_pickup", false))
    {
        SDKHook(entity, SDKHook_StartTouch, HalloweenGimmicksNerf_SpellPickup_BlockTouch);
        SDKHook(entity, SDKHook_Touch, HalloweenGimmicksNerf_SpellPickup_BlockTouch);
        SDKHook(entity, SDKHook_SpawnPost, HalloweenGimmicksNerf_SpellPickup_OnSpawnPost);
        return;
    }

    if (HalloweenGimmicksNerf_IsHalloweenBoss(entity))
    {
        SDKHook(entity, SDKHook_OnTakeDamage, HalloweenGimmicksNerf_OnTakeDamage);
    }

    if (!g_cvHalloweenStatus.BoolValue) return;

    int cleanupType = -1;
    if (g_cvHalloweenDisableStuns.BoolValue && StrEqual(classname, g_HalloweenCleanupClassnames[HALLOWEEN_CLEANUP_STUNS], false))
    {
        cleanupType = HALLOWEEN_CLEANUP_STUNS;
    }
    else if (g_cvHalloweenNoPumpkins.BoolValue && StrEqual(classname, g_HalloweenCleanupClassnames[HALLOWEEN_CLEANUP_PUMPKINS], false))
    {
        cleanupType = HALLOWEEN_CLEANUP_PUMPKINS;
    }

    if (cleanupType != -1)
    {
        CreateTimer(0.1, HalloweenGimmicksNerf_Timer_RemoveHalloweenEntities, cleanupType, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action HalloweenGimmicksNerf_OnTakeDamage(int entity, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    if (!IsValidEntity(inflictor) || !IsValidEntity(attacker))
        return Plugin_Continue;

    if (!g_cvHalloweenStatus.BoolValue)
        return Plugin_Continue;

    char classname[64];
    GetEntityClassname(inflictor, classname, sizeof(classname));
    if (StrEqual(classname, "tf_pumpkin_bomb") && g_cvHalloweenBetterPumpkins.BoolValue)
    {
        damage *= 0.5;
        if (attacker == entity)
        {
            int melee = GetPlayerWeaponSlot(entity, 2);
            if (melee > MaxClients && IsValidEntity(melee))
            {
                TF2Attrib_SetByName(melee, "rocket jump damage reduction HIDDEN", 0.40);
                RequestFrame(HalloweenGimmicksNerf_Frame_RemovePumpkinDamageReduction, EntIndexToEntRef(melee));
            }
        }
        return Plugin_Changed;
    }

    // Handle boss damage scaling
    if (g_cvHalloweenNerfBosses.BoolValue && IsValidEntity(entity) && HalloweenGimmicksNerf_IsHalloweenBoss(entity))
    {
        damage *= g_cvHalloweenBossNerfScale.FloatValue;
        return Plugin_Changed;
    }

    return Plugin_Continue;
}

void HalloweenGimmicksNerf_Frame_RemovePumpkinDamageReduction(any entityRef)
{
    int weapon = EntRefToEntIndex(entityRef);
    if (weapon != INVALID_ENT_REFERENCE && IsValidEntity(weapon))
    {
        TF2Attrib_RemoveByName(weapon, "rocket jump damage reduction HIDDEN");
    }
}

void HalloweenGimmicksNerf_OnRoundActive()
{
    HalloweenGimmicksNerf_CheckHalloweenStatus();
    HalloweenGimmicksNerf_QueueSpellPickupCleanup();
    if (g_cvHalloweenStatus.BoolValue)
    {
        if (g_cvHalloweenDisableStuns.BoolValue)
        {
            CreateTimer(0.1, HalloweenGimmicksNerf_Timer_RemoveHalloweenEntities, HALLOWEEN_CLEANUP_STUNS, TIMER_FLAG_NO_MAPCHANGE);
        }

        if (g_cvHalloweenNoPumpkins.BoolValue)
        {
            CreateTimer(0.1, HalloweenGimmicksNerf_Timer_RemoveHalloweenEntities, HALLOWEEN_CLEANUP_PUMPKINS, TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

void HalloweenGimmicksNerf_OnRoundStart()
{
    HalloweenGimmicksNerf_QueueSpellPickupCleanup();
}

public void HalloweenGimmicksNerf_OnSpellSettingChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    HalloweenGimmicksNerf_QueueSpellPickupCleanup();
}

void HalloweenGimmicksNerf_QueueSpellPickupCleanup()
{
    if (!g_cvHalloweenDisableSpells.BoolValue || g_HalloweenSpellCleanupQueued) return;
    g_HalloweenSpellCleanupQueued = true;
    RequestFrame(HalloweenGimmicksNerf_Frame_RemoveSpellPickups);
}

public void HalloweenGimmicksNerf_Frame_RemoveSpellPickups(any data)
{
    g_HalloweenSpellCleanupQueued = false;
    if (!g_cvHalloweenDisableSpells.BoolValue) return;
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "tf_spell_pickup")) != -1)
        RemoveEntity(entity);
}

public Action HalloweenGimmicksNerf_SpellPickup_BlockTouch(int entity, int other)
{
    return g_cvHalloweenDisableSpells.BoolValue ? Plugin_Handled : Plugin_Continue;
}

public void HalloweenGimmicksNerf_SpellPickup_OnSpawnPost(int entity)
{
    if (g_cvHalloweenDisableSpells.BoolValue)
    {
        // DropSpellPickup still uses the object after DispatchSpawn returns.
        RequestFrame(HalloweenGimmicksNerf_Frame_RemoveSpellPickup, EntIndexToEntRef(entity));
    }
}

public void HalloweenGimmicksNerf_Frame_RemoveSpellPickup(any entityRef)
{
    int entity = EntRefToEntIndex(entityRef);
    if (g_cvHalloweenDisableSpells.BoolValue && entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
        RemoveEntity(entity);
}

public void HalloweenGimmicksNerf_CheckHalloweenStatus()
{
    bool found = FindEntityByClassname(-1, "tf_logic_holiday") != -1
        || FindEntityByClassname(-1, "tf_halloween_gift_spawn_location") != -1;
    g_cvHalloweenStatus.SetBool(found);

    if (found)
    {
        PrintToServer("[HalloweenLimiter] Halloween map detected");
    }
}

void HalloweenGimmicksNerf_OnConditionAdded(int client, TFCond condition)
{
    if (g_cvHalloweenMiniCrump.BoolValue
        && g_cvHalloweenStatus.BoolValue
        && condition == TFCond_HalloweenCritCandy)
    {
        TF2_RemoveCondition(client, TFCond_HalloweenCritCandy);
        TF2_AddCondition(client, TFCond_CritCola, 4.0);
    }
}

public Action HalloweenGimmicksNerf_Timer_RemoveHalloweenEntities(Handle timer, any data)
{
    int cleanupType = data;
    if (cleanupType < 0 || cleanupType >= HALLOWEEN_CLEANUP_COUNT)
    {
        return Plugin_Stop;
    }

    int entity = -1;
    while ((entity = FindEntityByClassname(entity, g_HalloweenCleanupClassnames[cleanupType])) != -1)
    {
        AcceptEntityInput(entity, "Kill");
    }
    return Plugin_Stop;
}

bool HalloweenGimmicksNerf_IsHalloweenBoss(int entity)
{
    if (!IsValidEntity(entity))
        return false;

    char classname[64];
    GetEntityClassname(entity, classname, sizeof(classname));

    return (StrEqual(classname, "eyeball_boss") 
         || StrEqual(classname, "headless_hatman") 
         || StrEqual(classname, "merasmus"));
}
