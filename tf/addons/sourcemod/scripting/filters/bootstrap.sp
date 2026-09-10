public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int err_max)
{
    RegPluginLibrary("filters");
    CreateNative("Filters_IsRedlisted", Native_Filters_IsRedlisted);
    CreateNative("Filters_GetChatName", Native_Filters_GetChatName);
    CreateNative("Filters_GetSteamIdColorTag", Native_Filters_GetSteamIdColorTag);
    CreateNative("Filters_GetSteamIdChatName", Native_Filters_GetSteamIdChatName);
    CreateNative("Filters_GetLastRecordedSteamName", Native_Filters_GetLastRecordedSteamName);
    CreateNative("FilterAlerts_MarkAutobalance", Native_FilterAlerts_MarkAutobalance);
    CreateNative("FilterAlerts_SuppressTeamAlertWindow", Native_FilterAlerts_SuppressTeamAlertWindow);
    RegPluginLibrary("mutecheck");
    CreateNative("MuteCheck_GetMutedClientCount", Native_MuteCheck_GetMutedClientCount);
    MarkNativeAsOptional("AdminsDB_GetClientWhitelistLevel");
    MarkNativeAsOptional("Hugs_GetRapesGiven");
    MarkNativeAsOptional("Hugs_AreStatsLoaded");
    MarkNativeAsOptional("PointsStore_HasPurchase");
    MarkNativeAsOptional("WhaleTracker_GetCumulativeKills");
    MarkNativeAsOptional("WhaleTracker_AreStatsLoaded");
    MarkNativeAsOptional("Tags_GetSelectedTag");
    return APLRes_Success;
}

public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    Filters_EnsureCollections();
    LoadFilterConfig();
    Filters_CreateConVars();
    Filters_RegisterCookies();
    Filters_RegisterCommands();
    MuteCheck_Initialize();
    TidyChat_Initialize();
    RefreshHostAddress();
    Filters_SQLConnect();
    Filters_StartTimers();
    Filters_RestoreConnectedClients();
    Filters_UpdateVoiceOverrides();
}

static void Filters_EnsureCollections()
{
    if (g_WebNameColors == null)
    {
        g_WebNameColors = new StringMap();
    }
    if (g_ConnectQueue == null)
    {
        g_ConnectQueue = new ArrayList(sizeof(ConnectEvent));
    }
    if (g_PrenameIdRules == null)
    {
        g_PrenameIdRules = new StringMap();
    }
    if (g_PrenameOutputMap == null)
    {
        g_PrenameOutputMap = new StringMap();
    }
    BuildPath(Path_SM, g_PrenameDebugLogPath, sizeof(g_PrenameDebugLogPath), "logs/prename_migrate.log");
}

static void Filters_CreateConVars()
{
    g_sEnabled = CreateConVar("nobroly", "1", "If 0, filter chat to one word");
    g_sChatMode2 = CreateConVar("filtermode", "0", "0=off, 1=quarantine with mutual whitelist/blacklist visibility, 2=quarantine with whitelist monitoring only");
    g_hChatDebug = CreateConVar("filters_chat_debug", "0", "Enable verbose debug logging for chat relay");
    g_hChatFrontend = CreateConVar("filters_chat_frontend", "1", "Show frontend chat to all clients; blacklist level 3 clients still receive it when disabled");
    g_hCrossServerTag = CreateConVar("sm_filters_cross_sv_tag", "none", "Label stamped on database chat and shown when relayed to another server; none disables it.");
    g_hWebchatParsee = CreateConVar("sm_filters_webchat_parsee", "0", "If 1, render all webchat messages as Parsee in-game without changing frontend chat.", _, true, 0.0, true, 1.0);
    g_hFiltersEnabled = CreateConVar("filters", "0", "If 0, blacklist word matching is disabled.");
    g_hRedlistEnabled = CreateConVar("redlist", "0", "Enable/Disable redlist features.", _, true, 0.0, true, 1.0);
    g_hBlacklistMinLen = CreateConVar("filters_blacklist_minlen", "8", "Minimum message length to check blacklist words.");
    g_hFiltersChristmas = CreateConVar("filters_christmas", "0", "If 1, red chat is {axis} and blue chat is {green}.");
    g_hFiltersTeamChat = CreateConVar("teamchat", "0", "If 1, normal chat is sent to the sender's team only.");
    g_hPChat = CreateConVar("sm_pchat", "1", "If 0, filtered/monitored chat is only printed to server console and not shown to whitelisted clients.", _, true, 0.0, true, 1.0);
    g_hMuteDeafenEnabled = CreateConVar("sm_filters_mute_deafen", "0", "If 1, clients who mute another connected player cannot hear voice chat or send chat until no connected players are muted.", _, true, 0.0, true, 1.0);
    g_hParseeEnabled = CreateConVar("sm_filters_parsee", "0", "Enable Parsee archived messages and webchat impersonation.", _, true, 0.0, true, 1.0);
    g_hMemomanEnabled = CreateConVar("sm_filters_memoman", "0", "Enable Memoman archived messages and the Memoman event.", _, true, 0.0, true, 1.0);
    g_hFiltersCaseSensitive = CreateConVar("filters_case_sensitive", "1", "If 1, chat filters are case-sensitive (exact casing must match)");
    CreateConVar("sm_tidychat_version", TIDYCHAT_VERSION, "Tidy Chat Version", FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY);
    g_hTidyChatEnabled = CreateConVar("sm_tidychat_on", "1", "Enable Tidy Chat event cleanup.", _, true, 0.0, true, 1.0);
    g_hTidyChatVoice = CreateConVar("sm_tidychat_voice", "1", "Suppress voice subtitle messages.", _, true, 0.0, true, 1.0);
    g_hTidyChatDisconnect = CreateConVar("sm_tidychat_disconnect", "1", "Suppress stock disconnect messages.", _, true, 0.0, true, 1.0);
    g_hTidyChatTeam = CreateConVar("sm_tidychat_team", "1", "Replace stock team join messages.", _, true, 0.0, true, 1.0);
    g_hTidyChatCvar = CreateConVar("sm_tidychat_cvar", "1", "Suppress stock cvar messages.", _, true, 0.0, true, 1.0);
    HookConVarChange(g_sChatMode2, Filters_OnFilterModeChanged);
    HookConVarChange(g_hRedlistEnabled, Filters_OnRedlistChanged);
    HookConVarChange(g_hMuteDeafenEnabled, Filters_OnMuteDeafenChanged);
    HookConVarChange(g_hParseeEnabled, Filters_OnParseeChanged);
    HookConVarChange(g_hMemomanEnabled, Filters_OnMemomanChanged);
}

static void Filters_RegisterCookies()
{
    g_hCookieFilterWhitelist = RegClientCookie("filter_filterwhitelist", "Player is whitelisted from word filters only", CookieAccess_Protected);
    g_hCookieredlist = RegClientCookie("filter_redlist", "Player cannot hear blacklisted clients", CookieAccess_Protected);
    g_hCookieMuteArchivedSpeakers = RegClientCookie("filters_mute_parsee", "Player does not receive Parsee or Memoman messages", CookieAccess_Protected);
}

static void Filters_RegisterCommands()
{
    RegAdminCmd("sm_filterwhitelist", Command_FilterWhitelist, ADMFLAG_CHAT, "sm_filterwhitelist <player> - Whitelists a player from word filters only");
    RegAdminCmd("sm_unfilterwhitelist", Command_UnFilterWhitelist, ADMFLAG_CHAT, "sm_unfilterwhitelist <player> - Removes filter whitelist from a player");
    RegAdminCmd("sm_redlist", Command_redlist, ADMFLAG_CHAT, "sm_redlist <player> - redlist a player (can't hear blacklisted clients)");
    RegAdminCmd("sm_unredlist", Command_Unredlist, ADMFLAG_CHAT, "sm_unredlist <player> - Removes redlist from a player");
    RegAdminCmd("sm_redlists", Command_Listredlists, ADMFLAG_CHAT, "sm_redlists - Lists redlisted players");
    RegAdminCmd("sm_filtershelp", Command_FiltersHelp, ADMFLAG_CHAT, "sm_filtershelp - Shows filters convar help");
    RegConsoleCmd("sm_filters_debug", Command_FiltersDebug, "Show debug stats for filters");
    RegConsoleCmd("sm_colors", Command_Colors, "Show available chat colors");
    RegConsoleCmd("sm_colours", Command_Colors, "Show available chat colours");
    AddCommandListener(Listener_Colors, "colors");
    RegConsoleCmd("sm_gradientmenu", Command_GradientMenu, "Adjust where the second gradient color becomes full.");
    RegConsoleCmd("sm_gm", Command_GradientMenu, "Adjust where the second gradient color becomes full.");
    RegConsoleCmd("sm_prename", Command_Prename, "sm_prename <name_substring|steamid> <newname> (admins) or sm_prename <newname> (self)");
    RegConsoleCmd("sm_reset", Command_PrenameReset, "sm_reset <name|steamid> (admins) or sm_reset (self)");
    RegConsoleCmd("sm_parsee", Command_RandomParseeMessage, "Print a random archived Parsee message.");
    RegConsoleCmd("sm_randomparsee", Command_RandomParseeMessage, "Print a random archived Parsee message.");
    RegConsoleCmd("sm_randomparseemessage", Command_RandomParseeMessage, "Print a random archived Parsee message.");
    RegConsoleCmd("sm_memoman", Command_RandomMemomanMessage, "Print a random archived Memoman message.");
    // sm_memo remains reserved for the Points Store event.
    RegConsoleCmd("sm_bruh", Command_RandomMemomanMessage, "Print a random archived Memoman message.");
    RegConsoleCmd("sm_muteparsee", Command_MuteParsee, "Toggle Parsee and Memoman messages.");
    RegAdminCmd("sm_migrate", Command_PrenameMigrate, ADMFLAG_SLAY, "sm_migrate - Migrates legacy name rules to SteamID rules for connected clients");
    RegConsoleCmd("sm_websay", Command_WebSay, "Relay a web chat message to all players");
}
