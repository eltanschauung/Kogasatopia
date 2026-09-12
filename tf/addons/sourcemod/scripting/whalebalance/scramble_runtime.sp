static const char SCRAMBLE_COMMANDS[][] =
{
    "sm_scramble",
    "sm_scwamble",
    "sm_sc",
    "sm_scram",
    "sm_shitteam"
};

static const char SCRAMBLE_KEYWORDS[][] =
{
    "scramble",
    "scwamble",
    "sc",
    "scram",
    "shitteam"
};

static const char SURRENDER_KEYWORDS[][] =
{
    "surrender",
    "itsover"
};

bool g_bPlayerRequestedScramble[MAXPLAYERS + 1];
bool g_bPlayerRequestedSurrender[MAXPLAYERS + 1];
int g_iPlayerSurrenderVoteTeam[MAXPLAYERS + 1];
int g_iScrambleVoteRequests = 0;
bool g_bVoteRunning = false;
bool g_bNativeVotes = false;
bool g_bVoteAllowLowPop = false;
WhaleVoteKind g_eActiveVoteKind = WhaleVote_None;
int g_iActiveSurrenderTeam = 0;
NativeVote g_hVote = null;
ConVar g_hScrambleLogEnabled = null;
ConVar g_hAutoRounds = null;
ConVar g_hVoteTime = null;
ConVar g_hCountBots = null;
ConVar g_hTopSwap = null;
ConVar g_hRandom = null;
ConVar g_hFragBalance = null;
ConVar g_hWhaleRankBalance = null;
ConVar g_hStackRedPayload = null;
ConVar g_hDisableTfAuto = null;
ConVar g_hShortRoundAutoSeconds = null;
ConVar g_hKothNoCapAuto = null;
ConVar g_hPayloadStompFirstCapSeconds = null;
ConVar g_hWinStreakAuto = null;
ConVar g_hNoSequentialAuto = null;
ConVar g_hBalanceMedics = null;
ConVar g_hMpScrambleTeamsAuto = null;
int g_iRoundsSinceAuto = 0;
bool g_bAutoScramblePendingRoundStart = false;
float g_flAutoScramblePendingRoundStartUntil = 0.0;
bool g_bExecuteSwapImmediately = false;
bool g_bSuppressSwapRespawn = false;
bool g_bKothRedCapped = false;
bool g_bKothBluCapped = false;
bool g_bPayloadStompCheckedThisRound = false;
int g_iRoundCaptureCount = 0;
int g_iLastFullRoundWinner = 0;
int g_iWinStreak = 0;
bool g_bPendingFullRoundWin = false;
int g_iPendingFullRoundWinningTeam = 0;
bool g_bScrambledThisRound = false;
bool g_bLastRoundHadScramble = false;
bool g_bStackRedPayloadAttempted = false;
int g_iRoundStartTimestamp = 0;

#define TEAM_BLU  3
#define MAX_RANDOM_SWAP  5
#define MAX_TOP_SWAP  MAX_RANDOM_SWAP
#define MAX_SWAP_BUFFER  MAX_RANDOM_SWAP
#define MIN_SCRAMBLE_PLAYERS  3
#define SCORE_BALANCE_ENTRY_SUM  0
#define SCORE_BALANCE_ENTRY_CLIENT0  1
#define SCORE_BALANCE_ENTRY_CELLS  (SCORE_BALANCE_ENTRY_CLIENT0 + MAX_SWAP_BUFFER)

enum ScrambleScoreKind
{
    ScrambleScore_Frags = 0,
    ScrambleScore_WhaleRank
};
#define SCRAMBLE_PLAYER_PERCENT_DIVISOR  5
#define SCRAMBLE_SETUP_POLISH_DELAY  0.75
#define SCRAMBLE_SETUP_UBER_DELAY  0.25
#define SCRAMBLE_AUTO_RESPAWN_SWEEP_DELAY  0.85
#define SCRAMBLE_AUTO_RESPAWN_SWEEP_REPEAT_DELAY  1.10
#define SCRAMBLE_AUTO_RESPAWN_SWEEP_COUNT  3
#define WHALESCRAMBLE_STATS_DETAIL_MAX 384
void WhaleScramble_OnPluginStart()
{
    UpdateNativeVotes();
    g_hScrambleLogEnabled = CreateConVar("sm_whalescramble_log", "1", "Enable whalescramble debug logging.", _, true, 0.0, true, 1.0);
    LogWhale("Plugin started.");
    g_hAutoRounds = CreateConVar("whalescramble_rounds", "2", "Automatically start a scramble vote every X rounds. 0/1 disables auto vote.", _, true, 0.0, true, 100.0);
    g_hVoteTime = CreateConVar("whalescramble_votetime", "4", "Scramble vote duration in seconds.", _, true, 1.0, true, 30.0);
    g_hCountBots = CreateConVar("whalescramble_count_bots", "1", "Include bots when selecting whale scramble targets.", _, true, 0.0, true, 1.0);
    g_hTopSwap = CreateConVar("sm_ws_topswap", "0", "Enable topswap scramble mode.", _, true, 0.0, true, 1.0);
    g_hRandom = CreateConVar("sm_ws_random", "1", "Enable random scramble mode.", _, true, 0.0, true, 1.0);
    g_hFragBalance = CreateConVar("sm_ws_frags", "1", "Enable frag-balanced random scramble mode.", _, true, 0.0, true, 1.0);
    g_hWhaleRankBalance = CreateConVar("sm_ws_whaletracker_ranks", "0", "Enable WhaleTracker rank-balanced scramble mode.", _, true, 0.0, true, 1.0);
    g_hStackRedPayload = CreateConVar("whalescramble_stack_red_pl", "1", "Run one RED-favored 60:40 WhaleTracker balance per payload map when setup teams become ready.", _, true, 0.0, true, 1.0);
    g_hDisableTfAuto = CreateConVar("sm_whalescramble_disable_tf_auto", "1", "Disable TF2's built-in mp_scrambleteams_auto while WhaleScramble owns auto scrambles.", _, true, 0.0, true, 1.0);
    g_hShortRoundAutoSeconds = CreateConVar("sm_whalescramble_short_round_seconds", "60", "Automatically whale scramble when the previous round duration is under this many seconds. 0 disables.", _, true, 0.0, true, 600.0);
    g_hKothNoCapAuto = CreateConVar("sm_whalescramble_koth_no_cap", "1", "Automatically whale scramble when a full KOTH round ends with either team never capturing the point.", _, true, 0.0, true, 1.0);
    g_hPayloadStompFirstCapSeconds = CreateConVar("sm_whalescramble_payload_stomp_first_cap_seconds", "100", "Immediately whale scramble when BLU captures the first payload control point within this many seconds. 0 disables.", _, true, 0.0, true, 600.0);
    g_hWinStreakAuto = CreateConVar("sm_whalescramble_win_streak", "2", "Automatically whale scramble after one team wins this many full rounds in a row. 0 disables.", _, true, 0.0, true, 20.0);
    g_hNoSequentialAuto = CreateConVar("sm_whalescramble_no_sequential", "1", "Block auto scrambles from happening in consecutive rounds or more than once in one round.", _, true, 0.0, true, 1.0);
    g_hBalanceMedics = CreateConVar("sm_whalescramble_balance_medics", "1", "After a scramble, give a medic-less team one Medic when the opposing team has more than one.", _, true, 0.0, true, 1.0);
    g_hMpScrambleTeamsAuto = FindConVar("mp_scrambleteams_auto");
    for (int i = 0; i < sizeof(SCRAMBLE_COMMANDS); i++)
    {
        RegConsoleCmd(SCRAMBLE_COMMANDS[i], Command_Scramble);
    }
    RegConsoleCmd("sm_votescramble", Command_Scramble);
    RegConsoleCmd("sm_whalescramble", Command_Scramble);
    RegConsoleCmd("sm_surrender", Command_SurrenderRound);
    RegConsoleCmd("sm_itsover", Command_SurrenderRound);
    RegAdminCmd("sm_forcescramble", Command_WhaleScramble, ADMFLAG_GENERIC, "Immediately perform a whale scramble.");
    RegAdminCmd("sm_forcewhalescramble", Command_WhaleScramble, ADMFLAG_GENERIC, "Immediately perform a whale scramble.");
    RegAdminCmd("sm_whalebalance", Command_WhaleBalance, ADMFLAG_GENERIC, "Balance by WhaleTracker rank; optionally favor red/blu 60:40.");
    RegAdminCmd("sm_whalescramblevote", Command_ForceScrambleVote, ADMFLAG_GENERIC, "Force a whale scramble vote.");
    RegAdminCmd("sm_forcescramblevote", Command_ForceScrambleVote, ADMFLAG_GENERIC, "Force a whale scramble vote.");

    AddCommandListener(SayListener, "say");
    AddCommandListener(SayListener, "say_team");
    // This handler reads "full_round" and "team", so it needs a copied event.
    HookEvent("teamplay_round_win", Event_RoundWin, EventHookMode_Post);
    HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("teamplay_point_captured", Event_PointCaptured, EventHookMode_Post);
    HookEvent("teamplay_game_over", Event_GameOver, EventHookMode_PostNoCopy);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
}

public void OnConfigsExecuted()
{
    ApplyEngineScramblePolicy();
}

public void OnAllPluginsLoaded()
{
    UpdateNativeVotes();
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "nativevotes", false))
    {
        UpdateNativeVotes();
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "nativevotes", false))
    {
        g_bNativeVotes = false;
    }
}

void WhaleScramble_OnMapStart()
{
    g_bStackRedPayloadAttempted = false;
    ResetVotes();
    ClearAutoScramblePending();
    ApplyEngineScramblePolicy();
    g_iRoundsSinceAuto = 0;
    ResetWinStreakTracking();
    LogWhale("Map start: votes reset; team-balance controller owns runtime state.");
}

void WhaleScramble_OnMapEnd()
{
    ResetVotes();
    ClearAutoScramblePending();
    g_iRoundsSinceAuto = 0;
    ResetWinStreakTracking();
    LogWhale("Map end: votes reset.");
}

void WhaleScramble_OnPluginEnd()
{
    ResetVotes();
    TeamBalance_CancelScramble();
    ClearAutoScramblePending();
    LogWhale("Plugin ended.");
}

void WhaleScramble_OnClientDisconnect(int client)
{
    if (client <= 0 || client > MaxClients)
        return;
    if (g_bPlayerRequestedScramble[client])
    {
        g_bPlayerRequestedScramble[client] = false;
        if (g_iScrambleVoteRequests > 0)
        {
            g_iScrambleVoteRequests--;
        }
    }
    if (g_bPlayerRequestedSurrender[client])
    {
        LogWhale("Cleared surrender vote on disconnect: %N team=%d.", client, GetClientTeam(client));
        ClearClientSurrenderVote(client);
        LogSurrenderState("disconnect_clear");
    }
}

public void OnClientPutInServer(int client)
{
    if (client <= 0 || client > MaxClients)
        return;
}

public Action Command_Scramble(int client, int args)
{
    LogWhale("Scramble request via command from %N (%d).", client, GetClientUserId(client));
    HandleVoteRequest(client, WhaleVote_Scramble);
    return Plugin_Handled;
}

public Action Command_SurrenderRound(int client, int args)
{
    LogWhale("Surrender request via command from %N (%d).", client, GetClientUserId(client));
    HandleVoteRequest(client, WhaleVote_Surrender);
    return Plugin_Handled;
}

public Action Command_WhaleScramble(int client, int args)
{
    LogWhale("Admin whale scramble requested by %N (%d).", client, GetClientUserId(client));
    StartConfiguredWhaleScramble(client, true, true, true);
    return Plugin_Handled;
}

public Action Command_WhaleBalance(int client, int args)
{
    int favoredTeam = 0;
    if (args > 0)
    {
        char teamArg[16];
        GetCmdArg(1, teamArg, sizeof(teamArg));
        if (StrEqual(teamArg, "red", false))
        {
            favoredTeam = TEAM_RED;
        }
        else if (StrEqual(teamArg, "blu", false) || StrEqual(teamArg, "blue", false))
        {
            favoredTeam = TEAM_BLU;
        }
        else
        {
            ReplyToCommand(client, "[whalescramble] Usage: sm_whalebalance [red|blu|blue]");
            return Plugin_Handled;
        }
    }

    if (client > 0)
    {
        LogWhale("Admin WhaleTracker rank balance requested by %N (%d), favoredTeam=%d.", client, GetClientUserId(client), favoredTeam);
    }
    else
    {
        LogWhale("WhaleTracker rank balance requested by server console, favoredTeam=%d.", favoredTeam);
    }
    StartWhaleRankBalanceScramble(client, true, true, true, favoredTeam);
    return Plugin_Handled;
}

public void DGM_OnSetupTeamRatioReady(int realTeamPlayers, int connectedClients)
{
    if (g_bStackRedPayloadAttempted || g_hStackRedPayload == null || !g_hStackRedPayload.BoolValue)
    {
        return;
    }

    char gamemodeKey[16];
    if (GetFeatureStatus(FeatureType_Native, "DGM_GetGameModeKey") != FeatureStatus_Available
        || !DGM_GetGameModeKey(gamemodeKey, sizeof(gamemodeKey))
        || !StrEqual(gamemodeKey, "pl"))
    {
        return;
    }

    g_bStackRedPayloadAttempted = true;
    LogWhale(
        "Payload setup team ratio ready: realTeamPlayers=%d connectedClients=%d; starting RED-favored WhaleTracker balance.",
        realTeamPlayers,
        connectedClients);
    LogWhaleStat(
        "auto_scramble_decision",
        "trigger=setup_team_ratio|result=triggered|mode=whaletracker_rank|favored_team=%d|real_team_players=%d|connected_clients=%d",
        TEAM_RED,
        realTeamPlayers,
        connectedClients);
    StartWhaleRankBalanceScramble(0, false, true, true, TEAM_RED);
}

public Action Command_ForceScrambleVote(int client, int args)
{
    LogWhale("Admin force vote requested by %N (%d).", client, GetClientUserId(client));
    StartVote(client, false, true, WhaleVote_Scramble);
    return Plugin_Handled;
}

public Action SayListener(int client, const char[] command, int argc)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
    {
        return Plugin_Continue;
    }

    char text[192];
    GetCmdArgString(text, sizeof(text));
    TrimString(text);
    StripQuotes(text);
    TrimString(text);

    if (!text[0])
    {
        return Plugin_Continue;
    }

    for (int i = 0; i < sizeof(SCRAMBLE_KEYWORDS); i++)
    {
        if (StrEqual(text, SCRAMBLE_KEYWORDS[i], false))
        {
            LogWhale("Scramble request via chat from %N (%d): %s", client, GetClientUserId(client), text);
            HandleVoteRequest(client, WhaleVote_Scramble);
            return Plugin_Handled;
        }
    }

    for (int i = 0; i < sizeof(SURRENDER_KEYWORDS); i++)
    {
        if (StrEqual(text, SURRENDER_KEYWORDS[i], false))
        {
            LogWhale("Surrender request via chat from %N (%d): %s", client, GetClientUserId(client), text);
            HandleVoteRequest(client, WhaleVote_Surrender);
            return Plugin_Handled;
        }
    }

    return Plugin_Continue;
}

public void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
    bool fullRound = event.GetBool("full_round");
    LogWhale("Round win: full_round=%d voteRunning=%d activeKind=%d activeTeam=%d.",
        fullRound ? 1 : 0,
        g_bVoteRunning ? 1 : 0,
        g_eActiveVoteKind,
        g_iActiveSurrenderTeam);
    LogWhaleStat("round_context", "full_round=%d|winning_team=%d|vote_running=%d|active_kind=%d|active_team=%d",
        fullRound ? 1 : 0,
        event.GetInt("team"),
        g_bVoteRunning ? 1 : 0,
        g_eActiveVoteKind,
        g_iActiveSurrenderTeam);
    ResetSurrenderVotes("round_win");

    if (fullRound)
    {
        CreateTimer(0.1, Timer_CheckShortRoundAutoScramble, _, TIMER_FLAG_NO_MAPCHANGE);
        CheckKothNoCapAutoScramble();
        QueueFullRoundWinForWinStreak(event.GetInt("team"));
        g_bLastRoundHadScramble = g_bScrambledThisRound;
    }

    if (g_hAutoRounds == null)
    {
        return;
    }

    // full_round is 1 if the entire map/round is over (Red lost or Blue finished final stage)
    // full_round is 0 if it was just a stage completion (e.g., Goldrush Stage 1)
    if (!fullRound)
        return;

    int roundsRequired = g_hAutoRounds.IntValue;
    if (roundsRequired <= 1)
    {
        return;
    }

    g_iRoundsSinceAuto++;
    if (g_iRoundsSinceAuto < roundsRequired)
    {
        return;
    }

    TryArmAutoScrambleForNextRound("round-count");
}

public Action Timer_CheckShortRoundAutoScramble(Handle timer)
{
    if (g_hShortRoundAutoSeconds == null)
    {
        return Plugin_Stop;
    }

    int threshold = g_hShortRoundAutoSeconds.IntValue;
    if (threshold <= 0)
    {
        return Plugin_Stop;
    }

    if (GetFeatureStatus(FeatureType_Native, "DGM_GetLastRoundDurationSeconds") != FeatureStatus_Available)
    {
        LogWhale("Short-round auto scramble skipped: DGM_GetLastRoundDurationSeconds unavailable.");
        LogWhaleStat("auto_scramble_decision", "trigger=short_round|result=skipped|reason=native_unavailable|threshold=%d", threshold);
        return Plugin_Stop;
    }

    int duration = DGM_GetLastRoundDurationSeconds();
    if (duration <= 0 || duration >= threshold)
    {
        LogWhale("Short-round auto scramble skipped: duration=%d threshold=%d.", duration, threshold);
        LogWhaleStat("auto_scramble_decision", "trigger=short_round|result=skipped|reason=duration|duration=%d|threshold=%d", duration, threshold);
        return Plugin_Stop;
    }

    if (TryArmAutoScrambleForNextRound("short-round"))
    {
        CPrintToChatAll("{blue}[WhaleScramble]{default} Round ended in under {lightgreen}%d{default} seconds, scrambling!", threshold);
        LogWhale("Short-round auto scramble armed: duration=%d threshold=%d.", duration, threshold);
    }
    return Plugin_Stop;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    g_bKothRedCapped = false;
    g_bKothBluCapped = false;
    g_bPayloadStompCheckedThisRound = false;
    g_iRoundCaptureCount = 0;
    g_bScrambledThisRound = false;
    g_iRoundStartTimestamp = GetTime();

    CheckPendingFullRoundWinAutoScramble();

    if (!ConsumeAutoScramblePending())
    {
        return;
    }

    g_bExecuteSwapImmediately = true;
    g_bSuppressSwapRespawn = true;
    bool started = StartAutoScramble(true);
    g_bSuppressSwapRespawn = false;
    g_bExecuteSwapImmediately = false;

    if (!started)
    {
        LogWhale("Pending auto scramble could not start on round start.");
        LogWhaleStat("auto_scramble_decision", "trigger=pending_round_start|result=failed|reason=start_failed");
    }
}

public void Event_PointCaptured(Event event, const char[] name, bool dontBroadcast)
{
    int team = event.GetInt("team");
    g_iRoundCaptureCount++;

    if (team == TEAM_RED)
    {
        g_bKothRedCapped = true;
    }
    else if (team == TEAM_BLU)
    {
        g_bKothBluCapped = true;
    }

    if (team == TEAM_BLU && g_iRoundCaptureCount == 1 && !g_bPayloadStompCheckedThisRound)
    {
        g_bPayloadStompCheckedThisRound = true;
        CreateTimer(0.1, Timer_CheckPayloadStompFirstCapture, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_CheckPayloadStompFirstCapture(Handle timer)
{
    if (g_hPayloadStompFirstCapSeconds == null)
    {
        return Plugin_Stop;
    }

    int threshold = g_hPayloadStompFirstCapSeconds.IntValue;
    if (threshold <= 0)
    {
        return Plugin_Stop;
    }

    if (!IsCurrentPayloadGamemode())
    {
        LogWhaleStat("auto_scramble_decision", "trigger=payload_first_cap|result=skipped|reason=gamemode|threshold=%d", threshold);
        return Plugin_Stop;
    }

    if (GetFeatureStatus(FeatureType_Native, "DGM_GetRecentControlPointCaptureIntervalSeconds") != FeatureStatus_Available)
    {
        LogWhale("Payload first-cap auto scramble skipped: DGM_GetRecentControlPointCaptureIntervalSeconds unavailable.");
        LogWhaleStat("auto_scramble_decision", "trigger=payload_first_cap|result=skipped|reason=native_unavailable|threshold=%d", threshold);
        return Plugin_Stop;
    }

    int interval = DGM_GetRecentControlPointCaptureIntervalSeconds();
    if (interval <= 0 || interval > threshold)
    {
        LogWhale("Payload first-cap auto scramble skipped: interval=%d threshold=%d.", interval, threshold);
        LogWhaleStat("auto_scramble_decision", "trigger=payload_first_cap|result=skipped|reason=interval|interval=%d|threshold=%d", interval, threshold);
        return Plugin_Stop;
    }

    if (StartAutoScramble(true))
    {
        CPrintToChatAll("{blue}[WhaleScramble]{default} Payload stomp detected: first point captured in {lightgreen}%d{default} seconds, scrambling!", interval);
        LogWhale("Payload first-cap auto scramble triggered: interval=%d threshold=%d.", interval, threshold);
        LogWhaleStat("auto_scramble_decision", "trigger=payload_first_cap|result=triggered|interval=%d|threshold=%d", interval, threshold);
    }
    else
    {
        LogWhale("Payload first-cap auto scramble failed to start: interval=%d threshold=%d.", interval, threshold);
        LogWhaleStat("auto_scramble_decision", "trigger=payload_first_cap|result=failed|interval=%d|threshold=%d", interval, threshold);
    }

    return Plugin_Stop;
}

static void CheckKothNoCapAutoScramble()
{
    if (g_hKothNoCapAuto == null || !g_hKothNoCapAuto.BoolValue)
    {
        return;
    }

    if (!IsCurrentKothGamemode())
    {
        return;
    }

    if (g_bKothRedCapped && g_bKothBluCapped)
    {
        return;
    }

    if (TryArmAutoScrambleForNextRound("koth-no-cap"))
    {
        CPrintToChatAll("{blue}[WhaleScramble]{default} KOTH steamroll detected, scrambling!");
        LogWhale("KOTH no-cap auto scramble armed: redCapped=%d bluCapped=%d.", g_bKothRedCapped ? 1 : 0, g_bKothBluCapped ? 1 : 0);
    }
}

static bool IsCurrentKothGamemode()
{
    if (GetFeatureStatus(FeatureType_Native, "DGM_GetGameModeKey") != FeatureStatus_Available)
    {
        return false;
    }

    char gamemodeKey[32];
    if (!DGM_GetGameModeKey(gamemodeKey, sizeof(gamemodeKey)))
    {
        return false;
    }

    return StrEqual(gamemodeKey, "koth", false);
}

static bool IsCurrentPayloadGamemode()
{
    if (GetFeatureStatus(FeatureType_Native, "DGM_GetGameModeKey") != FeatureStatus_Available)
    {
        return false;
    }

    char gamemodeKey[32];
    if (!DGM_GetGameModeKey(gamemodeKey, sizeof(gamemodeKey)))
    {
        return false;
    }

    return StrEqual(gamemodeKey, "pl", false);
}

static void ClearPendingFullRoundWin()
{
    g_bPendingFullRoundWin = false;
    g_iPendingFullRoundWinningTeam = 0;
}

static void ResetWinStreakTracking()
{
    g_iLastFullRoundWinner = 0;
    g_iWinStreak = 0;
    ClearPendingFullRoundWin();
}

static void QueueFullRoundWinForWinStreak(int winningTeam)
{
    if (g_bPendingFullRoundWin)
    {
        LogWhale(
            "Full-round win already queued for win-streak; replacing queuedTeam=%d with team=%d.",
            g_iPendingFullRoundWinningTeam,
            winningTeam);
    }

    g_bPendingFullRoundWin = true;
    g_iPendingFullRoundWinningTeam = winningTeam;
}

static void CheckPendingFullRoundWinAutoScramble()
{
    if (!g_bPendingFullRoundWin)
    {
        return;
    }

    int winningTeam = g_iPendingFullRoundWinningTeam;
    ClearPendingFullRoundWin();
    LogWhale("Processing queued full-round win for win-streak: team=%d.", winningTeam);
    CheckWinStreakAutoScramble(winningTeam);
}

static void CheckWinStreakAutoScramble(int winningTeam)
{
    if (g_hWinStreakAuto == null)
    {
        return;
    }

    int threshold = g_hWinStreakAuto.IntValue;
    if (threshold <= 0)
    {
        return;
    }

    if (winningTeam != TEAM_RED && winningTeam != TEAM_BLU)
    {
        g_iLastFullRoundWinner = 0;
        g_iWinStreak = 0;
        return;
    }

    if (winningTeam == g_iLastFullRoundWinner)
    {
        g_iWinStreak++;
    }
    else
    {
        g_iLastFullRoundWinner = winningTeam;
        g_iWinStreak = 1;
    }

    if (g_iWinStreak < threshold)
    {
        return;
    }

    if (TryArmAutoScrambleForNextRound("win-streak"))
    {
        CPrintToChatAll("{blue}[WhaleScramble]{default} Win streak reached {lightgreen}%d{default}, scrambling!", threshold);
        LogWhale("Win-streak auto scramble armed: team=%d streak=%d threshold=%d.", winningTeam, g_iWinStreak, threshold);
    }
}

public void Event_GameOver(Event event, const char[] name, bool dontBroadcast)
{
    ClearAutoScramblePending();
    ClearPendingFullRoundWin();
    LogWhale("Game over: auto scramble pending state cleared.");
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    if (!g_bPlayerRequestedSurrender[client])
    {
        return;
    }

    int oldTeam = event.GetInt("oldteam");
    int newTeam = event.GetInt("team");
    if (event.GetBool("disconnect") || oldTeam != newTeam)
    {
        LogWhale("Cleared surrender vote on team change: %N old=%d new=%d disconnect=%d.", client, oldTeam, newTeam, event.GetBool("disconnect") ? 1 : 0);
        ClearClientSurrenderVote(client);
        LogSurrenderState("team_change_clear");
    }
}

