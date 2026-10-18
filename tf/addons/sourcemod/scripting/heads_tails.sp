#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#include <morecolors>

#undef REQUIRE_PLUGIN
#include <filters_api>
#define REQUIRE_PLUGIN

#define EIGHT_BALL_COOLDOWN 5.0
float g_NextEightBallUse[MAXPLAYERS + 1];

static const char g_EightBallAnswers[][] =
{
    "{green}It is certain.",
    "{green}It is decidedly so.",
    "{green}Without a doubt.",
    "{green}Yes, definitely.",
    "{green}You may rely on it.",
    "{green}As I see it, yes.",
    "{green}Most likely.",
    "{green}Outlook good.",
    "{green}Yes.",
    "{green}Signs point to yes.",
    "{gold}Reply hazy, try again.",
    "{gold}Ask again later.",
    "{gold}Better not tell you now.",
    "{gold}Cannot predict now.",
    "{gold}Concentrate and ask again.",
    "{red}Don't count on it.",
    "{red}My reply is no.",
    "{red}My sources say no.",
    "{red}Outlook not so good.",
    "{red}Very doubtful."
};

public Plugin myinfo =
{
    name = "Heads or Tails",
    author = "Hombre",
    description = "Flips a coin and answers Magic 8 Ball questions in chat.",
    version = "1.1.1",
    url = "https://kogasa.tf"
};

public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int maxlen)
{
    MarkNativeAsOptional("Filters_GetChatName");
    return APLRes_Success;
}

public void OnPluginStart()
{
    RegConsoleCmd("sm_toss", Command_Toss, "Flip a coin.");
    RegConsoleCmd("sm_coinflip", Command_Toss, "Flip a coin.");
    RegConsoleCmd("sm_flip", Command_Toss, "Flip a coin.");
    RegConsoleCmd("sm_8ball", Command_EightBall, "Ask the Magic 8 Ball a question.");
    RegConsoleCmd("sm_eightball", Command_EightBall, "Ask the Magic 8 Ball a question.");
    RegConsoleCmd("sm_magiceightball", Command_EightBall, "Ask the Magic 8 Ball a question.");
}

public void OnClientPutInServer(int client)
{
    g_NextEightBallUse[client] = 0.0;
}

public Action Command_EightBall(int client, int args)
{
    if (client > 0 && IsClientInGame(client))
    {
        // Engine time stays monotonic across map changes; all aliases share this gate.
        float now = GetEngineTime();
        float remaining = g_NextEightBallUse[client] - now;
        if (remaining > 0.0)
        {
            CPrintToChat(client, "{magenta}[Magic 8 Ball]{default} Wait %d seconds before asking again.", RoundToCeil(remaining));
            return Plugin_Handled;
        }
        g_NextEightBallUse[client] = now + EIGHT_BALL_COOLDOWN;

        int answer = GetRandomInt(0, sizeof(g_EightBallAnswers) - 1);
        CPrintToChatAll("{magenta}[Magic 8 Ball] %s{default}", g_EightBallAnswers[answer]);
    }
    return Plugin_Handled;
}

public Action Command_Toss(int client, int args)
{
    if (client > 0 && IsClientInGame(client))
    {
        TossCoin(client);
    }
    return Plugin_Handled;
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] args)
{
    if (client <= 0 || IsChatTrigger())
    {
        return;
    }

    if (StrEqual(args, "toss", false) || StrEqual(args, "coinflip", false) || StrEqual(args, "flip", false))
    {
        TossCoin(client);
    }
}

void TossCoin(int client)
{
    char displayName[256];
    BuildCoinFlipDisplayName(client, displayName, sizeof(displayName));

    if (GetRandomInt(0, 1) == 0)
    {
        CPrintToChatAll("%s rolled {gold}Heads!", displayName);
    }
    else
    {
        CPrintToChatAll("%s rolled {grey}Tails!", displayName);
    }
}

void BuildCoinFlipDisplayName(int client, char[] buffer, int maxlen)
{
    if (GetFeatureStatus(FeatureType_Native, "Filters_GetChatName") == FeatureStatus_Available
        && Filters_GetChatName(client, buffer, maxlen) && buffer[0])
    {
        char teamColor[16];
        switch (GetClientTeam(client))
        {
            case 2: strcopy(teamColor, sizeof(teamColor), "{red}");
            case 3: strcopy(teamColor, sizeof(teamColor), "{blue}");
            default: strcopy(teamColor, sizeof(teamColor), "{gold}");
        }
        ReplaceString(buffer, maxlen, "{teamcolor}", teamColor, false);
        return;
    }

    FormatEx(buffer, maxlen, "{gold}%N{default}", client);
}
