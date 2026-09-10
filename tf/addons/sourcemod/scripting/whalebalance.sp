#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>
#include <sdktools>
#include <tf2_stocks>
#include <morecolors>
#include <nativevotes>
#undef REQUIRE_PLUGIN
#include <dgm_api>
#include <clans_api>
#include <filters_api>
#include <points_store_api>
#include <saysounds>
#include <whaletracker_api>
#define REQUIRE_PLUGIN
#include <plugin_statistics>
#include "include/database.inc"
#include "include/duel_detection.inc"
#include "include/steam_identity.inc"
#include "include/buildings.inc"

native int FilterAlerts_MarkAutobalance(int client);
native int FilterAlerts_SuppressTeamAlertWindow(float seconds);

// One generation-owned respawn chain per client: whalebalance/runtime.sp.
#define CHECK_INTERVAL 3.0
#define MAP_START_DELAY 30.0
#define TEAM_RED 2
#define TEAM_BLUE 3
#define TEAM_GREEN 4
#define TEAM_YELLOW 5
#define GAME_TEAM_COUNT 4
#define MEDIC_AUTOBALANCE_UBER_FLOOR 0.05
#define POINTS_STORE_AB_IMMUNITY_ITEM "abImmunity24h"
#define TEAM_MOVE_SAYSOUND "tp-enderman"
#define TEAM_SWAP_COST 25
#define TEAM_SWAP_REWARD_ID "team_swap_receiver"
#define TEAM_SWAP_TIMEOUT 60.0
#define TEAM_BALANCE_SETTLE_TIME 3.0
#define TEAM_BALANCE_OPERATION_LEASE 5.0
#define TEAM_BALANCE_MOVE_PROTECTION 15.0
#define TEAM_BALANCE_SCRAMBLE_COOLDOWN 120.0
#define TEAM_BALANCE_RESPAWN_RETRY_DELAY 0.50
#define TEAM_BALANCE_RESPAWN_RETRY_COUNT 8
#define POINTS_STORE_SCRAMBLE_IMMUNITY_ITEM "scramImmunity24h"

enum TeamBalanceState
{
    TeamBalance_Idle = 0,
    TeamBalance_Autobalance,
    TeamBalance_ManualSwap,
    TeamBalance_ScrambleVote,
    TeamBalance_ScramblePending,
    TeamBalance_ScrambleMoving,
    TeamBalance_Settling
};

StringMap g_hMapImmunity = null;
StringMap g_hPersistentImmunity = null;
StringMap g_hVolunteers = null;
StringMap g_hScrambleImmunity = null;
Database g_hImmunityDb = null;
Handle g_hImmunityDbReconnectTimer = null;
bool g_bImmunityDbReady = false;
bool g_bVolunteerDbReady = false;
int g_iPersistentVolunteerCount = 0;
ConVar g_hLogEnabled;
ConVar g_hDiffThreshold;
ConVar g_hActionDelay;
ConVar g_hMaxUnbalanceTime;
ConVar g_hForceThresholdDelta;
ConVar g_hSimpleSelection;
ConVar g_hIgnoreWinning;
ConVar g_hDatabaseConfig;
ConVar g_hMpAutoteamBalance;
ConVar g_hMpTeamsUnbalanceLimit;
int g_iSavedAutoteamBalance;
int g_iSavedUnbalanceLimit;
Handle g_hAutoBalanceTimer = INVALID_HANDLE;
float g_fImbalanceDetectedAt = 0.0;
int g_iSwapRequestSenderUserId[MAXPLAYERS + 1];
int g_iSwapRequestSenderTeam[MAXPLAYERS + 1];
int g_iSwapRequestTargetTeam[MAXPLAYERS + 1];
Handle g_hSwapRequestTimer[MAXPLAYERS + 1];
bool g_bSwapRequestFinalizing[MAXPLAYERS + 1];
TeamBalanceState g_eTeamBalanceState = TeamBalance_Idle;
float g_fTeamBalanceStateUntil = 0.0;
float g_fScrambleCooldownUntil = 0.0;
int g_iScramblesSinceImmunityClear = 0;
int g_iBalanceRespawnAttempts[MAXPLAYERS + 1];
int g_iBalanceRespawnExpectedTeam[MAXPLAYERS + 1];
float g_fBalanceMovedUntil[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name = "whalebalance",
    author = "Hombre, AW 'Swixel' Stanley",
    description = "Unified autobalance, team-swap, scramble-vote, and ranking controller.",
    version = "3.0",
    url = "https://kogasa.tf"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    RegPluginLibrary("autobalance_4teams");
    RegPluginLibrary("whalebalance");
    CreateNative("Autobalance_HasPendingTeamSwap", Native_HasPendingTeamSwap);
    CreateNative("TeamBalance_IsBusy", Native_TeamBalanceIsBusy);
    CreateNative("TeamBalance_IsScrambleCooldownActive", Native_TeamBalanceIsScrambleCooldownActive);
    CreateNative("TeamBalance_BeginScrambleVote", Native_TeamBalanceBeginScrambleVote);
    CreateNative("TeamBalance_EndScrambleVote", Native_TeamBalanceEndScrambleVote);
    CreateNative("TeamBalance_BeginScramble", Native_TeamBalanceBeginScramble);
    CreateNative("TeamBalance_CancelScramble", Native_TeamBalanceCancelScramble);
    CreateNative("TeamBalance_FinishScramble", Native_TeamBalanceFinishScramble);
    CreateNative("TeamBalance_IsScrambleCandidate", Native_TeamBalanceIsScrambleCandidate);
    CreateNative("TeamBalance_HasScramblePurchaseImmunity", Native_TeamBalanceHasScramblePurchaseImmunity);
    CreateNative("TeamBalance_ConsumeScramblePurchaseImmunity", Native_TeamBalanceConsumeScramblePurchaseImmunity);
    CreateNative("TeamBalance_MoveScramblePair", Native_TeamBalanceMoveScramblePair);
    CreateNative("TeamBalance_QueueRespawn", Native_TeamBalanceQueueRespawn);
    MarkNativeAsOptional("FilterAlerts_MarkAutobalance");
    MarkNativeAsOptional("FilterAlerts_SuppressTeamAlertWindow");
    MarkNativeAsOptional("Clans_GetSameTeamClanMemberCount");
    MarkNativeAsOptional("PointsStore_ApplyBonusPoints");
    MarkNativeAsOptional("PointsStore_GetRewardAmount");
    MarkNativeAsOptional("PointsStore_RefundBonusPoints");
    MarkNativeAsOptional("PointsStore_AreBonusPointsLoaded");
    MarkNativeAsOptional("PointsStore_GetBonusPoints");
    MarkNativeAsOptional("PointsStore_SpendBonusPoints");
    MarkNativeAsOptional("PointsStore_HasPurchase");
    MarkNativeAsOptional("PointsStore_ConsumePurchaseUse");
    MarkNativeAsOptional("DGM_IsSmallFormatGamemode");
    MarkNativeAsOptional("DGM_RealTeamPlayerCount");
    MarkNativeAsOptional("DGM_GetObjectiveLeaderTeam");
    MarkNativeAsOptional("DGM_GetGameModeKey");
    MarkNativeAsOptional("DGM_NormalizeMapName");
    MarkNativeAsOptional("DGM_CurrentNormalizedMap");
    MarkNativeAsOptional("DGM_GetLastRoundDurationSeconds");
    MarkNativeAsOptional("DGM_GetRecentControlPointCaptureIntervalSeconds");
    MarkNativeAsOptional("DGM_IsSetupActive");
    MarkNativeAsOptional("SaySounds_PlayCommand");
    MarkNativeAsOptional("Filters_GetChatName");
    MarkNativeAsOptional("WhaleTracker_AreStatsLoaded");
    MarkNativeAsOptional("WhaleTracker_GetWhalePoints");
    return APLRes_Success;
}

#include "whalebalance/native_api.sp"
#include "whalebalance/runtime.sp"
#include "whalebalance/lifecycle.sp"
#include "whalebalance/team_swaps.sp"
#include "whalebalance/autobalance.sp"
#include "whalebalance/autobalance_selection.sp"
#include "whalebalance/persistence.sp"
#include "whalebalance/common.sp"
#include "whalebalance/scramble_runtime.sp"
#include "whalebalance/scramble_votes.sp"
#include "whalebalance/scramble_scoring.sp"
#include "whalebalance/scramble_execution.sp"
