// Shared chat precondition: console/out-of-range/connecting/disconnected slots
// must never reach player-state natives such as IsPlayerAlive/GetClientTeam.
bool Filters_IsInGameChatClient(int client)
{
    return client >= 1 && client <= MaxClients && IsClientInGame(client);
}

void BuildDeathPrefix(int client, char[] deadPrefix, int length)
{
    deadPrefix[0] = '\0';
    if (!Filters_IsInGameChatClient(client))
        return;

    if (!IsPlayerAlive(client))
    {
        if (GetClientTeam(client) == 1)
        {
            strcopy(deadPrefix, length, "{grey}*SPEC*{default} ");
            return;
        }
        strcopy(deadPrefix, length, "*DIDDY* ");
    }
}
