public void OnLotteryDisabledConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (IsLotteryEnabled())
    {
        EnsureActiveLottery();
        return;
    }

    ClearLocalLotteryState();
}

public void OnLotteryEqualTicketValueChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (g_CurrentLotteryEqual)
    {
        BeginEqualLotteryRefunds();
    }
}

void LogLotteryCreditEvent(const char[] reason, const char[] steamId, int amount, int lotteryId, int client, int balanceAfter)
{
    if (!IsPointsEventLoggingEnabled())
    {
        return;
    }

    char safeReason[64];
    char safeSteamId[32];
    char clientName[MAX_NAME_LENGTH];
    char clientClass[16];
    strcopy(safeReason, sizeof(safeReason), reason);
    strcopy(safeSteamId, sizeof(safeSteamId), steamId);
    SanitizeLogField(safeReason, sizeof(safeReason));
    SanitizeLogField(safeSteamId, sizeof(safeSteamId));

    if (client > 0)
    {
        char ignoredSteamId[32];
        GetClientLogIdentity(client, ignoredSteamId, sizeof(ignoredSteamId), clientName, sizeof(clientName));
        GetClientLogClass(client, clientClass, sizeof(clientClass));
    }
    else
    {
        strcopy(clientName, sizeof(clientName), "offline");
        strcopy(clientClass, sizeof(clientClass), "none");
    }

    LogPointsStoreEvent(
        "event=lottery_credit|time=%d|reason=%s|lottery_id=%d|client=%d|steamid64=%s|name=\"%s\"|class=%s|amount=%d|balance_after=%d",
        GetTime(),
        safeReason,
        lotteryId,
        client,
        safeSteamId,
        clientName,
        clientClass,
        amount,
        balanceAfter);
}

void RecordLotteryWelfarePoolCredit(int amount, int lotteryId)
{
    if (amount <= 0)
    {
        return;
    }

    if (QueueEconomyDelta(BP_ECONOMY_WELFARE_POOL_KEY, amount))
    {
        g_WelfarePoolBalance += amount;
    }

    LogEconomyEvent("lottery_welfare_pool", 0, amount, "lottery_tax", lotteryId, g_WelfarePoolBalance, g_CumulativeSpentBalance);
}
