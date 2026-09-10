#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#include <sdktools_gamerules>

#include <tf2_stocks>

#include <morecolors>

#undef REQUIRE_PLUGIN
#include <dgm_api>
#include <filters_api>
#include <points_store_api>
#include <tags_api>
#define REQUIRE_PLUGIN


#include "include/client_validation.inc"
#include "include/database.inc"
#include "include/steam_identity.inc"

#define PLUGIN_NAME               "Clans"
#define PLUGIN_AUTHOR             "Draggy"
#define PLUGIN_VERSION            "1.0.0"
#define PLUGIN_URL                "https://kogasa.tf"

#define CLAN_CREATE_GEM_COST      650
#define INVITE_EXPIRE_SECONDS     604800
#define CLAN_WAR_EXPIRE_SECONDS   604800
#define CLAN_WAR_REDECLARE_COOLDOWN_SECONDS 3600
#define CLAN_WAR_FLUSH_INTERVAL   3.0
#define CLAN_DB_RECONNECT_INITIAL_INTERVAL 5.0
#define CLAN_DB_RECONNECT_MAX_INTERVAL 60.0
#define CLAN_DB_KEEPALIVE_INTERVAL 300.0
#define CLAN_WAR_POINT_GOAL       50
#define CLAN_WAR_GEMS_STOLEN_PER_KILL 3
#define CLAN_NAME_MAXLEN          48
#define CLAN_DESC_MAXLEN          128
#define CLAN_TAG_MAXLEN           64
#define CLAN_TAG_STORE_MAXLEN     (CLAN_TAG_MAXLEN + 1)
#define STEAMID64_MAXLEN          32
#define SQL_STEAMID64_MAXLEN      ((STEAMID64_MAXLEN * 2) + 1)
#define SQL_CLAN_NAME_MAXLEN      ((CLAN_NAME_MAXLEN * 2) + 1)
#define SQL_CLAN_DESC_MAXLEN      ((CLAN_DESC_MAXLEN * 2) + 1)
#define SQL_CLAN_TAG_MAXLEN       ((CLAN_TAG_MAXLEN * 2) + 1)
#define CLAN_SUB_TAG_MAXLEN       64
#define CLAN_SUB_TAG_STORE_MAXLEN (CLAN_SUB_TAG_MAXLEN + 1)
#define SQL_CLAN_SUB_TAG_MAXLEN   ((CLAN_SUB_TAG_MAXLEN * 2) + 1)
#define CLAN_HISTORY_SUMMARY_MAXLEN 255
#define SQL_CLAN_HISTORY_SUMMARY_MAXLEN ((CLAN_HISTORY_SUMMARY_MAXLEN * 2) + 1)
#define CLAN_TAG_FORMAT_OVERHEAD  17 // Stored tag format: "[{gold}" + raw tag + "{default}]"
#define CLAN_TAG_PLAYER_MAXLEN    32
#define CLAN_TAG_ADMIN_MAXLEN     64
#define CLAN_TAGS_JOINED_MAXLEN   4096
#define INVITE_CLEANUP_INTERVAL   300.0
#define CLAN_MENU_TIME            MENU_TIME_FOREVER

enum ClanRank
{
    ClanRank_Member = 0,
    ClanRank_Officer,
    ClanRank_Owner
};

enum PromptState
{
    Prompt_None = 0,
    Prompt_ClanCreateName,
    Prompt_ClanRenameName,
    Prompt_ClanLeaveConfirm,
    Prompt_ClanTagChoice,
    Prompt_ClanTagInput,
    Prompt_ClanSubTagInput,
    Prompt_ClanDescInput,
    Prompt_ClanAdminDescInput
};

enum InviteMenuMode
{
    InviteMenu_Accept = 0,
    InviteMenu_Deny
};

enum ClanByPlayerCols
{
    ClanByPlayerCol_Id = 0,
    ClanByPlayerCol_Name,
    ClanByPlayerCol_Tag,
    ClanByPlayerCol_Owner,
    ClanByPlayerCol_IsOpen,
    ClanByPlayerCol_CreatedAt,
    ClanByPlayerCol_Rank,
    ClanByPlayerCol_JoinedAt
};

enum PendingInviteCols
{
    PendingInviteCol_Id = 0,
    PendingInviteCol_ClanId,
    PendingInviteCol_ClanName,
    PendingInviteCol_ClanTag,
    PendingInviteCol_InvitedBy,
    PendingInviteCol_ExpiresAt
};

enum ClanMenuContextCols
{
    ClanMenuCol_ClanId = 0,
    ClanMenuCol_Rank,
    ClanMenuCol_ClanName,
    ClanMenuCol_ClanTag,
    ClanMenuCol_IsOpen,
    ClanMenuCol_InviteCount
};

enum ClanMemberListCols
{
    ClanMemberListCol_SteamId64 = 0,
    ClanMemberListCol_Rank,
    ClanMemberListCol_JoinedAt,
    ClanMemberListCol_SubTag
};

enum ClanWarStatus
{
    ClanWarStatus_Active = 0,
    ClanWarStatus_Finished,
    ClanWarStatus_Expired,
    ClanWarStatus_Surrendered
};

enum struct ActiveClanWar
{
    int warId;
    int instanceId;
    int clanIdA;
    int clanIdB;
    int scoreA;
    int scoreB;
    int createdAt;
    int expiresAt;
    bool writeDirty;
    bool writePending;
    bool finalizePending;
    bool finalizeWritePending;
    int finalizeWinnerClanId;
    ClanWarStatus finalizeStatus;
    int finalizeFinishedAt;
    char announceLabelA[96];
    char announceLabelB[96];
    char historyLabelA[96];
    char historyLabelB[96];
}

enum struct PendingClanWarKillDelta
{
    int warInstanceId;
    int clanId;
    int kills;
    int currencyStolen;
    char steamid64[STEAMID64_MAXLEN];
}

#include "clans/clans_chat.inc"

public Plugin myinfo =
{
    name = PLUGIN_NAME,
    author = PLUGIN_AUTHOR,
    description = "Minecraft-style clans/factions scaffold backed by SQL",
    version = PLUGIN_VERSION,
    url = PLUGIN_URL
};

public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int err_max)
{
    RegPluginLibrary("clans");
    CreateNative("Clans_GetTags", Native_Clans_GetTags);
    CreateNative("Clans_GetSameTeamClanMemberCount", Native_Clans_GetSameTeamClanMemberCount);
    MarkNativeAsOptional("Filters_GetChatName");
    MarkNativeAsOptional("Filters_GetLastRecordedSteamName");
    MarkNativeAsOptional("PointsStore_RefundBonusPoints");
    MarkNativeAsOptional("PointsStore_SpendBonusPoints");
    MarkNativeAsOptional("PointsStore_StealBonusPoints");
    MarkNativeAsOptional("DGM_IsRoundRunning");
    MarkNativeAsOptional("Tags_GetTag");
    MarkNativeAsOptional("Tags_SetSelectedTag");
    return APLRes_Success;
}

bool IsClanGemStoreAvailable()
{
    return GetFeatureStatus(FeatureType_Native, "PointsStore_RefundBonusPoints") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "PointsStore_SpendBonusPoints") == FeatureStatus_Available;
}

bool GiveClanGems(int client, int gems)
{
    if (!IsClanGemStoreAvailable())
    {
        return false;
    }

    return PointsStore_RefundBonusPoints(client, gems, "clan_gems");
}

bool SpendClanGems(int client, int gems)
{
    if (!IsClanGemStoreAvailable())
    {
        return false;
    }

    return PointsStore_SpendBonusPoints(client, gems);
}

bool IsClanGemStealAvailable()
{
    return GetFeatureStatus(FeatureType_Native, "PointsStore_StealBonusPoints") == FeatureStatus_Available;
}

int StealClanWarGems(int attacker, int victim, int gems)
{
    if (!IsClanGemStealAvailable())
    {
        return 0;
    }

    return PointsStore_StealBonusPoints(victim, attacker, gems, "clan_war_steal");
}

Database g_Database = null;
bool g_bDatabaseReady = false;
char g_sDbDriver[16];
ConVar g_cvDatabaseConfig = null;
ConVar g_cvClanWarsEnabled = null;
Handle g_hInviteCleanupTimer = null;
Handle g_hClanWarFlushTimer = null;
Handle g_hDbReconnectTimer = null;
Handle g_hDbKeepaliveTimer = null;
Handle g_hDbInitTimer = null;
StringMap g_hClanIdCache = null;
bool g_bClanIdCacheReady = false;
ArrayList g_hActiveWars = null;
bool g_bActiveWarCacheReady = false;
ArrayList g_hPendingClanWarKillDeltas = null;
bool g_bClanWarKillFlushInFlight = false;
float g_flDbReconnectDelay = CLAN_DB_RECONNECT_INITIAL_INTERVAL;

PromptState g_PromptState[MAXPLAYERS + 1];
int g_PendingAdminClanDescId[MAXPLAYERS + 1];
char g_PendingAdminClanDescName[MAXPLAYERS + 1][CLAN_NAME_MAXLEN + 1];
int g_iClientClanId[MAXPLAYERS + 1];
bool g_bClientClanLoaded[MAXPLAYERS + 1];
bool g_bClientClanLoadPending[MAXPLAYERS + 1];
ClanRank g_ClientClanRank[MAXPLAYERS + 1];
char g_sClientClanName[MAXPLAYERS + 1][CLAN_NAME_MAXLEN + 1];
char g_sClientClanTag[MAXPLAYERS + 1][CLAN_TAG_STORE_MAXLEN];
char g_sClientClanTags[MAXPLAYERS + 1][CLAN_TAGS_JOINED_MAXLEN];
bool g_bClientClanTagsLoaded[MAXPLAYERS + 1];
bool g_bClientClanTagsPending[MAXPLAYERS + 1];
int g_iClanMembersMenuClanId[MAXPLAYERS + 1];
char g_sClanMembersMenuClanName[MAXPLAYERS + 1][CLAN_NAME_MAXLEN + 1];
int g_iClanHistoryMenuClanId[MAXPLAYERS + 1];
char g_sClanHistoryMenuClanName[MAXPLAYERS + 1][CLAN_NAME_MAXLEN + 1];

public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    g_cvDatabaseConfig = CreateConVar("sm_clans_database", "default", "Database config name from databases.cfg to use for clans.");
    g_cvClanWarsEnabled = CreateConVar("sm_clans_wars_enabled", "1", "Enable clan wars. Disable this to fail closed during database instability.", _, true, 0.0, true, 1.0);
    AutoExecConfig(true, "clans");

    RegConsoleCmd("sm_clan", Command_ClanMenu, "Open the clan menu.");
    RegConsoleCmd("sm_clans", Command_ClansList, "Browse clans.");
    RegConsoleCmd("sm_clanhelp", Command_ClanHelp, "Show a clan command summary.");
    RegConsoleCmd("sm_clancreate", Command_ClanCreate, "Create a clan.");
    RegConsoleCmd("sm_clanleave", Command_ClanLeave, "Leave your clan or delete it if you are the owner.");
    RegConsoleCmd("sm_claninvite", Command_ClanInvite, "Invite a player to your clan.");
    RegConsoleCmd("sm_clankick", Command_ClanKick, "Kick a player from your clan.");
    RegConsoleCmd("sm_clantag", Command_ClanTag, "Set your clan tag or personal sub-tag.");
    RegConsoleCmd("sm_clanjoin", Command_ClanJoin, "Join an open clan.");
    RegConsoleCmd("sm_clanparent", Command_ClanParent, "Set or clear your clan's parent relation.");
    RegConsoleCmd("sm_clanmembers", Command_ClanMembers, "Show clan members.");
    RegConsoleCmd("sm_claninfo", Command_ClanInfo, "Show clan info.");
    RegConsoleCmd("sm_clangems", Command_ClanGems, "Show clan Gems.");
    RegConsoleCmd("sm_clangem", Command_ClanGems, "Show clan Gems.");
    RegConsoleCmd("sm_clanpts", Command_ClanGems, "Show clan Gems.");
    RegConsoleCmd("sm_clanpoints", Command_ClanGems, "Show clan Gems.");
    RegConsoleCmd("sm_claninvites", Command_ClanInvites, "Show pending clan invites.");
    RegConsoleCmd("sm_clandesc", Command_ClanDesc, "Set your clan description.");
    RegConsoleCmd("sm_clanrename", Command_ClanRename, "Rename your clan.");
    RegConsoleCmd("sm_cc", Command_ClanChat, "Send a message to your clan.");
    RegConsoleCmd("sm_clanwar", Command_ClanWar, "Declare war on another clan or surrender an active war.");
    RegConsoleCmd("sm_clanhistory", Command_ClanHistory, "Show recent clan history.");
    RegAdminCmd("sm_clansetdesc", Command_ClanSetDesc, ADMFLAG_GENERIC, "Set any clan description.");

    /* Extra owner utility so open-clan menus are actually usable. */
    RegConsoleCmd("sm_clanopen", Command_ClanOpen, "Toggle whether your clan is open to direct joins.");

    /* Chat trigger aliases for invites. */
    RegConsoleCmd("sm_accept", Command_ClanAcceptInvite, "Accept a pending clan invite.");
    RegConsoleCmd("sm_yes", Command_ClanAcceptInvite, "Accept a pending clan invite.");
    RegConsoleCmd("sm_deny", Command_ClanDenyInvite, "Deny a pending clan invite.");

    AddCommandListener(CommandListener_Say, "say");
    AddCommandListener(CommandListener_Say, "say_team");
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);

    ConnectDatabase();
}

#include "clans/runtime.sp"
#include "clans/state_and_wars.sp"
#include "clans/prompts.sp"
#include "clans/main_menu.sp"
#include "clans/war_commands.sp"
#include "clans/browse.sp"
#include "clans/membership.sp"
#include "clans/invites_and_kicks.sp"
#include "clans/tags.sp"
#include "clans/open_join.sp"
#include "clans/relations_and_invites.sp"
