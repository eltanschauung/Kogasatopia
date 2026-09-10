/**
 * Custom hat configuration, persistence, menus, and wearable lifecycle.
 *
 * Hats intentionally keep their own config/schema while sharing the unified
 * Weapons plugin's item lifecycle and wearable helpers.
 */

#define CUSTOM_HATS_CONFIG_FILE "configs/custom_hats.cfg"
#define DEFAULT_SCOUT_MODEL "models/uma_musume/player/items/scout/mercenary_derby.mdl"
#define HAT_EF_BONEMERGE 0x0010
#define HAT_EF_BONEMERGE_FASTCULL 0x0800

#define MAX_HATS 32
#define HAT_COOKIE_VALUE_LEN 100
const float HAT_COOKIE_SAVE_DELAY = 2.0;
const float HAT_POSTINVENTORY_DELAY = 0.1;
const int HAT_POSTINVENTORY_MAX_RETRIES = 5;

bool g_bHatEnabled[MAXPLAYERS + 1][MAX_HATS];
int g_iHatRef[MAXPLAYERS + 1][MAX_HATS];
int g_iHideHatRef[MAXPLAYERS + 1][MAX_HATS];
char g_szHatIdChoice[MAXPLAYERS + 1][64];
bool g_bHatApplyPending[MAXPLAYERS + 1];
bool g_bHatStateLoaded[MAXPLAYERS + 1];
bool g_bHatStatePending[MAXPLAYERS + 1];
bool g_bHatStatePendingAllowClear[MAXPLAYERS + 1];
Handle g_hPostInventoryTimer[MAXPLAYERS + 1];
int g_iPostInventoryUserId[MAXPLAYERS + 1];
int g_iPostInventoryRetry[MAXPLAYERS + 1];
Handle g_hHatSaveTimer[MAXPLAYERS + 1];
bool g_bHatSaveAllowClear[MAXPLAYERS + 1];
int g_iClientEnabledHatCount[MAXPLAYERS + 1];
Handle g_hHatStateCookie = INVALID_HANDLE;
int g_iHatPaintChoice[MAXPLAYERS + 1][MAX_HATS];
ConVar g_hHatDebug = null;

enum struct HatConfig
{
	bool enabled;
	bool force;
	char id[64];
	char name[64];
	char prefix[128];
	char bluPrefix[128];
	char pointsStorePurchase[64];
	char model[PLATFORM_MAX_PATH];
	bool hasModelScale;
	float modelScale;
	int quality;
	int level;
	int defaultPaint;
	bool paintable;
	int style;
	int bluSkin;
	int classMask;
	int baseDefIndex;
	int baseHideDefIndex;
	int defindexByClass[10];
	int hideDefindexByClass[10];
}

HatConfig g_Hats[MAX_HATS];
int g_iHatCount = 0;
int g_iDefaultHatIndex = -1;
enum
{
	CLASSMASK_ALL = (1 << 9) - 1,
	CLASSMASK_SCOUT = (1 << 0),
	CLASSMASK_SOLDIER = (1 << 1),
	CLASSMASK_PYRO = (1 << 2),
	CLASSMASK_DEMO = (1 << 3),
	CLASSMASK_HEAVY = (1 << 4),
	CLASSMASK_ENGINEER = (1 << 5),
	CLASSMASK_MEDIC = (1 << 6),
	CLASSMASK_SNIPER = (1 << 7),
	CLASSMASK_SPY = (1 << 8)
};
#include "hats/lifecycle.sp"
#include "hats/client_state.sp"
#include "hats/menus.sp"
#include "hats/entities.sp"
#include "hats/definitions.sp"
#include "hats/persistence.sp"
#include "hats/config.sp"
#include "hats/tags_and_natives.sp"
#include "hats/rendering.sp"
