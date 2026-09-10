#if defined _points_store_lotteries_included
    #endinput
#endif
#define _points_store_lotteries_included

#define LOTTO_TABLE "points_store_lotteries"
#define LOTTO_TICKET_TABLE "points_store_lottery_tickets"
#define LOTTO_WORD_MAX 64
#define LOTTO_TOKEN_MAX 128
#define LOTTO_TICKET_MAX 2048
#define LOTTO_TICKET_PRINT_MAX 2304
#define LOTTO_HASH_MAX 32
#define LOTTO_SHORT_HASH_LEN 7
#define LOTTO_SHORT_HASH_MAX 8
#define LOTTO_NAME_MAX 256
#define LOTTO_REVEAL_INTERVAL 0.5
#define LOTTO_TICKET_UNIT 5
#define LOTTO_EXTRA_WINNER_PARTICIPANTS 4
#define LOTTO_EXTRA_WINNER_PERCENT 5
#define LOTTO_WELFARE_POOL_PERCENT 5
#define LOTTO_TICKET_WRITE_TIMEOUT 15.0
#define LOTTO_TICKET_MUTATION_COOLDOWN 2.0
#define LOTTO_MAP_CHANGE_DELAY 120.0

ConVar g_CvarLotteryDisabled = null;
ConVar g_CvarLotteryMaxTicketValue = null;
ConVar g_CvarLotteryEqualTicketValue = null;

StringMap g_LotteryPendingSteamIds = null;
int g_LotteryPendingTicketWrites = 0;
ArrayList g_LotteryWords = null;
ArrayList g_LotteryRarities = null;
ArrayList g_LotteryDrawTokens = null;
int g_LotteryTotalWeight = 0;

bool g_LotteryReady = false;
bool g_LotteryCreating = false;
bool g_LotteryDrawInProgress = false;
int g_CurrentLotteryId = 0;
char g_CurrentLotteryHash[LOTTO_HASH_MAX];
char g_CurrentLotteryHashColor[BP_CURRENCY_COLOR_MAX + 2];
bool g_CurrentLotterySuper = false;
bool g_CurrentLotteryEqual = false;
bool g_LotteryEqualRefundInProgress = false;

bool g_LotteryWaitingCustom[MAXPLAYERS + 1];
bool g_ClientLotteryTicketLoaded[MAXPLAYERS + 1];
bool g_ClientLotteryHasTicket[MAXPLAYERS + 1];
int g_ClientLotteryId[MAXPLAYERS + 1];
int g_ClientLotteryTicketValue[MAXPLAYERS + 1];
char g_ClientLotteryTicket[MAXPLAYERS + 1][LOTTO_TICKET_MAX];
float g_NextLotteryTicketMutationAt[MAXPLAYERS + 1];

Handle g_LotteryDrawTimer = null;
Handle g_LotteryCallTimer = null;
int g_LotteryCallRequesterUserId = 0;
int g_LotteryCallLotteryId = 0;
int g_LotteryMapChangeLotteryId = 0;
int g_LotteryDrawIndex = 0;
int g_LotteryDrawLotteryId = 0;
int g_LotteryDrawPrizePool = 0;
int g_LotteryDrawWinnerPrize = 0;
int g_LotteryDrawWelfarePoolPrize = 0;
int g_LotteryDrawWinnerTicketValue = 0;
char g_LotteryDrawWinnerSteamId[32];
char g_LotteryDrawWinnerName[LOTTO_NAME_MAX];
int g_LotteryDrawExtraWinnerCount = 0;
int g_LotteryDrawExtraWinnerPrizes[MAXPLAYERS + 1];
int g_LotteryDrawExtraWinnerTicketValues[MAXPLAYERS + 1];
char g_LotteryDrawExtraWinnerSteamIds[MAXPLAYERS + 1][32];
char g_LotteryDrawExtraWinnerNames[MAXPLAYERS + 1][LOTTO_NAME_MAX];
char g_LotteryDrawHash[LOTTO_HASH_MAX];
char g_LotteryDrawHashColor[BP_CURRENCY_COLOR_MAX + 2];

#include "lotteries/lifecycle_and_schema.inc"
#include "lotteries/state.inc"
#include "lotteries/ticket_cache.inc"
#include "lotteries/commands_and_history.inc"
#include "lotteries/ticket_menus.inc"
#include "lotteries/ticket_purchases.inc"
#include "lotteries/refunds_and_pool.inc"
#include "lotteries/draw.inc"
#include "lotteries/draw_helpers.inc"
#include "lotteries/words.inc"
#include "lotteries/config_and_logging.inc"
