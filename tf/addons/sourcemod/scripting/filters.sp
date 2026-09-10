#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>
#include <basecomm>
#include <sdktools>
#include <sdktools_functions>
#include <sdktools_voice>
#include <morecolors>

#undef REQUIRE_PLUGIN
#include <adminsdb_api>
#include <hugs_api>
#include <points_store_api>
#include <tags_api>
#include <whaletracker_api>
#define REQUIRE_PLUGIN

#include "include/database.inc"
#include "include/steam_identity.inc"

#define MAX_FILTERS 128
#define MAX_BLACKLIST 128
#define MAX_WORD_LENGTH 64
#define MAX_FILTER_REPLACEMENT_LENGTH 192
#define MAX_FORCED_STATUS 128
#define MAX_COMMANDS 64
#define FILTERS_OUTBOX_CLEANUP_INTERVAL 120
#define FILTERS_OUTBOX_RETENTION_SECONDS 3600
#define FILTERS_CHAT_RETENTION_SECONDS 86400
#define FILTERS_OUTBOX_POLL_INTERVAL 2.0
#define FILTERS_MUTE_CHECK_INTERVAL 1.0
#define FILTERS_CONNECT_QUEUE_DELAY 3.0
#define FILTERS_DEFAULT_DB_CONFIG "default"
#define FILTERS_DEFAULT_HOST_IP "0.0.0.0"
#define FILTERS_PUBLIC_HOST_IP "173.255.237.230"
#define FILTERS_ACCESS_DENIED "{default}[Filters] You do not have access to this command."
#define REDLIST_RAPES_THRESHOLD 1
#define PRENAME_MAX_PATTERN 64
#define PRENAME_MAX_RENAME 64
#define NAME_COLOR_AMERICA "america"
#define NAME_PATTERN_MAP "map"
#define NAME_PATTERN_TRANS "trans"
#define NAME_PATTERN_RAINBOW "rainbow"
#define NAME_PATTERN_GRADIENT_PREFIX "gradient:"
#define NAME_PATTERN_TRIPLE_GRADIENT_PREFIX "gradient3:"
#define NAME_PATTERN_MAX 96
#define NAME_GRADIENT_MAX_STEPS 8
#define NAME_GRADIENT_DEFAULT_COMPLETION 50
#define NAME_GRADIENT_MAX_COMPLETION 90
#define AMERICA_NAME_ACCESS_ITEM "america_flag_name"
#define MAP_NAME_ACCESS_ITEM "map_flag_name"
#define TRANS_NAME_ACCESS_ITEM "trans_flag_name"
#define RAINBOW_NAME_ACCESS_ITEM "rainbow_name_access"
#define GRADIENT_NAME_ACCESS_ITEM "gradient_name_access"
#define TRIPLE_GRADIENT_ACCESS_ITEM "triple_gradient_upgrade"
#define CHAT_PREFIX_MAXLEN 128
#define FILTERS_CROSS_SERVER_TAG_MAX 64
#define FILTERS_CHAT_DATABASE_IMMUNE_STEAMID64 "76561198081148684"
#define PARSEE_STEAMID64 "76561199812613650"
#define PARSEE_STEAMID2 "STEAM_0:0:926173961"
#define PARSEE_FALLBACK_NAME "Mizuhashi Parsee"
#define PARSEE_WEB_SUBNET_STAMP "70.175.0.0/16"
#define MEMOMAN_STEAMID64 "76561199873606169"
#define MEMOMAN_STEAMID2 "STEAM_0:1:956670220"
#define MEMOMAN_FALLBACK_NAME "Memoman"
#define PARSEE_COOLDOWN_REDUCTION_ITEM "parsee_cooldown_reduction"
#define ARCHIVED_MESSAGE_COOLDOWN_SECONDS 30
#define ARCHIVED_MESSAGE_WHITELIST_COOLDOWN_SECONDS 15
#define PARSEE_PURCHASE_COOLDOWN_SECONDS 5
#define ARCHIVED_MESSAGE_TEAM_DURATION_SECONDS 180
#define TIDYCHAT_VERSION "0.5"

enum ArchivedSpeaker
{
    ArchivedSpeaker_Parsee = 0,
    ArchivedSpeaker_Memoman,
    ArchivedSpeaker_Count
};

enum struct PlayerState
{
    bool isWhitelisted;
    bool isFilterWhitelisted;
    bool isBlacklisted;
    bool isredlisted;
    int rapesGiven;
    int whaleKills;
    bool hugsStatsLoaded;
    bool whaleStatsLoaded;
    bool cookiesProcessed;
}

PlayerState g_PlayerState[MAXPLAYERS + 1];
bool g_VoiceBlocked[MAXPLAYERS + 1][MAXPLAYERS + 1];
bool g_MuteDeafened[MAXPLAYERS + 1];
int g_AutoRedlistKills[MAXPLAYERS + 1];
int g_AutoRedlistRapes[MAXPLAYERS + 1];
bool g_AutoRedlistGotKills[MAXPLAYERS + 1];
bool g_AutoRedlistGotRapes[MAXPLAYERS + 1];
bool g_TidyChatSuppressNextTeamAlert[MAXPLAYERS + 1];
float g_TidyChatSuppressTeamAlertsUntil = 0.0;

#include "filters/mutecheck.inc"

Handle g_hCookieFilterWhitelist;
Handle g_hCookieredlist;
Handle g_hCookieMuteArchivedSpeakers;
Handle g_hChatFrontend;
bool g_bMuteArchivedSpeakers[MAXPLAYERS + 1];
char g_NameColors[MAXPLAYERS + 1][32];
char g_NamePatterns[MAXPLAYERS + 1][NAME_PATTERN_MAX];
Handle g_sEnabled = INVALID_HANDLE;
Handle g_sChatMode2 = INVALID_HANDLE;
ConVar g_hChatDebug = null;
ConVar g_hWebchatParsee = null;
ConVar g_hCrossServerTag = null;
ConVar g_hFiltersCaseSensitive = null;
ConVar g_hFiltersEnabled = null;
ConVar g_hBlacklistMinLen = null;
ConVar g_hFiltersChristmas = null;
ConVar g_hFiltersTeamChat = null;
ConVar g_hRedlistEnabled = null;
ConVar g_hPChat = null;
ConVar g_hMuteDeafenEnabled = null;
ConVar g_hParseeEnabled = null;
ConVar g_hMemomanEnabled = null;
ConVar g_hTidyChatEnabled = null;
ConVar g_hTidyChatVoice = null;
ConVar g_hTidyChatDisconnect = null;
ConVar g_hTidyChatTeam = null;
ConVar g_hTidyChatCvar = null;
char g_FilterWords[MAX_FILTERS][MAX_WORD_LENGTH];
char g_ReplacementWords[MAX_FILTERS][MAX_WORD_LENGTH];
int g_FilterCount = 0;
char g_CaseInsensitiveFilterWords[MAX_FILTERS][MAX_WORD_LENGTH];
char g_CaseInsensitiveReplacementWords[MAX_FILTERS][MAX_WORD_LENGTH];
int g_CaseInsensitiveFilterCount = 0;
char g_GoodnightStopperWords[MAX_FILTERS][MAX_WORD_LENGTH];
char g_GoodnightStopperReplacements[MAX_FILTERS][MAX_FILTER_REPLACEMENT_LENGTH];
int g_GoodnightStopperCount = 0;
char g_BlacklistWords[MAX_BLACKLIST][MAX_WORD_LENGTH];
int g_BlacklistCount = 0;
char g_BlacklistWords50[MAX_BLACKLIST][MAX_WORD_LENGTH];
int g_Blacklist50Count = 0;
char g_ForcedStatusSteamIDs[MAX_FORCED_STATUS][32];
char g_ForcedStatusTypes[MAX_FORCED_STATUS][32];
int g_ForcedStatusCount = 0;
char g_AllowedCommands[MAX_COMMANDS][MAX_WORD_LENGTH];
int g_AllowedCommandsCount = 0;
StringMap g_WebNameColors = null;
ArrayList g_ConnectQueue = null;
Handle g_ConnectQueueTimer = null;
Handle g_hPollOutboxTimer = null;
Handle g_hMuteDeafenTimer = null;
int g_iOutboxTimerGeneration = 0;
char g_sServerName[128];
ConVar g_hHostnameCvar = null;
StringMap g_PrenameIdRules = null;
StringMap g_PrenameOutputMap = null;
char g_PrenameDebugLogPath[PLATFORM_MAX_PATH];
bool g_PrenameDebugMigrate = false;
bool g_PrenameRulesLoaded = false;

enum struct ConnectEvent
{
    char name[MAX_NAME_LENGTH];
    bool connected;
}

char g_sHostIp[64];
char g_sPublicHostIp[64];
char g_sHostStamp[96];
ConVar g_hHostIpCvar = null;
ConVar g_hHostPortCvar = null;
int g_iHostPort = 27015;
bool g_bOutboxStampReady = false;
int g_iPendingSchemaQueries = 0;
int g_iArchivedMessageCounts[ArchivedSpeaker_Count];
int g_iNextArchivedMessageTime[MAXPLAYERS + 1][ArchivedSpeaker_Count];
int g_iArchivedSpeakerTeam[ArchivedSpeaker_Count];
int g_iArchivedSpeakerTeamExpiresAt[ArchivedSpeaker_Count];
int g_iLastOutboxCleanup = 0;
int g_iLastChatCleanup = 0;

public Plugin myinfo =
{
    name = "filters",
    author = "Hombre, Dr. McKay",
    description = "Chat Management + Filtered/Blacklisted Words + Web Communication Frontend",
    version = "1.0.0",
    url = "https://kogasa.tf"
};

// Configuration/registration are separate from the asynchronous relay implementation.
// Existing tidychat integration retains credit to pheadxdll.
#include "filters/bootstrap.sp"
#include "filters/common_state.sp"
#include "filters/tidychat.sp"
#include "filters/runtime.sp"
#include "filters/database.sp"
#include "filters/archived_personas.sp"
#include "filters/webchat.sp"
#include "filters/chat_commands.sp"
#include "filters/name_styles.sp"
#include "filters/chat_delivery.sp"
#include "filters/config.sp"
#include "filters/preferences_and_natives.sp"
#include "filters/moderation.sp"
#include "filters/prenames.sp"
