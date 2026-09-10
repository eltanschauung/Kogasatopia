#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>
#include <multicolors>
#undef REQUIRE_PLUGIN
#include <filters_api>
#include <hugs_api>
#include <points_store_api>
#include <rtd_api>
#include <saysounds>
#include <whaletracker_api>
#define REQUIRE_PLUGIN
#include "include/steam_identity.inc"

// Session-owned reminder lifecycle is implemented in server_mail/lifecycle.sp.
#define MAIL_DB_CONFIG "server_mail"
#define MAIL_TABLE "mail"
#define MAIL_STEAMID_MAX 32
#define MAIL_NAME_MAX 128
#define MAIL_TITLE_MAX 128
#define MAIL_CONTENTS_MAX 512
#define MAIL_REQUEST_KEY_MAX 128
#define MAIL_SEARCH_MAX 64
#define MAIL_ATTACHMENT_MAX 16
#define MAIL_LIST_MAX 50
#define MAIL_RECONNECT_DELAY 5.0
#define MAIL_SEND_COOLDOWN 60.0
#define MAIL_UNREAD_REMINDER_DELAY 30.0
#define MAIL_UNREAD_REMINDER_RETRY 5.0
#define MAIL_RTD_GIFT_COST 50
#define MAIL_PREFIX "{cornflowerblue}[Mail]{default}"

enum MailViewMode
{
    MailView_Inbox = 0,
    MailView_Sent,
    MailView_Unread
};
enum MailRedemptionQueueResult
{
    MailRedemption_Queued = 0,
    MailRedemption_AlreadyPending,
    MailRedemption_Failed
};
enum struct MailSearchResult
{
    char steamId[MAIL_STEAMID_MAX];
    char name[MAIL_NAME_MAX];
    int playtime;
    bool connected;
}

Database g_MailDatabase = null;
bool g_MailDatabaseReady = false;
bool g_MailDatabaseIsMySql = false;
Handle g_MailReconnectTimer = null;
GlobalForward g_MailSendResultForward = null;
Cookie g_MailUnreadReminderCookie = null;
Handle g_MailUnreadReminderTimer[MAXPLAYERS + 1];
bool g_MailUnreadReminderPending[MAXPLAYERS + 1];
ArrayList g_MailSearchResults[MAXPLAYERS + 1];
char g_MailPendingContents[MAXPLAYERS + 1][MAIL_CONTENTS_MAX];
char g_MailPendingSearch[MAXPLAYERS + 1][MAIL_NAME_MAX];
int g_MailPendingGems[MAXPLAYERS + 1];
char g_MailPendingAttachment[MAXPLAYERS + 1][MAIL_ATTACHMENT_MAX];
int g_MailSearchGeneration[MAXPLAYERS + 1];
int g_MailGiftSerial = 0;
float g_MailNextSendAllowedAt[MAXPLAYERS + 1];
bool g_MailUserSendPending[MAXPLAYERS + 1];
bool g_MailRedeemAllPending[MAXPLAYERS + 1];
bool g_MailReadAllPending[MAXPLAYERS + 1];
StringMap g_MailPendingRedemptions = null;
StringMap g_MailRedemptionUsers = null;
StringMap g_MailRedemptionTitles = null;
StringMap g_MailRedemptionSteamIds = null;
StringMap g_MailRedemptionAmounts = null;
StringMap g_MailPendingAttachments = null;

public Plugin myinfo =
{
    name = "server_mail",
    author = "Hombre",
    description = "Persistent player mail with optional currency attachments.",
    version = "1.0.0",
    url = "https://kogasa.tf"
};

public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int errMax)
{
    RegPluginLibrary("server_mail");
    CreateNative("ServerMail_Send", Native_ServerMail_Send);
    CreateNative("ServerMail_SendCustom", Native_ServerMail_SendCustom);
    CreateNative("ServerMail_SendCurrency", Native_ServerMail_SendCurrency);
    CreateNative("ServerMail_SendSteamId", Native_ServerMail_SendSteamId);
    CreateNative("ServerMail_SendCustomSteamId", Native_ServerMail_SendCustomSteamId);
    CreateNative("ServerMail_SendCurrencySteamId", Native_ServerMail_SendCurrencySteamId);
    CreateNative("ServerMail_CheckPendingStimulus", Native_ServerMail_CheckPendingStimulus);
    MarkNativeAsOptional("Filters_GetChatName");
    MarkNativeAsOptional("Filters_GetSteamIdColorTag");
    MarkNativeAsOptional("Filters_GetLastRecordedSteamName");
    MarkNativeAsOptional("Hugs_RedeemMailedHug");
    MarkNativeAsOptional("Hugs_RedeemMailedFeed");
    MarkNativeAsOptional("Hugs_RedeemMailedRape");
    MarkNativeAsOptional("Hugs_AnnounceMailedInteraction");
    MarkNativeAsOptional("PointsStore_ApplyBonusPointsSteamIdOnce");
    MarkNativeAsOptional("PointsStore_RefundBonusPointsSteamId");
    MarkNativeAsOptional("SaySounds_PlayCommand");
    MarkNativeAsOptional("RTD_ApplyGiftedRoll");
    MarkNativeAsOptional("WhaleTracker_GetRankedPlaytimeHours");
    g_MailSendResultForward = new GlobalForward("ServerMail_OnMailSendResult",
        ET_Ignore, Param_String, Param_Cell, Param_Cell, Param_Cell);
    return APLRes_Success;
}

#include "server_mail/lifecycle.sp"
#include "server_mail/database.sp"
#include "server_mail/commands.sp"
#include "server_mail/composition_and_search.sp"
#include "server_mail/delivery.sp"
#include "server_mail/mailbox.sp"
#include "server_mail/currency_redemption.sp"
#include "server_mail/attachments.sp"
#include "server_mail/native_api.sp"
#include "server_mail/stimulus.sp"
