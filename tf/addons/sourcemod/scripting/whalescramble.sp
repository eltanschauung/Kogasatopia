#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>
#include <sdktools>
#include <sdkhooks>
#include <sdktools_gamerules>
#include <dhooks>
#include <tf2>
#include <tf2_stocks>
#include <controlpoints>
#include <morecolors>
#include <nativevotes>
#include <plugin_statistics>

#undef REQUIRE_EXTENSIONS
#include <tf2_setuptime>
#include <tf2setupuber>
#define REQUIRE_EXTENSIONS

#undef REQUIRE_PLUGIN
#include <clans_api>
#include <filters_api>
#include <points_store_api>
#include <saysounds>
#include <whaletracker_api>
#define REQUIRE_PLUGIN

#include "include/database.inc"
#include "include/duel_detection.inc"
#include "include/steam_identity.inc"
#include "include/buildings.inc"
#include "include/client_validation.inc"
#include "include/tf2_classes.inc"

#define DGM_IMPLEMENTATION
#include "include/dgm_api.inc"
#undef DGM_IMPLEMENTATION

native int FilterAlerts_MarkAutobalance(int client);
native int FilterAlerts_SuppressTeamAlertWindow(float seconds);
native bool Announcers_IsGroupEnabled(int client, const char[] groupName);

#define PLUGIN_VERSION "5.0"

// DGM state and policy.
#define DGM_MAX_CONTROL_POINTS 8
#define DGM_MAX_CAPTURE_INTERVALS 64
#define DGM_SETUP_START_CHECK_INTERVAL 0.25
#define DGM_SETUP_START_CHECK_MAX 80
#define DGM_SETUP_FALSE_CONFIRM_MAX 3
#define DGM_NO_ENGINEER_SETUP_CHECK_DELAY 5.0
#define DGM_RT_STATE_SETUP 0
#define DGM_RESPAWN_DISABLED_TIME 30.0
#define DGM_RESPAWN_LOW_POP_RESTORE_TIME 5.0
#define DGM_RESPAWN_HIGH_POP_RESTORE_TIME 10.0
#define DGM_RESPAWN_HIGH_POP_THRESHOLD 15
#define DGM_RESPAWN_REMINDER_INTERVAL 20.0
#define DGM_SETUP_TEAM_RATIO_PERCENT 66

ConVar g_cvSetSetupTime;
ConVar g_cvAsymCapRespawn;
ConVar g_cvThreshold;
ConVar g_cvRedTime;
ConVar g_cvBluTime;
ConVar g_cvAutoAddTime;
ConVar g_cvSetupUberMultiplier;
ConVar g_cvSetupConstructionMultiplier;
ConVar g_cvUpgradeMetalPerHit;
ConVar g_cvTfObjUpgradePerHit;
ConVar g_cvNoEngineerSetupReduction;
ConVar g_cvTimeOverride;
ConVar g_cvRespawnTime;
ConVar g_cvPopulationConfigs;
ConVar g_cvPopulationRespawns;
ConVar g_cvLowPopThreshold;
ConVar g_cvHeavyInstantRespawnImmunity;
bool g_bSymmetrical;
bool g_bRoundStartedOnce;
bool g_bRespawnAdminTouchedThisMap;
bool g_bSetupTeamRatioForwardFired;
GlobalForward g_hSetupTeamRatioReadyForward;
ConVar g_cHostname;
int g_PointCaptures;
bool g_InternalOverride;
ConVar g_cvGameMode;
Handle g_cvMpDisableRespawnTimes = INVALID_HANDLE;
Handle g_hSetupStateTimer = INVALID_HANDLE;
Handle g_hSetupStartTimer = INVALID_HANDLE;
Handle g_hNoEngineerSetupReductionTimer = INVALID_HANDLE;
Handle g_hRespawnTimers[MAXPLAYERS + 1];
Handle g_hRespawnReminderTimers[MAXPLAYERS + 1];
bool g_bSetupActive = false;
bool g_bSetupConstructionMultiplierActive = false;
bool g_bSetupUpgradeMetalActive = false;
bool g_bGameRulesReady = false;
bool g_bNoEngineerSetupReduced = false;
bool g_bSetupUberUnavailableLogged = false;
int g_iSetupStartChecks = 0;
int g_iSetupFalseChecks = 0;
int g_iDgmRoundStartTimestamp = 0;
int g_iLastRoundDuration = 0;
int g_iLastCaptureTimestamp = 0;
int g_iCaptureIntervalCount = 0;
int g_iCaptureIntervalSeconds[DGM_MAX_CAPTURE_INTERVALS];
int g_iCaptureRoundElapsedSeconds[DGM_MAX_CAPTURE_INTERVALS];
int g_iCaptureTeam[DGM_MAX_CAPTURE_INTERVALS];
int g_iCapturePoint[DGM_MAX_CAPTURE_INTERVALS];
int g_iOriginalUpgradePerHit = 0;
DynamicDetour g_hConstructionMultiplierDetour = null;

// Team balance and WhaleScramble state and policy.
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
#define TEAM_MOVE_DRAGONBALL_SAYSOUND "instant_transmission"
#define TEAM_MOVE_DRAGONBALL_GROUP "dragonball"
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
#define SCRAMBLE_KOTH_ADD_TIME 180
#define TEAM_BALANCE_MIN_ROUND_TIME 30
#define VOLUNTEER_ELIGIBILITY_SECONDS (6 * 60 * 60)
#define VOLUNTEER_LEGACY_TIMESTAMP 1789808400

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
int g_iBalanceMovedOperationGeneration[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name = "WhaleScramble",
    author = "Hombre, AW 'Swixel' Stanley, Tsunami",
    description = "Unified gamemode, respawn, class-limit, autobalance, team-swap, and scramble controller.",
    version = PLUGIN_VERSION,
    url = "https://kogasa.tf"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
    DGM_RegisterPluginApi();
    WhaleBalance_RegisterPluginApi();
    ClassLimits_RegisterOptionalNatives();
    return APLRes_Success;
}

public void OnPluginStart()
{
    DGM_OnPluginStart();
    WhaleBalance_OnPluginStart();
    ClassLimits_OnPluginStart();
}

public void OnPluginEnd()
{
    ClassLimits_OnPluginEnd();
    WhaleBalance_OnPluginEnd();
    DGM_OnPluginEnd();
}

public void OnMapStart()
{
    DGM_OnMapStart();
    WhaleBalance_OnMapStart();
    ClassLimits_OnMapStart();
}

public void OnMapEnd()
{
    WhaleBalance_OnMapEnd();
    DGM_OnMapEnd();
}

public void OnConfigsExecuted()
{
    DGM_OnConfigsExecuted();
    WhaleBalance_OnConfigsExecuted();
    ClassLimits_OnConfigsExecuted();
}

public void OnAllPluginsLoaded()
{
    WhaleBalance_OnAllPluginsLoaded();
}

public void OnLibraryAdded(const char[] name)
{
    WhaleBalance_OnLibraryAdded(name);
}

public void OnLibraryRemoved(const char[] name)
{
    WhaleBalance_OnLibraryRemoved(name);
}

public void OnClientPutInServer(int client)
{
    DGM_OnClientPutInServer(client);
    WhaleBalance_OnClientPutInServer(client);
    ClassLimits_OnClientPutInServer(client);
}

public void OnClientDisconnect(int client)
{
    ClassLimits_OnClientDisconnect(client);
    WhaleBalance_OnClientDisconnect(client);
    DGM_OnClientDisconnect(client);
}

#include "dgm/population_and_objectives.sp"
#include "dgm/gamemodes.sp"
#include "dgm/internal_api.sp"
#include "dgm/native_api.sp"
#include "dgm/respawn_and_setup_state.sp"
#include "dgm/statistics.sp"
#include "dgm/setup_overrides.sp"
#include "dgm/configuration.sp"
#include "dgm/lifecycle.sp"
#include "dgm/commands.sp"
#include "dgm/respawn_timers.sp"
#include "dgm/round_events.sp"

#include "classlimits/module.sp"

#include "whalebalance/native_api.sp"
#include "whalebalance/plugin_api.sp"
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
