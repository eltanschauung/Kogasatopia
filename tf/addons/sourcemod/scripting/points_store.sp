#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>
#include <multicolors>
#undef REQUIRE_PLUGIN
#include <dgm_api>
#include <filters_api>
#include <saysounds>
#include <weapons>
#include <whaletracker_api>
#define REQUIRE_PLUGIN
#include <plugin_statistics>
#include "include/client_validation.inc"
#include "include/chat_colors.inc"
#include "include/database.inc"
#include "include/steam_identity.inc"
#include "include/tf2_classes.inc"

// Request ownership, indexed catalogues and receipt handling live in the modules below.
#define BP_TRANS_DB_CONFIG_DEFAULT "default"
#define BP_TRANS_TABLE "bonuspoints_transactions"
#define BP_BALANCE_TABLE "points_store_balances"
#define BP_ECONOMY_TABLE "points_store_economy"
#define BP_IDEMPOTENT_AWARDS_TABLE "points_store_idempotent_awards"
#define BP_PER_MAP_AWARDS_TABLE "points_store_per_map_awards"
#define BP_IDEMPOTENT_KEY_MAX 128
#define BP_PER_MAP_SCOPE_MAX 128
#define BP_PER_MAP_ACTION_NONE 0
#define BP_PER_MAP_ACTION_RESTORE 1
#define BP_PER_MAP_ACTION_RESET 2
#define BP_ECONOMY_WELFARE_POOL_KEY "welfare_pool"
#define BP_ECONOMY_CUMULATIVE_SPENT_KEY "cumulative_spent"
#define BP_ECONOMY_KEY_MAX 64
#define BP_TRANS_ITEM_KEY_MAX 64
#define BP_TRANS_ITEM_NAME_MAX 128
#define BP_TRANS_ITEM_DESCRIPTION_MAX 256
#define BP_SOUND_COMMAND "xp_gain"
#define BP_LEVEL_UP_SOUND_COMMAND "xp_levelup"
#define BP_BALANCE_MILESTONE 500
#define BP_EVENT_LOG_LINE_MAX 1024
#define BP_CURRENCY_SHORT_MAX 32
#define BP_CURRENCY_LONG_MAX 64
#define BP_CURRENCY_COLOR_MAX 32
#define BP_WELFARE_SOUND_COMMAND "monkey"
#define BP_WELFARE_MIN 4
#define BP_WELFARE_MAX 16
#define BP_PURCHASE_PERMANENT 0
#define BP_PURCHASE_UNLIMITED_USES -1
#define BP_LEADERBOARD_PAGE_SIZE 10
#define BP_BALANCE_SEARCH_MAX 20
#define BP_BALANCE_SEARCH_NAME_MAX 128

ArrayList g_ItemKeys = null;
ArrayList g_ItemNames = null;
ArrayList g_ItemDescriptions = null;
ArrayList g_ItemColors = null;
ArrayList g_ItemPrices = null;
ArrayList g_ItemDurations = null;
ArrayList g_ItemUses = null;
StringMap g_ClientPurchases[MAXPLAYERS + 1];
StringMap g_ClientPurchaseExpiresAt[MAXPLAYERS + 1];
StringMap g_ClientPurchaseUsesRemaining[MAXPLAYERS + 1];
bool g_ClientPurchasesLoaded[MAXPLAYERS + 1];
int g_ClientBonusPoints[MAXPLAYERS + 1];
bool g_ClientBonusPointsLoaded[MAXPLAYERS + 1];
bool g_ClientBonusPointsPending[MAXPLAYERS + 1];
char g_ClientShopDetailItem[MAXPLAYERS + 1][BP_TRANS_ITEM_KEY_MAX];
Database g_Database = null;
ConVar g_CvarDatabase = null;
ConVar g_CvarEventLogging = null;
ConVar g_CvarLogRandomMisses = null;
ConVar g_CvarCurrencyShort = null;
ConVar g_CvarCurrencyLong = null;
ConVar g_CvarCurrencyColor = null;
ConVar g_CvarSendCooldown = null;
ConVar g_CvarEnableWelfare = null;
ConVar g_CvarWelfareMinPlayers = null;
ConVar g_CvarBountyMinPlayers = null;
ConVar g_CvarBountyMinAmount = null;
ConVar g_CvarBountyMaxAmount = null;
ConVar g_CvarBountyTimeLimitMinutes = null;
ConVar g_CvarAutoBountyMinDeaths = null;
bool g_DatabaseReady = false;
bool g_IsMySql = false;
bool g_IdempotentAwardsReady = false;
Handle g_hDatabaseReconnectTimer = null;
GlobalForward g_IdempotentAwardForward = null;
bool g_EconomyStateLoaded = false;
int g_WelfarePoolBalance = 0;
int g_CumulativeSpentBalance = 0;
char g_CurrencyShortLabel[BP_CURRENCY_SHORT_MAX];
char g_CurrencyLongLabel[BP_CURRENCY_LONG_MAX];
char g_CurrencyColorTag[BP_CURRENCY_COLOR_MAX + 2];
char g_CurrencyPrefix[96];
float g_NextSendAllowedAt[MAXPLAYERS + 1];
int g_BalanceSearchGeneration[MAXPLAYERS + 1];
StringMap g_PerMapAwardCounts = null;
bool g_PerMapAwardsReady = false;
bool g_PerMapSchemaReady = false;
bool g_PerMapLateLoad = false;
bool g_PerMapIgnoreInitialMapStart = false;
int g_PerMapStateGeneration = 0;
int g_PerMapStateAction = 0;
int g_PerMapServerPort = 0;
char g_PerMapName[BP_PER_MAP_SCOPE_MAX];
#include "points_store/lotteries.inc"
#include "points_store/bounties.inc"
#include "points_store/rewards.inc"
#include "points_store/bonus_labels.inc"
#include "points_store/dailies.inc"
#include "points_store/memoman_event.inc"
#include "points_store/gameplay_rewards.inc"

public Plugin myinfo =
{
    name = "points_store",
    author = "Kogasa, Hombre",
    description = "Currency purchase receipts, shop UI, and ownership API.",
    version = "1.0.0",
    url = "https://kogasa.tf"
};

public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int err_max)
{
    g_PerMapLateLoad = late;
    MarkNativeAsOptional("Filters_GetChatName");
    MarkNativeAsOptional("Filters_GetSteamIdColorTag");
    MarkNativeAsOptional("SaySounds_PlayCommand");
    MarkNativeAsOptional("DGM_GetGameModeKey");
    MarkNativeAsOptional("DGM_NormalizeMapName");
    MarkNativeAsOptional("DGM_CurrentNormalizedMap");
    MarkNativeAsOptional("WhaleTracker_GetRankedPlaytimeHours");
    MarkNativeAsOptional("WhaleTracker_GetRankedPlaytimeSeconds");
    RegPluginLibrary("points_store");
    CreateNative("PointsStore_AreBonusPointsLoaded", Native_PointsStore_AreBonusPointsLoaded);
    CreateNative("PointsStore_GetBonusPoints", Native_PointsStore_GetBonusPoints);
    CreateNative("PointsStore_ApplyBonusPoints", Native_PointsStore_ApplyBonusPoints);
    CreateNative("PointsStore_ApplyBonusPointsSteamId", Native_PointsStore_ApplyBonusPointsSteamId);
    CreateNative("PointsStore_GetRewardAmount", Native_PointsStore_GetRewardAmount);
    CreateNative("PointsStore_GetRewardPerMapLimit", Native_PointsStore_GetRewardPerMapLimit);
    CreateNative("PointsStore_GetRewardLongName", Native_PointsStore_GetRewardLongName);
    CreateNative("PointsStore_GetRewardShortDescription", Native_PointsStore_GetRewardShortDescription);
    CreateNative("PointsStore_GetRewardLongDescription", Native_PointsStore_GetRewardLongDescription);
    CreateNative("PointsStore_ApplyBonusPointsSteamIdOnce", Native_PointsStore_ApplyBonusPointsSteamIdOnce);
    CreateNative("PointsStore_RefundBonusPoints", Native_PointsStore_RefundBonusPoints);
    CreateNative("PointsStore_RefundBonusPointsSteamId", Native_PointsStore_RefundBonusPointsSteamId);
    CreateNative("PointsStore_SpendBonusPoints", Native_PointsStore_SpendBonusPoints);
    CreateNative("PointsStore_StealBonusPoints", Native_PointsStore_StealBonusPoints);
    CreateNative("PointsStore_AwardMemomanEvent", Native_PointsStore_AwardMemomanEvent);
    CreateNative("PointsStore_HasPurchase", Native_PointsStore_HasPurchase);
    CreateNative("PointsStore_GetPurchasePrice", Native_PointsStore_GetPurchasePrice);
    CreateNative("PointsStore_GetPurchaseExpiresAt", Native_PointsStore_GetPurchaseExpiresAt);
    CreateNative("PointsStore_GetPurchaseUsesRemaining", Native_PointsStore_GetPurchaseUsesRemaining);
    CreateNative("PointsStore_ConsumePurchaseUse", Native_PointsStore_ConsumePurchaseUse);
    g_IdempotentAwardForward = new GlobalForward("PointsStore_OnApplyBonusPointsSteamIdOnce",
        ET_Ignore, Param_String, Param_Cell, Param_Cell);
    return APLRes_Success;
}

#include "points_store/lifecycle.sp"
#include "points_store/database.sp"
#include "points_store/command_listeners.sp"
#include "points_store/catalog.sp"
#include "points_store/client_state.sp"
#include "points_store/currency.sp"
#include "points_store/event_logging.sp"
#include "points_store/award_persistence.sp"
#include "points_store/awards.sp"
#include "points_store/leaderboard.sp"
#include "points_store/balance_commands.sp"
#include "points_store/transfers_and_welfare.sp"
#include "points_store/shop.sp"
#include "points_store/native_api.sp"
