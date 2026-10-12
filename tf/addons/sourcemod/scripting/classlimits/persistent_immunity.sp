// Uses WhaleScramble's shared asynchronous DB connection, but a separate table
// and in-memory cache: autobalance immunity never implies class-limit immunity.
StringMap g_ClassLimitImmunity = null;
StringMap g_ClassLimitImmunityPending = null;
bool g_bClassLimitImmunityReady;
int g_iClassLimitImmunityGeneration;

void ClassLimits_InitializePersistentImmunity()
{
    g_ClassLimitImmunity = new StringMap();
    g_ClassLimitImmunityPending = new StringMap();
    RegAdminCmd("sm_climmune", Command_ClassLimitImmune, ADMFLAG_GENERIC,
        "sm_climmune <name> - Toggle persistent class-limit immunity for a player.");
}

void ClassLimits_ClosePersistentImmunity()
{
    delete g_ClassLimitImmunity;
    delete g_ClassLimitImmunityPending;
}

void ClassLimits_InvalidateImmunityDatabase()
{
    g_bClassLimitImmunityReady = false;
    g_iClassLimitImmunityGeneration++;
    if (g_ClassLimitImmunityPending != null) g_ClassLimitImmunityPending.Clear();
    // Retain already-loaded immunity during a temporary DB outage.
}

void ClassLimits_LoadPersistentImmunity(Database db)
{
    db.Query(SQL_ClassLimitImmunitySchemaReady,
        "CREATE TABLE IF NOT EXISTS classlimits_immunity ("
        ... "steamid64 VARCHAR(32) NOT NULL PRIMARY KEY, "
        ... "immune TINYINT(1) NOT NULL DEFAULT 1)", g_iClassLimitImmunityGeneration);
}

public void SQL_ClassLimitImmunitySchemaReady(Database db, DBResultSet results, const char[] error, any generation)
{
    // Threaded queries supply cloned Database handles; compare our connection
    // generation, not the numeric handle identity.
    if (generation != g_iClassLimitImmunityGeneration) return;
    if (error[0])
    {
        LogError("[Class Limits] Persistent immunity schema failed: %s", error);
        if (Db_IsTransientError(error)) WhaleBalance_RequestImmunityDatabaseReconnect();
        return;
    }
    db.Query(SQL_ClassLimitImmunityLoaded,
        "SELECT steamid64 FROM classlimits_immunity WHERE immune != 0", generation);
}

public void SQL_ClassLimitImmunityLoaded(Database db, DBResultSet results, const char[] error, any generation)
{
    if (generation != g_iClassLimitImmunityGeneration) return;
    if (error[0] || results == null)
    {
        LogError("[Class Limits] Persistent immunity preload failed: %s", error);
        if (Db_IsTransientError(error)) WhaleBalance_RequestImmunityDatabaseReconnect();
        return;
    }
    g_ClassLimitImmunity.Clear();
    char steamId[32];
    while (results.FetchRow())
    {
        results.FetchString(0, steamId, sizeof(steamId));
        g_ClassLimitImmunity.SetValue(steamId, 1);
    }
    g_bClassLimitImmunityReady = true;
}

bool ClassLimits_IsPersistentlyImmune(int client)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client)
        || IsFakeClient(client) || g_ClassLimitImmunity == null) return false;
    char steamId[32];
    int value;
    return Kogasa_GetClientSteamId64(client, steamId, sizeof(steamId), true)
        && g_ClassLimitImmunity.GetValue(steamId, value) && value != 0;
}

public Action Command_ClassLimitImmune(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "[Class Limits] Usage: sm_climmune <client name/substring>");
        return Plugin_Handled;
    }
    if (g_hImmunityDb == null || !g_bClassLimitImmunityReady)
    {
        ReplyToCommand(client, "[Class Limits] Persistent immunity database is not ready.");
        return Plugin_Handled;
    }
    char targetArg[MAX_TARGET_LENGTH];
    GetCmdArgString(targetArg, sizeof(targetArg));
    TrimString(targetArg);
    StripQuotes(targetArg);
    int target = FindTarget(client, targetArg, true, false);
    if (target <= 0) return Plugin_Handled;
    char steamId[32];
    if (!Kogasa_GetClientSteamId64(target, steamId, sizeof(steamId), true))
    {
        ReplyToCommand(client, "[Class Limits] Target authentication is not ready.");
        return Plugin_Handled;
    }
    int value;
    if (g_ClassLimitImmunityPending.GetValue(steamId, value))
    {
        ReplyToCommand(client, "[Class Limits] An immunity change for this player is still pending.");
        return Plugin_Handled;
    }
    bool wasImmune = g_ClassLimitImmunity.GetValue(steamId, value) && value != 0;
    char escaped[65];
    if (!g_hImmunityDb.Escape(steamId, escaped, sizeof(escaped)))
    {
        ReplyToCommand(client, "[Class Limits] Could not prepare the immunity change.");
        return Plugin_Handled;
    }
    char query[256];
    if (wasImmune)
        FormatEx(query, sizeof(query), "DELETE FROM classlimits_immunity WHERE steamid64 = '%s'", escaped);
    else
        FormatEx(query, sizeof(query), "REPLACE INTO classlimits_immunity (steamid64, immune) VALUES ('%s', 1)", escaped);
    DataPack pack = new DataPack();
    pack.WriteCell(g_iClassLimitImmunityGeneration);
    pack.WriteCell(client > 0 ? GetClientUserId(client) : 0);
    pack.WriteCell(GetClientUserId(target));
    pack.WriteCell(wasImmune);
    pack.WriteString(steamId);
    g_ClassLimitImmunityPending.SetValue(steamId, 1);
    g_hImmunityDb.Query(SQL_ClassLimitImmunityToggled, query, pack);
    return Plugin_Handled;
}

public void SQL_ClassLimitImmunityToggled(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int generation = pack.ReadCell();
    int actor = GetClientOfUserId(pack.ReadCell());
    int target = GetClientOfUserId(pack.ReadCell());
    bool wasImmune = pack.ReadCell() != 0;
    char steamId[32];
    pack.ReadString(steamId, sizeof(steamId));
    delete pack;
    if (generation != g_iClassLimitImmunityGeneration) return;
    g_ClassLimitImmunityPending.Remove(steamId);
    if (error[0])
    {
        ReplyToCommand(actor, "[Class Limits] Failed to save persistent immunity; no change applied.");
        LogError("[Class Limits] Persistent immunity toggle failed: %s", error);
        if (Db_IsTransientError(error)) WhaleBalance_RequestImmunityDatabaseReconnect();
        return;
    }
    if (wasImmune) g_ClassLimitImmunity.Remove(steamId);
    else g_ClassLimitImmunity.SetValue(steamId, 1);
    if (target > 0 && IsClientInGame(target))
    {
        CPrintToChatAllEx(target, "{olive}[Class Limits]{default} {teamcolor}%N{default} is %s persistently class-limit-immune.",
            target, wasImmune ? "no longer" : "now");
        LogAction(actor, target, "\"%L\" %s persistent class-limit immunity for \"%L\"", actor, wasImmune ? "removed" : "granted", target);
    }
    else ReplyToCommand(actor, "[Class Limits] Persistent class-limit immunity %s.", wasImmune ? "removed" : "granted");
}
