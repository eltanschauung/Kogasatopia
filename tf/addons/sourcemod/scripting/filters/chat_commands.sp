static void Filters_ApplyAdminTargetAction(int client, int target, FilterAdminAction action)
{
    switch (action)
    {
        case FilterAdmin_FilterWhitelist: PerformFilterWhitelist(client, target);
        case FilterAdmin_UnFilterWhitelist: PerformUnFilterWhitelist(client, target);
        case FilterAdmin_redlist: Performredlist(client, target);
        case FilterAdmin_Unredlist: PerformUnredlist(client, target);
    }
}

Action Filters_RunTargetAdminCommand(int client, int args, const char[] usage, const char[] activity, FilterAdminAction action)
{
    if (args < 1)
    {
        ReplyToCommand(client, usage);
        return Plugin_Handled;
    }

    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    char targetName[MAX_TARGET_LENGTH];
    int targetList[MAXPLAYERS];
    bool targetNameIsMl;
    int targetCount = ProcessTargetString(
        arg,
        client,
        targetList,
        MAXPLAYERS,
        0,
        targetName,
        sizeof(targetName),
        targetNameIsMl);

    if (targetCount <= 0)
    {
        ReplyToTargetError(client, targetCount);
        return Plugin_Handled;
    }

    for (int i = 0; i < targetCount; i++)
    {
        Filters_ApplyAdminTargetAction(client, targetList[i], action);
    }

    ShowActivity2(client, "[Kogasa] ", activity, targetName);
    return Plugin_Handled;
}

Action Filters_RunStatusListCommand(int client, FilterStatusList status)
{
    if (client <= 0)
    {
        return Plugin_Handled;
    }

    if (!Filters_CanUseListCommand(client))
    {
        CPrintToChat(client, FILTERS_ACCESS_DENIED);
        return Plugin_Handled;
    }

    Filters_PrintStatusList(client, status);
    return Plugin_Handled;
}

Action Filters_RunFiltersHelpCommand(int client)
{
    if (client <= 0)
    {
        return Plugin_Handled;
    }

    if (!Filters_CanUseHelpCommand(client))
    {
        CPrintToChat(client, FILTERS_ACCESS_DENIED);
        return Plugin_Handled;
    }

    Filters_PrintHelp(client);
    return Plugin_Handled;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
    if (!client)
        return Plugin_Continue;

    char dead[64];
    BuildDeathPrefix(client, dead, sizeof(dead));

    if (HandleNameColorCommand(client, sArgs))
    {
        return Plugin_Stop;
    }

    if (HandleFiltersHelpCommand(client, sArgs))
    {
        return Plugin_Stop;
    }

    if (HandleListStatusCommand(client, sArgs))
    {
        return Plugin_Stop;
    }

    if (CheckCommands(sArgs))
    {
        PrintToServer("%s", sArgs);
        return Plugin_Continue;
    }

    Filters_ScheduleArchivedMessageTriggers(client, sArgs);

    if (TryHandleTeamChat(client, command, sArgs, dead))
    {
        return Plugin_Stop;
    }

    ChatContext context;
    BuildChatContext(client, sArgs, context);

    char publicBody[256];
    bool hasPrivateOriginal = Filters_FindGoodnightStopperReplacement(client, sArgs, publicBody, sizeof(publicBody));
    if (!hasPrivateOriginal)
    {
        strcopy(publicBody, sizeof(publicBody), sArgs);
    }
    else
    {
        // Farewell replacements supersede the matching blacklist rule.
        context.hasBlacklistedTerm = false;
    }

    if (context.hasBlacklistedTerm || context.isBlacklisted)
    {
        LogBlacklistedMessage(client, sArgs, context.hasBlacklistedTerm, context.isBlacklisted);
    }

    char messageColorTag[16];
    BuildMessageColorTag(client, messageColorTag, sizeof(messageColorTag));

    char displayName[384];
    BuildChatDisplayName(client, displayName, sizeof(displayName));

    char output[256];
    Format(output, sizeof(output), "%s%s%s%s : %s", messageColorTag, dead, displayName, messageColorTag, publicBody);

    char senderOutput[256];
    senderOutput[0] = '\0';
    if (hasPrivateOriginal)
    {
        Format(senderOutput, sizeof(senderOutput), "%s%s%s%s : %s", messageColorTag, dead, displayName, messageColorTag, sArgs);
    }

    ApplyFiltersIfNeeded(output, sizeof(output), context);

    if (HandleCordModeBlacklistedChat(client, output, context, senderOutput))
    {
        return Plugin_Stop;
    }

    if (HandleRestrictedMessage(client, output, context, senderOutput))
    {
        return Plugin_Stop;
    }

    if (HandleEnabledChat(client, output, context, senderOutput))
    {
        return Plugin_Stop;
    }

    SendFallbackMessage(client);
    return Plugin_Stop;
}

void BuildChatContext(int client, const char[] sArgs, ChatContext context)
{
    Filters_RefreshAdminDbStatus(client);
    context.pluginEnabled = GetConVarInt(g_sEnabled) != 0;
    context.cordMode = Filters_IsCordModeEnabled();
    context.isBlacklisted = g_PlayerState[client].isBlacklisted;
    context.isWhitelisted = g_PlayerState[client].isWhitelisted;
    context.isFilterWhitelisted = g_PlayerState[client].isFilterWhitelisted;
    context.hasBlacklistedTerm = CheckBlacklistedTerms(sArgs);
    context.isGagged = Filters_IsClientGagged(client);
}

static void LogBlacklistedMessage(int client, const char[] message, bool hasBlacklistedTerm, bool isBlacklistedClient)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));

    char steamId[32];
    if (!Kogasa_GetClientSteam2(client, steamId, sizeof(steamId), true))
    {
        strcopy(steamId, sizeof(steamId), "unknown");
    }

    LogToFileEx("addons/sourcemod/logs/filters_blacklist.log",
        "name=\"%s\" steamid=\"%s\" term=%d blacklisted=%d msg=\"%s\"",
        name, steamId, hasBlacklistedTerm ? 1 : 0, isBlacklistedClient ? 1 : 0, message);
}

void BuildDeathPrefix(int client, char[] deadPrefix, int length)
{
    if (!IsPlayerAlive(client))
    {
        Format(deadPrefix, length, "*負け犬* ");
        return;
    }

    deadPrefix[0] = '\0';
}

bool HandleNameColorCommand(int client, const char[] sArgs)
{
    if (!sArgs[0])
    {
        return false;
    }

    char buffer[256];
    strcopy(buffer, sizeof(buffer), sArgs);
    TrimString(buffer);

    if (!buffer[0])
    {
        return false;
    }

    char commandToken[16];
    int nextIndex = BreakString(buffer, commandToken, sizeof(commandToken));
    bool americaCommand = StrEqual(commandToken, "!america", false) || StrEqual(commandToken, "/america", false);
    bool mapCommand = StrEqual(commandToken, "!mapflag", false) || StrEqual(commandToken, "/mapflag", false);
    bool transCommand = StrEqual(commandToken, "!trans", false) || StrEqual(commandToken, "/trans", false);
    bool rainbowCommand = StrEqual(commandToken, "!rainbow", false) || StrEqual(commandToken, "/rainbow", false);
    bool gradientCommand = StrEqual(commandToken, "!gradient", false) || StrEqual(commandToken, "/gradient", false)
        || StrEqual(commandToken, "!hue", false) || StrEqual(commandToken, "/hue", false);

    if (!americaCommand
        && !mapCommand
        && !transCommand
        && !rainbowCommand
        && !gradientCommand
        && !StrEqual(commandToken, "!name", false)
        && !StrEqual(commandToken, "/name", false)
        && !StrEqual(commandToken, "!color", false)
        && !StrEqual(commandToken, "/color", false))
    {
        return false;
    }

    if (gradientCommand)
    {
        return HandleGradientNameCommand(client, buffer, nextIndex);
    }

    if (americaCommand)
    {
        return HandlePresetNamePatternCommand(client, NAME_COLOR_AMERICA, AMERICA_NAME_ACCESS_ITEM, "America Flag Name Color", "america");
    }

    if (mapCommand)
    {
        return HandlePresetNamePatternCommand(client, NAME_PATTERN_MAP, MAP_NAME_ACCESS_ITEM, "MAP Flag Name Color", "map");
    }

    if (transCommand)
    {
        return HandlePresetNamePatternCommand(client, NAME_PATTERN_TRANS, TRANS_NAME_ACCESS_ITEM, "Trans Name Color", "trans");
    }

    if (rainbowCommand)
    {
        return HandlePresetNamePatternCommand(client, NAME_PATTERN_RAINBOW, RAINBOW_NAME_ACCESS_ITEM, "Rainbow Name Color", "rainbow");
    }

    if (nextIndex == -1 || !buffer[nextIndex])
    {
        PrintCurrentNamePreference(client);
        return true;
    }

    char colorName[32];
    strcopy(colorName, sizeof(colorName), buffer[nextIndex]);
    TrimString(colorName);

    if (!colorName[0])
    {
        PrintCurrentNamePreference(client);
        return true;
    }

    ToLowercase(colorName);

    if (StrEqual(colorName, "default", false) || StrEqual(colorName, "team", false) || StrEqual(colorName, "teamcolor", false))
    {
        if (!g_NameColors[client][0] && !HasValidNamePattern(client))
        {
            CPrintToChat(client, "{default}[Filters] Your name color already uses the {teamcolor}team color{default}.");
            return true;
        }

        ResetNamePreferences(client);
        CPrintToChat(client, "{default}[Filters] Your name color has been reset to the {teamcolor}team color{default}.");
        return true;
    }

    if (IsAmericaNamePattern(colorName))
    {
        return HandlePresetNamePatternCommand(client, NAME_COLOR_AMERICA, AMERICA_NAME_ACCESS_ITEM, "America Flag Name Color", "america");
    }

    if (IsMapNamePattern(colorName))
    {
        return HandlePresetNamePatternCommand(client, NAME_PATTERN_MAP, MAP_NAME_ACCESS_ITEM, "MAP Flag Name Color", "map");
    }

    if (IsTransNamePattern(colorName))
    {
        return HandlePresetNamePatternCommand(client, NAME_PATTERN_TRANS, TRANS_NAME_ACCESS_ITEM, "Trans Name Color", "trans");
    }

    if (IsRainbowNamePattern(colorName))
    {
        return HandlePresetNamePatternCommand(client, NAME_PATTERN_RAINBOW, RAINBOW_NAME_ACCESS_ITEM, "Rainbow Name Color", "rainbow");
    }

    if (!CColorExists(colorName))
    {
        CPrintToChat(client, "{default}[Filters] Unknown color \"%s\". Example: !name deeppink, !america, !mapflag, !trans, !rainbow, or !gradient blue red", colorName);
        return true;
    }

    if (StrEqual(g_NameColors[client], colorName, false))
    {
        CPrintToChat(client, "{default}[Filters] Your name color is already {%s}%s{default}.", g_NameColors[client], g_NameColors[client]);
        return true;
    }

    SetNameColorPreference(client, colorName);

    CPrintToChat(client, "{default}[Filters] Your name color is now {%s}%s{default}.", colorName, colorName);
    return true;
}

static void PrintCurrentNamePreference(int client)
{
    if (HasValidNamePattern(client))
    {
        char renderedName[256];
        BuildRenderedClientName(client, renderedName, sizeof(renderedName));
        CPrintToChat(client,
            "{default}[Filters] Your name color is currently %s. Use !name <color>, !america, !mapflag, !trans, !rainbow, !gradient <color1> <color2>, or !name default.",
            renderedName);
    }
    else if (g_NameColors[client][0] != '\0')
    {
        CPrintToChat(client,
            "{default}[Filters] Your name color is currently {%s}%s{default}. Use !name <color>, !america, !mapflag, !trans, !rainbow, !gradient <color1> <color2>, or !name default.",
            g_NameColors[client],
            g_NameColors[client]);
    }
    else
    {
        CPrintToChat(client,
            "{default}[Filters] Your name color uses the {teamcolor}team color{default}. Use !name <color>, !america, !mapflag, !trans, !rainbow, or !gradient <color1> <color2> to change it.");
    }
}

static bool ClientHasNamePatternAccess(int client, const char[] itemKey, const char[] itemName)
{
    if (GetFeatureStatus(FeatureType_Native, "PointsStore_HasPurchase") != FeatureStatus_Available)
    {
        CPrintToChat(client, "{default}[Filters] Name pattern purchases are temporarily unavailable.");
        return false;
    }

    if (!PointsStore_HasPurchase(client, itemKey))
    {
        CPrintToChat(client,
            "{default}[Filters] Purchase {gold}%s{default} from {gold}!shop{default} before using this name pattern.",
            itemName);
        return false;
    }

    return true;
}

static bool HandlePresetNamePatternCommand(int client, const char[] pattern, const char[] itemKey, const char[] itemName, const char[] patternName)
{
    if (StrEqual(g_NamePatterns[client], pattern, false))
    {
        ClearNamePatternPreference(client);
        CPrintToChat(client, "{default}[Filters] Your %s name pattern has been disabled.", patternName);
        return true;
    }

    if (!ClientHasNamePatternAccess(client, itemKey, itemName))
    {
        return true;
    }

    SetNamePatternPreference(client, pattern);

    char renderedName[256];
    BuildRenderedClientName(client, renderedName, sizeof(renderedName));
    CPrintToChat(client, "{default}[Filters] Your name color is now %s.", renderedName);
    return true;
}

static int ParseGradientCommandColors(
    const char[] command,
    int argumentsIndex,
    char[] firstColor,
    int firstLen,
    char[] secondColor,
    int secondLen,
    char[] thirdColor,
    int thirdLen)
{
    firstColor[0] = '\0';
    secondColor[0] = '\0';
    thirdColor[0] = '\0';
    if (argumentsIndex == -1 || !command[argumentsIndex])
    {
        return 0;
    }

    char arguments[128];
    strcopy(arguments, sizeof(arguments), command[argumentsIndex]);
    TrimString(arguments);
    int secondIndex = BreakString(arguments, firstColor, firstLen);
    if (secondIndex == -1 || !arguments[secondIndex])
    {
        return 0;
    }

    char remaining[96];
    strcopy(remaining, sizeof(remaining), arguments[secondIndex]);
    TrimString(remaining);
    int extraIndex = BreakString(remaining, secondColor, secondLen);
    if (extraIndex != -1 && remaining[extraIndex])
    {
        char trailing[64];
        strcopy(trailing, sizeof(trailing), remaining[extraIndex]);
        TrimString(trailing);
        int fourthIndex = BreakString(trailing, thirdColor, thirdLen);
        if (fourthIndex != -1 && trailing[fourthIndex])
        {
            return 0;
        }
    }

    TrimString(firstColor);
    TrimString(secondColor);
    TrimString(thirdColor);
    ToLowercase(firstColor);
    ToLowercase(secondColor);
    ToLowercase(thirdColor);
    if (!firstColor[0] || !secondColor[0])
    {
        return 0;
    }
    return thirdColor[0] ? 3 : 2;
}

static bool HandleGradientNameCommand(int client, const char[] command, int argumentsIndex)
{
    if (!ClientHasNamePatternAccess(client, GRADIENT_NAME_ACCESS_ITEM, "Gradient Color Name Access"))
    {
        return true;
    }

    char firstColor[32];
    char secondColor[32];
    char thirdColor[32];
    int colorCount = ParseGradientCommandColors(
        command,
        argumentsIndex,
        firstColor,
        sizeof(firstColor),
        secondColor,
        sizeof(secondColor),
        thirdColor,
        sizeof(thirdColor));
    if (colorCount == 0)
    {
        CPrintToChat(client,
            "{default}[Filters] Usage: {gold}!gradient <color1> <color2> [color3]{default}. Use {gold}!colors{default} to list colors.");
        return true;
    }

    if (colorCount == 3
        && !ClientHasNamePatternAccess(client, TRIPLE_GRADIENT_ACCESS_ITEM, "Triple Gradient Upgrade"))
    {
        return true;
    }

    if (!CColorExists(firstColor))
    {
        CPrintToChat(client, "{default}[Filters] Unknown color \"%s\". Use {gold}!colors{default} to list colors.", firstColor);
        return true;
    }
    if (!CColorExists(secondColor))
    {
        CPrintToChat(client, "{default}[Filters] Unknown color \"%s\". Use {gold}!colors{default} to list colors.", secondColor);
        return true;
    }
    if (colorCount == 3 && !CColorExists(thirdColor))
    {
        CPrintToChat(client, "{default}[Filters] Unknown color \"%s\". Use {gold}!colors{default} to list colors.", thirdColor);
        return true;
    }

    char pattern[NAME_PATTERN_MAX];
    if (colorCount == 3)
    {
        FormatEx(pattern, sizeof(pattern), "%s%s:%s:%s", NAME_PATTERN_TRIPLE_GRADIENT_PREFIX, firstColor, secondColor, thirdColor);
    }
    else
    {
        FormatEx(pattern, sizeof(pattern), "%s%s:%s:%d", NAME_PATTERN_GRADIENT_PREFIX, firstColor, secondColor, NAME_GRADIENT_DEFAULT_COMPLETION);
    }
    if (StrEqual(g_NamePatterns[client], pattern, false))
    {
        CPrintToChat(client, "{default}[Filters] Your name already uses that gradient.");
        return true;
    }

    SetNamePatternPreference(client, pattern);
    char renderedName[256];
    BuildRenderedClientName(client, renderedName, sizeof(renderedName));
    CPrintToChat(client, "{default}[Filters] Your name gradient is now %s.", renderedName);
    return true;
}

public Action Command_GradientMenu(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }
    if (!ClientHasNamePatternAccess(client, GRADIENT_NAME_ACCESS_ITEM, "Gradient Color Name Access"))
    {
        return Plugin_Handled;
    }
    if (IsTripleGradientNamePattern(g_NamePatterns[client]))
    {
        CPrintToChat(client, "{default}[Filters] Gradient Control only adjusts two-color gradients.");
        return Plugin_Handled;
    }

    char firstColor[32];
    char secondColor[32];
    int completionPercent;
    if (!ParseGradientNamePattern(
        g_NamePatterns[client],
        firstColor,
        sizeof(firstColor),
        secondColor,
        sizeof(secondColor),
        completionPercent))
    {
        CPrintToChat(client, "{default}[Filters] Use {gold}!gradient <color1> <color2>{default} before opening Gradient Control.");
        return Plugin_Handled;
    }

    ShowGradientControlMenu(client, completionPercent);
    return Plugin_Handled;
}

static void ShowGradientControlMenu(int client, int completionPercent)
{
    Menu menu = new Menu(MenuHandler_GradientControl);
    menu.SetTitle("Gradient Control");

    int positionCount = GetGradientControlPositionCount();
    menu.AddItem("left", "Adjust Left", completionPercent > GetGradientControlPercent(0) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    menu.AddItem("right", "Adjust Right", completionPercent < GetGradientControlPercent(positionCount - 1) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

    char percentage[16];
    FormatEx(percentage, sizeof(percentage), "%d%%", completionPercent);
    menu.AddItem("percentage", percentage, ITEMDRAW_DISABLED);
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_GradientControl(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }
    if (action != MenuAction_Select || client <= 0 || !IsClientInGame(client))
    {
        return 0;
    }

    char direction[16];
    menu.GetItem(item, direction, sizeof(direction));

    char firstColor[32];
    char secondColor[32];
    int completionPercent;
    if (!ParseGradientNamePattern(
        g_NamePatterns[client],
        firstColor,
        sizeof(firstColor),
        secondColor,
        sizeof(secondColor),
        completionPercent))
    {
        CPrintToChat(client, "{default}[Filters] Your active name pattern is no longer a gradient.");
        return 0;
    }

    if (StrEqual(direction, "left", false))
    {
        completionPercent = GetAdjacentGradientControlPercent(completionPercent, false);
    }
    else if (StrEqual(direction, "right", false))
    {
        completionPercent = GetAdjacentGradientControlPercent(completionPercent, true);
    }

    char pattern[NAME_PATTERN_MAX];
    FormatEx(pattern, sizeof(pattern), "%s%s:%s:%d", NAME_PATTERN_GRADIENT_PREFIX, firstColor, secondColor, completionPercent);
    SetNamePatternPreference(client, pattern);
    ShowGradientControlMenu(client, completionPercent);
    return 0;
}

static int GetGradientControlSlotCount()
{
    int count = 0;
    for (int slot = 1; slot <= NAME_GRADIENT_MAX_STEPS; slot++)
    {
        int percent = RoundToNearest(float(slot) * 100.0 / float(NAME_GRADIENT_MAX_STEPS));
        if (percent > NAME_GRADIENT_MAX_COMPLETION)
        {
            break;
        }
        count++;
    }
    return count;
}

static int GetGradientControlPositionCount()
{
    int slotCount = GetGradientControlSlotCount();
    return GetGradientControlPercent(slotCount - 1) < NAME_GRADIENT_MAX_COMPLETION ? slotCount + 1 : slotCount;
}

static int GetGradientControlPercent(int position)
{
    int slotCount = GetGradientControlSlotCount();
    if (position >= slotCount)
    {
        return NAME_GRADIENT_MAX_COMPLETION;
    }
    if (position < 0)
    {
        position = 0;
    }
    return RoundToNearest(float(position + 1) * 100.0 / float(NAME_GRADIENT_MAX_STEPS));
}

static int GetAdjacentGradientControlPercent(int completionPercent, bool moveRight)
{
    int positionCount = GetGradientControlPositionCount();
    if (moveRight)
    {
        for (int position = 0; position < positionCount; position++)
        {
            int candidate = GetGradientControlPercent(position);
            if (candidate > completionPercent)
            {
                return candidate;
            }
        }
        return GetGradientControlPercent(positionCount - 1);
    }

    for (int position = positionCount - 1; position >= 0; position--)
    {
        int candidate = GetGradientControlPercent(position);
        if (candidate < completionPercent)
        {
            return candidate;
        }
    }
    return GetGradientControlPercent(0);
}

bool Filters_CanUseListCommand(int client)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return false;
    }

    return g_PlayerState[client].isWhitelisted;
}

bool Filters_CanUseHelpCommand(int client)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return false;
    }

    if (!g_PlayerState[client].isWhitelisted)
    {
        return false;
    }

    return CheckCommandAccess(client, "sm_filtershelp", ADMFLAG_CHAT, true);
}

void Filters_PrintHelp(int client)
{
    CPrintToChat(client, "{default}[Filters] nobroly - If 0, filter chat to one word.");
    CPrintToChat(client, "{default}[Filters] filtermode - 0=off, 1=quarantine with mutual whitelist/blacklist visibility, 2=quarantine with whitelist monitoring only.");
    CPrintToChat(client, "{default}[Filters] filters_chat_debug - Enable verbose debug logging for chat relay.");
    CPrintToChat(client, "{default}[Filters] filters_chat_frontend - Show frontend chat to all clients; blacklist level 3 clients still receive it when disabled.");
    CPrintToChat(client, "{default}[Filters] sm_filters_cross_sv_tag - Label shown on messages relayed from this server; none disables.");
    CPrintToChat(client, "{default}[Filters] filters_filters - If 0, blacklist word matching is disabled.");
    CPrintToChat(client, "{default}[Filters] filters_blacklist_minlen - Minimum message length to check blacklist words.");
    CPrintToChat(client, "{default}[Filters] filters_christmas - If 1, red chat is {axis} and blue chat is {green}.");
    CPrintToChat(client, "{default}[Filters] teamchat - If 1, normal chat is sent to the sender's team only.");
    CPrintToChat(client, "{default}[Filters] sm_pchat - If 0, filtered/monitored chat is only printed to server console instead of whitelisted clients.");
    CPrintToChat(client, "{default}[Filters] filters_case_sensitive - If 1, chat filters are case-sensitive.");
}

bool HandleFiltersHelpCommand(int client, const char[] sArgs)
{
    if (!sArgs[0])
    {
        return false;
    }

    char buffer[256];
    strcopy(buffer, sizeof(buffer), sArgs);
    TrimString(buffer);

    if (!buffer[0] || buffer[0] != '/')
    {
        return false;
    }

    char commandToken[32];
    BreakString(buffer, commandToken, sizeof(commandToken));

    if (!StrEqual(commandToken, "/filtershelp", false))
    {
        return false;
    }

    if (!Filters_CanUseHelpCommand(client))
    {
        CPrintToChat(client, FILTERS_ACCESS_DENIED);
        return true;
    }

    Filters_PrintHelp(client);
    return true;
}

void Filters_PrintStatusList(int client, FilterStatusList status)
{
    char label[16];
    switch (status)
    {
        case FilterStatus_redlist: strcopy(label, sizeof(label), "redlisted");
        default: strcopy(label, sizeof(label), "Players");
    }

    char header[96];
    Format(header, sizeof(header), "{default}[Filters] %s: ", label);
    int headerLen = strlen(header);

    char line[256];
    strcopy(line, sizeof(line), header);
    int lineLen = headerLen;
    int count = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
        {
            continue;
        }

        if (status == FilterStatus_redlist && !g_PlayerState[i].isredlisted)
        {
            continue;
        }

        char name[MAX_NAME_LENGTH];
        GetClientName(i, name, sizeof(name));
        int nameLen = strlen(name);
        int extraLen = nameLen + (count > 0 && lineLen > headerLen ? 2 : 0);

        if (lineLen + extraLen >= sizeof(line) - 1)
        {
            CPrintToChat(client, "%s", line);
            strcopy(line, sizeof(line), header);
            lineLen = headerLen;
        }

        char next[256];
        if (lineLen == headerLen)
        {
            Format(next, sizeof(next), "%s%s", line, name);
        }
        else
        {
            Format(next, sizeof(next), "%s, %s", line, name);
        }
        strcopy(line, sizeof(line), next);
        lineLen = strlen(line);
        count++;
    }

    if (count == 0)
    {
        CPrintToChat(client, "{default}[Filters] %s: none", label);
        return;
    }

    CPrintToChat(client, "%s", line);
}

bool HandleListStatusCommand(int client, const char[] sArgs)
{
    if (!sArgs[0])
    {
        return false;
    }

    char buffer[256];
    strcopy(buffer, sizeof(buffer), sArgs);
    TrimString(buffer);

    if (!buffer[0] || buffer[0] != '/')
    {
        return false;
    }

    char commandToken[32];
    BreakString(buffer, commandToken, sizeof(commandToken));

    bool listredlist = StrEqual(commandToken, "/redlists", false);

    if (!listredlist)
    {
        return false;
    }

    if (!Filters_CanUseListCommand(client))
    {
        CPrintToChat(client, FILTERS_ACCESS_DENIED);
        return true;
    }

    Filters_PrintStatusList(client, FilterStatus_redlist);
    return true;
}

bool TryHandleTeamChat(int client, const char[] command, const char[] sArgs, const char[] deadPrefix)
{
    if (!StrEqual(command, "say_team"))
    {
        return false;
    }

    Filters_RefreshAdminDbStatus(client);

    char tag[16];
    BuildTeamTag(GetClientTeam(client), tag, sizeof(tag));

    char messageColorTag[16];
    BuildMessageColorTag(client, messageColorTag, sizeof(messageColorTag));

    char displayName[384];
    BuildChatDisplayName(client, displayName, sizeof(displayName));

    char publicBody[256];
    bool hasPrivateOriginal = Filters_FindGoodnightStopperReplacement(client, sArgs, publicBody, sizeof(publicBody));
    if (!hasPrivateOriginal)
    {
        strcopy(publicBody, sizeof(publicBody), sArgs);
    }

    char output[256];
    Format(output, sizeof(output), "%s%s%s %s%s : %s", messageColorTag, deadPrefix, tag, displayName, messageColorTag, publicBody);

    char senderOutput[256];
    senderOutput[0] = '\0';
    if (hasPrivateOriginal)
    {
        Format(senderOutput, sizeof(senderOutput), "%s%s%s %s%s : %s", messageColorTag, deadPrefix, tag, displayName, messageColorTag, sArgs);
    }

    if (Filters_IsClientGagged(client))
    {
        CPrintToChatEx(client, client, "%s", senderOutput[0] ? senderOutput : output);
        PrintToServer("x: %s", output);
        SendToWhitelistedAdmins(client, output, "x:");
        Filters_RelayChatToServers(client, output);
        return true;
    }

    int filterMode = Filters_GetFilterMode();
    bool cordMode = filterMode != 0;
    if (cordMode)
    {
        if (g_PlayerState[client].isBlacklisted)
        {
            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsClientInGame(i) && g_PlayerState[i].isBlacklisted && Filters_ShouldReceiveChat(i, client))
                {
                    Filters_SendChatToReceiver(i, client, output, senderOutput);
                }
            }

            if (Filters_CordModeWhitelistedCanReceiveBlacklisted())
            {
                SendToWhitelistedAdminsBlacklisted(client, output, "fm1:");
            }
            PrintToServer("x: %s", output);
            return true;
        }

        int senderTeam = GetClientTeam(client);
        char prefixed[256];
        bool prefixedReady = false;

        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i))
            {
                continue;
            }
            if (!Filters_ShouldReceiveChat(i, client))
            {
                continue;
            }

            bool isWhitelisted = g_PlayerState[i].isWhitelisted;
            bool isBlacklisted = g_PlayerState[i].isBlacklisted;
            if (GetClientTeam(i) == senderTeam)
            {
                if (!isBlacklisted || isWhitelisted || (g_PlayerState[client].isWhitelisted && Filters_CordModeBlacklistedCanReceiveWhitelisted()))
                {
                    Filters_SendChatToReceiver(i, client, output, senderOutput);
                }
            }
            else if (Filters_CanSeeEnemyTeamChat(i))
            {
                if (!prefixedReady)
                {
                    Format(prefixed, sizeof(prefixed), "t: %s", output);
                    prefixedReady = true;
                }
                Filters_SendChatToReceiver(i, client, prefixed);
            }
        }

        PrintToServer("%s", output);
        return true;
    }

    if (g_PlayerState[client].isBlacklisted)
    {
        int senderTeam = GetClientTeam(client);
        char prefixed[256];
        bool prefixedReady = false;

        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i) || !Filters_ShouldReceiveChat(i, client))
            {
                continue;
            }

            if (GetClientTeam(i) == senderTeam)
            {
                Filters_SendChatToReceiver(i, client, output, senderOutput);
            }
            else if (Filters_CanSeeEnemyTeamChat(i))
            {
                if (!prefixedReady)
                {
                    Format(prefixed, sizeof(prefixed), "t: %s", output);
                    prefixedReady = true;
                }
                Filters_SendChatToReceiver(i, client, prefixed);
            }
        }
    }
    else
    {
        CPrintToChatTeam(GetClientTeam(client), client, output, senderOutput);
    }
    PrintToServer("%s", output);
    return true;
}

