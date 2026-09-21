/**
 * Embedded SourceMod BaseComm provider.
 *
 * The command/menu/native implementation remains split into the upstream
 * BaseComm source modules below, but compiles into filters.smx.  This file owns
 * lifecycle integration and the one-time standalone-plugin migration.
 */

#define FILTERS_BASECOMM_FILE "basecomm.smx"
#define FILTERS_BASECOMM_KOG_FILE "basecomm_kog.smx"

enum struct BaseCommPlayerState
{
    bool isMuted;
    bool isGagged;
    int gagTarget;
}

BaseCommPlayerState playerstate[MAXPLAYERS + 1];

ConVar g_Cvar_Deadtalk = null;
ConVar g_Cvar_Alltalk = null;
bool g_Hooked = false;
TopMenu hTopMenu = null;
bool g_BaseCommMigrationScheduled = false;

#include "filters/basecomm/gag.sp"
#include "filters/basecomm/natives.sp"
#include "filters/basecomm/forwards.sp"

static bool FiltersBaseComm_MoveStandaloneFile(
    const char[] pluginFile,
    char[] error,
    int errorLength)
{
    char enabledPath[PLATFORM_MAX_PATH];
    char disabledPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, enabledPath, sizeof(enabledPath), "plugins/%s", pluginFile);
    if (!FileExists(enabledPath))
    {
        return true;
    }

    BuildPath(Path_SM, disabledPath, sizeof(disabledPath), "plugins/disabled/%s", pluginFile);
    if (FileExists(disabledPath))
    {
        BuildPath(
            Path_SM,
            disabledPath,
            sizeof(disabledPath),
            "plugins/disabled/merged-%d-%08x-%s",
            GetTime(),
            GetURandomInt(),
            pluginFile);
    }

    if (!RenameFile(disabledPath, enabledPath))
    {
        Format(error, errorLength, "Could not move %s into plugins/disabled", pluginFile);
        return false;
    }

    LogMessage("[Filters] Disabled standalone BaseComm binary %s.", pluginFile);
    return true;
}

bool FiltersBaseComm_PrepareMergedProvider(Handle self, char[] error, int errorLength)
{
    static const char standaloneFiles[][] =
    {
        FILTERS_BASECOMM_FILE,
        FILTERS_BASECOMM_KOG_FILE
    };

    bool loaded[sizeof(standaloneFiles)];
    bool foundLoadedProvider = false;
    g_BaseCommMigrationScheduled = false;

    for (int i = 0; i < sizeof(standaloneFiles); i++)
    {
        Handle plugin = FindPluginByFile(standaloneFiles[i]);
        loaded[i] = plugin != INVALID_HANDLE && plugin != self;
        foundLoadedProvider = foundLoadedProvider || loaded[i];

        if (!FiltersBaseComm_MoveStandaloneFile(standaloneFiles[i], error, errorLength))
        {
            return false;
        }
    }

    if (!foundLoadedProvider)
    {
        return true;
    }

    for (int i = 0; i < sizeof(standaloneFiles); i++)
    {
        if (loaded[i])
        {
            ServerCommand("sm plugins unload \"%s\"", standaloneFiles[i]);
        }
    }

    char selfFile[PLATFORM_MAX_PATH];
    GetPluginFilename(self, selfFile, sizeof(selfFile));
    ServerCommand("sm plugins load \"%s\"", selfFile);
    g_BaseCommMigrationScheduled = true;

    Format(
        error,
        errorLength,
        "Standalone BaseComm is being disabled; filters.smx will reload as its replacement");
    return false;
}

bool FiltersBaseComm_MigrationScheduled()
{
    return g_BaseCommMigrationScheduled;
}

void FiltersBaseComm_RegisterNatives()
{
    CreateNative("BaseComm_IsClientGagged", Native_IsClientGagged);
    CreateNative("BaseComm_IsClientMuted", Native_IsClientMuted);
    CreateNative("BaseComm_SetClientGag", Native_SetClientGag);
    CreateNative("BaseComm_SetClientMute", Native_SetClientMute);
    RegPluginLibrary("basecomm");
}

void FiltersBaseComm_Initialize()
{
    LoadTranslations("basecomm.phrases");

    // Voice flags live on the client and survive a plugin handoff. Recover
    // that state so a standalone BaseComm mute can still be undone afterward.
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            playerstate[client].isMuted =
                (GetClientListeningFlags(client) & VOICE_MUTED) != 0;
        }
    }

    g_Cvar_Deadtalk = CreateConVar(
        "sm_deadtalk",
        "0",
        "Controls how dead communicate. 0 - Off. 1 - Dead players ignore teams. 2 - Dead players talk to living teammates.",
        0,
        true,
        0.0,
        true,
        2.0);
    g_Cvar_Alltalk = FindConVar("sv_alltalk");

    RegAdminCmd("sm_mute", Command_Mute, ADMFLAG_CHAT, "sm_mute <player> - Removes a player's ability to use voice.");
    RegAdminCmd("sm_gag", Command_Gag, ADMFLAG_CHAT, "sm_gag <player> - Removes a player's ability to use chat.");
    RegAdminCmd("sm_silence", Command_Silence, ADMFLAG_CHAT, "sm_silence <player> - Removes a player's ability to use voice or chat.");
    RegAdminCmd("sm_unmute", Command_Unmute, ADMFLAG_CHAT, "sm_unmute <player> - Restores a player's ability to use voice.");
    RegAdminCmd("sm_ungag", Command_Ungag, ADMFLAG_CHAT, "sm_ungag <player> - Restores a player's ability to use chat.");
    RegAdminCmd("sm_unsilence", Command_Unsilence, ADMFLAG_CHAT, "sm_unsilence <player> - Restores a player's ability to use voice and chat.");

    g_Cvar_Deadtalk.AddChangeHook(ConVarChange_Deadtalk);
    if (g_Cvar_Alltalk != null)
    {
        g_Cvar_Alltalk.AddChangeHook(ConVarChange_Alltalk);
    }

    if (g_Cvar_Deadtalk.IntValue != 0)
    {
        HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
        HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
        g_Hooked = true;
    }

    TopMenu topmenu;
    if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null))
    {
        OnAdminMenuReady(topmenu);
    }
}

void FiltersBaseComm_ResetClient(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    playerstate[client].isGagged = false;
    playerstate[client].isMuted = false;
    playerstate[client].gagTarget = 0;
}

public bool OnClientConnect(int client, char[] rejectMessage, int maxLength)
{
    FiltersBaseComm_ResetClient(client);
    return true;
}

bool FiltersBaseComm_IsClientGagged(int client)
{
    return client > 0
        && client <= MaxClients
        && IsClientInGame(client)
        && playerstate[client].isGagged;
}

public void OnAdminMenuReady(Handle topMenuHandle)
{
    TopMenu topmenu = TopMenu.FromHandle(topMenuHandle);
    if (topmenu == hTopMenu)
    {
        return;
    }

    hTopMenu = topmenu;
    TopMenuObject playerCommands = hTopMenu.FindCategory(ADMINMENU_PLAYERCOMMANDS);
    if (playerCommands != INVALID_TOPMENUOBJECT)
    {
        hTopMenu.AddItem("sm_gag", AdminMenu_Gag, playerCommands, "sm_gag", ADMFLAG_CHAT);
    }
}

public void ConVarChange_Deadtalk(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (g_Cvar_Deadtalk.IntValue != 0 && !g_Hooked)
    {
        HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
        HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
        g_Hooked = true;
    }
    else if (g_Cvar_Deadtalk.IntValue == 0 && g_Hooked)
    {
        UnhookEvent("player_spawn", Event_PlayerSpawn);
        UnhookEvent("player_death", Event_PlayerDeath);
        g_Hooked = false;
    }
}

public void ConVarChange_Alltalk(ConVar convar, const char[] oldValue, const char[] newValue)
{
    int mode = g_Cvar_Deadtalk.IntValue;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client))
        {
            continue;
        }

        if (playerstate[client].isMuted)
        {
            SetClientListeningFlags(client, VOICE_MUTED);
        }
        else if (g_Cvar_Alltalk.BoolValue)
        {
            SetClientListeningFlags(client, VOICE_NORMAL);
        }
        else if (!IsPlayerAlive(client))
        {
            if (mode == 1)
            {
                SetClientListeningFlags(client, VOICE_LISTENALL);
            }
            else if (mode == 2)
            {
                SetClientListeningFlags(client, VOICE_TEAM);
            }
        }
    }
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client == 0)
    {
        return;
    }

    SetClientListeningFlags(
        client,
        playerstate[client].isMuted ? VOICE_MUTED : VOICE_NORMAL);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client == 0)
    {
        return;
    }

    if (playerstate[client].isMuted)
    {
        SetClientListeningFlags(client, VOICE_MUTED);
        return;
    }

    if (g_Cvar_Alltalk != null && g_Cvar_Alltalk.BoolValue)
    {
        SetClientListeningFlags(client, VOICE_NORMAL);
        return;
    }

    int mode = g_Cvar_Deadtalk.IntValue;
    if (mode == 1)
    {
        SetClientListeningFlags(client, VOICE_LISTENALL);
    }
    else if (mode == 2)
    {
        SetClientListeningFlags(client, VOICE_TEAM);
    }
}
