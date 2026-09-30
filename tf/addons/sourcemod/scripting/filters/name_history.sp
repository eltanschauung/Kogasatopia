bool g_SteamNameHistoryReady;
char g_ForcedPersonaName[MAXPLAYERS + 1][MAX_NAME_LENGTH];
int g_ForcedPersonaSerial[MAXPLAYERS + 1];

void Filters_NameHistoryInit()
{
    HookEvent("player_changename", Filters_RecordNameChange, EventHookMode_Pre);
}

void Filters_SetPersonaOverride(int client, const char[] name)
{
    Filters_RecordSteamName(client);
    g_ForcedPersonaSerial[client] = GetClientSerial(client);
    strcopy(g_ForcedPersonaName[client], sizeof(g_ForcedPersonaName[]), name);
    SetClientName(client, name);
}

bool Filters_IsPersonaOverride(int client, const char[] name)
{
    return g_ForcedPersonaSerial[client] == GetClientSerial(client)
        && StrEqual(g_ForcedPersonaName[client], name);
}

public Action Filters_RecordNameChange(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!Filters_IsRealClientInGame(client)) return Plugin_Continue;
    char persona[MAX_NAME_LENGTH];event.GetString("newname", persona, sizeof(persona));
    if (!Filters_IsPersonaOverride(client, persona)) Filters_RecordSteamName(client, persona);
    return Plugin_Continue;
}

void Filters_SeedNameHistory()
{
    g_SteamNameHistoryReady = true;
    // Preserve names already known at deployment. History contains one durable
    // row per exact spelling, including case changes, and is never pruned.
    g_hFiltersDb.Query(Filters_SimpleSqlCallback,
        "INSERT INTO filters_steam_name_history (steamid64, name, name_lower, first_seen, last_seen) "
        ... "SELECT steamid64, last_name, last_name_lower, updated_at, updated_at FROM filters_steam_names WHERE last_name <> '' "
        ... "ON DUPLICATE KEY UPDATE first_seen = LEAST(first_seen, VALUES(first_seen)), last_seen = GREATEST(last_seen, VALUES(last_seen))");
}
