static const char g_LotteryColors[][] =
{
    "aliceblue", "antiquewhite", "aqua", "aquamarine", "azure", "beige", "bisque", "black",
    "blanchedalmond", "blue", "blueviolet", "brown", "burlywood", "cadetblue", "chartreuse",
    "chocolate", "coral", "cornflowerblue", "cornsilk", "crimson", "cyan", "darkblue", "darkcyan",
    "darkgoldenrod", "darkgray", "darkgrey", "darkgreen", "darkkhaki", "darkmagenta", "darkolivegreen",
    "darkorange", "darkorchid", "darkred", "darksalmon", "darkseagreen", "darkslateblue",
    "darkslategray", "darkslategrey", "darkturquoise", "darkviolet", "deeppink", "deepskyblue",
    "dimgray", "dimgrey", "dodgerblue", "firebrick", "floralwhite", "forestgreen", "fuchsia",
    "gainsboro", "ghostwhite", "gold", "goldenrod", "gray", "grey", "green", "greenyellow",
    "honeydew", "hotpink", "indianred", "indigo", "ivory", "khaki", "lavender", "lavenderblush",
    "lawngreen", "lemonchiffon", "lightblue", "lightcoral", "lightcyan", "lightgoldenrodyellow",
    "lightgray", "lightgrey", "lightgreen", "lightpink", "lightsalmon", "lightseagreen", "lightskyblue",
    "lightslategray", "lightslategrey", "lightsteelblue", "lightyellow", "lime", "limegreen", "linen",
    "magenta", "maroon", "mediumaquamarine", "mediumblue", "mediumorchid", "mediumpurple",
    "mediumseagreen", "mediumslateblue", "mediumspringgreen", "mediumturquoise", "mediumvioletred",
    "midnightblue", "mintcream", "mistyrose", "moccasin", "navajowhite", "navy", "oldlace", "olive",
    "olivedrab", "orange", "orangered", "orchid", "palegoldenrod", "palegreen", "paleturquoise",
    "palevioletred", "papayawhip", "peachpuff", "peru", "pink", "plum", "powderblue", "purple",
    "red", "rosybrown", "royalblue", "saddlebrown", "salmon", "sandybrown", "seagreen", "seashell",
    "sienna", "silver", "skyblue", "slateblue", "slategray", "slategrey", "snow", "springgreen",
    "steelblue", "tan", "teal", "thistle", "tomato", "turquoise", "violet", "wheat", "white",
    "whitesmoke", "yellow", "yellowgreen"
};

void ResetLotteryDrawState()
{
    g_LotteryDrawIndex = 0;
    g_LotteryDrawLotteryId = 0;
    g_LotteryDrawPrizePool = 0;
    g_LotteryDrawWinnerPrize = 0;
    g_LotteryDrawWelfarePoolPrize = 0;
    g_LotteryDrawWinnerTicketValue = 0;
    g_LotteryDrawWinnerSteamId[0] = '\0';
    g_LotteryDrawWinnerName[0] = '\0';
    g_LotteryDrawExtraWinnerCount = 0;
    for (int i = 0; i <= MaxClients; i++)
    {
        g_LotteryDrawExtraWinnerPrizes[i] = 0;
        g_LotteryDrawExtraWinnerTicketValues[i] = 0;
        g_LotteryDrawExtraWinnerSteamIds[i][0] = '\0';
        g_LotteryDrawExtraWinnerNames[i][0] = '\0';
    }
    g_LotteryDrawHash[0] = '\0';
    g_LotteryDrawHashColor[0] = '\0';
    if (g_LotteryDrawTokens != null)
    {
        g_LotteryDrawTokens.Clear();
    }
}

void CancelPendingLotteryCall()
{
    if (g_LotteryCallTimer != null)
    {
        KillTimer(g_LotteryCallTimer);
        g_LotteryCallTimer = null;
    }
    g_LotteryCallRequesterUserId = 0;
    g_LotteryCallLotteryId = 0;
}

void ReplyToLotteryRequester(int userId, const char[] format, any ...)
{
    char message[256];
    VFormat(message, sizeof(message), format, 3);

    int client = userId > 0 ? GetClientOfUserId(userId) : 0;
    if (client > 0 || userId == 0)
    {
        ReplyToCommand(client, "%s", message);
    }
}

void BuildLotteryTicketDisplay(const char[] storedTicket, char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    int out = 0;
    int len = strlen(storedTicket);
    for (int i = 0; i < len && out < maxlen - 1; i++)
    {
        if (i > 0 && storedTicket[i] == '{' && out < maxlen - 2)
        {
            buffer[out++] = ' ';
        }
        buffer[out++] = storedTicket[i];
    }
    buffer[out] = '\0';
}

void BuildLotteryDrawTokens(const char[] storedTicket)
{
    g_LotteryDrawTokens.Clear();

    int len = strlen(storedTicket);
    int start = 0;
    for (int i = 1; i < len; i++)
    {
        if (storedTicket[i] == '{')
        {
            PushLotteryDrawToken(storedTicket, start, i);
            start = i;
        }
    }

    if (start < len)
    {
        PushLotteryDrawToken(storedTicket, start, len);
    }
}

void PushLotteryDrawToken(const char[] storedTicket, int start, int end)
{
    char token[LOTTO_TOKEN_MAX];
    int out = 0;
    for (int i = start; i < end && out < sizeof(token) - 1; i++)
    {
        token[out++] = storedTicket[i];
    }
    token[out] = '\0';
    TrimString(token);
    if (token[0] != '\0')
    {
        g_LotteryDrawTokens.PushString(token);
    }
}

void GenerateLotteryTicket(char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    if (g_LotteryWords == null || g_LotteryWords.Length <= 0)
    {
        return;
    }

    int wordCount = GetRandomInt(6, 10);
    bool allowDuplicates = g_LotteryWords.Length < wordCount;
    StringMap usedWords = new StringMap();

    for (int i = 0; i < wordCount; i++)
    {
        char word[LOTTO_WORD_MAX];
        bool picked = false;
        for (int attempt = 0; attempt < 64; attempt++)
        {
            if (!PickWeightedLotteryWord(word, sizeof(word)))
            {
                break;
            }

            int dummy = 0;
            if (allowDuplicates || !usedWords.GetValue(word, dummy))
            {
                picked = true;
                usedWords.SetValue(word, 1, true);
                break;
            }
        }

        if (!picked)
        {
            continue;
        }

        char colorName[BP_CURRENCY_COLOR_MAX];
        char token[LOTTO_TOKEN_MAX];
        GetRandomLotteryColorName(colorName, sizeof(colorName));
        Format(token, sizeof(token), "{%s}%s", colorName, word);
        StrCat(buffer, maxlen, token);
    }

    delete usedWords;
}

bool PickWeightedLotteryWord(char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    if (g_LotteryWords == null || g_LotteryWords.Length <= 0)
    {
        return false;
    }

    int totalWeight = g_LotteryTotalWeight;
    if (totalWeight <= 0)
    {
        totalWeight = 1;
    }

    int roll = GetRandomInt(1, totalWeight);
    int running = 0;
    for (int i = 0; i < g_LotteryWords.Length; i++)
    {
        int rarity = g_LotteryRarities.Get(i);
        running += GetLotteryRarityWeight(rarity);
        if (roll <= running)
        {
            g_LotteryWords.GetString(i, buffer, maxlen);
            return buffer[0] != '\0';
        }
    }

    g_LotteryWords.GetString(g_LotteryWords.Length - 1, buffer, maxlen);
    return buffer[0] != '\0';
}

int GetLotteryRarityWeight(int rarity)
{
    switch (rarity)
    {
        case 1: return 12;
        case 2: return 4;
        case 3: return 1;
    }
    return 1;
}

void GetRandomLotteryColorName(char[] buffer, int maxlen)
{
    int index = GetRandomInt(0, sizeof(g_LotteryColors) - 1);
    strcopy(buffer, maxlen, g_LotteryColors[index]);
}

void BuildLotteryHash(int createdAt, char[] buffer, int maxlen)
{
    if (maxlen <= 0)
    {
        return;
    }

    buffer[0] = '\0';

    char input[32];
    IntToString(createdAt, input, sizeof(input));

    int hash = -2128831035;
    int len = strlen(input);
    for (int i = 0; i < len; i++)
    {
        hash ^= input[i];
        hash *= 16777619;
    }

    int h1 = hash & 0x7fffffff;
    int h2 = (hash ^ (createdAt * 1103515245)) & 0x7fffffff;
    Format(buffer, maxlen, "%07x%07x", h1, h2);
}

void GetLotteryShortHash(const char[] hash, char[] buffer, int maxlen)
{
    if (maxlen <= 0)
    {
        return;
    }

    buffer[0] = '\0';

    int copyLen = strlen(hash);
    if (copyLen < LOTTO_SHORT_HASH_LEN)
    {
        strcopy(buffer, maxlen, "unknown");
        return;
    }

    copyLen = LOTTO_SHORT_HASH_LEN;
    if (copyLen > maxlen - 1)
    {
        copyLen = maxlen - 1;
    }

    for (int i = 0; i < copyLen; i++)
    {
        buffer[i] = hash[i];
    }
    buffer[copyLen] = '\0';
}

void ResolveLotteryWinnerName(const char[] steamId, const char[] storedName, char[] buffer, int maxlen)
{
    int client = Kogasa_FindClientBySteamId64(steamId);
    if (client > 0)
    {
        BuildPurchaseDisplayName(client, buffer, maxlen);
        return;
    }

    if (storedName[0] != '\0')
    {
        strcopy(buffer, maxlen, storedName);
        return;
    }

    strcopy(buffer, maxlen, steamId);
}

void CreditSteamId64BonusPoints(const char[] steamId, int amount, const char[] reason = "direct_credit", int lotteryId = 0)
{
    if (amount <= 0 || !g_DatabaseReady || g_Database == null)
    {
        return;
    }

    char escapedSteamId[65];
    if (!EscapeSql(steamId, escapedSteamId, sizeof(escapedSteamId)))
    {
        LogError("[points_store] Failed to escape SteamID64 for direct lottery credit.");
        return;
    }

    DataPack pack = new DataPack();
    pack.WriteString(steamId);
    pack.WriteCell(amount);
    pack.WriteString(reason);
    pack.WriteCell(lotteryId);

    char query[512];
    if (g_IsMySql)
    {
        Format(query, sizeof(query),
            "INSERT INTO %s (steamid64, balance) VALUES ('%s', %d) ON DUPLICATE KEY UPDATE balance = GREATEST(0, balance + VALUES(balance))",
            BP_BALANCE_TABLE,
            escapedSteamId,
            amount);
    }
    else
    {
        Format(query, sizeof(query),
            "INSERT INTO %s (steamid64, balance) VALUES ('%s', %d) ON CONFLICT(steamid64) DO UPDATE SET balance = MAX(0, balance + excluded.balance), updated_at = CURRENT_TIMESTAMP",
            BP_BALANCE_TABLE,
            escapedSteamId,
            amount);
    }

    g_Database.Query(SQL_OnLotteryDirectCredit, query, pack);
}

public void SQL_OnLotteryDirectCredit(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    char steamId[32];
    pack.ReadString(steamId, sizeof(steamId));
    int amount = pack.ReadCell();
    char reason[64];
    pack.ReadString(reason, sizeof(reason));
    int lotteryId = pack.ReadCell();
    delete pack;

    if (error[0] != '\0')
    {
        LogError("[points_store] Failed direct lottery credit for %s: %s", steamId, error);
        return;
    }

    int client = Kogasa_FindClientBySteamId64(steamId);
    int balanceAfter = -1;
    if (client > 0 && g_ClientBonusPointsLoaded[client])
    {
        g_ClientBonusPoints[client] += amount;
        if (g_ClientBonusPoints[client] < 0)
        {
            g_ClientBonusPoints[client] = 0;
        }
        balanceAfter = g_ClientBonusPoints[client];
    }

    if (Client_IsHumanInGame(client))
    {
        if (StrEqual(reason, "lottery_main_payout", false))
        {
            PlayLevelUpSound(client);
        }
        else if (StrEqual(reason, "lottery_extra_payout", false))
        {
            PlayBonusPointsSound(client, true);
        }
    }

    LogLotteryCreditEvent(reason, steamId, amount, lotteryId, client, balanceAfter);
}

