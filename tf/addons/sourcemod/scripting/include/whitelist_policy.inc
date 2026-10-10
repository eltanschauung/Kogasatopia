// SPDX-License-Identifier: GPL-3.0-or-later
#if defined _whitelist_policy_included
    #endinput
#endif
#define _whitelist_policy_included
enum WhitelistPolicyReason {
    WhitelistPolicy_Allowed,
    WhitelistPolicy_ItemDenied,
    WhitelistPolicy_DemoCombination
};
#define WHITELIST_CLASS_WEARABLE 1
#define WHITELIST_CLASS_SHIELD 2
#define WHITELIST_CLASS_SWORD 4
native void WhitelistPolicy_BeginPolicy(bool defaultAllowed);
native void WhitelistPolicy_RegisterDefinition(int index, int classification, bool allowed);
native void WhitelistPolicy_CommitPolicy();
native void WhitelistPolicy_ResetTransactions();
native void WhitelistPolicy_BeginInventory(int client);
native void WhitelistPolicy_EndInventory(int client);
native WhitelistPolicyReason WhitelistPolicy_Evaluate(int client, int playerClass, int slot, Address &replacement);
native void WhitelistPolicy_GetStats(int stats[5]);

// Cold resolver returns a serial-checked entity reference containing m_Item,
// or INVALID_ENT_REFERENCE to retain the engine/whitelist result. Do not bind
// while a SourcePawn GetLoadoutItem detour is installed: ownership is exclusive.
typedef WeaponsLoadoutResolver = function int(int client, int playerClass, int slot);
typedef WeaponsLoadoutNotice = function void(int client, WhitelistPolicyReason reason);
native void WeaponsLoadout_Bind(WeaponsLoadoutResolver resolver, WeaponsLoadoutNotice notice);
native void WeaponsLoadout_Unbind();
native void WeaponsLoadout_PublishSelection(int client, int playerClass, const bool selected[7]);
native void WeaponsLoadout_InvalidateClient(int client);
native void WeaponsLoadout_GetStats(int stats[6]);
public Extension __ext_whitelist_policy = {
    name = "TF2 Whitelist Policy",
    file = "whitelist_policy.ext",
    autoload = 1,
    required = 1
};
