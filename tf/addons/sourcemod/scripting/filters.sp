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

// Player state structure
enum struct PlayerState
{
    bool isWhitelisted;        // Player bypasses all filters and blacklist
    bool isFilterWhitelisted;  // Player bypasses word filters only
    bool isBlacklisted;        // Player cannot send any messages
    bool isredlisted;         // Player cannot hear blacklisted clients
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

public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int err_max)
{
    RegPluginLibrary("filters");
    CreateNative("Filters_IsRedlisted", Native_Filters_IsRedlisted);
    CreateNative("Filters_GetChatName", Native_Filters_GetChatName);
    CreateNative("Filters_GetSteamIdColorTag", Native_Filters_GetSteamIdColorTag);
    CreateNative("Filters_GetSteamIdChatName", Native_Filters_GetSteamIdChatName);
    CreateNative("Filters_GetLastRecordedSteamName", Native_Filters_GetLastRecordedSteamName);
    CreateNative("FilterAlerts_MarkAutobalance", Native_FilterAlerts_MarkAutobalance);
    CreateNative("FilterAlerts_SuppressTeamAlertWindow", Native_FilterAlerts_SuppressTeamAlertWindow);
    RegPluginLibrary("mutecheck");
    CreateNative("MuteCheck_GetMutedClientCount", Native_MuteCheck_GetMutedClientCount);
    MarkNativeAsOptional("AdminsDB_GetClientWhitelistLevel");
    MarkNativeAsOptional("Hugs_GetRapesGiven");
    MarkNativeAsOptional("Hugs_AreStatsLoaded");
    MarkNativeAsOptional("PointsStore_HasPurchase");
    MarkNativeAsOptional("WhaleTracker_GetCumulativeKills");
    MarkNativeAsOptional("WhaleTracker_AreStatsLoaded");
    MarkNativeAsOptional("Tags_GetSelectedTag");
    return APLRes_Success;
}

// Cookie handles
Handle g_hCookieFilterWhitelist;
Handle g_hCookieredlist;
Handle g_hCookieMuteArchivedSpeakers;
Handle g_hChatFrontend;
bool g_bMuteArchivedSpeakers[MAXPLAYERS + 1];

// Per-client name color and pattern preferences (empty string means unset)
char g_NameColors[MAXPLAYERS + 1][32];
char g_NamePatterns[MAXPLAYERS + 1][NAME_PATTERN_MAX];

// Truthtext handles
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

// Global arrays for word filtering
char g_FilterWords[MAX_FILTERS][MAX_WORD_LENGTH];
char g_ReplacementWords[MAX_FILTERS][MAX_WORD_LENGTH];
int g_FilterCount = 0;
char g_CaseInsensitiveFilterWords[MAX_FILTERS][MAX_WORD_LENGTH];
char g_CaseInsensitiveReplacementWords[MAX_FILTERS][MAX_WORD_LENGTH];
int g_CaseInsensitiveFilterCount = 0;
char g_GoodnightStopperWords[MAX_FILTERS][MAX_WORD_LENGTH];
char g_GoodnightStopperReplacements[MAX_FILTERS][MAX_FILTER_REPLACEMENT_LENGTH];
int g_GoodnightStopperCount = 0;

// Global array for blacklisted words
char g_BlacklistWords[MAX_BLACKLIST][MAX_WORD_LENGTH];
int g_BlacklistCount = 0;
char g_BlacklistWords50[MAX_BLACKLIST][MAX_WORD_LENGTH];
int g_Blacklist50Count = 0;

// Global arrays for forced status
char g_ForcedStatusSteamIDs[MAX_FORCED_STATUS][32];
char g_ForcedStatusTypes[MAX_FORCED_STATUS][32]; // "whitelist", "blacklist", "redlist", or "filter_whitelist"
int g_ForcedStatusCount = 0;

// Global array for whitelisted/immunue commands
char g_AllowedCommands[MAX_COMMANDS][MAX_WORD_LENGTH];
int g_AllowedCommandsCount = 0;

// Web name color overrides (from filters.cfg -> webnames section)
StringMap g_WebNameColors = null;

// Connection event queue
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

bool Filters_DebugEnabled()
{
    return g_hChatDebug != null && g_hChatDebug.BoolValue;
}

bool Filters_RedlistEnabled()
{
    return g_hRedlistEnabled != null && g_hRedlistEnabled.BoolValue;
}

bool Filters_PChatEnabled()
{
    return g_hPChat == null || g_hPChat.BoolValue;
}

bool Filters_MuteDeafenEnabled()
{
    return g_hMuteDeafenEnabled != null && g_hMuteDeafenEnabled.BoolValue;
}

bool Filters_IsClientGagged(int client)
{
    return BaseComm_IsClientGagged(client)
        || (Filters_MuteDeafenEnabled() && g_MuteDeafened[client]);
}

int Filters_GetFilterMode()
{
    if (g_sChatMode2 == INVALID_HANDLE)
    {
        return 0;
    }

    int mode = GetConVarInt(g_sChatMode2);
    if (mode < 0)
    {
        return 0;
    }
    if (mode > 2)
    {
        return 2;
    }
    return mode;
}

bool Filters_IsCordModeEnabled()
{
    return Filters_GetFilterMode() != 0;
}

bool Filters_CordModeWhitelistedCanReceiveBlacklisted()
{
    return Filters_GetFilterMode() != 0;
}

bool Filters_CordModeBlacklistedCanReceiveWhitelisted()
{
    return Filters_GetFilterMode() == 1;
}

void Filters_LogDebug(const char[] fmt, any ...)
{
    if (!Filters_DebugEnabled())
        return;

    char buffer[256];
    VFormat(buffer, sizeof(buffer), fmt, 2);
    LogMessage("[Filters][Chat] %s", buffer);
}

bool Filters_IsClientIndex(int client)
{
    return client > 0 && client <= MaxClients;
}

bool Filters_IsRealClientInGame(int client)
{
    return Filters_IsClientIndex(client) && IsClientInGame(client) && !IsFakeClient(client);
}


void Filters_ClearClientState(int client)
{
    if (!Filters_IsClientIndex(client))
    {
        return;
    }

    g_PlayerState[client].isWhitelisted = false;
    g_PlayerState[client].isFilterWhitelisted = false;
    g_PlayerState[client].isBlacklisted = false;
    g_PlayerState[client].isredlisted = false;
    g_PlayerState[client].cookiesProcessed = false;
    g_NameColors[client][0] = '\0';
    g_NamePatterns[client][0] = '\0';
}

void Filters_ResetExternalStats(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    g_PlayerState[client].rapesGiven = 0;
    g_PlayerState[client].whaleKills = 0;
    g_PlayerState[client].hugsStatsLoaded = false;
    g_PlayerState[client].whaleStatsLoaded = false;

    g_AutoRedlistKills[client] = 0;
    g_AutoRedlistRapes[client] = 0;
    g_AutoRedlistGotKills[client] = false;
    g_AutoRedlistGotRapes[client] = false;
}

static bool Filters_TryGetRapesGiven(int client, int &value)
{
    if (GetFeatureStatus(FeatureType_Native, "Hugs_GetRapesGiven") != FeatureStatus_Available
        || GetFeatureStatus(FeatureType_Native, "Hugs_AreStatsLoaded") != FeatureStatus_Available)
    {
        return false;
    }

    if (!Hugs_AreStatsLoaded(client))
    {
        return false;
    }

    value = Hugs_GetRapesGiven(client);
    return true;
}

static bool Filters_TryGetWhaleKills(int client, int &value)
{
    if (GetFeatureStatus(FeatureType_Native, "WhaleTracker_GetCumulativeKills") != FeatureStatus_Available
        || GetFeatureStatus(FeatureType_Native, "WhaleTracker_AreStatsLoaded") != FeatureStatus_Available)
    {
        return false;
    }

    if (!WhaleTracker_AreStatsLoaded(client))
    {
        return false;
    }

    value = WhaleTracker_GetCumulativeKills(client);
    return true;
}

void Filters_UpdateExternalStats(int client)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
    {
        return;
    }

    int value = 0;
    if (Filters_TryGetRapesGiven(client, value))
    {
        g_PlayerState[client].rapesGiven = value;
        g_PlayerState[client].hugsStatsLoaded = true;
    }
    else
    {
        g_PlayerState[client].hugsStatsLoaded = false;
    }

    if (Filters_TryGetWhaleKills(client, value))
    {
        g_PlayerState[client].whaleKills = value;
        g_PlayerState[client].whaleStatsLoaded = true;
    }
    else
    {
        g_PlayerState[client].whaleStatsLoaded = false;
    }

}

void RefreshHostAddress()
{
    if (g_hHostIpCvar == null)
    {
        g_hHostIpCvar = FindConVar("ip");
        if (g_hHostIpCvar == null)
        {
            g_hHostIpCvar = FindConVar("hostip");
        }
    }

    if (g_hHostIpCvar != null)
    {
        g_hHostIpCvar.GetString(g_sHostIp, sizeof(g_sHostIp));
    }
    else
    {
        g_sHostIp[0] = '\0';
    }

    if (!g_sHostIp[0])
    {
        strcopy(g_sHostIp, sizeof(g_sHostIp), FILTERS_DEFAULT_HOST_IP);
    }

    if (g_hHostPortCvar == null)
    {
        g_hHostPortCvar = FindConVar("hostport");
    }
    g_iHostPort = (g_hHostPortCvar != null) ? g_hHostPortCvar.IntValue : 27015;

    RefreshPublicHostIp();

    Filters_LogDebug("Host identity refreshed: local=%s public=%s port=%d",
        g_sHostIp[0] ? g_sHostIp : "(unset)",
        g_sPublicHostIp[0] ? g_sPublicHostIp : "(unset)",
        g_iHostPort);
    Filters_UpdateHostStampString();
}

void RefreshServerHostname()
{
    if (g_hHostnameCvar == null)
    {
        g_hHostnameCvar = FindConVar("hostname");
    }
    if (g_hHostnameCvar != null)
    {
        g_hHostnameCvar.GetString(g_sServerName, sizeof(g_sServerName));
    }
    else
    {
        g_sServerName[0] = '\0';
    }
}

static void RefreshPublicHostIp()
{
    strcopy(g_sPublicHostIp, sizeof(g_sPublicHostIp), FILTERS_PUBLIC_HOST_IP);
}

static void Filters_GetPreferredHostIp(char[] buffer, int maxlen)
{
    if (!g_sPublicHostIp[0] && !g_sHostIp[0])
    {
        RefreshHostAddress();
    }

    if (g_sPublicHostIp[0])
    {
        strcopy(buffer, maxlen, g_sPublicHostIp);
    }
    else
    {
        strcopy(buffer, maxlen, g_sHostIp);
    }
}

void Filters_GetLocalHostStamp(char[] ipOut, int ipLen, int &portOut)
{
    Filters_GetPreferredHostIp(ipOut, ipLen);
    portOut = g_iHostPort;
}

bool Filters_IsLocalHostStamp(const char[] otherIp, int otherPort)
{
    if (!otherIp[0] || otherPort <= 0)
    {
        return false;
    }

    char localIp[64];
    Filters_GetPreferredHostIp(localIp, sizeof(localIp));
    if (!localIp[0])
    {
        return false;
    }

    return (StrEqual(localIp, otherIp, false) && otherPort == g_iHostPort);
}

static void Filters_UpdateHostStampString()
{
    char ip[64];
    int port;
    Filters_GetLocalHostStamp(ip, sizeof(ip), port);
    if (!ip[0])
    {
        strcopy(ip, sizeof(ip), FILTERS_DEFAULT_HOST_IP);
    }
    Format(g_sHostStamp, sizeof(g_sHostStamp), "%s:%d", ip, port);
}

void Filters_GetHostStamp(char[] buffer, int maxlen)
{
    if (!g_sHostStamp[0])
    {
        Filters_UpdateHostStampString();
    }
    strcopy(buffer, maxlen, g_sHostStamp);
}

public Plugin myinfo = 
{
    name = "filters",
    author = "Hombre, Dr. McKay",
    description = "Chat Management + Filtered/Blacklisted Words + Web Communication Frontend",
    version = "1.0.0",
    url = "https://kogasa.tf"
};

// This plugin has merged with my tidychat fork, credit to pheadxdll for creating tidychat

public void OnPluginStart()
{
    LoadTranslations("common.phrases");

    Filters_EnsureCollections();
    LoadFilterConfig();
    Filters_CreateConVars();
    Filters_RegisterCookies();
    Filters_RegisterCommands();
    MuteCheck_Initialize();
    TidyChat_Initialize();

    RefreshHostAddress();
    Filters_SQLConnect();
    Filters_StartTimers();
    Filters_RestoreConnectedClients();

    Filters_UpdateVoiceOverrides();
}

static void Filters_EnsureCollections()
{
    if (g_WebNameColors == null)
    {
        g_WebNameColors = new StringMap();
    }

    if (g_ConnectQueue == null)
    {
        g_ConnectQueue = new ArrayList(sizeof(ConnectEvent));
    }
    if (g_PrenameIdRules == null)
    {
        g_PrenameIdRules = new StringMap();
    }
    if (g_PrenameOutputMap == null)
    {
        g_PrenameOutputMap = new StringMap();
    }

    BuildPath(Path_SM, g_PrenameDebugLogPath, sizeof(g_PrenameDebugLogPath), "logs/prename_migrate.log");
}

static void Filters_CreateConVars()
{
    g_sEnabled = CreateConVar("nobroly", "1", "If 0, filter chat to one word");
    g_sChatMode2 = CreateConVar("filtermode", "0", "0=off, 1=quarantine with mutual whitelist/blacklist visibility, 2=quarantine with whitelist monitoring only");
    g_hChatDebug = CreateConVar("filters_chat_debug", "0", "Enable verbose debug logging for chat relay");
    g_hChatFrontend = CreateConVar("filters_chat_frontend", "1", "Show frontend chat to all clients; blacklist level 3 clients still receive it when disabled");
    g_hCrossServerTag = CreateConVar(
        "sm_filters_cross_sv_tag",
        "none",
        "Label stamped on database chat and shown when relayed to another server; none disables it."
    );
    g_hWebchatParsee = CreateConVar(
        "sm_filters_webchat_parsee",
        "0",
        "If 1, render all webchat messages as Parsee in-game without changing frontend chat.",
        _,
        true,
        0.0,
        true,
        1.0
    );
    g_hFiltersEnabled = CreateConVar("filters", "0", "If 0, blacklist word matching is disabled.");
    g_hRedlistEnabled = CreateConVar("redlist", "0", "Enable/Disable redlist features.", _, true, 0.0, true, 1.0);
    g_hBlacklistMinLen = CreateConVar("filters_blacklist_minlen", "8", "Minimum message length to check blacklist words.");
    g_hFiltersChristmas = CreateConVar("filters_christmas", "0", "If 1, red chat is {axis} and blue chat is {green}.");
    g_hFiltersTeamChat = CreateConVar("teamchat", "0", "If 1, normal chat is sent to the sender's team only.");
    g_hPChat = CreateConVar("sm_pchat", "1", "If 0, filtered/monitored chat is only printed to server console and not shown to whitelisted clients.", _, true, 0.0, true, 1.0);
    g_hMuteDeafenEnabled = CreateConVar(
        "sm_filters_mute_deafen",
        "0",
        "If 1, clients who mute another connected player cannot hear voice chat or send chat until no connected players are muted.",
        _,
        true,
        0.0,
        true,
        1.0
    );
    g_hParseeEnabled = CreateConVar(
        "sm_filters_parsee",
        "0",
        "Enable Parsee archived messages and webchat impersonation.",
        _,
        true,
        0.0,
        true,
        1.0
    );
    g_hMemomanEnabled = CreateConVar(
        "sm_filters_memoman",
        "0",
        "Enable Memoman archived messages and the Memoman event.",
        _,
        true,
        0.0,
        true,
        1.0
    );
    g_hFiltersCaseSensitive = CreateConVar(
        "filters_case_sensitive",
        "1",
        "If 1, chat filters are case-sensitive (exact casing must match)"
    );

    CreateConVar("sm_tidychat_version", TIDYCHAT_VERSION, "Tidy Chat Version", FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY);
    g_hTidyChatEnabled = CreateConVar("sm_tidychat_on", "1", "Enable Tidy Chat event cleanup.", _, true, 0.0, true, 1.0);
    g_hTidyChatVoice = CreateConVar("sm_tidychat_voice", "1", "Suppress voice subtitle messages.", _, true, 0.0, true, 1.0);
    g_hTidyChatDisconnect = CreateConVar("sm_tidychat_disconnect", "1", "Suppress stock disconnect messages.", _, true, 0.0, true, 1.0);
    g_hTidyChatTeam = CreateConVar("sm_tidychat_team", "1", "Replace stock team join messages.", _, true, 0.0, true, 1.0);
    g_hTidyChatCvar = CreateConVar("sm_tidychat_cvar", "1", "Suppress stock cvar messages.", _, true, 0.0, true, 1.0);

    HookConVarChange(g_sChatMode2, Filters_OnFilterModeChanged);
    HookConVarChange(g_hRedlistEnabled, Filters_OnRedlistChanged);
    HookConVarChange(g_hMuteDeafenEnabled, Filters_OnMuteDeafenChanged);
    HookConVarChange(g_hParseeEnabled, Filters_OnParseeChanged);
    HookConVarChange(g_hMemomanEnabled, Filters_OnMemomanChanged);
}

static void Filters_RegisterCookies()
{
    g_hCookieFilterWhitelist = RegClientCookie("filter_filterwhitelist", "Player is whitelisted from word filters only", CookieAccess_Protected);
    g_hCookieredlist = RegClientCookie("filter_redlist", "Player cannot hear blacklisted clients", CookieAccess_Protected);
    g_hCookieMuteArchivedSpeakers = RegClientCookie("filters_mute_parsee", "Player does not receive Parsee or Memoman messages", CookieAccess_Protected);
}

static void Filters_RegisterCommands()
{
    RegAdminCmd("sm_filterwhitelist", Command_FilterWhitelist, ADMFLAG_CHAT, "sm_filterwhitelist <player> - Whitelists a player from word filters only");
    RegAdminCmd("sm_unfilterwhitelist", Command_UnFilterWhitelist, ADMFLAG_CHAT, "sm_unfilterwhitelist <player> - Removes filter whitelist from a player");

    RegAdminCmd("sm_redlist", Command_redlist, ADMFLAG_CHAT, "sm_redlist <player> - redlist a player (can't hear blacklisted clients)");
    RegAdminCmd("sm_unredlist", Command_Unredlist, ADMFLAG_CHAT, "sm_unredlist <player> - Removes redlist from a player");
    RegAdminCmd("sm_redlists", Command_Listredlists, ADMFLAG_CHAT, "sm_redlists - Lists redlisted players");
    RegAdminCmd("sm_filtershelp", Command_FiltersHelp, ADMFLAG_CHAT, "sm_filtershelp - Shows filters convar help");
    RegConsoleCmd("sm_filters_debug", Command_FiltersDebug, "Show debug stats for filters");
    RegConsoleCmd("sm_colors", Command_Colors, "Show available chat colors");
    RegConsoleCmd("sm_colours", Command_Colors, "Show available chat colours");
    AddCommandListener(Listener_Colors, "colors");
    RegConsoleCmd("sm_gradientmenu", Command_GradientMenu, "Adjust where the second gradient color becomes full.");
    RegConsoleCmd("sm_gm", Command_GradientMenu, "Adjust where the second gradient color becomes full.");
    RegConsoleCmd("sm_prename", Command_Prename, "sm_prename <name_substring|steamid> <newname> (admins) or sm_prename <newname> (self)");
    RegConsoleCmd("sm_reset", Command_PrenameReset, "sm_reset <name|steamid> (admins) or sm_reset (self)");
    RegConsoleCmd("sm_parsee", Command_RandomParseeMessage, "Print a random archived Parsee message.");
    RegConsoleCmd("sm_randomparsee", Command_RandomParseeMessage, "Print a random archived Parsee message.");
    RegConsoleCmd("sm_randomparseemessage", Command_RandomParseeMessage, "Print a random archived Parsee message.");
    RegConsoleCmd("sm_memoman", Command_RandomMemomanMessage, "Print a random archived Memoman message.");
    // sm_memo is reserved for the Points Store Memoman event while it is active.
    // RegConsoleCmd("sm_memo", Command_RandomMemomanMessage, "Print a random archived Memoman message.");
    RegConsoleCmd("sm_bruh", Command_RandomMemomanMessage, "Print a random archived Memoman message.");
    RegConsoleCmd("sm_muteparsee", Command_MuteParsee, "Toggle Parsee and Memoman messages.");
    RegAdminCmd("sm_migrate", Command_PrenameMigrate, ADMFLAG_SLAY, "sm_migrate - Migrates legacy name rules to SteamID rules for connected clients");

    RegConsoleCmd("sm_websay", Command_WebSay, "Relay a web chat message to all players");
}

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
