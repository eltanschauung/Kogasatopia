/** Unified TF2 weapon configuration, custom loadout, models, sounds and gameplay. */
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>
#include <sdkhooks>
#include <sdktools>
#include <sdktools_sound>
#include <tf2>
#include <tf2utils>
#include <tf_econ_data>
#include <tf2attributes>
#include <tf2items>
#include <tf2_stocks>
#include <tf_ontakedamage>
#include <morecolors>
#include <sourcescramble>
#include <dhooks>
#include <addplayerhealth>
#include <stocksoup/convars>
#include <stocksoup/handles>
#include <stocksoup/math>
#include <stocksoup/tf/econ>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/tf/weapon>

#undef REQUIRE_EXTENSIONS
#include <tf2_spread_patterns>
#define REQUIRE_EXTENSIONS

#undef REQUIRE_EXTENSIONS
#include <scattergun_pellets>
#define REQUIRE_EXTENSIONS

#undef REQUIRE_PLUGIN
#include <dgm_api>
#include <points_store_api>
#define REQUIRE_PLUGIN
#include <plugin_statistics>
#define WEAPONS_INCLUDE_SHAREDDEFS_ONLY
#include <weapons>
#include "include/database.inc"
#include "include/steam_identity.inc"
#include "include/item_indexes.inc"
#include "include/client_validation.inc"
#include "include/strings.inc"
#include "include/tf2_classes.inc"

#tryinclude <autoversioning/version>
#if defined __ninjabuild_auto_version_included
    #define VERSION_SUFFIX "-" ... GIT_COMMIT_SHORT_HASH
#else
    #define VERSION_SUFFIX ""
#endif

public Plugin myinfo =
{
    name = "Weapons",
    author = "nosoop, Hombre, tsuza, Mir, Huutti, Utsuho, Sappykun, Nanochip, Leonardo, MikeJS, Jaro 'Monkeys' Vanderheijden",
    description = "Unified custom weapons, weapon behavior, models, sounds, and loadouts.",
    version = "7.1" ... VERSION_SUFFIX,
    url = "https://kogasa.tf"
};

#define MAX_ITEM_IDENTIFIER_LENGTH 64
#define MAX_ITEM_NAME_LENGTH 128
#define MAX_ITEM_DESCRIPTION_LENGTH 512
#define WEAPONS_CONFIG_PATH "configs/weapons.cfg"
#define WEAPONS_CONFIG_ROOT "Weapons"
#define WEAPONS_ITEM_CLASSES_SECTION "ItemClasses"
#define WEAPONS_CONFIG_ITEM_SECTION "CustomWeapons"
#define WEAPONS_CONFIG_SOUND_SECTION "SoundGroups"
#define NUM_ITEMS 7
#define NUM_PLAYER_CLASSES 10
#define WEAPONS_STATS_DB_CONFIG_DEFAULT "default"
// Preserve existing statistics and external integrations.
#define WEAPONS_STATS_STATE_TABLE "cwx_weapon_popularity"
#define ATTRIB_NAME_CUSTOM_UID "random drop line item unusual list"
#define POINTS_STORE_HAS_PURCHASE_NATIVE "PointsStore_HasPurchase"

bool g_bRetrievedLoadout[MAXPLAYERS + 1];
Cookie g_ItemPersistCookies[NUM_PLAYER_CLASSES][NUM_ITEMS];
bool g_bForceReequipItems[MAXPLAYERS + 1];
enum WeaponsHtmlMotdPreference
{
    WeaponsHtmlMotd_Unknown = 0,
    WeaponsHtmlMotd_Enabled,
    WeaponsHtmlMotd_Disabled
};
WeaponsHtmlMotdPreference g_WeaponsHtmlMotdPreference[MAXPLAYERS + 1];
ConVar sm_weapons_enable_loadout;
ConVar sm_weapons_statistics;
ConVar sm_weapons_statistics_database;
ConVar sm_weapons_validate_debug;
ConVar sm_weapons_validate_repair;
ConVar sm_weapons_hide_reskin_only;
ConVar sm_weapons_free;
ConVar mp_stalemate_meleeonly;
Database g_WeaponsStatsDb = null;
bool g_WeaponsStatsDbReady = false;
bool g_WeaponsStatsIsMySql = false;
Handle g_hWeaponsStatsDbReconnectTimer = null;
Handle g_hOnItemRuntimeStateReady = null;
int g_attrdef_AllowedInMedievalMode;

#include "weapons/custom_attributes.sp"
#include "weapons/whitelist.sp"
#include "weapons/movement_attributes.sp"
#include "weapons/item_config.sp"
#include "weapons/item_entity.sp"
#include "weapons/hats.sp"
#include "weapons/hat_visibility.sp"
#include "weapons/item_export.sp"
#include "weapons/loadout_entries.sp"
#include "weapons/loadout_radio_menu.sp"
#include "weapons/sound_overrides.sp"
#include "weapons/model_overrides.sp"
#include "weapons/gameplay.sp"
#include "weapons/commands.sp"
#include "weapons/equip_commands.sp"
#include "weapons/loadout_controller.sp"
#include "weapons/statistics_persistence.sp"

public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int maxlen)
{
    WeaponsCustomAttributes_RegisterNatives();
    CustomHats_RegisterNatives();
    MarkNativeAsOptional("DGM_CurrentNormalizedMap");
    MarkNativeAsOptional("DGM_NormalizeMapName");
    MarkNativeAsOptional("DGM_GetGameModeKey");
    RegPluginLibrary("weapons");
    WeaponsGameplay_RegisterNatives();
    CreateNative("Weapons_SetPlayerLoadoutItem", Native_SetPlayerLoadoutItem);
    CreateNative("Weapons_RemovePlayerLoadoutItem", Native_RemovePlayerLoadoutItem);
    CreateNative("Weapons_GetPlayerLoadoutItem", Native_GetPlayerLoadoutItem);
    CreateNative("Weapons_EquipPlayerItem", Native_EquipPlayerItem);
    CreateNative("Weapons_CanPlayerAccessItem", Native_CanPlayerAccessItem);
    CreateNative("Weapons_GetItemList", Native_GetItemList);
    CreateNative("Weapons_IsItemUIDValid", Native_IsItemUIDValid);
    CreateNative("Weapons_GetItemUIDFromEntity", Native_GetItemUIDFromEntity);
    CreateNative("Weapons_GetItemDisplayName", Native_GetItemDisplayName);
    CreateNative("Weapons_IsItemReskinOnly", Native_IsItemReskinOnly);
    CreateNative("Weapons_GetItemExtData", Native_GetItemExtData);
    CreateNative("Weapons_GetItemLoadoutSlot", Native_GetItemLoadoutSlot);
    CreateNative("Weapons_GetKillingWeapon", Native_GetKillingWeapon);
    return APLRes_Success;
}

public void OnPluginStart()
{
    WeaponsCustomAttributes_OnPluginStart();
    WeaponsWhitelist_OnPluginStart();
    WeaponsMovement_OnPluginStart();
    CustomHats_OnPluginStart();
    WeaponsHatVisibility_OnPluginStart();
    LoadTranslations("weapons.phrases");
    LoadTranslations("common.phrases");
    LoadTranslations("core.phrases");
    GameData gameConf = new GameData("weapons");
    if (gameConf == null)
    {
        SetFailState("Failed to load gamedata (weapons.txt).");
    }
    Handle getLoadout = DHookCreateFromConf(gameConf, "CTFPlayer::GetLoadoutItem()");
    Handle manageWeapons = DHookCreateFromConf(gameConf, "CTFPlayer::ManageRegularWeapons()");
    if (getLoadout == null || manageWeapons == null)
    {
        delete gameConf;
        SetFailState("Failed to create required weapon loadout detours.");
    }
    DHookEnableDetour(getLoadout, false, OnGetLoadoutItemPre);
    DHookEnableDetour(getLoadout, true, OnGetLoadoutItemPost);
    DHookEnableDetour(manageWeapons, false, OnManageRegularWeaponsPre);
    DHookEnableDetour(manageWeapons, true, OnManageRegularWeaponsPost);
    WeaponsGameplay_OnPluginStart(gameConf);
    WeaponsSound_OnPluginStart(gameConf);
    delete gameConf;
    HookUserMessage(GetUserMessageId("PlayerLoadoutUpdated"), OnPlayerLoadoutUpdated,
        .post = OnPlayerLoadoutUpdatedPost);
    CreateVersionConVar("sm_weapons_version", "Unified weapons plugin version.");
    sm_weapons_enable_loadout = CreateConVar("sm_weapons_enable_loadout", "1", "Allows players to receive custom items they have selected.");
    sm_weapons_statistics = CreateConVar("sm_weapons_statistics", "1", "Record custom weapons equip/unequip popularity statistics.", _, true, 0.0, true, 1.0);
    sm_weapons_statistics_database = CreateConVar("sm_weapons_statistics_database", WEAPONS_STATS_DB_CONFIG_DEFAULT, "Database config used for custom weapon popularity statistics.");
    sm_weapons_validate_debug = CreateConVar("sm_weapons_validate_debug", "0", "Log m_bValidatedAttachedEntity state after custom item creation and equip.", _, true, 0.0, true, 1.0);
    sm_weapons_validate_repair = CreateConVar("sm_weapons_validate_repair", "1", "Re-assert m_bValidatedAttachedEntity if TF2 clears it after attachment.", _, true, 0.0, true, 1.0);
    sm_weapons_hide_reskin_only = CreateConVar("sm_weapons_hide_reskin_only", "1", "Hide reskin-only weapons from sm_c descriptions.", _, true, 0.0, true, 1.0);
    sm_weapons_free = CreateConVar("sm_weapons_free", "0", "Treat all custom weapons as unlocked in sm_cw.", _, true, 0.0, true, 1.0);
    sm_weapons_statistics.AddChangeHook(OnWeaponsStatisticsEnabledChanged);
    sm_weapons_statistics_database.AddChangeHook(OnWeaponsStatisticsDatabaseChanged);
    ConnectWeaponsStatisticsDatabase();
    g_hOnItemRuntimeStateReady = CreateGlobalForward("Weapons_OnItemRuntimeStateReady", ET_Ignore, Param_Cell, Param_Cell);
    RegAdminCmd("sm_weapons_export", ExportActiveWeapon, ADMFLAG_ROOT);
    RegAdminCmd("sm_cw", DisplayItems, 0);
    RegAdminCmd("sm_cwc", DisplayItems, 0);
    RegAdminCmd("sm_cwx", DisplayItems, 0);
    RegAdminCmd("sm_items", DisplayItems, 0);
    RegAdminCmd("sm_weapons", DisplayItems, 0);
    RegAdminCmd("sm_weapon", DisplayItems, 0);
    RegAdminCmd("sm_custom", DisplayItems, 0);
    RegAdminCmd("sm_customweapons", DisplayItems, 0);
    RegAdminCmd("sm_weps", DisplayItems, 0);
    RegAdminCmd("sm_equip", DisplayItems, 0);
    RegAdminCmd("sm_c", DisplayItemDescriptions, 0);
    RegAdminCmd("sm_cp", DisplayItemDescriptions, 0);
    RegAdminCmd("sm_c2", DisplayItemDescriptions, 0);
    AddCommandListener(DisplayItemsCompat, "sm_cus");
    mp_stalemate_meleeonly = FindConVar("mp_stalemate_meleeonly");
    char cookieName[64], cookieDesc[128];
    for (int playerClass = 0; playerClass < NUM_PLAYER_CLASSES; playerClass++)
    {
        for (int slot = 0; slot < NUM_ITEMS; slot++)
        {
            FormatEx(cookieName, sizeof(cookieName), "cwx_loadout_%d_%d", playerClass, slot);
            FormatEx(cookieDesc, sizeof(cookieDesc), "Weapons loadout entry for class %d in slot %d", playerClass, slot);
            g_ItemPersistCookies[playerClass][slot] = new Cookie(cookieName, cookieDesc, CookieAccess_Private);
        }
    }
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientConnected(client))
        {
            continue;
        }
        OnClientConnected(client);
        if (IsClientInGame(client))
        {
            WeaponsCommands_QueryHtmlMotdPreference(client);
        }
        if (IsClientAuthorized(client))
        {
            FetchLoadoutItems(client);
        }
    }
    WeaponsModels_OnPluginStart();
    LoadWeaponsConfig();
    WeaponsCommands_OnPluginStart();
    WeaponsEquipCommands_OnPluginStart();
}

public void OnPluginEnd()
{
    CustomHats_OnPluginEnd();
    WeaponsGameplay_OnPluginEnd();
    WeaponsModels_OnPluginEnd();
    WeaponsSound_OnPluginEnd();
    WeaponsStats_StopConnection();
    delete g_hOnItemRuntimeStateReady;
    WeaponsConfig_Close();
    WeaponsCustomAttributes_OnPluginEnd();
    delete g_WeaponsItemMetadataOffsets;
}

public void OnConfigsExecuted()
{
    WeaponsMovement_OnConfigsExecuted();
    CustomHats_OnConfigsExecuted();
}

void Weapons_NotifyItemRuntimeStateReady(int client, int entity)
{
    if (!Weapons_IsValidClient(client) || entity <= MaxClients || !IsValidEntity(entity))
    {
        return;
    }
    int serial = GetClientSerial(client);
    int ref = EntIndexToEntRef(entity);
    Weapons_ApplyEngineOverrides(entity);
    if (!Weapons_LoadoutIdentityMatches(serial, client, ref, entity)) return;
    WeaponsMovement_OnItemRuntimeStateReady(client, entity);
    if (!Weapons_LoadoutIdentityMatches(serial, client, ref, entity)) return;
    WeaponsModels_OnItemRuntimeStateReady(client, entity);
    if (!Weapons_LoadoutIdentityMatches(serial, client, ref, entity)) return;
    WeaponsSound_OnItemRuntimeStateReady(client, entity);
    if (!Weapons_LoadoutIdentityMatches(serial, client, ref, entity)) return;
    WeaponsGameplay_OnItemRuntimeStateReady(client, entity);
    if (!Weapons_LoadoutIdentityMatches(serial, client, ref, entity)
        || g_hOnItemRuntimeStateReady == null) return;
    Call_StartForward(g_hOnItemRuntimeStateReady);
    Call_PushCell(client);
    Call_PushCell(entity);
    Call_Finish();
}

public void OnAllPluginsLoaded()
{
    BuildLoadoutSlotMenu();
    g_attrdef_AllowedInMedievalMode = TF2Econ_TranslateAttributeNameToDefinitionIndex("allowed in medieval mode");
}

public void OnLibraryAdded(const char[] name)
{
    CustomHats_OnLibraryAdded(name);
}

public void OnLibraryRemoved(const char[] name)
{
    CustomHats_OnLibraryRemoved(name);
}

public void OnMapStart()
{
    WeaponsMovement_OnMapStart();
    WeaponsCustomAttributes_OnMapStart();
    WeaponsModels_OnMapStart();
    CustomHats_OnMapStart();
    LoadWeaponsConfig();
    PrecacheMenuResources();
    WeaponsGameplay_OnMapStart();
}

public void OnMapEnd()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        Weapons_ResetLoadoutRequests(client);
    }
    WeaponsMovement_OnMapEnd();
    WeaponsSound_Clear();
    WeaponsGameplay_OnMapEnd();
    WeaponsCustomAttributes_OnMapEnd();
}

public void OnClientPutInServer(int client)
{
    WeaponsMovement_OnClientPutInServer(client);
    WeaponsSound_ResetClient(client, true);
    WeaponsModels_OnClientPutInServer(client);
    WeaponsGameplay_OnClientPutInServer(client);
    CustomHats_OnClientPutInServer(client);
    WeaponsHatVisibility_OnClientPutInServer(client);
}

public void OnClientPostAdminCheck(int client)
{
    WeaponsCommands_QueryHtmlMotdPreference(client);
}

public void OnClientDisconnect(int client)
{
    WeaponsCommands_ResetClient(client);
    Weapons_ResetLoadoutRequests(client);
    CustomHats_OnClientDisconnect(client);
    WeaponsHatVisibility_OnClientDisconnect(client);
    WeaponsMovement_OnClientDisconnect(client);
    WeaponsWhitelist_OnClientDisconnect(client);
    WeaponsSound_ResetClient(client, true);
    WeaponsModels_OnClientDisconnect(client);
    WeaponsGameplay_OnClientDisconnect(client);
}

void Weapons_OnWeaponSwitchPost(int client, int weapon)
{
    Plasma_OnWeaponSwitchPost(client);
    WeaponsMovement_OnWeaponSwitchPost(client, weapon);
    WeaponsSound_OnWeaponSwitchPost(client, weapon);
    WeaponsModels_OnWeaponSwitchPost(client, weapon);
}

public void OnEntityCreated(int entity, const char[] className)
{
    WeaponsCustomAttributes_OnEntityCreated(entity);
    WeaponsSound_OnEntityCreated(entity, className);
    WeaponsModels_OnEntityCreated(entity, className);
    WeaponsGameplay_OnEntityCreated(entity, className);
    WeaponsHatVisibility_OnEntityCreated(entity, className);
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
    WeaponsModels_OnConditionRemoved(client, condition);
    WeaponsGameplay_OnConditionRemoved(client, condition);
}
