StringMap g_StimulusPendingSenders;
int g_StimulusSequence;

void Stimulus_OnPluginStart()
{
    g_StimulusPendingSenders = new StringMap();
    RegAdminCmd("sm_stimulus", Command_Stimulus, ADMFLAG_GENERIC,
        "sm_stimulus <amount> \"<title>\" - Mail a currency check to connected players.");
}

void Stimulus_OnPluginEnd()
{
    delete g_StimulusPendingSenders;
}

static bool Stimulus_ParseAmount(const char[] value, int &amount)
{
    amount = 0;
    if (!value[0])
    {
        return false;
    }

    for (int i = 0; value[i]; i++)
    {
        int digit = value[i] - '0';
        if (digit < 0 || digit > 9 || amount > (2147483647 - digit) / 10)
        {
            return false;
        }
        amount = amount * 10 + digit;
    }
    return amount > 0;
}

public Action Command_Stimulus(int client, int args)
{
    if (args != 2)
    {
        ReplyToCommand(client, "[Points Store] Usage: sm_stimulus <amount> \"<title>\"");
        return Plugin_Handled;
    }

    char amountText[512];
    char title[512];
    GetCmdArg(1, amountText, sizeof(amountText));
    GetCmdArg(2, title, sizeof(title));
    TrimString(title);
    int amount;
    if (!Stimulus_ParseAmount(amountText, amount))
    {
        ReplyToCommand(client, "[Points Store] Amount must be a positive whole number (maximum 2147483647).");
        return Plugin_Handled;
    }
    if (!title[0] || strlen(title) >= 128)
    {
        ReplyToCommand(client, "[Points Store] Title must contain 1 to 127 bytes; quote titles containing spaces.");
        return Plugin_Handled;
    }
    if (GetFeatureStatus(FeatureType_Native, "ServerMail_SendCurrency") != FeatureStatus_Available)
    {
        ReplyToCommand(client, "[Points Store] Server Mail is unavailable; no checks were sent.");
        return Plugin_Handled;
    }

    char contents[256];
    FormatEx(contents, sizeof(contents), "A stimulus check worth %d %s. Redeem the attachment to collect it.",
        amount, g_CurrencyShortLabel);
    int senderUserId = client > 0 ? GetClientUserId(client) : 0;
    int sequence = ++g_StimulusSequence;
    int nonce = GetURandomInt();
    int queued;
    int failed;
    for (int target = 1; target <= MaxClients; target++)
    {
        if (!Client_IsHumanInGame(target))
        {
            continue;
        }

        char steamId[KOGASA_STEAMID_MAX];
        if (!Kogasa_GetClientSteamId64(target, steamId, sizeof(steamId), true))
        {
            failed++;
            continue;
        }

        // Separate from Server Mail's ranked-stimulus deployment request keys.
        char requestKey[128];
        FormatEx(requestKey, sizeof(requestKey), "points_store:stimulus:%d:%d:%d:%s",
            GetTime(), nonce, sequence, steamId);
        g_StimulusPendingSenders.SetValue(requestKey, senderUserId);
        if (!ServerMail_SendCurrency(0, target, title, contents, amount, requestKey))
        {
            g_StimulusPendingSenders.Remove(requestKey);
            failed++;
            continue;
        }

        queued++;
        LogAction(client, target, "\"%L\" queued a stimulus check of %d %s for \"%L\": \"%s\".",
            client, amount, g_CurrencyShortLabel, target, title);
    }

    ReplyToCommand(client, "[Points Store] Queued \"%s\" (%d %s each) for %d connected players; %d failed.",
        title, amount, g_CurrencyShortLabel, queued, failed);
    return Plugin_Handled;
}

public void ServerMail_OnMailSendResult(const char[] requestKey, bool success, int mailId, bool newlyCreated)
{
    int senderUserId;
    if (!g_StimulusPendingSenders.GetValue(requestKey, senderUserId))
    {
        return;
    }
    g_StimulusPendingSenders.Remove(requestKey);
    if (success)
    {
        LogMessage("[points_store] Stimulus mail %d persisted (%s).", mailId, requestKey);
        return;
    }

    LogError("[points_store] Failed to persist stimulus check (%s).", requestKey);
    int client = senderUserId > 0 ? GetClientOfUserId(senderUserId) : 0;
    if (senderUserId == 0 || Client_IsInGame(client))
    {
        ReplyToCommand(client, "[Points Store] A stimulus check could not be saved; see the server error log.");
    }
}
