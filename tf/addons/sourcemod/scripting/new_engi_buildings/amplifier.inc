#if defined _new_engi_buildings_amplifier_included
	#endinput
#endif
#define _new_engi_buildings_amplifier_included

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>

#include <sdktools>
#include <sdkhooks>
#include <sdktools_functions>
#include <dhooks>

#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>

#include <morecolors>
#undef REQUIRE_PLUGIN
#include <tf_custom_attributes>
#define REQUIRE_PLUGIN
#include <conch_no_speed>

#include <client_validation>

#define MAX_AMPLIFIER_CLIENTS (MAXPLAYERS + 1)
#define MAX_AMPLIFIER_ENTITIES 2048

// Compatibility aliases used by the existing public/native data layout.
// Keep the old names local to avoid touching external config/schema/command contracts.
#define MP MAX_AMPLIFIER_CLIENTS
#define ME MAX_AMPLIFIER_ENTITIES

#define AMPLIFIER_PLUGIN_VERSION "2.5"

// Models and Sounds
#define AmplifierBuildModel "models/buildables/rayzar/rayzar"
#define AmplifierActiveModel "models/buildables/rayzar/rayzar_active"
#define AmplifierMaterialPath "materials/models/buildables/rayzar/"
#define AMPLIFIER_TOOLBOX_BODYGROUP_VISIBLE 0
#define AMPLIFIER_PULSE_SOUND "buttons/blip1.wav"
#define AMPLIFIER_CONSTRUCTION_SOUND "misc/rd_points_return01.wav"
#define AMPLIFIER_IDLE_SOUND "Building_Dispenser.Idle"
#define AMPLIFIER_BUFF_SOUND "weapons/dispenser_heal.wav"

// Gameplay
#define ATTR_FIRE_RATE "fire rate bonus HIDDEN"
#define ATTR_RELOAD_RATE "reload time increased hidden" // Set to < 1 for more speed
#define BEGGARS_BAZOOKA 730
#define AMPLIFIER_HEALTH 150
#define AMPLIFIER_MODEL_TOP_Z 66.629
#define AMPLIFIER_RING_CLEARANCE 3.0
#define AMPLIFIER_UPDATE_INTERVAL 0.5
#define AMPLIFIER_PULSE_INTERVAL_MIN 0.8
#define AMPLIFIER_PULSE_INTERVAL_MAX 1.5
#define AMPLIFIER_RING_RADIUS 180.0
#define AMPLIFIER_DAMAGE_RADIUS 180.0
#define AMPLIFIER_RING_LIFE 3.0
#define AMPLIFIER_PDA_SLOT_FIRST 3
#define AMPLIFIER_PDA_SLOT_LAST 4
#define AMPLIFIER_FORCE_MIN_PLAYERS 3

// Entity classes / commands
#define BUILDING_DISPENSER "obj_dispenser"
#define BUILDING_SENTRY "obj_sentrygun"
#define BUILDING_SAPPER "obj_attachment_sapper"
#define OBJECT_DISPENSER 0
#define OBJECT_TELEPORTER 1
#define OBJECT_SENTRY 2
#define DESTROY_DISPENSER "destroy 0"
#define DESTROY_SENTRY "destroy 2"
#define TIMER_NO_MAPCHANGE TIMER_FLAG_NO_MAPCHANGE

// Sprites
int g_BeamSprite;
int g_HaloSprite;
int g_AmplifierIdleSoundChannel;
int g_AmplifierIdleSoundLevel;
int g_AmplifierIdleSoundPitch;
float g_AmplifierIdleSoundVolume;
char g_AmplifierIdleSoundSample[PLATFORM_MAX_PATH];
bool g_AmplifierIdleSoundResolved;

// Player State
enum struct AmplifierPlayerState
{
    bool useDispenser;
    bool useSentry;
    bool nearAmplifier;
    int engiAssists;
    Handle effectTimer;
}

AmplifierPlayerState g_PlayerState[MP];

Handle g_hAmplifierTimer = INVALID_HANDLE;
Handle g_hAmplifierPulseTimer = INVALID_HANDLE;
Handle g_hAmplifierStopSound = INVALID_HANDLE;
DynamicDetour g_hAmplifierCanBeUpgraded = null;
// Building States
bool AmplifierOn[ME];
bool AmplifierSapped[ME];
bool AmplifierCarried[ME];
bool AmplifierIdleSoundPlaying[ME];
bool ConditionApplied[ME][MP];
float AmplifierDistance[ME];
TFCond AmplifierCondition[ME];
int BuildingRef[ME];
int g_ActiveAmplifiers[ME];
bool g_bAmplifierExplosionActive = false;

// ConVars
ConVar cvarDistance;
ConVar cvarEffectLength;
ConVar cvarForceAmplifier;
ConVar cvarForcePlayercount;
ConVar cvarEnableExplosion;
ConVar cvarEnableZap;

TFCond DefaultCondition = TFCond_RuneHaste; // Formerly TFCond_Buffed

// Forward
Handle fwdOnAmplify;
Handle g_hEngiPadsCookie;

// Native Control
bool NativeControl;
TFCond NativeConditionDisp[MP];
TFCond NativeConditionSentry[MP];
float NativeDistanceDisp[MP];
float NativeDistanceSentry[MP];
int NativePercentDisp[MP];
int NativePercentSentry[MP];

// Client Preferences
Handle g_hCookieDisp;
Handle g_hCookieSentry;

#tryinclude <tf2_player>
#if !defined _tf2_player_included
    #define TF2_IsDisguised(%1) (((%1) & TF_CONDFLAG_DISGUISED) != TF_CONDFLAG_NONE)
    #define TF2_IsCloaked(%1) (((%1) & TF_CONDFLAG_CLOAKED) != TF_CONDFLAG_NONE)
#endif

static bool IsValidPlayerIndex(int client)
{
    return client > 0 && client < sizeof(g_PlayerState);
}

static bool IsTrackedEntityIndex(int ent)
{
    return ent > 0 && ent < sizeof(BuildingRef);
}

static int GetTrackedEntityLimit(int maxEntities = 0)
{
    int limit = maxEntities > 0 ? maxEntities : GetMaxEntities();
    if (limit > sizeof(BuildingRef))
    {
        limit = sizeof(BuildingRef);
    }

    return limit;
}

static bool IsValidCookieHandle(Handle cookie)
{
    return cookie != null && cookie != INVALID_HANDLE;
}

static bool IsDispenserClass(const char[] classname)
{
    return StrEqual(classname, BUILDING_DISPENSER);
}

static bool IsSentryClass(const char[] classname)
{
    return StrEqual(classname, BUILDING_SENTRY);
}

static void ResetAmplifierBuildingState(int ent)
{
    if (!IsTrackedEntityIndex(ent))
    {
        return;
    }

    AmplifierOn[ent] = false;
    AmplifierSapped[ent] = false;
    AmplifierCarried[ent] = false;
    AmplifierIdleSoundPlaying[ent] = false;
    AmplifierDistance[ent] = 0.0;
    AmplifierCondition[ent] = DefaultCondition;
    BuildingRef[ent] = 0;
    ClearAmplifierConditionForBuilding(ent);
}

static void ResetPlayerState(int client, bool resetPreferences = true)
{
    if (client <= 0 || client >= sizeof(g_PlayerState))
        return;

    StopAmplifierEffect(client, false);

    g_PlayerState[client].nearAmplifier = false;
    g_PlayerState[client].engiAssists = 0;

    if (resetPreferences)
    {
        g_PlayerState[client].useDispenser = false;
        g_PlayerState[client].useSentry = false;
    }
}

void Amplifier_RegisterNatives()
{
	CreateNative("ControlAmplifier", Native_ControlAmplifier);
	CreateNative("SetAmplifierDisp", Native_SetAmplifierDisp);
	CreateNative("SetAmplifierSentry", Native_SetAmplifierSentry);
	CreateNative("HasAmplifier", Native_HasAmplifier);
	CreateNative("ConvertToAmplifier", Native_ConvertToAmplifier);
	CreateNative("Amplifier_WouldReplaceBuilding", Native_WouldReplaceBuilding);
	fwdOnAmplify = CreateGlobalForward("OnAmplify", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
	RegPluginLibrary("Amplifier");
}

void InitializeAmplifierHooks()
{
	GameData gameData = new GameData("buildings");
	if (gameData == null)
	{
		SetFailState("[Amplifier] Unable to load gamedata file 'buildings.txt'.");
		return;
	}

	g_hAmplifierCanBeUpgraded =
		DynamicDetour.FromConf(gameData, "CBaseObject::CanBeUpgraded");

	StartPrepSDKCall(SDKCall_Entity);
	if (!PrepSDKCall_SetFromConf(gameData, SDKConf_Signature, "CBaseEntity::StopSound"))
	{
		delete gameData;
		SetFailState("[Amplifier] Missing CBaseEntity::StopSound signature.");
		return;
	}
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	g_hAmplifierStopSound = EndPrepSDKCall();
	delete gameData;

	if (g_hAmplifierCanBeUpgraded == null)
	{
		SetFailState("[Amplifier] Failed to create CBaseObject::CanBeUpgraded detour.");
		return;
	}
	if (g_hAmplifierStopSound == INVALID_HANDLE)
	{
		SetFailState("[Amplifier] Failed to prepare CBaseEntity::StopSound SDKCall.");
		return;
	}

	if (!g_hAmplifierCanBeUpgraded.Enable(
		Hook_Pre,
		Amplifier_CanBeUpgraded_Pre))
	{
		SetFailState("[Amplifier] Failed to enable CBaseObject::CanBeUpgraded detour.");
	}
}

void Amplifier_OnPluginStart()
{
	InitializeAmplifierHooks();

	CreateConVar("amplifier_version", AMPLIFIER_PLUGIN_VERSION, "The Amplifier Version", FCVAR_REPLICATED|FCVAR_NOTIFY);
	cvarEffectLength = CreateConVar("amplifier_effect_length", "3.0", "Length in seconds for the Amplifier condition to last", FCVAR_PLUGIN);
	cvarDistance = CreateConVar("amplifier_distance", "220.0", "Distance the amplifier works.", FCVAR_PLUGIN);
	cvarForceAmplifier = CreateConVar("amplifier_force", "0", "Force amplifier mode: 0=nothing, 1=dispenser, 2=sentry, 3=both", FCVAR_PLUGIN, true, 0.0, true, 3.0);
	cvarForcePlayercount = CreateConVar("amplifier_force_playercount", "0", "If >0 and human player count is below this value, treat amplifier_force as 2 (sentry only).", FCVAR_PLUGIN, true, 0.0);
	cvarEnableExplosion = CreateConVar("amplifier_explode", "65", "Enable Amplifier death explosions? >0 for damage value.", FCVAR_PLUGIN, true, 0.0);
	SetConVarBounds(cvarEnableExplosion, ConVarBound_Upper, false);
	cvarEnableZap = CreateConVar("amplifier_zap", "0.0", "Should Amplifier pulses harm the enemy team? 0 to disable, >0 for damage.", FCVAR_PLUGIN, true, 0.0, true, 50.0);

	HookEventEx("player_dropobject", Event_ObjectDropped);
	HookEvent("object_destroyed", Event_AmplifierObjectDestroyedPre, EventHookMode_Pre);

	RegConsoleCmd("sm_amplifier", CallPanel, "Select engineer's building type");
	RegConsoleCmd("sm_a", CallPanel, "Select engineer's building type");
	RegConsoleCmd("sm_p", CallPanel, "Select engineer's building type");
	RegConsoleCmd("sm_amp", CallPanel, "Select engineer's building type");
	RegConsoleCmd("sm_amphelp", HelpPanel, "Show info about Amplifier");
	RegConsoleCmd("sm_ah", HelpPanel, "Show info about Amplifier");
	RegConsoleCmd("sm_ph", PadHelpPanel, "Show info about Jump/Speed Pads");
	RegConsoleCmd("sm_killsentries", Command_KillSentries, "Destroy all sentry guns");

	g_hEngiPadsCookie = FindClientCookie("engipads_toggle");

	// Cookies
	g_hCookieDisp = RegClientCookie("amplifier_dispenser", "Dispenser Amplifier preference", CookieAccess_Public);
	g_hCookieSentry = RegClientCookie("amplifier_sentry", "Sentry Amplifier preference", CookieAccess_Public);

	for (int i = 1; i <= MaxClients; i++)
	{
		ResetPlayerState(i);
		if (IsClientInGame(i))
		{
			Amplifier_OnClientPostAdminCheck(i);
		}
	}
}

void Amplifier_OnPluginEnd()
{
	if (g_hAmplifierCanBeUpgraded != null)
	{
		g_hAmplifierCanBeUpgraded.Disable(
			Hook_Pre,
			Amplifier_CanBeUpgraded_Pre);
		delete g_hAmplifierCanBeUpgraded;
		g_hAmplifierCanBeUpgraded = null;
	}

	if (g_hAmplifierTimer != INVALID_HANDLE)
	{
		KillTimer(g_hAmplifierTimer);
		g_hAmplifierTimer = INVALID_HANDLE;
	}
	if (g_hAmplifierPulseTimer != INVALID_HANDLE)
	{
		KillTimer(g_hAmplifierPulseTimer);
		g_hAmplifierPulseTimer = INVALID_HANDLE;
	}
	if (g_hAmplifierStopSound != INVALID_HANDLE)
	{
		delete g_hAmplifierStopSound;
		g_hAmplifierStopSound = INVALID_HANDLE;
	}

	if (fwdOnAmplify != null)
	{
		delete fwdOnAmplify;
		fwdOnAmplify = null;
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		StopAmplifierEffect(client);
	}

	ConvertAllAmplifiersToBuildings();
}

void Amplifier_OnConfigsExecuted()
{
	if (g_hAmplifierTimer == INVALID_HANDLE)
	{
		g_hAmplifierTimer = CreateTimer(AMPLIFIER_UPDATE_INTERVAL, Timer_amplifier, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
	if (g_hAmplifierPulseTimer == INVALID_HANDLE)
	{
		ScheduleAmplifierPulse();
	}
}

void ScheduleAmplifierPulse()
{
	g_hAmplifierPulseTimer = CreateTimer(
		GetRandomFloat(AMPLIFIER_PULSE_INTERVAL_MIN, AMPLIFIER_PULSE_INTERVAL_MAX),
		Timer_amplifier_pulse,
		_,
		TIMER_FLAG_NO_MAPCHANGE);
}

void Amplifier_OnMapStart()
{
	PrecacheScriptSound(AMPLIFIER_IDLE_SOUND);
	g_AmplifierIdleSoundResolved = GetGameSoundParams(
		AMPLIFIER_IDLE_SOUND,
		g_AmplifierIdleSoundChannel,
		g_AmplifierIdleSoundLevel,
		g_AmplifierIdleSoundVolume,
		g_AmplifierIdleSoundPitch,
		g_AmplifierIdleSoundSample,
		sizeof(g_AmplifierIdleSoundSample),
		SOUND_FROM_WORLD);
	g_BeamSprite = 0;
	g_HaloSprite = 0;
}

void Amplifier_OnMapEnd()
{
	for (int ent = 1; ent < GetTrackedEntityLimit(); ent++)
	{
		ResetAmplifierBuildingState(ent);
	}

	g_hAmplifierTimer = INVALID_HANDLE;
	g_hAmplifierPulseTimer = INVALID_HANDLE;
}

void Amplifier_OnClientPostAdminCheck(int client)
{
	if (!Client_IsInGame(client) || IsFakeClient(client))
	{
		return;
	}

	ResetPlayerState(client, false);

	if (AreClientCookiesCached(client))
	{
		LoadClientPreferences(client);
	}
}

void Amplifier_OnClientCookiesCached(int client)
{
	if (!Client_IsInGame(client) || IsFakeClient(client))
	{
		return;
	}

	LoadClientPreferences(client);
}

void Amplifier_OnClientDisconnect(int client)
{
	ResetPlayerState(client);
}

void LoadClientPreferences(int client)
{
	if (!Client_IsInGame(client) || !AreClientCookiesCached(client))
	{
		return;
	}

	char szValue[8];

	GetClientCookie(client, g_hCookieDisp, szValue, sizeof(szValue));
	if (szValue[0] != '\0')
	{
		g_PlayerState[client].useDispenser = view_as<bool>(StringToInt(szValue));
	}

	GetClientCookie(client, g_hCookieSentry, szValue, sizeof(szValue));
	if (szValue[0] != '\0')
	{
		g_PlayerState[client].useSentry = view_as<bool>(StringToInt(szValue));
	}
}

void SaveClientPreferences(int client)
{
	if (!Client_IsInGame(client) || !AreClientCookiesCached(client)) return;

	char szValue[8];

	IntToString(g_PlayerState[client].useDispenser, szValue, sizeof(szValue));
	SetClientCookie(client, g_hCookieDisp, szValue);

	IntToString(g_PlayerState[client].useSentry, szValue, sizeof(szValue));
	SetClientCookie(client, g_hCookieSentry, szValue);
}

int GetEffectiveForceAmplifier()
{
	if (IsPlayercountForceActive())
	{
		return 2;
	}

	return GetConVarInt(cvarForceAmplifier);
}

bool IsPlayercountForceActive()
{
	int forceAmplifier = GetConVarInt(cvarForceAmplifier);
	int forcePlayercount = GetConVarInt(cvarForcePlayercount);
	if (forceAmplifier == 2 || forcePlayercount <= 0)
	{
		return false;
	}

	int playerCount = GetClientCount(false);
	if (playerCount < AMPLIFIER_FORCE_MIN_PLAYERS)
	{
		return false;
	}

	return playerCount < forcePlayercount;
}

bool ShouldClientBuildAmplifier(int client, bool isDispenser, bool isSentry, bool &forcedConversion, bool &playercountForceActive, int &effectiveForceAmplifier, bool &playerRequestedAmplifier)
{
	forcedConversion = false;
	playercountForceActive = false;
	effectiveForceAmplifier = 0;
	playerRequestedAmplifier = false;

	if ((!isDispenser && !isSentry) || !Client_IsInGame(client))
	{
		return false;
	}

	playercountForceActive = IsPlayercountForceActive();
	effectiveForceAmplifier = GetEffectiveForceAmplifier();

	bool hasAmplifierAttribute = (isDispenser && CheckAmpAttributesDisp(client))
		|| (isSentry && CheckAmpAttributesSentry(client));
	bool hasAmplifierPreference = (isDispenser && g_PlayerState[client].useDispenser)
		|| (isSentry && g_PlayerState[client].useSentry);
	playerRequestedAmplifier = hasAmplifierAttribute || hasAmplifierPreference;

	if (effectiveForceAmplifier == 1 && isDispenser)
	{
		forcedConversion = true;
		return true;
	}
	if (effectiveForceAmplifier == 2 && isSentry)
	{
		forcedConversion = true;
		return true;
	}
	if (effectiveForceAmplifier == 3)
	{
		forcedConversion = true;
		return true;
	}

	return playerRequestedAmplifier;
}

bool WouldObjectTypeBecomeAmplifier(int client, int objectType)
{
	bool forcedConversion;
	bool playercountForceActive;
	int effectiveForceAmplifier;
	bool playerRequestedAmplifier;

	return ShouldClientBuildAmplifier(
		client,
		objectType == OBJECT_DISPENSER,
		objectType == OBJECT_SENTRY,
		forcedConversion,
		playercountForceActive,
		effectiveForceAmplifier,
		playerRequestedAmplifier);
}

bool GetDestroyCommandForBuilding(const char[] buildingClass, char[] destroyCmd, int destroyCmdSize)
{
	if (IsDispenserClass(buildingClass))
	{
		strcopy(destroyCmd, destroyCmdSize, DESTROY_DISPENSER);
		return true;
	}

	if (IsSentryClass(buildingClass))
	{
		strcopy(destroyCmd, destroyCmdSize, DESTROY_SENTRY);
		return true;
	}

	destroyCmd[0] = '\0';
	return false;
}

void RemoveBuilding(int client, const char[] buildingClass)
{
	if (!Client_IsInGame(client))
	{
		return;
	}

	char destroyCmd[32];
	if (!GetDestroyCommandForBuilding(buildingClass, destroyCmd, sizeof(destroyCmd)))
	{
		return;
	}

	char classname[64];

	for (int j = 1; j < GetTrackedEntityLimit(); j++)
	{
		int ent = EntRefToEntIndex(BuildingRef[j]);
		if (!IsTrackedEntityIndex(ent) || !IsValidEntity(ent))
		{
			if (BuildingRef[j] != 0)
			{
				BuildingRef[j] = 0;
				ClearAmplifierConditionForBuilding(j);
			}
			continue;
		}

		GetEdictClassname(ent, classname, sizeof(classname));
		if (!StrEqual(classname, buildingClass) || GetEntPropEnt(ent, Prop_Send, "m_hBuilder") != client)
		{
			continue;
		}
		if (AmplifierOn[ent] || IsAmplifierModel(ent))
		{
			StopAmplifierIdleSound(ent);
		}

		char health[16];
		IntToString(GetEntProp(ent, Prop_Send, "m_iMaxHealth") + 1, health, sizeof(health));
		SetVariantString(health);
		AcceptEntityInput(ent, "RemoveHealth");
		FakeClientCommand(client, destroyCmd);

		Event event = CreateEvent("object_removed", true);
		if (event != null)
		{
			SetEventInt(event, "userid", GetClientUserId(client));
			SetEventInt(event, "index", ent);
			event.Fire();
		}

		AcceptEntityInput(ent, "kill");
	}
}

public int AmpHelpPanelH(Handle menu, MenuAction action, int param1, int param2) { return 0; }

public Action HelpPanel(int client, int args)
{
	if (!Client_IsInGame(client))
	{
		return Plugin_Continue;
	}

	Handle panel = CreatePanel();

	SetPanelTitle(panel, "Amplifier Info");
	DrawPanelText(panel, "Amplifiers buff allies with 40% faster reload speed and health on hit");
	DrawPanelText(panel, "They zap enemies within range and explode on death");
	DrawPanelText(panel, "Ammo is fuel, hit with your wrench to refill");
	DrawPanelText(panel, "If sentries are disabled, amplifiers replace them. Otherwise, equip amplifiers with !a");
	DrawPanelItem(panel, "Close");

	SendPanelToClient(panel, client, AmpHelpPanelH, 20);
	delete panel;
	return Plugin_Continue;
}

public Action PadHelpPanel(int client, int args)
{
	if (!Client_IsInGame(client))
	{
		return Plugin_Continue;
	}

	Handle panel = CreatePanel();

	DrawPanelText(panel, "Jump/Speed Pad Info");
	DrawPanelText(panel, "Teleporters can be converted to Jump or Speed pads");
	DrawPanelText(panel, "Turn your pad once to place a jump pad instead of a speed pad");
	DrawPanelText(panel, "Use !pads to toggle these buildings");
	DrawPanelItem(panel, "Close");

	SendPanelToClient(panel, client, AmpHelpPanelH, 20);
	delete panel;
	return Plugin_Continue;
}

public Action CallPanel(int client, int args)
{
	if (!NativeControl && Client_IsInGame(client))
	{
		ShowAmplifierMenu(client);
	}
	return Plugin_Continue;
}

void ShowAmplifierMenu(int client)
{
	if (!Client_IsInGame(client))
		return;

	Handle menu = CreateMenu(MenuHandler_Amplifier);

	SetMenuTitle(menu, "Amplifier Settings");

	char szItem[128];
	Format(szItem, sizeof(szItem), "Sentry Gun: %s", g_PlayerState[client].useSentry ? "[✓] Amplifier" : "[  ] Normal");
	AddMenuItem(menu, "sentry", szItem);

	Format(szItem, sizeof(szItem), "Dispenser: %s", g_PlayerState[client].useDispenser ? "[✓] Amplifier" : "[  ] Normal");
	AddMenuItem(menu, "disp", szItem);

	// I've added Engipads to this nice menu
	bool usePadSpeed = GetClientCookieBool(client, g_hEngiPadsCookie);

	Format(szItem, sizeof(szItem), "Teleporters: %s", usePadSpeed ? "[✓] Speed/Jump" : "[  ] Normal");
	AddMenuItem(menu, "tele", szItem);

	AddMenuItem(menu, "info", "── Help & Info ──");

	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

// Engipads attachment
bool GetClientCookieBool(int client, Handle cookie)
{
	if (!Client_IsInGame(client) || !IsValidCookieHandle(cookie) || !AreClientCookiesCached(client))
	{
		return false;
	}

	char value[8];
	GetClientCookie(client, cookie, value, sizeof(value));
	return StrEqual(value, "1") || StrEqual(value, "true");
}

void SetClientCookieBool(int client, Handle cookie, bool value)
{
	if (!Client_IsInGame(client) || !IsValidCookieHandle(cookie) || !AreClientCookiesCached(client))
	{
		return;
	}

	char szToggle[8];
	Format(szToggle, sizeof(szToggle), "%s", value ? "1" : "0");
	SetClientCookie(client, cookie, szToggle);
}

void ToggleAmplifierBuildingPreference(int client, bool sentry)
{
	if (!Client_IsInGame(client))
	{
		return;
	}

	if (sentry)
	{
		g_PlayerState[client].useSentry = !g_PlayerState[client].useSentry;
		SaveClientPreferences(client);

		if (g_PlayerState[client].useSentry)
		{
			CPrintToChat(client, "{orange}[Amplifier]{default} Sentries will now be {green}Amplifiers{default}!");
			RemoveBuilding(client, BUILDING_SENTRY);
		}
		else
		{
			CPrintToChat(client, "{orange}[Amplifier]{default} Sentries will now be {lightgreen}Normal{default}!");
			RemoveBuilding(client, BUILDING_SENTRY);
		}
	}
	else
	{
		g_PlayerState[client].useDispenser = !g_PlayerState[client].useDispenser;
		SaveClientPreferences(client);

		if (g_PlayerState[client].useDispenser)
		{
			CPrintToChat(client, "{orange}[Amplifier]{default} Dispensers will now be {green}Amplifiers{default}!");
			RemoveBuilding(client, BUILDING_DISPENSER);
		}
		else
		{
			CPrintToChat(client, "{orange}[Amplifier]{default} Dispensers will now be {lightgreen}Normal{default}!");
			RemoveBuilding(client, BUILDING_DISPENSER);
		}
	}

	ShowAmplifierMenu(client);
}

public int MenuHandler_Amplifier(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		if (!Client_IsInGame(param1))
		{
			return 0;
		}

		char info[32];
		if (!GetMenuItem(menu, param2, info, sizeof(info)))
		{
			return 0;
		}

		if (StrEqual(info, "disp"))
		{
			ToggleAmplifierBuildingPreference(param1, false);
		}
		else if (StrEqual(info, "sentry"))
		{
			ToggleAmplifierBuildingPreference(param1, true);
		}
		else if (StrEqual(info, "info"))
		{
			HelpPanel(param1, 0);
		}
		else if (StrEqual(info, "tele"))
		{
			bool usePadSpeed = GetClientCookieBool(param1, g_hEngiPadsCookie);
			usePadSpeed = !usePadSpeed; // toggle it
			SetClientCookieBool(param1, g_hEngiPadsCookie, usePadSpeed);

			PrintToChat(param1, "[Kogasa] Teleporter mode set to: %s", usePadSpeed ? "Speed/Jump" : "Normal");
			ShowAmplifierMenu(param1);
		}
	}
	else if (action == MenuAction_End && menu != INVALID_HANDLE)
	{
		delete menu;
	}

	return 0;
}

bool IsAmplifierModel(int ent)
{
	if (!IsTrackedEntityIndex(ent) || !IsValidEntity(ent))
		return false;

	char modelname[256];
	char expectedBuildModel[128];
	char expectedActiveModel[128];
	GetEntPropString(ent, Prop_Data, "m_ModelName", modelname, sizeof(modelname));
	Format(expectedBuildModel, sizeof(expectedBuildModel), "%s.mdl", AmplifierBuildModel);
	Format(expectedActiveModel, sizeof(expectedActiveModel), "%s.mdl", AmplifierActiveModel);
	return StrEqual(modelname, expectedBuildModel, false)
		|| StrEqual(modelname, expectedActiveModel, false);
}

bool IsAmplifierActiveModel(int ent)
{
	if (!IsTrackedEntityIndex(ent) || !IsValidEntity(ent))
		return false;

	char modelname[256];
	char expectedModel[128];
	GetEntPropString(ent, Prop_Data, "m_ModelName", modelname, sizeof(modelname));
	Format(expectedModel, sizeof(expectedModel), "%s.mdl", AmplifierActiveModel);
	return StrEqual(modelname, expectedModel, false);
}

bool IsAmplifierUpgradeBlockedEntity(int ent)
{
	if (!IsTrackedEntityIndex(ent) || !IsValidEntity(ent)
		|| BuildingRef[ent] != EntIndexToEntRef(ent))
	{
		return false;
	}

	char buildingClass[64];
	GetEdictClassname(ent, buildingClass, sizeof(buildingClass));
	if (!IsDispenserClass(buildingClass) && !IsSentryClass(buildingClass))
	{
		return false;
	}

	// The model identifies an amplifier during construction. AmplifierOn remains
	// authoritative afterward in case TF2 temporarily overwrites the model.
	return AmplifierOn[ent] || IsAmplifierModel(ent);
}

public MRESReturn Amplifier_CanBeUpgraded_Pre(
	int ent,
	DHookReturn returnValue,
	DHookParam parameters)
{
	if (!IsAmplifierUpgradeBlockedEntity(ent))
	{
		return MRES_Ignored;
	}

	returnValue.Value = false;
	return MRES_Supercede;
}

bool GetObjectBoolProp(int ent, const char[] propName)
{
	if (!IsTrackedEntityIndex(ent) || !IsValidEntity(ent) || !HasEntProp(ent, Prop_Send, propName))
		return false;

	return view_as<bool>(GetEntProp(ent, Prop_Send, propName));
}

bool IsAmplifierBeingCarried(int ent)
{
	if (!IsTrackedEntityIndex(ent) || !IsValidEntity(ent))
		return false;

	return AmplifierCarried[ent]
		|| GetObjectBoolProp(ent, "m_bCarried")
		|| GetObjectBoolProp(ent, "m_bPlacing")
		|| GetObjectBoolProp(ent, "m_bCarryDeploy");
}

void SetAmplifierCarriedState(int ent, bool carried)
{
	if (!IsTrackedEntityIndex(ent) || !IsValidEntity(ent) || (!AmplifierOn[ent] && !IsAmplifierModel(ent)))
		return;

	AmplifierCarried[ent] = carried;
	if (carried)
	{
		StopAmplifierIdleSound(ent);
		ClearAmplifierConditionForBuilding(ent);
	}
}

bool IsActiveAmplifier(int ent)
{
	// AmplifierOn is the authoritative plugin state.  Do not gate this on
	// IsAmplifierModel(): TF2 can overwrite the model during late construction
	// or native upgrade handling, and requiring the model here prevents the
	// plugin from ever repairing that overwritten state.
	return IsTrackedEntityIndex(ent) && IsValidEntity(ent) && AmplifierOn[ent] && !AmplifierSapped[ent] && !IsAmplifierBeingCarried(ent);
}

void StartAmplifierIdleSound(int ent)
{
	if (!IsTrackedEntityIndex(ent) || !IsValidEntity(ent) || AmplifierIdleSoundPlaying[ent])
		return;

	if (EmitGameSoundToAll(AMPLIFIER_IDLE_SOUND, ent))
	{
		AmplifierIdleSoundPlaying[ent] = true;
	}
}

void StopAmplifierIdleSound(int ent)
{
	if (!IsTrackedEntityIndex(ent))
		return;

	if (IsValidEntity(ent) && g_hAmplifierStopSound != INVALID_HANDLE)
	{
		SDKCall(g_hAmplifierStopSound, ent, AMPLIFIER_IDLE_SOUND);
	}

	if (g_AmplifierIdleSoundResolved)
	{
		StopSound(ent, g_AmplifierIdleSoundChannel, g_AmplifierIdleSoundSample);

		for (int client = 1; client <= MaxClients; client++)
		{
			if (!IsClientInGame(client))
				continue;

			EmitSoundToClient(
				client,
				g_AmplifierIdleSoundSample,
				ent,
				g_AmplifierIdleSoundChannel,
				g_AmplifierIdleSoundLevel,
				SND_STOP,
				g_AmplifierIdleSoundVolume,
				g_AmplifierIdleSoundPitch);
		}
	}

	AmplifierIdleSoundPlaying[ent] = false;
}

public Action Event_AmplifierObjectDestroyedPre(Event event, const char[] name, bool dontBroadcast)
{
	int ent = event.GetInt("index");
	if (IsTrackedEntityIndex(ent)
		&& (AmplifierOn[ent] || AmplifierIdleSoundPlaying[ent]))
	{
		StopAmplifierIdleSound(ent);
	}

	return Plugin_Continue;
}

void SetAmplifierBuildModel(int ent)
{
	char modelname[128];
	Format(modelname, sizeof(modelname), "%s.mdl", AmplifierBuildModel);
	SetEntityModel(ent, modelname);
	SetEntProp(ent, Prop_Send, "m_nBody", AMPLIFIER_TOOLBOX_BODYGROUP_VISIBLE);
}

void SetAmplifierActiveVisualState(int ent)
{
	// Match CObjectDispenser::OnGoActive(): replace the construction model
	// with the separate finished model. Its ref sequence is marked autoplay,
	// which starts the active radar animation as soon as the model is set.
	char modelname[128];
	Format(modelname, sizeof(modelname), "%s.mdl", AmplifierActiveModel);
	SetEntityModel(ent, modelname);
}

bool IsAmplifierConstructionComplete(int ent)
{
	if (!IsTrackedEntityIndex(ent) || !IsValidEntity(ent))
		return false;

	if (GetEntPropFloat(ent, Prop_Send, "m_flPercentageConstructed") < 1.0)
		return false;

	// m_flPercentageConstructed can reach 1.0 before TF2 is done with native
	// construction finalization.  Waiting for m_bBuilding to clear keeps our
	// final model/health/ammo writes from racing those native writes.
	return GetEntProp(ent, Prop_Send, "m_bBuilding") == 0;
}

void ClampAmplifierHealthToMax(int ent)
{
	SetEntProp(ent, Prop_Send, "m_iMaxHealth", AMPLIFIER_HEALTH);

	int currentHealth = GetEntProp(ent, Prop_Send, "m_iHealth");
	if (currentHealth > AMPLIFIER_HEALTH)
	{
		char sHealth[16];
		IntToString(AMPLIFIER_HEALTH, sHealth, sizeof(sHealth));
		SetVariantString(sHealth);
		AcceptEntityInput(ent, "SetHealth");
	}
}

void ReassertAmplifierRuntimeState(int ent)
{
	if (!IsTrackedEntityIndex(ent) || !IsValidEntity(ent) || !AmplifierOn[ent])
		return;
	if (IsAmplifierBeingCarried(ent))
		return;

	char buildingClass[64];
	GetEdictClassname(ent, buildingClass, sizeof(buildingClass));
	if (!IsDispenserClass(buildingClass) && !IsSentryClass(buildingClass))
		return;

	SetEntProp(ent, Prop_Send, "m_bDisabled", 1);
	SetEntProp(ent, Prop_Send, "m_iUpgradeLevel", 1);
	SetEntProp(ent, Prop_Send, "m_iHighestUpgradeLevel", 1);
	if (HasEntProp(ent, Prop_Send, "m_bMiniBuilding"))
	{
		SetEntProp(ent, Prop_Send, "m_bMiniBuilding", 0);
	}
	SetEntPropFloat(ent, Prop_Send, "m_flModelScale", 1.0);
	if (!IsAmplifierActiveModel(ent))
		SetAmplifierActiveVisualState(ent);
	ClampAmplifierHealthToMax(ent);
	StartAmplifierIdleSound(ent);
}

float GetAmplifierEffectiveRadius(int ent)
{
	// Keep the gameplay range and visual pulse range in lock-step.
	return IsTrackedEntityIndex(ent) ? AmplifierDistance[ent] : 0.0;
}

float GetAmplifierEffectLength()
{
	return GetConVarFloat(cvarEffectLength);
}

void ClearAmplifierConditionForClient(int client, int maxEntities)
{
	if (!IsValidPlayerIndex(client))
		return;

	for (int ent = 1; ent < GetTrackedEntityLimit(maxEntities); ent++)
	{
		ConditionApplied[ent][client] = false;
	}
}

void ClearAmplifierConditionForBuilding(int ent)
{
	if (!IsTrackedEntityIndex(ent))
		return;

	for (int client = 1; client <= MaxClients; client++)
	{
		ConditionApplied[ent][client] = false;
	}
}

int CollectActiveAmplifiers(int maxEntities, int activeAmps[ME])
{
	int activeCount = 0;

	for (int slot = 1; slot < GetTrackedEntityLimit(maxEntities); slot++)
	{
		int ref = BuildingRef[slot];
		if (ref == 0)
			continue;

		int ent = EntRefToEntIndex(ref);
		if (ent <= 0)
		{
			BuildingRef[slot] = 0;
			ClearAmplifierConditionForBuilding(slot);
			continue;
		}
		if (IsAmplifierBeingCarried(ent))
		{
			ClearAmplifierConditionForBuilding(ent);
			continue;
		}

		if (IsActiveAmplifier(ent))
		{
			ReassertAmplifierRuntimeState(ent);
			activeAmps[activeCount++] = ent;
		}
	}

	return activeCount;
}

bool TryApplyAmplifierToClient(int client, int amp)
{
	if (!IsActiveAmplifier(amp))
		return false;

	float clientPos[3];
	float amplifierPos[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", clientPos);
	GetEntPropVector(amp, Prop_Send, "m_vecOrigin", amplifierPos);

	if (GetVectorDistance(clientPos, amplifierPos) > GetAmplifierEffectiveRadius(amp))
		return false;
	if (!TraceTargetIndex(amp, client, amplifierPos, clientPos))
		return false;

	TFTeam clientTeam = view_as<TFTeam>(GetClientTeam(client));
	TFTeam team = view_as<TFTeam>(GetEntProp(amp, Prop_Send, "m_iTeamNum"));

	if (TF2_GetPlayerClass(client) == TFClass_Spy && TF2_IsPlayerInCondition(client, TFCond_Disguised) && !TF2_IsPlayerInCondition(client, TFCond_Cloaked))
		team = clientTeam;

	TFCond Condition = DefaultCondition;
	Action res = Plugin_Continue;
	int builder = GetEntPropEnt(amp, Prop_Send, "m_hBuilder");
	if (fwdOnAmplify != null)
	{
		Call_StartForward(fwdOnAmplify);
		Call_PushCell(builder);
		Call_PushCell(client);
		Call_PushCell(Condition);
		Call_Finish(res);
	}
	if (res != Plugin_Continue)
		return false;

    if (clientTeam != team)
    {
        return false;
    }

    if (!AddAmplifierEffect(client))
        return false;

    if (!ConditionApplied[amp][client])
    {
        EmitSoundToClient(client, AMPLIFIER_BUFF_SOUND, amp, _, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5, SNDPITCH_HIGH);
    }
    ConditionApplied[amp][client] = true;
    g_PlayerState[client].nearAmplifier = true;

    return true;
}

void ApplyAmplifierEffectsToPlayers(int activeAmps[ME], int activeCount, int maxEntities)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!Client_IsInGame(client))
			continue;

		g_PlayerState[client].nearAmplifier = false;

		if (!IsPlayerAlive(client) || !IsValidEdict(client))
			continue;

		for (int slot = 0; slot < activeCount; slot++)
		{
			int amp = activeAmps[slot];
            if (TryApplyAmplifierToClient(client, amp))
                break;
		}

		if (!g_PlayerState[client].nearAmplifier)
		{
			ClearAmplifierConditionForClient(client, maxEntities);
		}
	}
}

void DamageEnemiesFromAmplifierPulse(int amp, float amplifierPos[3])
{
    float zapDamage = GetConVarFloat(cvarEnableZap);
    if (zapDamage <= 0.0)
        return;

    TFTeam amplifierTeam = view_as<TFTeam>(GetEntProp(amp, Prop_Send, "m_iTeamNum"));
    int builder = GetEntPropEnt(amp, Prop_Send, "m_hBuilder");

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!Client_IsInGame(client) || !IsPlayerAlive(client))
            continue;

        float clientPos[3];
        GetEntPropVector(client, Prop_Send, "m_vecOrigin", clientPos);
        if (GetVectorDistance(clientPos, amplifierPos) > AMPLIFIER_DAMAGE_RADIUS)
            continue;
        if (!TraceTargetIndex(amp, client, amplifierPos, clientPos))
            continue;

        TFTeam clientTeam = view_as<TFTeam>(GetClientTeam(client));
        if (clientTeam == amplifierTeam)
            continue;
        if (TF2_GetPlayerClass(client) == TFClass_Spy
            && TF2_IsPlayerInCondition(client, TFCond_Disguised)
            && !TF2_IsPlayerInCondition(client, TFCond_Cloaked))
        {
            continue;
        }

        TFCond condition = DefaultCondition;
        Action result = Plugin_Continue;
        if (fwdOnAmplify != null)
        {
            Call_StartForward(fwdOnAmplify);
            Call_PushCell(builder);
            Call_PushCell(client);
            Call_PushCell(condition);
            Call_Finish(result);
        }
        if (result != Plugin_Continue)
            continue;

        DealElectricDamage(client, builder, amplifierPos, zapDamage, AMPLIFIER_DAMAGE_RADIUS);
    }
}

void PulseAmplifierBuilding(int ent)
{
	if (!IsActiveAmplifier(ent))
		return;

	float pos[3];
	GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);

	float ringPos[3];
	GetEntPropVector(ent, Prop_Send, "m_vecOrigin", ringPos);
	float modelScale = GetEntPropFloat(ent, Prop_Send, "m_flModelScale");
	if (modelScale <= 0.0)
		modelScale = 1.0;
	ringPos[2] += (AMPLIFIER_MODEL_TOP_Z * modelScale) + AMPLIFIER_RING_CLEARANCE;

	pos[2] += 90;

	int beamColor[4];
	if (view_as<TFTeam>(GetEntProp(ent, Prop_Send, "m_iTeamNum")) == TFTeam_Red)
		beamColor = {255, 75, 75, 255};
	else
		beamColor = {75, 75, 255, 255};

	EmitAmbientSound(AMPLIFIER_PULSE_SOUND, pos, ent, SNDLEVEL_CAR, SND_NOFLAGS, 0.6, SNDPITCH_NORMAL);

	if (g_BeamSprite <= 0)
	{
		g_BeamSprite = FindStringIndex(
			FindStringTable("modelprecache"),
			"materials/sprites/laser.vmt");
	}
	if (g_HaloSprite <= 0)
	{
		g_HaloSprite = FindStringIndex(
			FindStringTable("modelprecache"),
			"materials/sprites/halo01.vmt");
	}
	if (g_BeamSprite <= 0 || g_HaloSprite <= 0)
	{
		LogError("Amplifier beam materials were not precached by precachefiles.cfg");
		return;
	}

    TE_SetupBeamRingPoint(ringPos, 0.0, AMPLIFIER_RING_RADIUS, g_BeamSprite, g_HaloSprite, 0, 15, AMPLIFIER_RING_LIFE, 5.0, 0.0, beamColor, 3, 0);
    TE_SendToAll();

    float amplifierPos[3];
    GetEntPropVector(ent, Prop_Send, "m_vecOrigin", amplifierPos);
    DamageEnemiesFromAmplifierPulse(ent, amplifierPos);
}

void PulseAmplifierBuildings()
{
	int maxEntities = GetTrackedEntityLimit();
	for (int slot = 1; slot < maxEntities; slot++)
	{
		int ref = BuildingRef[slot];
		if (ref == 0)
			continue;

		int ent = EntRefToEntIndex(ref);
		PulseAmplifierBuilding(ent);
	}
}

public Action Timer_amplifier(Handle hTimer)
{
    int maxEntities = GetTrackedEntityLimit();
    int activeCount = CollectActiveAmplifiers(maxEntities, g_ActiveAmplifiers);

    ApplyAmplifierEffectsToPlayers(g_ActiveAmplifiers, activeCount, maxEntities);

	return Plugin_Continue;
}

public Action Timer_amplifier_pulse(Handle hTimer)
{
	g_hAmplifierPulseTimer = INVALID_HANDLE;
	PulseAmplifierBuildings();
	ScheduleAmplifierPulse();
	return Plugin_Stop;
}

public Action event_player_death(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	if (!IsValidPlayerIndex(attacker))
	{
		return Plugin_Continue;
	}

	int maxEntities = GetTrackedEntityLimit();
	for (int i = 1; i < maxEntities; i++)
	{
		int ent = EntRefToEntIndex(BuildingRef[i]);
		if (!IsTrackedEntityIndex(ent) || !AmplifierOn[ent] || AmplifierSapped[ent] || attacker == i)
		{
			continue;
		}

		if (ConditionApplied[ent][attacker])
		{
			int builder = GetEntPropEnt(ent, Prop_Send, "m_hBuilder");
			if (IsValidPlayerIndex(builder))
			{
				g_PlayerState[builder].engiAssists++;
				if (g_PlayerState[builder].engiAssists >= 4)
				{
					Event escortEvent = CreateEvent("player_escort_score", true);
					if (escortEvent != null)
					{
						escortEvent.SetInt("player", builder);
						escortEvent.SetInt("points", 1);
						escortEvent.Fire();
					}
					g_PlayerState[builder].engiAssists = 0;
				}
			}
			break;
		}
	}
	return Plugin_Continue;
}

public Action Event_Build(Event event, const char[] name, bool dontBroadcast)
{
	int ent = GetEventInt(event, "index");
	CheckBuilding(ent);
	CheckSapper(ent);
	return Plugin_Continue;
}

public void Event_ObjectCarried(Event event, const char[] name, bool dontBroadcast)
{
	int ent = event.GetInt("index");
	SetAmplifierCarriedState(ent, true);
}

public void Event_ObjectDropped(Event event, const char[] name, bool dontBroadcast)
{
	int ent = event.GetInt("index");
	if (!IsTrackedEntityIndex(ent) || !IsValidEntity(ent))
		return;

	AmplifierCarried[ent] = false;
	if (AmplifierOn[ent])
	{
		CreateTimer(0.1, Timer_ReassertAmplifierAfterDrop, EntIndexToEntRef(ent), TIMER_NO_MAPCHANGE);
	}
}

public Action Timer_ReassertAmplifierAfterDrop(Handle timer, any ref)
{
	int ent = EntRefToEntIndex(ref);
	if (IsActiveAmplifier(ent))
	{
		ReassertAmplifierRuntimeState(ent);
	}

	return Plugin_Stop;
}

public Action Event_ObjectDestroyed(Event event, const char[] name, bool dontBroadcast)
{
    int entindex = event.GetInt("index"); // the destroyed entity
    if (!IsTrackedEntityIndex(entindex) || !IsValidEntity(entindex))
        return Plugin_Continue;
	if (!AmplifierOn[entindex] && !AmplifierCarried[entindex] && !IsAmplifierModel(entindex))
		return Plugin_Continue;

	float amplifierDistance = GetAmplifierEffectiveRadius(entindex);
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	bool entwasbuilding = event.GetBool("was_building"); // building in progress
	bool wasCarried = IsAmplifierBeingCarried(entindex);
	float position[3];
	GetEntPropVector(entindex, Prop_Send, "m_vecOrigin", position);
	int explosionDamage = GetConVarInt(cvarEnableExplosion);
	if (explosionDamage > 0 && !wasCarried && !g_bAmplifierExplosionActive)
	{
		CreateAmplifierExplosion(position, attacker, entwasbuilding, explosionDamage, amplifierDistance);
	}

	StopAmplifierIdleSound(entindex);
	ResetAmplifierBuildingState(entindex);
	return Plugin_Changed;
}

void CheckBuilding(int ent)
{
	if (!IsTrackedEntityIndex(ent) || !IsValidEntity(ent))
	{
		return;
	}

    char classname[64];
    int Client = GetEntPropEnt(ent, Prop_Send, "m_hBuilder");
    GetEdictClassname(ent, classname, sizeof(classname));

	bool isDispenser = IsDispenserClass(classname);
	bool isSentry = IsSentryClass(classname);

	if ((!isDispenser && !isSentry) || !Client_IsInGame(Client)) return;

	ResetAmplifierBuildingState(ent);
	BuildingRef[ent] = EntIndexToEntRef(ent);

	bool forcedConversion = false;
	bool playercountForceActive = false;
	int effectiveForceAmplifier = 0;
	bool playerRequestedAmplifier = false;
	bool shouldConvert = ShouldClientBuildAmplifier(Client, isDispenser, isSentry, forcedConversion, playercountForceActive, effectiveForceAmplifier, playerRequestedAmplifier);

    if (shouldConvert)
    {
        AmplifierOn[ent] = false;
        SetEntProp(ent, Prop_Send, "m_bDisabled", 1);
		SetEntPropFloat(ent, Prop_Send, "m_flModelScale", 1.0);
		if (HasEntProp(ent, Prop_Send, "m_bMiniBuilding"))
		{
			SetEntProp(ent, Prop_Send, "m_bMiniBuilding", 0);
		}

		AmplifierSapped[ent] = false;

		if (NativeControl)
		{
			AmplifierDistance[ent] = isDispenser ? NativeDistanceDisp[Client] : NativeDistanceSentry[Client];
			AmplifierCondition[ent] = isDispenser ? NativeConditionDisp[Client] : NativeConditionSentry[Client];
		}
		else
		{
			AmplifierDistance[ent] = GetConVarFloat(cvarDistance);
			AmplifierCondition[ent] = DefaultCondition;
		}

		SetAmplifierBuildModel(ent);
		SetEntProp(ent, Prop_Send, "m_nSkin", GetEntProp(ent, Prop_Send, "m_nSkin") + 2);
        // Build-rate modifiers can complete a sentry before a one-second
        // delayed check runs, so start the construction watchdog almost
        // immediately and let it continue after activation.
        CreateTimer(0.1, BuildingCheckStage2, EntIndexToEntRef(ent), TIMER_REPEAT | TIMER_NO_MAPCHANGE);

        if (forcedConversion && effectiveForceAmplifier == 2 && !playerRequestedAmplifier)
        {
            if (playercountForceActive)
            {
                CPrintToChat(Client, "{orange}[Amplifier]{default} Playercount is below %d; sentry replaced with amplifier!", GetConVarInt(cvarForcePlayercount));
            }
            else
            {
                CPrintToChat(Client, "{orange}[Amplifier]{default} Sentries have been disabled for this map; have an Amplifier instead!");
            }
        }
    }
}

public Action BuildingCheckStage1(Handle hTimer, any ref)
{
	int ent = EntRefToEntIndex(ref);
	if (IsTrackedEntityIndex(ent) && IsValidEntity(ent))
	{
		CreateTimer(0.1, BuildingCheckStage2, ref, TIMER_REPEAT | TIMER_NO_MAPCHANGE);
	}
	return Plugin_Continue;
}

void SetAmplifierHealth(int ent, int health)
{
	SetEntProp(ent, Prop_Send, "m_iMaxHealth", health);
	char sHealth[16];
	IntToString(health, sHealth, sizeof(sHealth));
	SetVariantString(sHealth);
	AcceptEntityInput(ent, "SetHealth");
}

public Action BuildingCheckStage2(Handle hTimer, any ref)
{
	int ent = EntRefToEntIndex(ref);
	if (!IsTrackedEntityIndex(ent) || !IsValidEntity(ent)) return Plugin_Stop;
	if (BuildingRef[ent] != ref) return Plugin_Stop;

	if (!AmplifierOn[ent])
	{
		if (!IsAmplifierConstructionComplete(ent))
			return Plugin_Continue;

		AmplifierOn[ent] = true;
		SetEntProp(ent, Prop_Send, "m_iUpgradeLevel", 1);
		SetEntProp(ent, Prop_Send, "m_iHighestUpgradeLevel", 1);
		SetAmplifierActiveVisualState(ent);

		SetAmplifierHealth(ent, AMPLIFIER_HEALTH);

		SetEntProp(ent, Prop_Send, "m_nSkin", GetEntProp(ent, Prop_Send, "m_nSkin") - 2);
		ReassertAmplifierRuntimeState(ent);
		EmitSoundToAll(
			AMPLIFIER_CONSTRUCTION_SOUND,
			ent,
			SNDCHAN_AUTO,
			SNDLEVEL_NORMAL);

		return Plugin_Continue;
	}

	ReassertAmplifierRuntimeState(ent);

	return Plugin_Continue;
}

void CheckSapper(int ent)
{
	if (IsTrackedEntityIndex(ent) && IsValidEntity(ent))
	{
		CreateTimer(0.5, SapperCheckStage1, EntIndexToEntRef(ent), TIMER_NO_MAPCHANGE);
	}
}

public Action SapperCheckStage1(Handle hTimer, any ref)
{
	int ent = EntRefToEntIndex(ref);
	if (ent > 0 && IsValidEntity(ent))
	{
		char classname[64];
		GetEdictClassname(ent, classname, sizeof(classname));
		if (StrEqual(classname, BUILDING_SAPPER))
		{
			int maxEntities = GetTrackedEntityLimit();
			for (int i = 1; i < maxEntities; i++)
			{
				int ampref = BuildingRef[i];
				int ampent = EntRefToEntIndex(ampref);
				if (IsTrackedEntityIndex(ampent) && IsValidEntity(ampent) && GetEntProp(ampent, Prop_Send, "m_bHasSapper") == 1 && !AmplifierSapped[ampent])
				{
					AmplifierSapped[ampent] = true;
					CreateTimer(0.5, SapperCheckStage2, ampref, TIMER_REPEAT | TIMER_NO_MAPCHANGE);
					break;
				}
			}
		}
	}
	return Plugin_Continue;
}

public Action SapperCheckStage2(Handle hTimer, any ref)
{
	int ent = EntRefToEntIndex(ref);
	if (ent <= 0 || !IsValidEntity(ent)) return Plugin_Stop;

	if (GetEntProp(ent, Prop_Send, "m_bHasSapper") == 0 && AmplifierSapped[ent])
	{
		AmplifierSapped[ent] = false;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

stock bool AddAmplifierEffect(int client)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
        return false;

    StopAmplifierEffect(client, false);

	float effectLength = GetAmplifierEffectLength();
	TF2ConchNoSpeed_AddRegenBuff(client, effectLength, client);
    // Apply to first 3 slots
    for (int slot = 0; slot < 3; slot++)
    {
        int weapon = GetPlayerWeaponSlot(client, slot);
        if (weapon > MaxClients && IsValidEntity(weapon))
        {
			float factor_reloadrate = 0.60;
            int defIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
			if (defIndex == BEGGARS_BAZOOKA)
			{
				factor_reloadrate = 1.0;
			}
            //TF2Attrib_SetByName(weapon, ATTR_FIRE_RATE, factor_firerate);
	        TF2Attrib_SetByName(weapon, ATTR_RELOAD_RATE, factor_reloadrate);
        }
    }

    // Create a default length timer
    g_PlayerState[client].effectTimer = CreateTimer(effectLength, Timer_RemoveAmplifierEffect, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	return true;
}

void RemoveAmplifierWeaponEffects(int client)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return;

	TF2ConchNoSpeed_RemoveRegenBuff(client);

	for (int slot = 0; slot < 3; slot++)
	{
		int weapon = GetPlayerWeaponSlot(client, slot);
		if (weapon <= MaxClients || !IsValidEntity(weapon))
			continue;

		int defIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
		if (defIndex == BEGGARS_BAZOOKA)
		{
			//TF2Attrib_SetByName(weapon, ATTR_FIRE_RATE, 0.30);
			TF2Attrib_SetByName(weapon, ATTR_RELOAD_RATE, 1.30);
		}
		else
		{
			//TF2Attrib_RemoveByName(weapon, ATTR_FIRE_RATE);
			TF2Attrib_RemoveByName(weapon, ATTR_RELOAD_RATE);
		}
	}
}

void StopAmplifierEffect(int client, bool removeWeaponEffects = true)
{
	if (client < 1 || client > MaxClients)
		return;

	bool hadEffect = g_PlayerState[client].effectTimer != INVALID_HANDLE;
	if (g_PlayerState[client].effectTimer != INVALID_HANDLE)
	{
		delete g_PlayerState[client].effectTimer;
		g_PlayerState[client].effectTimer = INVALID_HANDLE;
	}

	if (removeWeaponEffects && hadEffect)
	{
		RemoveAmplifierWeaponEffects(client);
	}
}

public Action Timer_RemoveAmplifierEffect(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && client <= MaxClients)
    {
		if (g_PlayerState[client].effectTimer == timer)
		{
			g_PlayerState[client].effectTimer = INVALID_HANDLE;
			RemoveAmplifierWeaponEffects(client);
		}
    }
    return Plugin_Stop;
}

stock bool ClientHasAmplifierAttribute(int client, const char[] attribute)
{
    if (!Client_IsInGame(client))
        return false;

    for (int slot = AMPLIFIER_PDA_SLOT_FIRST; slot <= AMPLIFIER_PDA_SLOT_LAST; slot++)
    {
        int weapon = GetPlayerWeaponSlot(client, slot);
        if (weapon <= MaxClients || !IsValidEntity(weapon))
        {
            continue;
        }

        if (TF2CustAttr_GetInt(weapon, attribute) != 0)
        {
            return true;
        }
    }

    return false;
}

stock bool CheckAmpAttributesDisp(int client)
{
    return ClientHasAmplifierAttribute(client, "amplifier attributes");
}

stock bool CheckAmpAttributesSentry(int client)
{
    return ClientHasAmplifierAttribute(client, "amplifier attributes sentry");
}

void ConvertAllAmplifiersToBuildings()
{
	int maxEntities = GetTrackedEntityLimit();
	for (int i = 1; i < maxEntities; i++)
	{
		int ent = EntRefToEntIndex(BuildingRef[i]);
		if (IsTrackedEntityIndex(ent) && IsValidEntity(ent) && AmplifierOn[ent])
		{
			char buildingClass[64];
			GetEdictClassname(ent, buildingClass, sizeof(buildingClass));

			AmplifierOn[ent] = false;
			StopAmplifierIdleSound(ent);
			SetEntProp(ent, Prop_Send, "m_bDisabled", 0);
			char modelname[128];
			if (IsDispenserClass(buildingClass))
				Format(modelname, sizeof(modelname), "models/buildables/dispenser.mdl");
			else if (IsSentryClass(buildingClass))
				Format(modelname, sizeof(modelname), "models/buildables/sentry1.mdl");
			else
				continue;

			SetEntityModel(ent, modelname);
			SetEntPropFloat(ent, Prop_Send, "m_flModelScale", 1.0);
			ResetAmplifierBuildingState(ent);
		}
	}
}

// Natives
public any Native_ControlAmplifier(Handle plugin, int numParams)
{
	NativeControl = view_as<bool>(GetNativeCell(1));
	return 0;
}

public any Native_SetAmplifierDisp(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidPlayerIndex(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);

	g_PlayerState[client].useDispenser = view_as<bool>(GetNativeCell(2));

	float distance = view_as<float>(GetNativeCell(3));
	NativeDistanceDisp[client] = (distance < 0.0) ? GetConVarFloat(cvarDistance) : distance;

	TFCond condition = view_as<TFCond>(GetNativeCell(4));
	NativeConditionDisp[client] = (condition < TFCond_Slowed) ? DefaultCondition : condition;
	return 0;
}

public any Native_SetAmplifierSentry(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidPlayerIndex(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);

	g_PlayerState[client].useSentry = view_as<bool>(GetNativeCell(2));

	float distance = view_as<float>(GetNativeCell(3));
	NativeDistanceSentry[client] = (distance < 0.0) ? GetConVarFloat(cvarDistance) : distance;

	TFCond condition = view_as<TFCond>(GetNativeCell(4));
	NativeConditionSentry[client] = (condition < TFCond_Slowed) ? DefaultCondition : condition;
	return 0;
}

public any Native_HasAmplifier(Handle plugin, int numParams)
{
	int count = 0;
	int client = GetNativeCell(1);
	int maxEntities = GetTrackedEntityLimit();
	for (int i = 1; i < maxEntities; i++)
	{
		int ampref = BuildingRef[i];
		int ampent = EntRefToEntIndex(ampref);
		if (IsTrackedEntityIndex(ampent) && IsValidEntity(ampent) && GetEntPropEnt(ampent, Prop_Send, "m_hBuilder") == client)
			count++;
	}
	return count;
}

public any Native_ConvertToAmplifier(Handle plugin, int numParams)
{
	int ent = GetNativeCell(1);
	if (!IsTrackedEntityIndex(ent) || !IsValidEntity(ent)) return 0;

	int client = GetNativeCell(2);
	if (!IsValidPlayerIndex(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);

	char buildingClass[64];
	GetEdictClassname(ent, buildingClass, sizeof(buildingClass));
	bool isDispenser = IsDispenserClass(buildingClass);

	bool saveDisp = g_PlayerState[client].useDispenser;
	bool saveSentry = g_PlayerState[client].useSentry;
	float saveDistDisp = NativeDistanceDisp[client];
	float saveDistSentry = NativeDistanceSentry[client];
	TFCond saveCondDisp = NativeConditionDisp[client];
	TFCond saveCondSentry = NativeConditionSentry[client];
	int savePercentDisp = NativePercentDisp[client];
	int savePercentSentry = NativePercentSentry[client];

	float distance = view_as<float>(GetNativeCell(3));
	TFCond condition = view_as<TFCond>(GetNativeCell(4));
	int percent = GetNativeCell(5);

	if (isDispenser)
	{
		if (distance >= 0.0) NativeDistanceDisp[client] = distance;
		if (condition >= TFCond_Slowed) NativeConditionDisp[client] = condition;
		if (percent >= 0) NativePercentDisp[client] = percent;
		g_PlayerState[client].useDispenser = true;
	}
	else
	{
		if (distance >= 0.0) NativeDistanceSentry[client] = distance;
		if (condition >= TFCond_Slowed) NativeConditionSentry[client] = condition;
		if (percent >= 0) NativePercentSentry[client] = percent;
		g_PlayerState[client].useSentry = true;
	}

	CheckBuilding(ent);

	NativeConditionDisp[client] = saveCondDisp;
	NativeConditionSentry[client] = saveCondSentry;
	NativeDistanceDisp[client] = saveDistDisp;
	NativeDistanceSentry[client] = saveDistSentry;
	NativePercentDisp[client] = savePercentDisp;
	NativePercentSentry[client] = savePercentSentry;
	g_PlayerState[client].useDispenser = saveDisp;
	g_PlayerState[client].useSentry = saveSentry;
	return 0;
}

public any Native_WouldReplaceBuilding(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int objectType = GetNativeCell(2);
	return WouldObjectTypeBecomeAmplifier(client, objectType);
}

void DealElectricDamage(int client, int builder, const float amplifierPos[3], float damage, float maxDistance)
{
    if (!Client_IsInGame(client) || !IsPlayerAlive(client) || maxDistance <= 0.0)
        return;

    float clientPos[3];
    GetEntPropVector(client, Prop_Send, "m_vecOrigin", clientPos);

    float dist = GetVectorDistance(clientPos, amplifierPos);
    if (dist > maxDistance)
        return;

    // Damage scales inversely with distance (closer = more damage).
    float damageFinal = damage * (1.0 - (dist / maxDistance));
    if (damageFinal < 0.0) damageFinal = 0.0;

	int attacker = Client_IsInGame(builder) ? builder : 0;
    SDKHooks_TakeDamage(client, attacker, attacker, damageFinal, DMG_SHOCK);
}


void CreateAmplifierExplosion(float position[3], int attacker = 0, bool entwasbuilding = false, int damage = 0, float radiusUnits = 0.0)
{
	if (entwasbuilding) return;
    int explosion = CreateEntityByName("env_explosion");
    if (explosion == -1) {
        return;
    }

    if (radiusUnits <= 0.0)
        radiusUnits = GetConVarFloat(cvarDistance);
	int radius = RoundFloat(radiusUnits);
    char sDamage[16], sRadius[16];
    IntToString(damage, sDamage, sizeof(sDamage));
    IntToString(radius, sRadius, sizeof(sRadius));

    // Set explosion properties
    DispatchKeyValue(explosion, "iMagnitude", sDamage);
    DispatchKeyValue(explosion, "iRadiusOverride", sRadius);
    DispatchKeyValue(explosion, "spawnflags", "828");

    TeleportEntity(explosion, position, NULL_VECTOR, NULL_VECTOR);

    // Set attacker if valid
    bool validAttacker = Client_IsInGame(attacker);
    if (validAttacker)
    {
        SetEntPropEnt(explosion, Prop_Send, "m_hOwnerEntity", attacker);
    }

    DispatchSpawn(explosion);
    g_bAmplifierExplosionActive = true;
    AcceptEntityInput(explosion, "Explode");
    CreateTimer(0.2, Timer_ClearAmplifierExplosionActive, _, TIMER_NO_MAPCHANGE);

	// Create visual explosion effect
	TE_SetupExplosion(position, 0, 10.0, 1, 0, radius, 5000);
	TE_SendToAll();

	int particle = CreateEntityByName("info_particle_system");
	if (particle != -1)
	{
		int team = validAttacker ? GetClientTeam(attacker) : 0;
		TeleportEntity(particle, position, NULL_VECTOR, NULL_VECTOR);
		char storedParticle[64];
		strcopy(storedParticle, sizeof(storedParticle), "powerup_supernova_explode_red_spikes");
		if (team == 2)
		{
			strcopy(storedParticle, sizeof(storedParticle), "powerup_supernova_explode_blue_spikes");
		}
		DispatchKeyValue(particle, "effect_name", storedParticle);
		DispatchKeyValue(particle, "start_active", "0");
		DispatchSpawn(particle);
		ActivateEntity(particle);
		AcceptEntityInput(particle, "Start");
		CreateTimer(2.0, Timer_RemoveEntity, EntIndexToEntRef(particle), TIMER_NO_MAPCHANGE);
	}

	// Clean up explosion entity
	CreateTimer(0.1, Timer_RemoveEntity, EntIndexToEntRef(explosion), TIMER_NO_MAPCHANGE);
}

public Action Timer_ClearAmplifierExplosionActive(Handle timer)
{
	g_bAmplifierExplosionActive = false;
	return Plugin_Stop;
}

public Action Timer_RemoveEntity(Handle timer, int ref)
{
    int entity = EntRefToEntIndex(ref);
    if (entity != INVALID_ENT_REFERENCE && entity > MaxClients && IsValidEntity(entity))
    {
        RemoveEntity(entity);
    }
    return Plugin_Stop;
}

void KillAllSentries()
{
    int maxEnts = GetTrackedEntityLimit();
    char classname[64];
    for (int ent = MaxClients + 1; ent < maxEnts; ent++)
    {
        if (!IsValidEntity(ent))
            continue;

        GetEdictClassname(ent, classname, sizeof(classname));
        bool isSentry = IsSentryClass(classname);
        if (isSentry)
        {
            AcceptEntityInput(ent, "Kill");
        }
    }
}

public void killAllSentries()
{
    KillAllSentries();
}

public Action Command_KillSentries(int client, int args)
{
    KillAllSentries();

    if (client > 0 && IsClientInGame(client))
    {
        CPrintToChat(client, "{gold}[Amplifier]{default} All sentries have been destroyed.");
    }
    else
    {
        PrintToServer("[Amplifier] All sentries have been destroyed.");
    }

    return Plugin_Handled;
}

// Ray Trace
#tryinclude <raytrace>
#if !defined _raytrace_included
stock bool TraceTargetIndex(int client, int target, float clientLoc[3], float targetLoc[3])
{
	targetLoc[2] += 50.0;
	TR_TraceRayFilter(clientLoc, targetLoc, MASK_SOLID, RayType_EndPoint, TraceRayDontHitSelf, client);
	return (!TR_DidHit() || TR_GetEntityIndex() == target);
}

public bool TraceRayDontHitSelf(int entity, int mask, any data)
{
	return (entity != data);
}
#endif
