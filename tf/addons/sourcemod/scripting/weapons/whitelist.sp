// SPDX-License-Identifier: GPL-3.0-or-later
// Inspired by Sappykun's whitelist enabler plugin.
#include <whitelist_policy>

bool g_WeaponsWhitelistNoticePending[MAXPLAYERS + 1];
WhitelistPolicyReason g_WeaponsWhitelistNoticeReason[MAXPLAYERS + 1];

void WeaponsWhitelist_OnAllPluginsLoaded()
{
    if (!LibraryExists("whitelist_policy"))
        SetFailState("Whitelist Policy companion plugin is required");
    int stats[5];
    WhitelistPolicy_GetStats(stats);
    if (!stats[0]) SetFailState("Native whitelist policy is not initialized");
}

void WeaponsWhitelist_OnClientDisconnect(int client)
{
    g_WeaponsWhitelistNoticePending[client] = false;
    g_WeaponsWhitelistNoticeReason[client] = WhitelistPolicy_Allowed;
}

public void WeaponsWhitelist_QueueNotice(int client, WhitelistPolicyReason reason)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client)
        || reason == WhitelistPolicy_Allowed) return;
    // Preserve the priority of combo denial over ordinary item notices.
    if (reason == WhitelistPolicy_DemoCombination
        || g_WeaponsWhitelistNoticeReason[client] == WhitelistPolicy_Allowed)
        g_WeaponsWhitelistNoticeReason[client] = reason;
    if (!g_WeaponsWhitelistNoticePending[client])
    {
        g_WeaponsWhitelistNoticePending[client] = true;
        RequestFrame(WeaponsWhitelist_SendNotice, GetClientSerial(client));
    }
}

void WeaponsWhitelist_SendNotice(any serial)
{
    int client = GetClientFromSerial(serial);
    if (client <= 0 || !IsClientInGame(client)) return;
    g_WeaponsWhitelistNoticePending[client] = false;
    WhitelistPolicyReason reason = g_WeaponsWhitelistNoticeReason[client];
    g_WeaponsWhitelistNoticeReason[client] = WhitelistPolicy_Allowed;
    if (reason == WhitelistPolicy_DemoCombination)
        CPrintToChat(client, "{gold}[WhiteList]{default} Demoknight has been disabled on this server.");
    else if (reason == WhitelistPolicy_ItemDenied)
        CPrintToChat(client, "{gold}[WhiteList]{default} An item in your loadout is disabled on this server.");
}
