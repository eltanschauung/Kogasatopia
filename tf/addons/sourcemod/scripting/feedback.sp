#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define FEEDBACK_DB_CONFIG "sourcemod"
#define FEEDBACK_TABLE "whaletracker_feedback"
#define FEEDBACK_MAX_MESSAGE 512

Database g_hDatabase = null;
Handle g_hReconnectTimer = null;

public Plugin myinfo =
{
    name = "Feedback",
    author = "Hombre",
    description = "Stores !feedback in a database",
    version = "1.0.0",
    url = "https://kogasa.tf"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_feedback", Command_Feedback, "Submit feedback to server admins");
    ConnectToDatabase();
}

public void OnPluginEnd()
{
    if (g_hReconnectTimer != null)
    {
        CloseHandle(g_hReconnectTimer);
        g_hReconnectTimer = null;
    }

    if (g_hDatabase != null)
    {
        delete g_hDatabase;
        g_hDatabase = null;
    }
}

void ConnectToDatabase()
{
    if (g_hDatabase != null)
    {
        delete g_hDatabase;
        g_hDatabase = null;
    }

    if (g_hReconnectTimer != null)
    {
        CloseHandle(g_hReconnectTimer);
        g_hReconnectTimer = null;
    }

    if (!SQL_CheckConfig(FEEDBACK_DB_CONFIG))
    {
        LogError("[Feedback] Database config '%s' not found.", FEEDBACK_DB_CONFIG);
        return;
    }

    SQL_TConnect(SQL_OnDatabaseConnected, FEEDBACK_DB_CONFIG);
}

public Action Timer_ReconnectDatabase(Handle timer, any data)
{
    g_hReconnectTimer = null;
    ConnectToDatabase();
    return Plugin_Stop;
}

public void SQL_OnDatabaseConnected(Handle owner, Handle hndl, const char[] error, any data)
{
    if (hndl == null)
    {
        LogError("[Feedback] Database connect failed: %s", error[0] ? error : "unknown error");

        if (g_hReconnectTimer == null)
        {
            g_hReconnectTimer = CreateTimer(10.0, Timer_ReconnectDatabase, _, TIMER_FLAG_NO_MAPCHANGE);
        }
        return;
    }

    g_hDatabase = view_as<Database>(hndl);
    EnsureFeedbackTable();
}

void EnsureFeedbackTable()
{
    if (g_hDatabase == null)
    {
        return;
    }

    char query[512];
    Format(query, sizeof(query),
        "CREATE TABLE IF NOT EXISTS %s ("
        ... "id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, "
        ... "player_name VARCHAR(64) NOT NULL, "
        ... "message TEXT NOT NULL, "
        ... "created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP"
        ... ")",
        FEEDBACK_TABLE);

    SQL_TQuery(g_hDatabase, SQL_OnSchemaOpComplete, query);
}

public void SQL_OnSchemaOpComplete(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0])
    {
        LogError("[Feedback] Failed to ensure table: %s", error);
    }
}

public Action Command_Feedback(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }

    if (args < 1)
    {
        PrintToChat(client, "[Kogasa] Format: !feedback message");
        return Plugin_Handled;
    }

    if (g_hDatabase == null)
    {
        PrintToChat(client, "[Kogasa] Feedback database is unavailable right now.");
        return Plugin_Handled;
    }

    char message[FEEDBACK_MAX_MESSAGE];
    GetCmdArgString(message, sizeof(message));
    TrimString(message);
    StripQuotes(message);
    TrimString(message);

    if (message[0] == '\0')
    {
        PrintToChat(client, "[Kogasa] Format: !feedback message");
        return Plugin_Handled;
    }

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));
    TrimString(name);
    if (name[0] == '\0')
    {
        strcopy(name, sizeof(name), "unknown");
    }

    char escapedName[(MAX_NAME_LENGTH * 2) + 1];
    char escapedMessage[(FEEDBACK_MAX_MESSAGE * 2) + 1];
    SQL_EscapeString(g_hDatabase, name, escapedName, sizeof(escapedName));
    SQL_EscapeString(g_hDatabase, message, escapedMessage, sizeof(escapedMessage));

    char query[2048];
    Format(query, sizeof(query),
        "INSERT INTO %s (player_name, message, created_at) VALUES ('%s', '%s', NOW())",
        FEEDBACK_TABLE,
        escapedName,
        escapedMessage);

    SQL_TQuery(g_hDatabase, SQL_OnFeedbackInserted, query, GetClientUserId(client));
    PrintToChat(client, "[Kogasa] Feedback sent.");

    return Plugin_Handled;
}

public void SQL_OnFeedbackInserted(Database db, DBResultSet results, const char[] error, any data)
{
    if (!error[0])
    {
        return;
    }

    int client = GetClientOfUserId(data);
    if (client > 0 && IsClientInGame(client))
    {
        PrintToChat(client, "[Kogasa] Could not save feedback right now.");
    }

    LogError("[Feedback] Failed to save feedback: %s", error);

    if (StrContains(error, "Lost connection", false) != -1 || StrContains(error, "server has gone away", false) != -1)
    {
        ConnectToDatabase();
    }
}
