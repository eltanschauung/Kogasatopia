#if defined _public_messages_included
 #endinput
#endif
#define _public_messages_included

// Preserve author-aware team colors without filtering public recipients.
stock void PublicChat_AllEx(int author, const char[] format, any ...)
{
    char message[512];
    VFormat(message, sizeof(message), format, 3);
    for (int viewer = 1; viewer <= MaxClients; viewer++)
    {
        if (!IsClientInGame(viewer) || IsFakeClient(viewer)) continue;
        if (author > 0 && IsClientInGame(author)) CPrintToChatEx(viewer, author, "%s", message);
        else CPrintToChat(viewer, "%s", message);
    }
}

stock void PublicChat_SteamAll(const char[] steamId, const char[] format, any ...)
{
    char message[512], auth[32];
    VFormat(message, sizeof(message), format, 3);
    int author;
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client) && !IsFakeClient(client)
            && GetClientAuthId(client, AuthId_SteamID64, auth, sizeof(auth)) && StrEqual(auth, steamId))
        {
            author = client;
            break;
        }
    if (!author) ReplaceString(message, sizeof(message), "{teamcolor}", "{gold}", false);
    PublicChat_AllEx(author, "%s", message);
}
