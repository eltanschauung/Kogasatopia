#if defined _oblivion_messages_included
 #endinput
#endif
#define _oblivion_messages_included
#include <oblivion>

stock bool Oblivion_MessageVisible(int viewer, int actor, int other = 0)
{
    return viewer > 0 && IsClientInGame(viewer) && !IsFakeClient(viewer)
        && !Oblivion_ShouldHide(viewer, actor) && !Oblivion_ShouldHide(viewer, other);
}

stock bool Oblivion_SteamMessageVisible(int viewer, const char[] steamId)
{
    return !steamId[0] || GetFeatureStatus(FeatureType_Native, "Oblivion_IsSteamHidden") != FeatureStatus_Available
        || !Oblivion_IsSteamHidden(viewer, steamId);
}

stock void Oblivion_ChatAllEx(int author, const char[] format, any ...)
{
    char message[512];VFormat(message, sizeof(message), format, 3);
    for (int viewer = 1; viewer <= MaxClients; viewer++)
    {
        if (!Oblivion_MessageVisible(viewer, author)) continue;
        if (author > 0 && IsClientInGame(author)) CPrintToChatEx(viewer, author, "%s", message);
        else CPrintToChat(viewer, "%s", message);
    }
}

stock void Oblivion_ChatPairAllEx(int author, int other, const char[] format, any ...)
{
    char message[512];VFormat(message, sizeof(message), format, 4);
    for (int viewer = 1; viewer <= MaxClients; viewer++)
    {
        if (!Oblivion_MessageVisible(viewer, author, other)) continue;
        if (author > 0 && IsClientInGame(author)) CPrintToChatEx(viewer, author, "%s", message);
        else CPrintToChat(viewer, "%s", message);
    }
}

stock void Oblivion_ChatSteamAll(const char[] first, const char[] second, const char[] format, any ...)
{
    char message[512];VFormat(message, sizeof(message), format, 4);
    int author;
    char auth[32];
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client) && !IsFakeClient(client)
            && GetClientAuthId(client, AuthId_SteamID64, auth, sizeof(auth)) && StrEqual(auth, first)) { author = client;break; }
    if (!author) ReplaceString(message, sizeof(message), "{teamcolor}", "{gold}", false);
    for (int viewer = 1; viewer <= MaxClients; viewer++)
    {
        if (!Oblivion_MessageVisible(viewer, 0) || !Oblivion_SteamMessageVisible(viewer, first)
            || !Oblivion_SteamMessageVisible(viewer, second)) continue;
        if (author > 0) CPrintToChatEx(viewer, author, "%s", message);
        else CPrintToChat(viewer, "%s", message);
    }
}
