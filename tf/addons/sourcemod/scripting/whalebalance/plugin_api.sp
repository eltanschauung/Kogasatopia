void WhaleBalance_RegisterPluginApi()
{
    RegPluginLibrary("autobalance_4teams");
    RegPluginLibrary("whalebalance");
    CreateNative("Autobalance_HasPendingTeamSwap", Native_HasPendingTeamSwap);
    CreateNative("TeamBalance_IsBusy", Native_TeamBalanceIsBusy);
    CreateNative("TeamBalance_IsScrambleCooldownActive", Native_TeamBalanceIsScrambleCooldownActive);
    CreateNative("TeamBalance_BeginScrambleVote", Native_TeamBalanceBeginScrambleVote);
    CreateNative("TeamBalance_EndScrambleVote", Native_TeamBalanceEndScrambleVote);
    CreateNative("TeamBalance_BeginScramble", Native_TeamBalanceBeginScramble);
    CreateNative("TeamBalance_CancelScramble", Native_TeamBalanceCancelScramble);
    CreateNative("TeamBalance_FinishScramble", Native_TeamBalanceFinishScramble);
    CreateNative("TeamBalance_IsScrambleCandidate", Native_TeamBalanceIsScrambleCandidate);
    CreateNative("TeamBalance_IsVolunteer", Native_TeamBalanceIsVolunteer);
    CreateNative("TeamBalance_IsVolunteerEligible", Native_TeamBalanceIsVolunteerEligible);
    CreateNative("TeamBalance_HasScramblePurchaseImmunity", Native_TeamBalanceHasScramblePurchaseImmunity);
    CreateNative("TeamBalance_ConsumeScramblePurchaseImmunity", Native_TeamBalanceConsumeScramblePurchaseImmunity);
    CreateNative("TeamBalance_MoveScramblePair", Native_TeamBalanceMoveScramblePair);
    CreateNative("TeamBalance_QueueRespawn", Native_TeamBalanceQueueRespawn);

    MarkNativeAsOptional("FilterAlerts_MarkAutobalance");
    MarkNativeAsOptional("FilterAlerts_SuppressTeamAlertWindow");
    MarkNativeAsOptional("Announcers_IsGroupEnabled");
    MarkNativeAsOptional("Clans_GetSameTeamClanMemberCount");
    MarkNativeAsOptional("PointsStore_ApplyBonusPoints");
    MarkNativeAsOptional("PointsStore_GetRewardAmount");
    MarkNativeAsOptional("PointsStore_RefundBonusPoints");
    MarkNativeAsOptional("PointsStore_AreBonusPointsLoaded");
    MarkNativeAsOptional("PointsStore_GetBonusPoints");
    MarkNativeAsOptional("PointsStore_SpendBonusPoints");
    MarkNativeAsOptional("PointsStore_HasPurchase");
    MarkNativeAsOptional("PointsStore_ConsumePurchaseUse");
    MarkNativeAsOptional("SaySounds_PlayCommand");
    MarkNativeAsOptional("Filters_GetChatName");
    MarkNativeAsOptional("WhaleTracker_AreStatsLoaded");
    MarkNativeAsOptional("WhaleTracker_GetWhalePoints");
}
