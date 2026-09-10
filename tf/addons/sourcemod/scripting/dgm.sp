#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <sdktools_gamerules>
#include <dhooks>
#include <tf2>
#include <tf2_stocks>
#include <controlpoints>
#include <morecolors>
#include <plugin_statistics>
#undef REQUIRE_EXTENSIONS
#include <tf2_setuptime>
#include <tf2setupuber>
#define REQUIRE_EXTENSIONS

// Uses the repository's fork of controlpoints by powerlord / babasproke2.
// Session-owned timers are implemented in dgm/respawn_timers.sp.
#define PLUGIN_VERSION "4.3"
#include "include/dgm_api.inc"
#include "include/client_validation.inc"
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
int g_iRoundStartTimestamp = 0;
int g_iLastRoundDuration = 0;
int g_iLastCaptureTimestamp = 0;
int g_iCaptureIntervalCount = 0;
int g_iCaptureIntervalSeconds[DGM_MAX_CAPTURE_INTERVALS];
int g_iCaptureRoundElapsedSeconds[DGM_MAX_CAPTURE_INTERVALS];
int g_iCaptureTeam[DGM_MAX_CAPTURE_INTERVALS];
int g_iCapturePoint[DGM_MAX_CAPTURE_INTERVALS];
int g_iOriginalUpgradePerHit = 0;
DynamicDetour g_hConstructionMultiplierDetour = null;

public Plugin myinfo =
{
    name = "Gamemode Detector",
    author = "Hombre",
    description = "Handles gamemode settings and instant respawns",
    version = PLUGIN_VERSION,
    url = "https://kogasa.tf"
};

#include "dgm/population_and_objectives.sp"
#include "dgm/gamemodes.sp"
#include "dgm/native_api.sp"
#include "dgm/respawn_and_setup_state.sp"
#include "dgm/statistics.sp"
#include "dgm/setup_overrides.sp"
#include "dgm/configuration.sp"
#include "dgm/lifecycle.sp"
#include "dgm/commands.sp"
#include "dgm/respawn_timers.sp"
#include "dgm/round_events.sp"
