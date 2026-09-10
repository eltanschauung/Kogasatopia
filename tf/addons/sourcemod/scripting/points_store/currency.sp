bool AreBonusPointsReady(int client)
{
    return Client_IsHumanInGame(client) && g_ClientBonusPointsLoaded[client];
}

int GetCachedBonusPoints(int client)
{
    if (client <= 0 || client > MaxClients || !g_ClientBonusPointsLoaded[client])
    {
        return 0;
    }

    return g_ClientBonusPoints[client] > 0 ? g_ClientBonusPoints[client] : 0;
}

void GetCurrencyShortLabel(char[] buffer, int maxlen)
{
    strcopy(buffer, maxlen, g_CurrencyShortLabel);
}

void GetCurrencyShortLabelForAmount(int amount, char[] buffer, int maxlen)
{
    GetCurrencyShortLabel(buffer, maxlen);

    int len = strlen(buffer);
    if (amount == 1 && len > 0 && buffer[len - 1] == 's')
    {
        buffer[len - 1] = '\0';
    }
}

void GetCurrencyLongLabel(char[] buffer, int maxlen)
{
    strcopy(buffer, maxlen, g_CurrencyLongLabel);
}

void GetCurrencyColorTag(char[] buffer, int maxlen)
{
    strcopy(buffer, maxlen, g_CurrencyColorTag);
}

void GetCurrencyPrefix(char[] buffer, int maxlen)
{
    strcopy(buffer, maxlen, g_CurrencyPrefix);
}

public void OnCurrencyConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    RefreshCurrencyLabels();
}

void RefreshCurrencyLabels()
{
    g_CurrencyShortLabel[0] = '\0';
    if (g_CvarCurrencyShort != null)
    {
        g_CvarCurrencyShort.GetString(g_CurrencyShortLabel, sizeof(g_CurrencyShortLabel));
        TrimString(g_CurrencyShortLabel);
    }

    if (g_CurrencyShortLabel[0] == '\0')
    {
        strcopy(g_CurrencyShortLabel, sizeof(g_CurrencyShortLabel), "BP");
    }

    g_CurrencyLongLabel[0] = '\0';
    if (g_CvarCurrencyLong != null)
    {
        g_CvarCurrencyLong.GetString(g_CurrencyLongLabel, sizeof(g_CurrencyLongLabel));
        TrimString(g_CurrencyLongLabel);
    }

    if (g_CurrencyLongLabel[0] == '\0')
    {
        strcopy(g_CurrencyLongLabel, sizeof(g_CurrencyLongLabel), "Bonus Points");
    }

    char color[BP_CURRENCY_COLOR_MAX];
    color[0] = '\0';
    if (g_CvarCurrencyColor != null)
    {
        g_CvarCurrencyColor.GetString(color, sizeof(color));
        TrimString(color);
    }

    if (color[0] == '\0')
    {
        strcopy(color, sizeof(color), "magenta");
    }

    if (color[0] == '{')
    {
        strcopy(g_CurrencyColorTag, sizeof(g_CurrencyColorTag), color);
    }
    else
    {
        Format(g_CurrencyColorTag, sizeof(g_CurrencyColorTag), "{%s}", color);
    }

    Format(g_CurrencyPrefix, sizeof(g_CurrencyPrefix), "%s[%s]{default}", g_CurrencyColorTag, g_CurrencyShortLabel);
    Bounties_RefreshPrefix();
}

