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
public Extension __ext_whitelist_policy = {
    name = "TF2 Whitelist Policy",
    file = "whitelist_policy.ext",
    autoload = 1,
    required = 1
};
