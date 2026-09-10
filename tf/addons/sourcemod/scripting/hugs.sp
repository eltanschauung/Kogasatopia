#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>
#include <dbi>

#include <sdktools>

#include <morecolors>

#undef REQUIRE_PLUGIN
#include <filters_api>
#define REQUIRE_PLUGIN

#include "include/database.inc"
#include "include/steam_identity.inc"

	public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int err_max)
	{
		RegPluginLibrary("hugs");
		CreateNative("Hugs_GetRapesGiven", Native_Hugs_GetRapesGiven);
		CreateNative("Hugs_AreStatsLoaded", Native_Hugs_AreStatsLoaded);
		CreateNative("Hugs_RedeemMailedHug", Native_Hugs_RedeemMailedHug);
		CreateNative("Hugs_RedeemMailedFeed", Native_Hugs_RedeemMailedFeed);
		CreateNative("Hugs_RedeemMailedRape", Native_Hugs_RedeemMailedRape);
		CreateNative("Hugs_AnnounceMailedInteraction", Native_Hugs_AnnounceMailedInteraction);
		MarkNativeAsOptional("Filters_IsRedlisted");
		MarkNativeAsOptional("Filters_GetChatName");
		MarkNativeAsOptional("Filters_GetSteamIdColorTag");
		MarkNativeAsOptional("Filters_GetSteamIdChatName");
		return APLRes_Success;
	}

	public Plugin myinfo =
	{
		name = "hugs",
		author = "Your Name",
		description = "Allows players to hug/rape each other, track hugs/rapes, check stats, and view last huggers/rapists",
		version = "1.5",
		url = "https://example.com"
	};

#define HUGS_DB_CONFIG "default"
#define HUGS_DB_TABLE  "hugs_stats"
#define HUGS_DUEL_HISTORY_TABLE "hugs_duel_history"
#define MAX_HISTORY_ENTRIES 5
#define HISTORY_STRING_LEN 256

int g_iHugsReceived[MAXPLAYERS + 1];
int g_iHugsGiven[MAXPLAYERS + 1];
int g_iFeedsReceived[MAXPLAYERS + 1];
int g_iFeedsGiven[MAXPLAYERS + 1];
int g_iRapesReceived[MAXPLAYERS + 1];
int g_iRapesGiven[MAXPLAYERS + 1];
char g_szLastHuggers[MAXPLAYERS + 1][MAX_HISTORY_ENTRIES][MAX_NAME_LENGTH];
char g_szLastFeeders[MAXPLAYERS + 1][MAX_HISTORY_ENTRIES][MAX_NAME_LENGTH];
char g_szLastRapists[MAXPLAYERS + 1][HISTORY_STRING_LEN];
	char g_szClientSteamId[MAXPLAYERS + 1][32];
	bool g_bStatsLoaded[MAXPLAYERS + 1];
	bool g_bStatsPending[MAXPLAYERS + 1];

	Database g_hDatabase = null;
bool g_bDatabaseReady = false;
Handle g_hDbReconnectTimer = null;
ConVar g_hMultiplierCvar = null;
int g_iMultiplier = 1;
Handle g_hReminderTimer[MAXPLAYERS + 1];
Handle g_hStatsRetryTimer[MAXPLAYERS + 1];
int g_iSchemaOpsPending = 0;
Handle g_hRedlistCookie = INVALID_HANDLE;

enum HugsLeaderboardKind
{
	HugsLeaderboard_Hugs = 0,
	HugsLeaderboard_Rapes
};

#include "hugs/mail_api.sp"
#include "hugs/lifecycle.sp"
#include "hugs/multiplier.sp"
#include "hugs/leaderboards.sp"
#include "hugs/protection_and_history.sp"
#include "hugs/duels.sp"
#include "hugs/helpers.sp"
#include "hugs/interactions.sp"
#include "hugs/statistics_updates.sp"
#include "hugs/statistics_persistence.sp"
#include "hugs/database.sp"
