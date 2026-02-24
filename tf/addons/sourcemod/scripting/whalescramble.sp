// Whale scramble vote helper (NativeVotes)
#include <sourcemod>
#include <morecolors>
#include <nativevotes>
#include <tf2_stocks>

#pragma semicolon 1
#pragma newdecls required

native int FilterAlerts_SuppressTeamAlertWindow(float seconds);
native bool Filters_GetChatName(int client, char[] buffer, int maxlen);

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

bool g_bPlayerVoted[MAXPLAYERS + 1];
bool g_bScrambledThisMap[MAXPLAYERS + 1];
int g_iVoteRequests = 0;
bool g_bVoteRunning = false;
bool g_bNativeVotes = false;
bool g_bVoteAllowLowPop = false;
NativeVote g_hVote = null;
ConVar g_hLogEnabled = null;
ConVar g_hAutoRounds = null;
ConVar g_hVoteTime = null;
ConVar g_hDisableRespawnTimes = null;
ConVar g_hCountBots = null;
int g_iRespawnDisableRefs = 0;
int g_iRoundsSinceAuto = 0;
char g_sLogPath[PLATFORM_MAX_PATH];

#define TEAM_RED  2
#define TEAM_BLU  3
#define MAX_SWAP  4

public Plugin myinfo =
{
    name = "whalescramble",
    author = "Hombre",
    description = "Player-triggered whale scramble vote helper",
    version = "1.1.0",
    url = "https://kogasa.tf"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    MarkNativeAsOptional("FilterAlerts_SuppressTeamAlertWindow");
    MarkNativeAsOptional("Filters_GetChatName");
    return APLRes_Success;
}

public void OnPluginStart()
{
    UpdateNativeVotes();
    g_hLogEnabled = CreateConVar("sm_whalescramble_log", "1", "Enable whalescramble debug logging.", _, true, 0.0, true, 1.0);
    BuildPath(Path_SM, g_sLogPath, sizeof(g_sLogPath), "logs/whalescramble.log");
    LogWhale("Plugin started.");
    g_hAutoRounds = CreateConVar("votescramble_rounds", "2", "Automatically start a scramble vote every X rounds. 0/1 disables auto vote.", _, true, 0.0, true, 100.0);
    g_hVoteTime = CreateConVar("votescramble_votetime", "4", "Scramble vote duration in seconds.", _, true, 1.0, true, 30.0);
    g_hDisableRespawnTimes = FindConVar("mp_disable_respawn_times");
    g_hCountBots = CreateConVar("whalescramble_count_bots", "0", "Include bots when selecting whale scramble targets.", _, true, 0.0, true, 1.0);

    for (int i = 0; i < sizeof(SCRAMBLE_COMMANDS); i++)
    {
        RegConsoleCmd(SCRAMBLE_COMMANDS[i], Command_Scramble);
    }
    RegConsoleCmd("sm_votescramble", Command_Scramble);
    RegAdminCmd("sm_forcescramble", Command_WhaleScramble, ADMFLAG_GENERIC, "Immediately perform a whale scramble.");
    RegAdminCmd("sm_whalescramble", Command_WhaleScramble, ADMFLAG_GENERIC, "Immediately perform a whale scramble.");
    RegAdminCmd("sm_whalescramblevote", Command_ForceScrambleVote, ADMFLAG_GENERIC, "Force a whale scramble vote.");
    RegAdminCmd("sm_forcescramblevote", Command_ForceScrambleVote, ADMFLAG_GENERIC, "Force a whale scramble vote.");

    AddCommandListener(SayListener, "say");
    AddCommandListener(SayListener, "say_team");
    HookEvent("teamplay_round_win", Event_RoundWin, EventHookMode_PostNoCopy);
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

public void OnMapStart()
{
    ResetVotes();
    g_iRoundsSinceAuto = 0;
    g_iRespawnDisableRefs = 0;
    SetDisableRespawnTimes(false);
    for (int i = 1; i <= MaxClients; i++)
    {
        g_bScrambledThisMap[i] = false;
    }
    LogWhale("Map start: immunity cleared, votes reset.");
}

public void OnMapEnd()
{
    ResetVotes();
    g_iRoundsSinceAuto = 0;
    LogWhale("Map end: votes reset.");
}

public void OnPluginEnd()
{
    SetDisableRespawnTimes(false);
    ResetVotes();
    LogWhale("Plugin ended.");
}

public void OnClientDisconnect(int client)
{
    if (client <= 0 || client > MaxClients)
        return;
    g_bScrambledThisMap[client] = false;
    if (g_bPlayerVoted[client])
    {
        g_bPlayerVoted[client] = false;
        if (g_iVoteRequests > 0)
        {
            g_iVoteRequests--;
        }
    }
}

public void OnClientPutInServer(int client)
{
    if (client <= 0 || client > MaxClients)
        return;
    g_bScrambledThisMap[client] = false;
}

public Action Command_Scramble(int client, int args)
{
    LogWhale("Scramble request via command from %N (%d).", client, GetClientUserId(client));
    HandleScrambleRequest(client);
    return Plugin_Handled;
}

public Action Command_WhaleScramble(int client, int args)
{
    LogWhale("Admin whale scramble requested by %N (%d).", client, GetClientUserId(client));
    StartWhaleScramble(client, true, true);
    return Plugin_Handled;
}

public Action Command_ForceScrambleVote(int client, int args)
{
    LogWhale("Admin force vote requested by %N (%d).", client, GetClientUserId(client));
    StartScrambleVote(client, false, true);
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
            HandleScrambleRequest(client);
            return Plugin_Handled;
        }
    }

    return Plugin_Continue;
}

public void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
    if (g_hAutoRounds == null)
    {
        return;
    }

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

    if (StartAutoScramble(true))
    {
        g_iRoundsSinceAuto = 0;
    }
}

static void UpdateNativeVotes()
{
    g_bNativeVotes = LibraryExists("nativevotes") && NativeVotes_IsVoteTypeSupported(NativeVotesType_Custom_YesNo);
}

static void HandleScrambleRequest(int client)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
        return;

    if (g_bVoteRunning || NativeVotes_IsVoteInProgress() || IsVoteInProgress())
    {
        CPrintToChat(client, "{blue}[WhaleScramble]{default} A vote is already running.");
        LogWhale("Vote request rejected: vote already running (client %N).", client);
        return;
    }

    if (g_bPlayerVoted[client])
    {
        CPrintToChat(client, "{blue}[WhaleScramble]{default} You already requested a scramble.");
        LogWhale("Vote request rejected: already requested (client %N).", client);
        return;
    }

    g_bPlayerVoted[client] = true;
    g_iVoteRequests++;

    CPrintToChatAll("{blue}[WhaleScramble]{default} %N requested a scramble (%d/4).", client, g_iVoteRequests);
    LogWhale("Vote request counted: %N (%d/%d).", client, g_iVoteRequests, 4);

    if (g_iVoteRequests >= 4)
    {
        StartScrambleVote(client, false, false);
    }
}

static bool StartScrambleVote(int client, bool suppressFeedback, bool allowLowPop)
{
    LogWhale("Starting vote: caller=%d allowLowPop=%d suppressFeedback=%d.", client, allowLowPop ? 1 : 0, suppressFeedback ? 1 : 0);
    if (!g_bNativeVotes)
    {
        if (!suppressFeedback && client > 0 && IsClientInGame(client))
        {
            CPrintToChat(client, "{blue}[WhaleScramble]{default} NativeVotes is unavailable.");
        }
        LogWhale("Vote start failed: NativeVotes unavailable.");
        return false;
    }

    if (g_bVoteRunning || NativeVotes_IsVoteInProgress() || IsVoteInProgress())
    {
        if (!suppressFeedback && client > 0 && IsClientInGame(client))
        {
            CPrintToChat(client, "{blue}[WhaleScramble]{default} A vote is already running.");
        }
        LogWhale("Vote start failed: vote already running.");
        return false;
    }

    int delay = NativeVotes_CheckVoteDelay();
    if (delay > 0)
    {
        if (!suppressFeedback && client > 0 && IsClientInGame(client))
        {
            NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_Recent, delay);
        }
        LogWhale("Vote start failed: vote delay %d.", delay);
        return false;
    }

    if (!NativeVotes_IsNewVoteAllowed())
    {
        if (!suppressFeedback && client > 0 && IsClientInGame(client))
        {
            CPrintToChat(client, "{blue}[WhaleScramble]{default} A vote is not allowed right now.");
        }
        LogWhale("Vote start failed: new vote not allowed.");
        return false;
    }

    if (g_hVote != null)
    {
        g_hVote.Close();
        g_hVote = null;
    }

    g_hVote = new NativeVote(ScrambleVoteHandler, NativeVotesType_Custom_YesNo, MENU_ACTIONS_ALL);
    NativeVotes_SetTitle(g_hVote, "Whale scramble teams?");

    int voteTime = 4;
    if (g_hVoteTime != null)
    {
        voteTime = g_hVoteTime.IntValue;
    }
    if (voteTime < 1)
    {
        voteTime = 1;
    }

    g_bVoteRunning = NativeVotes_DisplayToAll(g_hVote, voteTime);
    if (!g_bVoteRunning)
    {
        g_hVote.Close();
        g_hVote = null;
        g_bVoteAllowLowPop = false;
        LogWhale("Vote start failed: display to all returned false.");
        return false;
    }

    g_bVoteAllowLowPop = allowLowPop;
    LogWhale("Vote started: duration=%d allowLowPop=%d.", voteTime, allowLowPop ? 1 : 0);
    return true;
}

static bool StartAutoScramble(bool suppressFeedback)
{
    if (g_bVoteRunning || NativeVotes_IsVoteInProgress() || IsVoteInProgress())
    {
        return false;
    }

    if (!suppressFeedback)
    {
        CPrintToChatAll("{blue}[WhaleScramble]{default} Auto scramble triggered.");
    }

    LogWhale("Auto scramble triggered.");
    return StartWhaleScramble(0, !suppressFeedback, false);
}

public int ScrambleVoteHandler(NativeVote vote, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_End:
        {
            vote.Close();
            g_hVote = null;
            g_bVoteRunning = false;
            g_bVoteAllowLowPop = false;
            ResetVotes();
            LogWhale("Vote ended.");
            return 0;
        }
        case MenuAction_VoteCancel:
        {
            if (param1 == VoteCancel_NoVotes)
            {
                NativeVotes_DisplayFail(vote, NativeVotesFail_NotEnoughVotes);
            }
            else
            {
                NativeVotes_DisplayFail(vote, NativeVotesFail_Generic);
            }
            g_bVoteAllowLowPop = false;
            LogWhale("Vote cancelled: %d.", param1);
            return 0;
        }
        case MenuAction_VoteEnd:
        {
            int votes = 0;
            int totalVotes = 0;
            NativeVotes_GetInfo(param2, votes, totalVotes);

            if (totalVotes <= 0)
            {
                NativeVotes_DisplayFail(vote, NativeVotesFail_NotEnoughVotes);
                LogWhale("Vote failed: no votes.");
                return 0;
            }

            int yesVotes = (param1 == NATIVEVOTES_VOTE_YES) ? votes : (totalVotes - votes);
            float yesPercent = float(yesVotes) / float(totalVotes);

            if (yesPercent < 0.50)
            {
                NativeVotes_DisplayFail(vote, NativeVotesFail_Loses);
                CPrintToChatAll("Vote failed (Yes %.0f%%).", yesPercent * 100.0);
                g_bVoteAllowLowPop = false;
                LogWhale("Vote failed: yes=%d total=%d (%.1f%%).", yesVotes, totalVotes, yesPercent * 100.0);
            }
            else
            {
                bool started = StartWhaleScramble(0, true, g_bVoteAllowLowPop);
                if (started)
                {
                    NativeVotes_DisplayPassCustom(vote, "Vote passed. Whale scrambling teams...");
                    LogWhale("Vote passed: yes=%d total=%d (%.1f%%).", yesVotes, totalVotes, yesPercent * 100.0);
                }
                else
                {
                    NativeVotes_DisplayPassCustom(vote, "Vote passed. Scramble conditions not met.");
                    LogWhale("Vote passed but scramble conditions not met.");
                }
                g_bVoteAllowLowPop = false;
            }
            return 0;
        }
    }
    return 0;
}

static void ResetVotes()
{
    g_iVoteRequests = 0;
    g_bVoteRunning = false;
    for (int i = 1; i <= MaxClients; i++)
    {
        g_bPlayerVoted[i] = false;
    }
}

static bool StartWhaleScramble(int issuer, bool broadcastFailures, bool allowLowPop)
{
    LogWhale("StartWhaleScramble: issuer=%d allowLowPop=%d.", issuer, allowLowPop ? 1 : 0);
    g_iRoundsSinceAuto = 0;
    int totalPlayers = 0;
    int redCount = 0;
    int bluCount = 0;
    int redEligible = 0;
    int bluEligible = 0;

    int topRed[MAX_SWAP];
    int topBlu[MAX_SWAP];
    int topRedScore[MAX_SWAP];
    int topBluScore[MAX_SWAP];

    for (int i = 0; i < MAX_SWAP; i++)
    {
        topRed[i] = 0;
        topBlu[i] = 0;
        topRedScore[i] = -999999;
        topBluScore[i] = -999999;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i)) continue;
        if (IsFakeClient(i) && (g_hCountBots == null || !g_hCountBots.BoolValue)) continue;

        int team = GetClientTeam(i);
        if (team != TEAM_RED && team != TEAM_BLU) continue;

        totalPlayers++;
        if (team == TEAM_RED) redCount++;
        else bluCount++;

        if (g_bScrambledThisMap[i]) continue;

        if (team == TEAM_RED) redEligible++;
        else bluEligible++;

        int score = GetScrambleScore(i, false);
        if (team == TEAM_RED)
        {
            InsertTopN(i, score, topRed, topRedScore, MAX_SWAP);
        }
        else
        {
            InsertTopN(i, score, topBlu, topBluScore, MAX_SWAP);
        }
    }

    LogWhale("Counts: total=%d red=%d blu=%d eligibleRed=%d eligibleBlu=%d.", totalPlayers, redCount, bluCount, redEligible, bluEligible);
    ClearScrambleImmunity();

    int swapCount = 0;
    bool lowPop = (totalPlayers < 12);

    if (!lowPop)
    {
        if (totalPlayers >= 20)
        {
            swapCount = 4;
        }
        else
        {
            swapCount = 3;
        }
    }
    else if (allowLowPop)
    {
        swapCount = redEligible < bluEligible ? redEligible : bluEligible;
        if (swapCount > 2)
        {
            swapCount = 2;
        }
    }

    bool needsFallback = (redEligible < swapCount || bluEligible < swapCount);
    if (allowLowPop && lowPop && swapCount == 0)
    {
        needsFallback = true;
    }
    if (needsFallback)
    {
        LogWhale("Eligibility low; recalculating without class/immunity filters.");
        redEligible = 0;
        bluEligible = 0;
        for (int i = 0; i < MAX_SWAP; i++)
        {
            topRed[i] = 0;
            topBlu[i] = 0;
            topRedScore[i] = -999999;
            topBluScore[i] = -999999;
        }

        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i)) continue;
            if (IsFakeClient(i) && (g_hCountBots == null || !g_hCountBots.BoolValue)) continue;

            int team = GetClientTeam(i);
            if (team != TEAM_RED && team != TEAM_BLU) continue;

            if (team == TEAM_RED) redEligible++;
            else bluEligible++;

            int score = GetScrambleScore(i, true);
            if (team == TEAM_RED)
            {
                InsertTopN(i, score, topRed, topRedScore, MAX_SWAP);
            }
            else
            {
                InsertTopN(i, score, topBlu, topBluScore, MAX_SWAP);
            }
        }
        if (allowLowPop && lowPop)
        {
            swapCount = redEligible < bluEligible ? redEligible : bluEligible;
            if (swapCount > 2)
            {
                swapCount = 2;
            }
        }
    }

    if (swapCount == 0)
    {
        if (allowLowPop && lowPop)
        {
            NotifyFailure(issuer, broadcastFailures, "Not enough eligible players to swap (RED=%d BLU=%d).", redEligible, bluEligible);
            LogWhale("Scramble aborted: not enough eligible players (red=%d blu=%d).", redEligible, bluEligible);
        }
        else
        {
            NotifyFailure(issuer, broadcastFailures, "Need at least 12 players (current: %d).", totalPlayers);
            LogWhale("Scramble aborted: not enough players (total=%d).", totalPlayers);
        }
        return false;
    }

    if (redCount < swapCount || bluCount < swapCount)
    {
        NotifyFailure(issuer, broadcastFailures, "Each team needs at least %d players (RED=%d BLU=%d).", swapCount, redCount, bluCount);
        LogWhale("Scramble aborted: team size too small (swap=%d red=%d blu=%d).", swapCount, redCount, bluCount);
        return false;
    }

    if (redEligible < swapCount || bluEligible < swapCount)
    {
        NotifyFailure(issuer, broadcastFailures, "Each team needs at least %d eligible players (RED=%d BLU=%d).", swapCount, redEligible, bluEligible);
        LogWhale("Scramble aborted: eligible too small (swap=%d red=%d blu=%d).", swapCount, redEligible, bluEligible);
        return false;
    }

    DataPack pack = new DataPack();
    pack.WriteCell(issuer > 0 ? GetClientUserId(issuer) : 0);
    pack.WriteCell(swapCount);
    for (int i = 0; i < swapCount; i++)
    {
        pack.WriteCell(GetClientUserId(topRed[i]));
    }
    for (int i = 0; i < swapCount; i++)
    {
        pack.WriteCell(GetClientUserId(topBlu[i]));
    }

    g_iRespawnDisableRefs++;
    SetDisableRespawnTimes(true);
    CreateTimer(0.1, Timer_DoSwap, pack, TIMER_FLAG_NO_MAPCHANGE);
    LogWhale("Scramble scheduled: swapCount=%d.", swapCount);
    return true;
}

public Action Timer_DoSwap(Handle timer, DataPack pack)
{
    pack.Reset();
    int issuerUserId = pack.ReadCell();
    int swapCount = pack.ReadCell();

    int redIds[MAX_SWAP];
    int bluIds[MAX_SWAP];

    for (int i = 0; i < swapCount; i++)
    {
        redIds[i] = pack.ReadCell();
    }
    for (int i = 0; i < swapCount; i++)
    {
        bluIds[i] = pack.ReadCell();
    }

    delete pack;

    if (GetFeatureStatus(FeatureType_Native, "FilterAlerts_SuppressTeamAlertWindow") == FeatureStatus_Available)
    {
        FilterAlerts_SuppressTeamAlertWindow(2.0);
    }

    int moved = 0;
    int pairR[MAX_SWAP];
    int pairB[MAX_SWAP];
    int pairCount = 0;
    for (int i = 0; i < swapCount; i++)
    {
        int r = GetClientOfUserId(redIds[i]);
        int b = GetClientOfUserId(bluIds[i]);

        if (r <= 0 || b <= 0) continue;
        if (!IsClientInGame(r) || !IsClientInGame(b)) continue;
        if (GetClientTeam(r) != TEAM_RED || GetClientTeam(b) != TEAM_BLU) continue;

        if (pairCount < MAX_SWAP)
        {
            pairR[pairCount] = r;
            pairB[pairCount] = b;
            pairCount++;
        }

        if (r > 0 && IsClientInGame(r) && GetClientTeam(r) == TEAM_RED)
        {
            ChangeClientTeam(r, TEAM_BLU);
            g_bScrambledThisMap[r] = true;
        }
        if (b > 0 && IsClientInGame(b) && GetClientTeam(b) == TEAM_BLU)
        {
            ChangeClientTeam(b, TEAM_RED);
            g_bScrambledThisMap[b] = true;
        }
    }

    moved = pairCount * 2;
    if (moved > 0)
    {
        CPrintToChatAll("{tomato}[{purple}Gap{tomato}]{default} {gold}Whalescrambling{default} %d players!", moved);
        LogWhale("Scramble executed: moved=%d pairs=%d.", moved, pairCount);
        for (int i = 0; i < pairCount; i++)
        {
            int r = pairR[i];
            int b = pairB[i];

            char nameR[256];
            char nameB[256];
            bool hasFilterR = GetFiltersNameOrEmpty(r, nameR, sizeof(nameR));
            bool hasFilterB = GetFiltersNameOrEmpty(b, nameB, sizeof(nameB));

            int srcClient = r;
            bool useTeamColorR = false;
            bool useTeamColorB = false;

            if (!hasFilterR && !hasFilterB)
            {
                srcClient = r;
                useTeamColorR = true;
            }
            else if (!hasFilterR)
            {
                srcClient = r;
                useTeamColorR = true;
            }
            else if (!hasFilterB)
            {
                srcClient = b;
                useTeamColorB = true;
            }

            if (!hasFilterR)
            {
                BuildFallbackName(r, useTeamColorR, nameR, sizeof(nameR));
            }
            if (!hasFilterB)
            {
                BuildFallbackName(b, useTeamColorB, nameB, sizeof(nameB));
            }

            CPrintToChatAllEx(srcClient, "%s <-> %s", nameR, nameB);
            LogWhale("Pair %d: %N <-> %N.", i + 1, r, b);
        }

        for (int i = 0; i < pairCount; i++)
        {
            int r = pairR[i];
            int b = pairB[i];
            if (r > 0 && IsClientInGame(r))
            {
                PrintHintText(r, "You have been WhaleScrambled!");
            }
            if (b > 0 && IsClientInGame(b))
            {
                PrintHintText(b, "You have been WhaleScrambled!");
            }
        }
    }
    else
    {
        int issuer = GetClientOfUserId(issuerUserId);
        if (issuer > 0 && IsClientInGame(issuer))
        {
            ReplyToCommand(issuer, "[whalescramble] No eligible players to swap.");
        }
        LogWhale("Scramble executed: no eligible pairs.");
    }

    CreateTimer(8.0, Timer_EnableRespawnTimes, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_EnableRespawnTimes(Handle timer)
{
    if (g_iRespawnDisableRefs > 0)
    {
        g_iRespawnDisableRefs--;
    }
    if (g_iRespawnDisableRefs == 0)
    {
        SetDisableRespawnTimes(false);
    }

    return Plugin_Stop;
}

static void NotifyFailure(int issuer, bool broadcastFailures, const char[] fmt, any ...)
{
    char buffer[256];
    VFormat(buffer, sizeof(buffer), fmt, 4);
    if (issuer > 0 && IsClientInGame(issuer))
    {
        ReplyToCommand(issuer, "[whalescramble] %s", buffer);
        return;
    }
    if (broadcastFailures)
    {
        CPrintToChatAll("{blue}[WhaleScramble]{default} %s", buffer);
    }
}

static void InsertTopN(int client, int score, int clients[MAX_SWAP], int scores[MAX_SWAP], int maxCount)
{
    for (int i = 0; i < maxCount; i++)
    {
        if (score > scores[i])
        {
            for (int j = maxCount - 1; j > i; j--)
            {
                scores[j] = scores[j - 1];
                clients[j] = clients[j - 1];
            }
            scores[i] = score;
            clients[i] = client;
            return;
        }
    }
}

static int GetScrambleScore(int client, bool ignoreClass)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return 0;
    }

    if (!ignoreClass)
    {
        TFClassType cls = TF2_GetPlayerClass(client);
        if (cls == TFClass_Spy || cls == TFClass_Engineer || cls == TFClass_Medic)
        {
            return 0;
        }
    }

    return GetClientFrags(client);
}

static void ClearScrambleImmunity()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        g_bScrambledThisMap[i] = false;
    }
}

static void LogWhale(const char[] fmt, any ...)
{
    if (g_hLogEnabled == null || !g_hLogEnabled.BoolValue)
    {
        return;
    }

    char buffer[512];
    VFormat(buffer, sizeof(buffer), fmt, 2);
    LogToFileEx(g_sLogPath, "%s", buffer);
}

static void SetDisableRespawnTimes(bool enabled)
{
    if (g_hDisableRespawnTimes == null)
    {
        return;
    }
    g_hDisableRespawnTimes.IntValue = enabled ? 1 : 0;
}

static bool GetFiltersNameOrEmpty(int client, char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    if (client <= 0 || !IsClientInGame(client))
    {
        return false;
    }

    if (GetFeatureStatus(FeatureType_Native, "Filters_GetChatName") == FeatureStatus_Available)
    {
        if (Filters_GetChatName(client, buffer, maxlen) && buffer[0] != '\0')
        {
            return true;
        }
    }
    return false;
}

static void BuildFallbackName(int client, bool useTeamColor, char[] buffer, int maxlen)
{
    buffer[0] = '\0';
    if (client <= 0 || !IsClientInGame(client))
    {
        return;
    }

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));

    if (useTeamColor)
    {
        Format(buffer, maxlen, "{teamcolor}%s{default}", name);
        return;
    }

    char colorTag[16];
    switch (GetClientTeam(client))
    {
        case TEAM_RED: strcopy(colorTag, sizeof(colorTag), "{red}");
        case TEAM_BLU: strcopy(colorTag, sizeof(colorTag), "{blue}");
        case 4: strcopy(colorTag, sizeof(colorTag), "{green}");
        case 5: strcopy(colorTag, sizeof(colorTag), "{yellow}");
        default: strcopy(colorTag, sizeof(colorTag), "{default}");
    }

    Format(buffer, maxlen, "%s%s{default}", colorTag, name);
}
