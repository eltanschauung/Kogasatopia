#if defined _points_store_bounties_included
    #endinput
#endif
#define _points_store_bounties_included

#define BOUNTY_TABLE "points_store_bounties"
#define BOUNTY_STEAMID_MAX 32
#define BOUNTY_NAME_MAX 128
#define BOUNTY_SEARCH_MAX 64
#define BOUNTY_TOKEN_MAX 128
#define BOUNTY_SYSTEM_STEAMID "system"
#define BOUNTY_WALL_EXPIRY_SECONDS 604800
#define BOUNTY_KILL_GROWTH_AMOUNT 5
#define BOUNTY_MEDIC_ASSISTS_PER_GROWTH 2
#define BOUNTY_MAINTENANCE_INTERVAL 60.0
#define BOUNTY_DISCONNECT_GRACE_SECONDS 300
#define BOUNTY_PLACEMENT_COOLDOWN_SECONDS 900
#define BOUNTY_MAX_ACTIVE 3
#define BOUNTY_CHALLENGE_SOUND "duel_challenge"
#define BOUNTY_EVENT_SOUND "duel_event"
#define BOUNTY_AUTOMATIC_CHANCE_PERCENT 15
#define BOUNTY_AUTOMATIC_AMOUNT 100
#define BOUNTY_AUTOMATIC_MIN_BALANCE 500
#define BOUNTY_AUTOMATIC_MIN_RATIO 4
#define BOUNTY_AUTOMATIC_TARGET_COOLDOWN_SECONDS 7200

enum struct BountySearchResult
{
    char steamId[BOUNTY_STEAMID_MAX];
    char name[BOUNTY_NAME_MAX];
    int playtime;
    bool connected;
}

bool g_BountyDatabaseReady = false;
bool g_BountyExpiryPending = false;
bool g_BountyProgressPending = false;
bool g_BountyDisconnectRefundPending = false;
StringMap g_ActiveBountyTargets = null;
int g_BountyTargetCacheGeneration = 0;
int g_ActiveBountyCount = 0;
bool g_BountyPlacementPending[MAXPLAYERS + 1];
ArrayList g_BountySearchResults[MAXPLAYERS + 1];
char g_BountyPendingSearch[MAXPLAYERS + 1][BOUNTY_NAME_MAX];
char g_BountyPendingTargetSteamId[MAXPLAYERS + 1][BOUNTY_STEAMID_MAX];
char g_BountyPendingTargetName[MAXPLAYERS + 1][BOUNTY_NAME_MAX];
int g_BountyPendingAmount[MAXPLAYERS + 1];
int g_BountyMedicAssistsLife[MAXPLAYERS + 1];
int g_BountySearchGeneration[MAXPLAYERS + 1];
int g_BountyLastPlacementAt[MAXPLAYERS + 1];
int g_BountyOperationSerial = 0;
Handle g_BountyMaintenanceTimer = null;
char g_BountyPrefix[96];
int g_BountySchemaChecksPending = 0;
bool g_BountySchemaCheckFailed = false;
bool g_BountyAutomaticPlacementPending = false;
int g_BountyKillAssistsOffset = -1;

#include "bounties/lifecycle_and_config.inc"
#include "bounties/automatic_placement.inc"
#include "bounties/client_state_and_schema.inc"
#include "bounties/placement_menus.inc"
#include "bounties/placement_persistence.inc"
#include "bounties/listing_and_cache.inc"
#include "bounties/growth_and_disconnects.inc"
#include "bounties/claims.inc"
#include "bounties/expiry.inc"
#include "bounties/progress.inc"
