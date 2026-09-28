#include <sourcemod>

public Plugin myinfo =
{
    name = "Thule Join Message",
    author = "Kogasatopia",
    description = "Broadcasts a fixed join message on command.",
    version = "1.0"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_thulejoin", Command_ThuleJoin);
}

public Action Command_ThuleJoin(int client, int args)
{
    PrintToChatAll("captain thule has joined the game");
    return Plugin_Handled;
}
