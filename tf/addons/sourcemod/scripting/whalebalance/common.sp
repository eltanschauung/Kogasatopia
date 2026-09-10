bool IsGameTeam(int team)
{
    return team == TEAM_RED || team == TEAM_BLUE || team == TEAM_GREEN || team == TEAM_YELLOW;
}

int GetClientScore(int client)
{
    return GetClientFrags(client);
}

void AB_GetTeamName(int team, char[] buffer, int maxlen)
{
    switch (team)
    {
        case TEAM_RED:    strcopy(buffer, maxlen, "RED");
        case TEAM_BLUE:   strcopy(buffer, maxlen, "BLU");
        case TEAM_GREEN:  strcopy(buffer, maxlen, "GREEN");
        case TEAM_YELLOW: strcopy(buffer, maxlen, "YELLOW");
        default:          strcopy(buffer, maxlen, "UNKNOWN");
    }
}

void AB_GetTeamChatLabel(int team, char[] buffer, int maxlen)
{
    switch (team)
    {
        case TEAM_RED:    strcopy(buffer, maxlen, "{red}RED{default}");
        case TEAM_BLUE:   strcopy(buffer, maxlen, "{blue}BLU{default}");
        case TEAM_GREEN:  strcopy(buffer, maxlen, "{green}GREEN{default}");
        case TEAM_YELLOW: strcopy(buffer, maxlen, "{yellow}YELLOW{default}");
        default:          strcopy(buffer, maxlen, "{default}UNKNOWN");
    }
}

void AB_GetTeamColorName(int team, char[] buffer, int maxlen)
{
    switch (team)
    {
        case TEAM_RED:    strcopy(buffer, maxlen, "{red}Red");
        case TEAM_BLUE:   strcopy(buffer, maxlen, "{blue}Blue");
        case TEAM_GREEN:  strcopy(buffer, maxlen, "{green}Green");
        case TEAM_YELLOW: strcopy(buffer, maxlen, "{yellow}Yellow");
        default:          strcopy(buffer, maxlen, "{default}Unknown");
    }
}

bool IsBalanceLoggingEnabled()
{
    return g_hLogEnabled != null && g_hLogEnabled.BoolValue;
}

void LogBalance(const char[] fmt, any ...)
{
    if (!IsBalanceLoggingEnabled())
    {
        return;
    }

    char buffer[512];
    VFormat(buffer, sizeof(buffer), fmt, 2);
    char eventName[64];
    DeriveBalanceEventName(buffer, eventName, sizeof(eventName));
    PluginStats_Record(eventName, buffer);
}

static void DeriveBalanceEventName(const char[] message, char[] output, int maxlen)
{
    int start = strncmp(message, "[whalebalance] ", 15, false) == 0 ? 15 : 0;
    if (strncmp(message[start], "Autobalancing ", 14, false) == 0)
    {
        strcopy(output, maxlen, "autobalance_move");
        return;
    }
    if (strncmp(message[start], "Imbalance:", 10, false) == 0)
    {
        strcopy(output, maxlen, "imbalance_detected");
        return;
    }
    if (strncmp(message[start], "Skip balance", 12, false) == 0)
    {
        strcopy(output, maxlen, "balance_skipped");
        return;
    }

    int write = 0;
    for (int read = start; message[read] && write < maxlen - 1; read++)
    {
        char c = message[read];
        if (c == ':' || c == '.' || c == '(')
        {
            break;
        }
        if (c >= 'A' && c <= 'Z')
        {
            c += 32;
        }
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
        {
            output[write++] = c;
        }
        else if ((c == ' ' || c == '-' || c == '_') && write > 0 && output[write - 1] != '_')
        {
            output[write++] = '_';
        }
    }
    while (write > 0 && output[write - 1] == '_')
    {
        write--;
    }
    output[write] = '\0';
    if (!output[0])
    {
        strcopy(output, maxlen, "autobalance_event");
    }
}

void ApplyServerBalanceCvars(bool pluginLoaded)
{
    if (g_hMpAutoteamBalance == null)
        g_hMpAutoteamBalance = FindConVar("mp_autoteambalance");

    if (g_hMpTeamsUnbalanceLimit == null)
        g_hMpTeamsUnbalanceLimit = FindConVar("mp_teams_unbalance_limit");

    if (pluginLoaded)
    {
        // Save originals before we overwrite them.
        if (g_hMpAutoteamBalance != null)
        {
            g_iSavedAutoteamBalance = g_hMpAutoteamBalance.IntValue;
            g_hMpAutoteamBalance.IntValue = 0;
        }

        if (g_hMpTeamsUnbalanceLimit != null)
        {
            g_iSavedUnbalanceLimit = g_hMpTeamsUnbalanceLimit.IntValue;
            g_hMpTeamsUnbalanceLimit.IntValue = 1;
        }
    }
    else
    {
        // Restore originals on unload.
        if (g_hMpAutoteamBalance != null)
            g_hMpAutoteamBalance.IntValue = g_iSavedAutoteamBalance;

        if (g_hMpTeamsUnbalanceLimit != null)
            g_hMpTeamsUnbalanceLimit.IntValue = g_iSavedUnbalanceLimit;
    }
}

// ---------------------------------------------------------------------------
// Integrated WhaleScramble vote, automatic-trigger, and ranking subsystem
// ---------------------------------------------------------------------------

enum WhaleVoteKind
{
    WhaleVote_None = 0,
    WhaleVote_Scramble,
    WhaleVote_Surrender
};

