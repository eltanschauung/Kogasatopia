// Admin deafening is separate from sm_filters_mute_deafen's automatic state.
Handle g_hCookiePermanentDeafen;
bool g_bAdminDeafened[MAXPLAYERS + 1];
bool g_bPermanentlyDeafened[MAXPLAYERS + 1];

void FiltersDeafen_Initialize()
{
    g_hCookiePermanentDeafen = RegClientCookie(
        "permamute-deafen", "Permanent incoming player voice restriction", CookieAccess_Protected);

    RegAdminCmd("sm_deafen", Command_Deafen, ADMFLAG_CHAT,
        "sm_deafen <player> - Removes a player's ability to hear other players' voice.");
    RegAdminCmd("sm_undeafen", Command_Undeafen, ADMFLAG_CHAT,
        "sm_undeafen <player> - Restores a player's ability to hear other players' voice.");
    RegAdminCmd("sm_pdeafen", Command_PDeafen, ADMFLAG_CHAT,
        "sm_pdeafen <player> - Permanently removes a player's ability to hear other players' voice.");
    RegAdminCmd("sm_pundeafen", Command_PUndeafen, ADMFLAG_CHAT,
        "sm_pundeafen <player> - Removes a player's permanent incoming voice restriction.");
}

void FiltersDeafen_ResetClient(int client)
{
    g_bAdminDeafened[client] = false;
    g_bPermanentlyDeafened[client] = false;
}

void FiltersDeafen_LoadCookie(int client)
{
    if (!Filters_IsRealClientInGame(client) || !AreClientCookiesCached(client))
    {
        return;
    }

    char value[8];
    GetClientCookie(client, g_hCookiePermanentDeafen, value, sizeof(value));
    g_bPermanentlyDeafened[client] = StrEqual(value, "1");
}

bool FiltersDeafen_IsClientDeafened(int client)
{
    return g_bAdminDeafened[client] || g_bPermanentlyDeafened[client];
}

static bool FiltersDeafen_SetState(int target, bool deafened, bool permanent)
{
    if (!Filters_IsRealClientInGame(target))
    {
        return false;
    }

    if (permanent)
    {
        // Never overwrite a pending cookie load or claim persistence for bots.
        if (!AreClientCookiesCached(target))
        {
            return false;
        }

        SetClientCookie(target, g_hCookiePermanentDeafen, deafened ? "1" : "0");
        g_bPermanentlyDeafened[target] = deafened;
        // Permanent commands supersede any temporary administrative restriction.
        g_bAdminDeafened[target] = false;
    }
    else
    {
        if (!deafened && g_bPermanentlyDeafened[target])
        {
            return false;
        }

        g_bAdminDeafened[target] = deafened;
    }

    return true;
}

static void FiltersDeafen_ShowActivity(
    int client, const char[] prefix, const char[] action, const char[] targetName, bool targetIsPhrase)
{
    if (targetIsPhrase)
    {
        ShowActivity2(client, prefix, "%s %t.", action, targetName);
    }
    else
    {
        ShowActivity2(client, prefix, "%s %s.", action, targetName);
    }
}

static Action FiltersDeafen_Command(
    int client, int args, const char[] command, bool deafened, bool permanent)
{
    char prefix[16];
    strcopy(prefix, sizeof(prefix), permanent ? "[PERMAMUTE] " : "[SM] ");

    if (args < 1)
    {
        ReplyToCommand(client, "%sUsage: %s <player>", prefix, command);
        return Plugin_Handled;
    }

    char argument[64];
    GetCmdArg(1, argument, sizeof(argument));

    char targetName[MAX_TARGET_LENGTH];
    int targets[MAXPLAYERS];
    bool targetIsPhrase;
    int targetCount = ProcessTargetString(
        argument, client, targets, sizeof(targets), COMMAND_FILTER_NO_BOTS,
        targetName, sizeof(targetName), targetIsPhrase);
    if (targetCount <= 0)
    {
        ReplyToTargetError(client, targetCount);
        return Plugin_Handled;
    }

    char action[32];
    if (permanent)
    {
        strcopy(action, sizeof(action), deafened ? "Permanently Deafened" : "Permanently Undeafened");
    }
    else
    {
        strcopy(action, sizeof(action), deafened ? "Deafened" : "Undeafened");
    }

    bool applied[MAXPLAYERS];
    int appliedCount;
    for (int i = 0; i < targetCount; i++)
    {
        int target = targets[i];
        if (permanent && !AreClientCookiesCached(target))
        {
            ReplyToCommand(client, "%sCookie data for %N is not ready; please try again.", prefix, target);
            continue;
        }
        if (!permanent && !deafened && g_bPermanentlyDeafened[target])
        {
            ReplyToCommand(client, "%s%N is permanently deafened; use sm_pundeafen.", prefix, target);
            continue;
        }

        if (FiltersDeafen_SetState(target, deafened, permanent))
        {
            applied[i] = true;
            appliedCount++;
            LogAction(client, target, "\"%L\" %s \"%L\"", client, action, target);
        }
    }

    if (appliedCount == 0)
    {
        return Plugin_Handled;
    }

    // One matrix refresh for a multi-target command, retaining every other gate.
    Filters_UpdateVoiceOverrides();
    if (appliedCount == targetCount)
    {
        FiltersDeafen_ShowActivity(client, prefix, action, targetName, targetIsPhrase);
    }
    else
    {
        // Do not claim an entire target group was changed when some were skipped.
        for (int i = 0; i < targetCount; i++)
        {
            if (!applied[i]) continue;
            GetClientName(targets[i], targetName, sizeof(targetName));
            FiltersDeafen_ShowActivity(client, prefix, action, targetName, false);
        }
    }

    return Plugin_Handled;
}

public Action Command_Deafen(int client, int args)
{
    return FiltersDeafen_Command(client, args, "sm_deafen", true, false);
}

public Action Command_Undeafen(int client, int args)
{
    return FiltersDeafen_Command(client, args, "sm_undeafen", false, false);
}

public Action Command_PDeafen(int client, int args)
{
    return FiltersDeafen_Command(client, args, "sm_pdeafen", true, true);
}

public Action Command_PUndeafen(int client, int args)
{
    return FiltersDeafen_Command(client, args, "sm_pundeafen", false, true);
}
