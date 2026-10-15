// Kunai healing is applied synchronously at the end of CTFKnife::PrimaryAttack.
// Keep a bounded invocation stack so nested attacks cannot overwrite snapshots.
#define ATTR_KUNAI_NERF "kunai nerf"
#define KUNAI_NERF_HEALTH_CAP 185
#define KUNAI_NERF_MAX_ATTACK_DEPTH 16

enum struct KunaiNerfAttack
{
    int weaponRef;
    int clientSerial;
    int preHealth;
    bool backstab;
}

DynamicDetour g_KunaiNerfPrimaryAttack;
KunaiNerfAttack g_KunaiNerfAttacks[KUNAI_NERF_MAX_ATTACK_DEPTH];
int g_KunaiNerfAttackDepth;

void KunaiNerf_Init()
{
    GameData data = new GameData("weapons.games");
    if (data == null)
    {
        SetFailState("Missing weapons.games gamedata (kunai_nerf)");
        return;
    }
    g_KunaiNerfPrimaryAttack = DynamicDetour.FromConf(data, "CTFKnife::PrimaryAttack");
    delete data;
    if (g_KunaiNerfPrimaryAttack == null
        || !g_KunaiNerfPrimaryAttack.Enable(Hook_Pre, KunaiNerf_PrimaryAttack_Pre)
        || !g_KunaiNerfPrimaryAttack.Enable(Hook_Post, KunaiNerf_PrimaryAttack_Post))
        SetFailState("Failed to detour CTFKnife::PrimaryAttack for kunai nerf");
}

void KunaiNerf_Shutdown()
{
    if (g_KunaiNerfPrimaryAttack != null)
    {
        g_KunaiNerfPrimaryAttack.Disable(Hook_Pre, KunaiNerf_PrimaryAttack_Pre);
        g_KunaiNerfPrimaryAttack.Disable(Hook_Post, KunaiNerf_PrimaryAttack_Post);
        delete g_KunaiNerfPrimaryAttack;
    }
    g_KunaiNerfAttackDepth = 0;
}

static int KunaiNerf_CappedHealth(int preHealth, int postHealth)
{
    if (postHealth > preHealth && postHealth > KUNAI_NERF_HEALTH_CAP)
        return preHealth > KUNAI_NERF_HEALTH_CAP ? preHealth : KUNAI_NERF_HEALTH_CAP;
    return postHealth;
}

public MRESReturn KunaiNerf_PrimaryAttack_Pre(int weapon)
{
    int depth = g_KunaiNerfAttackDepth++;
    if (depth >= sizeof(g_KunaiNerfAttacks))
        return MRES_Ignored;

    g_KunaiNerfAttacks[depth].weaponRef = INVALID_ENT_REFERENCE;
    g_KunaiNerfAttacks[depth].clientSerial = 0;
    g_KunaiNerfAttacks[depth].preHealth = 0;
    g_KunaiNerfAttacks[depth].backstab = false;
    if (!WeaponsGameplay_IsEnabled() || !Weapons_IsValidWeaponEntity(weapon)
        || TF2CustAttr_GetInt(weapon, ATTR_KUNAI_NERF, 0) == 0)
        return MRES_Ignored;

    int client = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
    if (!Weapons_IsClientInGame(client) || !IsPlayerAlive(client)
        || TF2_GetPlayerClass(client) != TFClass_Spy)
        return MRES_Ignored;

    g_KunaiNerfAttacks[depth].weaponRef = EntIndexToEntRef(weapon);
    g_KunaiNerfAttacks[depth].clientSerial = GetClientSerial(client);
    g_KunaiNerfAttacks[depth].preHealth = GetClientHealth(client);
    return MRES_Ignored;
}

// Called by the existing death handler after resolving the actual kill weapon.
// Never use m_bReadyToBackstab: it is only a prediction, and misses are possible.
void KunaiNerf_RecordBackstab(Event event, int attacker, int killWeapon)
{
    if (g_KunaiNerfAttackDepth <= 0
        || g_KunaiNerfAttackDepth > sizeof(g_KunaiNerfAttacks)
        || event.GetInt("customkill") != TF_CUSTOM_BACKSTAB
        || (event.GetInt("death_flags") & TF_DEATHFLAG_DEADRINGER) != 0
        || !Weapons_IsValidWeaponEntity(killWeapon))
        return;

    int depth = g_KunaiNerfAttackDepth - 1;
    if (EntRefToEntIndex(g_KunaiNerfAttacks[depth].weaponRef) == killWeapon
        && GetClientFromSerial(g_KunaiNerfAttacks[depth].clientSerial) == attacker)
        g_KunaiNerfAttacks[depth].backstab = true;
}

public MRESReturn KunaiNerf_PrimaryAttack_Post(int weapon)
{
    if (g_KunaiNerfAttackDepth <= 0)
        return MRES_Ignored;
    int depth = --g_KunaiNerfAttackDepth;
    if (depth >= sizeof(g_KunaiNerfAttacks))
        return MRES_Ignored;

    KunaiNerfAttack attack;
    attack = g_KunaiNerfAttacks[depth];
    g_KunaiNerfAttacks[depth].clientSerial = 0;
    g_KunaiNerfAttacks[depth].weaponRef = INVALID_ENT_REFERENCE;
    g_KunaiNerfAttacks[depth].backstab = false;
    if (!attack.backstab || !WeaponsGameplay_IsEnabled()
        || !Weapons_IsValidWeaponEntity(weapon)
        || EntRefToEntIndex(attack.weaponRef) != weapon)
        return MRES_Ignored;

    int client = GetClientFromSerial(attack.clientSerial);
    if (!Weapons_IsClientInGame(client) || !IsPlayerAlive(client)
        || GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity") != client
        || TF2_GetPlayerClass(client) != TFClass_Spy)
        return MRES_Ignored;

    int postHealth = GetClientHealth(client);
    int cappedHealth = KunaiNerf_CappedHealth(attack.preHealth, postHealth);
    if (cappedHealth != postHealth)
        SetEntityHealth(client, cappedHealth);
    return MRES_Ignored;
}
