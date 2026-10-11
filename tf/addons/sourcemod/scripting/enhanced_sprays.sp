// SPDX-License-Identifier: GPL-3.0-or-later
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <enhanced_sprays>

#define ENHANCED_SPRAYS_VERSION "1.0.0"
public Plugin myinfo = {
    name = "enhanced_sprays", author = "Hombre, Dragon",
    description = "Unified spray switching, resizing, tracing and moderation",
    version = ENHANCED_SPRAYS_VERSION,
    url = "https://github.com/eltanschauung/Kogasatopia"
};

#include "enhanced_sprays/switching.sp"
// Keep upstream Spray Tracer's proven database/UI code in its own module.
// Original authors: Nican132, CptMoore and Lebson506th.
#pragma newdecls optional
#include "enhanced_sprays/moderation.sp"
#pragma newdecls required
#include "enhanced_sprays/resizing.sp"

bool g_EnhancedStarted;
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int maxlen) {
    // Reject before dependency autoload whenever the legacy library is present.
    if (LibraryExists("instant_sprays") || LibraryExists("latedl")) {
        strcopy(error, maxlen, "Retire legacy spray extensions and cold-restart before activation.");
        return APLRes_Failure;
    }
    Moderation_AskLoad(myself, late, error, maxlen);
    RegPluginLibrary("enhanced_sprays_plugin");
    return APLRes_Success;
}

void RejectLegacyOwners() {
    if (LibraryExists("instant_sprays") || LibraryExists("latedl"))
        SetFailState("Legacy spray extensions still own hooks; cold-restart after retirement.");
    // Refuse conflicting hook ownership; never unload a plugin on the admin's behalf.
    char filename[PLATFORM_MAX_PATH];
    Handle iterator = GetPluginIterator();
    bool conflict;
    while (MorePlugins(iterator)) {
        Handle plugin = ReadPlugin(iterator);
        GetPluginFilename(plugin, filename, sizeof(filename));
        if (StrEqual(filename, "instant_sprays.smx") || StrEqual(filename, "resizablesprays.smx")
            || StrEqual(filename, "spraytrace.smx")) {
            conflict = true;
            break;
        }
    }
    delete iterator;
    if (conflict)SetFailState("Retire %s before activating enhanced_sprays; see rollout README.", filename);
    static const char oldExtensions[][] = {
        "instant_sprays.ext", "instant_sprays.ext.2.tf2", "latedl.ext", "latedl.ext.2.tf2"
    };
    for (int i = 0; i < sizeof(oldExtensions); i++)
        if (GetExtensionFileStatus(oldExtensions[i], filename, sizeof(filename)) >= 0)
            SetFailState("Retire instant_sprays and latedl extensions and cold-restart before activation.");
}

public void OnPluginStart() {
    RejectLegacyOwners();
    Switching_Start();
    Moderation_Start();
    Resize_Start();
    CreateConVar("sm_enhanced_sprays_version", ENHANCED_SPRAYS_VERSION,
        "enhanced_sprays version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    AutoExecConfig(true, "enhanced_sprays");
    g_EnhancedStarted = true;
}
public void OnMapStart() {
    if (!g_EnhancedStarted)return;
    Switching_MapStart();
    Moderation_MapStart();
    Resize_Reset();
}
public void OnMapEnd() {
    if (!g_EnhancedStarted)return;
    Resize_Reset();
    Switching_MapEnd();
}
public void OnPluginEnd() {
    if (!g_EnhancedStarted)return;
    Resize_Stop();
    Switching_Stop();
    Moderation_Stop();
}
public void OnClientPutInServer(int client) {
    if (!g_EnhancedStarted)return;
    Resize_ClientJoin(client);
    Switching_ClientJoin(client);
}
public void OnClientPostAdminCheck(int client) {
    if (g_EnhancedStarted)Moderation_ClientReady(client);
}
public void OnClientDisconnect(int client) {
    if (!g_EnhancedStarted)return;
    Switching_ClientLeave(client);
    Moderation_ClientLeave(client);
    Resize_ClientLeave(client);
}
public void OnPluginPauseChange(bool paused) {
    if (!g_EnhancedStarted)return;
    Switching_Pause(paused);
    if (paused)Resize_Reset();
}
public void ESprays_OnSprayChanged(int client) {
    if (!g_EnhancedStarted)return;
    Moderation_SprayChanged(client);
    Resize_SprayChanged(client);
}
public void ESprays_OnAssetReady(int client, int token, const char[] path, bool success) {
    if (g_EnhancedStarted)Resize_ProcessPending(client, token);
}
