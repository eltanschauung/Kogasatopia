#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>
#include <textparse>
#include <morecolors>
#include <sdktools_sound>
#include <sdktools_stringtables>
#include <sdktools_functions>
#include <sdktools_gamerules>

#undef REQUIRE_PLUGIN
#include <tf_custom_attributes>
#define REQUIRE_PLUGIN

#undef REQUIRE_PLUGIN
#include <points_store_api>
#include <dgm_api>
#include <filters_api>
#define REQUIRE_PLUGIN
#include <plugin_statistics>
#include "include/chat_colors.inc"
#include "include/steam_identity.inc"
#include "include/strings.inc"

#define CONFIG_FILE "configs/saysounds.cfg"
#define MAX_COMMAND_NAME 64
#define MAX_GROUP_NAME 32
#define MAX_GROUP_PREF_VALUE 512
#define DEFAULT_GROUP "all"
#define API_ONLY_GROUPS_SECTION "apionlygroups"
#define PAID_SAYSOUND_GROUPS_SECTION "paidsaysoundgroups"
#define GROUP_ALIASES_SECTION "groupaliases"
#define ROUND_START_SIRENS_SECTION "roundstartsirenreplacements"
#define ROUND_WIN_REPLACEMENTS_SECTION "roundwinreplacements"
#define ROUND_LOSE_REPLACEMENTS_SECTION "roundlosereplacements"
#define ANNOUNCER_MISC_REPLACEMENTS_SECTION "replaceannouncermisc"
#define COUNTDOWN_REPLACEMENTS_SECTION "countdownreplacements"
#define UNLOCK_REPLACEMENTS_SECTION "unlockreplacements"
#define STOCK_ROUND_START_SIREN "ambient_mp3/siren.mp3"
#define STOCK_ROUND_WIN_SOUND "Game.YourTeamWon"
#define STOCK_ROUND_LOSE_SOUND "Game.YourTeamLost"
#define STOCK_OVERTIME_SOUND "Game.Overtime"
#define STOCK_CP_SUCCESS "Announcer.Success"
#define STOCK_CP_FAILURE "Announcer.Failure"
#define CLIENT_ANNOUNCER_REPLACEMENT_DELAY 0.05
#define MAX_TRACKED_CONTROL_POINTS 8
#define CONTROL_POINT_UNLOCK_EVENT_DEBOUNCE 0.50
#define CONTROL_POINT_ENABLED_WARNING_BIT (1 << 5)
#define CONTROL_POINT_COUNTDOWN_SUPPRESS_AT 7.0
#define COUNTDOWN_MONITOR_INTERVAL 0.01
#define LIVE_COUNTDOWN_SUPPRESS_AT 7.0
#define ROUND_TIMER_STATE_SETUP 0
#define ROUND_TIMER_STATE_NORMAL 1
#define ROUND_START_SIREN_CHANNEL (SNDCHAN_USER_BASE + 1)
#define ROUND_START_SIREN_REPLACEMENT_DELAY 0.05
#define ROUND_START_AUTO_COUNTDOWN_RESTORE_DELAY 0.50
#define ROUND_START_SIREN_DUPLICATE_GUARD 5.0
#define ROUND_RESULT_PAIR_WINDOW 5.0
#define SOUND_PREF_GROUP_ITEM_PREFIX "group:"
#define SAYSOUND_ON_KILL_ATTR "saysound on kill"
#define POINTS_STORE_HAS_PURCHASE_NATIVE "PointsStore_HasPurchase"
#define SAYSOUNDS_STATS_SAMPLE_RATE 3

public Plugin myinfo =
{
    name = "saysounds",
    author = "Hombre",
    description = "Chat-triggered say sounds with opt-out and volume features",
    version = "2.0.1",
    url = "https://kogasa.tf"
};

StringMap gSoundMap;
StringMap gSoundGroupMap;
StringMap gAPIOnlyGroups;
StringMap gForcedSoundGroups;
StringMap gPaidSaysoundGroups;
StringMap gGroupAliases;
ArrayList gCommandNames;
ArrayList gGroupNames;
ArrayList gRoundStartSirenReplacements;
ArrayList gRoundStartSirenGroups;
ArrayList gReadyRoundStartSirenReplacements;
ArrayList gReadyRoundStartSirenGroups;
ArrayList gRoundWinReplacements;
ArrayList gRoundWinGroups;
ArrayList gReadyRoundWinReplacements;
ArrayList gReadyRoundWinGroups;
ArrayList gRoundLoseReplacements;
ArrayList gRoundLoseGroups;
ArrayList gReadyRoundLoseReplacements;
ArrayList gReadyRoundLoseGroups;
ArrayList gAnnouncerMiscReplacements;
ArrayList gAnnouncerMiscGroups;
ArrayList gReadyAnnouncerMiscReplacements;
ArrayList gReadyAnnouncerMiscGroups;
ArrayList gCountdownReplacements;
ArrayList gCountdownGroups;
ArrayList gReadyCountdownReplacements;
ArrayList gReadyCountdownGroups;
ArrayList gUnlockReplacements;
ArrayList gUnlockGroups;
ArrayList gReadyUnlockReplacements;
ArrayList gReadyUnlockGroups;
bool gConfigLoaded = false;
bool gConfigInAPIOnlyGroups = false;
bool gConfigInPaidSaysoundGroups = false;
bool gConfigInGroupAliases = false;
bool gConfigInRoundStartSirens = false;
bool gConfigInRoundWinReplacements = false;
bool gConfigInRoundLoseReplacements = false;
bool gConfigInAnnouncerMiscReplacements = false;
bool gConfigInCountdownReplacements = false;
bool gConfigInUnlockReplacements = false;
int gConfigSectionDepth = 0;
int gConfigAPIOnlyGroupsDepth = -1;
int gConfigPaidSaysoundGroupsDepth = -1;
int gConfigGroupAliasesDepth = -1;
int gConfigRoundStartSirensDepth = -1;
int gConfigRoundWinReplacementsDepth = -1;
int gConfigRoundLoseReplacementsDepth = -1;
int gConfigAnnouncerMiscReplacementsDepth = -1;
int gConfigCountdownReplacementsDepth = -1;
int gConfigUnlockReplacementsDepth = -1;
float g_fClientVolume[MAXPLAYERS + 1];
float g_fNextAllowedSound[MAXPLAYERS + 1];
char g_szDeathSound[MAXPLAYERS + 1][MAX_COMMAND_NAME * 4];
char g_szKillSound[MAXPLAYERS + 1][MAX_COMMAND_NAME * 4];
StringMap g_hClientDisabledGroups[MAXPLAYERS + 1];
Handle g_hVolumeCookie = INVALID_HANDLE;
Handle g_hDeathCookie = INVALID_HANDLE;
Handle g_hKillCookie = INVALID_HANDLE;
Handle g_hDisabledGroupsCookie = INVALID_HANDLE;
Handle g_hCountdownMonitorTimer = INVALID_HANDLE;
Handle g_hRoundStartSirenTimer = INVALID_HANDLE;
Handle g_hRoundStartAutoCountdownRestoreTimer = INVALID_HANDLE;
bool gNormalSoundHookAdded = false;
bool gAmbientSoundHookAdded = false;
ConVar g_hForce;
ConVar g_hForcedGroups;
ConVar g_hDefaultDeathSound;
ConVar g_hDefaultVolume;
int g_iSaySoundStatsCounter = 0;
int g_iTrackedSetupCountdownTimerRef = INVALID_ENT_REFERENCE;
int g_iSetupCountdownArmedMask = 0;
float g_fLastSetupCountdownRemaining = -1.0;
int g_iTrackedLiveCountdownTimerRef = INVALID_ENT_REFERENCE;
int g_iLiveCountdownArmedMask = 0;
float g_fLastLiveCountdownRemaining = -1.0;
bool g_bTrackedLiveAutoCountdownOriginal = false;
bool g_bTrackedLiveAutoCountdownSuppressed = false;
float g_fTrackedControlPointUnlockTime[MAX_TRACKED_CONTROL_POINTS];
int g_iControlPointUnlockArmedMask[MAX_TRACKED_CONTROL_POINTS];
float g_fLastControlPointUnlockEvent[MAX_TRACKED_CONTROL_POINTS];
bool g_bControlPointEnabledReplacementHandled[MAX_TRACKED_CONTROL_POINTS];
bool g_bControlPointCountdownSuppressed[MAX_TRACKED_CONTROL_POINTS];
int g_iTrackedSetupSirenTimerRef = INVALID_ENT_REFERENCE;
int g_iTrackedSetupSirenState = -1;
bool g_bTrackedSetupAutoCountdownOriginal = false;
bool g_bTrackedSetupAutoCountdownSuppressed = false;
int g_iPendingSetupSirenTimerRef = INVALID_ENT_REFERENCE;
float g_fLastRoundStartSirenTime = -9999.0;
int g_iNextRoundStartSirenIndex = -1;
int g_iRoundStartSirenTransitionSerial = 0;
int g_iPendingRoundStartSirenSerial = 0;
int g_iPendingRoundStartSirenIndex = -1;
bool g_bEmittingRoundStartSiren = false;
int g_iEmittingRoundStartSirenSerial = 0;
int g_iEmittingRoundStartSirenIndex = -1;
int g_iEmittingRoundStartSirenClient = 0;
int g_iNextRoundResultReplacementIndex = -1;
int g_iActiveRoundResultReplacementIndex = -1;
int g_iRoundResultSelectionSerial = 0;
float g_fRoundResultSelectionTime = -9999.0;
int g_iNextUnlockReplacementIndex = -1;

const float MIN_VOLUME = 0.0;
const float MAX_VOLUME = 1.0;
const float DEFAULT_COOLDOWN = 5.0;
const float ADMIN_COOLDOWN = 1.0;
const int MAX_SOUND_OPTIONS = 16;

#include "saysounds/lifecycle.sp"
#include "saysounds/announcer_replacements.sp"
#include "saysounds/countdown_replacements.sp"
#include "saysounds/chat_commands.sp"
#include "saysounds/config.sp"
#include "saysounds/group_preferences.sp"
#include "saysounds/statistics.sp"
#include "saysounds/event_preferences.sp"
#include "saysounds/api_and_commands.sp"
#include "saysounds/playback.sp"
#include "saysounds/event_sounds.sp"
