public Action CommandListener_ShowBonusPointsAlias(int client, const char[] command, int argc)
{
    return Command_ShowBonusPoints(client, 0);
}

public Action CommandListener_PointsStoreChatAlias(int client, const char[] command, int argc)
{
    if (!Client_IsHumanInGame(client))
    {
        return Plugin_Continue;
    }

    char text[32];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);
    TrimString(text);

    if (StrEqual(text, "gem", false) || StrEqual(text, "gems", false) || StrEqual(text, "wallet", false))
    {
        return Command_ShowBonusPoints(client, 0);
    }

    if (StrEqual(text, "refund", false))
    {
        return Command_LotteryRefund(client, 0);
    }

    if (StrEqual(text, "pool", false))
    {
        return Command_LotteryPrizePool(client, 0);
    }

    if (StrEqual(text, "daily", false)
        || StrEqual(text, "dailies", false)
        || StrEqual(text, "limit", false)
        || StrEqual(text, "limits", false))
    {
        return Command_Dailies(client, 0);
    }

    return Plugin_Continue;
}

public void SQL_OnIgnoredResult(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[bonuspoints_transactions] SQL query failed: %s", error);
    }
}

