void ConnectMailDatabase()
{
    g_MailDatabaseReady = false;
    delete g_MailDatabase;
    g_MailDatabase = null;

    if (g_MailReconnectTimer != null)
    {
        delete g_MailReconnectTimer;
        g_MailReconnectTimer = null;
    }

    if (!SQL_CheckConfig(MAIL_DB_CONFIG))
    {
        LogError("[server_mail] Missing databases.cfg entry '%s'.", MAIL_DB_CONFIG);
        ScheduleMailReconnect();
        return;
    }

    Database.Connect(SQL_OnMailDatabaseConnected, MAIL_DB_CONFIG);
}

void ScheduleMailReconnect()
{
    if (g_MailReconnectTimer == null)
    {
        g_MailReconnectTimer = CreateTimer(MAIL_RECONNECT_DELAY, Timer_MailReconnect, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_MailReconnect(Handle timer)
{
    g_MailReconnectTimer = null;
    ConnectMailDatabase();
    return Plugin_Stop;
}

public void SQL_OnMailDatabaseConnected(Database db, const char[] error, any data)
{
    if (db == null)
    {
        LogError("[server_mail] Database connection failed: %s", error);
        ScheduleMailReconnect();
        return;
    }

    g_MailDatabase = db;
    g_MailDatabase.SetCharset("utf8mb4");

    char driver[32];
    g_MailDatabase.Driver.GetIdentifier(driver, sizeof(driver));
    g_MailDatabaseIsMySql = StrEqual(driver, "mysql", false);
    EnsureMailSchema();
}

void EnsureMailSchema()
{
    char query[2048];
    if (g_MailDatabaseIsMySql)
    {
        FormatEx(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "mail_id BIGINT NOT NULL AUTO_INCREMENT, "
            ... "sender_steamid64 VARCHAR(32) NOT NULL DEFAULT '', "
            ... "sender_name VARCHAR(128) NOT NULL, "
            ... "receiver_steamid64 VARCHAR(32) NOT NULL, "
            ... "receiver_name VARCHAR(128) NOT NULL, "
            ... "created_at INT NOT NULL, "
            ... "title VARCHAR(128) NOT NULL, "
            ... "contents VARCHAR(512) NOT NULL, "
            ... "gems INT NOT NULL DEFAULT 0, "
            ... "gems_redeemed TINYINT NOT NULL DEFAULT 0, "
            ... "attachment_type VARCHAR(16) NOT NULL DEFAULT '', "
            ... "attachment_redeemed TINYINT NOT NULL DEFAULT 0, "
            ... "expires_at INT NOT NULL DEFAULT 0, "
            ... "read_at INT NOT NULL DEFAULT 0, "
            ... "idempotency_key VARCHAR(128) NULL, "
            ... "PRIMARY KEY (mail_id), "
            ... "UNIQUE KEY unique_mail_idempotency (idempotency_key), "
            ... "KEY idx_mail_receiver (receiver_steamid64, created_at), "
            ... "KEY idx_mail_sender (sender_steamid64, created_at)"
            ... ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
            MAIL_TABLE);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "CREATE TABLE IF NOT EXISTS %s ("
            ... "mail_id INTEGER PRIMARY KEY AUTOINCREMENT, "
            ... "sender_steamid64 VARCHAR(32) NOT NULL DEFAULT '', "
            ... "sender_name VARCHAR(128) NOT NULL, "
            ... "receiver_steamid64 VARCHAR(32) NOT NULL, "
            ... "receiver_name VARCHAR(128) NOT NULL, "
            ... "created_at INTEGER NOT NULL, "
            ... "title VARCHAR(128) NOT NULL, "
            ... "contents VARCHAR(512) NOT NULL, "
            ... "gems INTEGER NOT NULL DEFAULT 0, "
            ... "gems_redeemed INTEGER NOT NULL DEFAULT 0, "
            ... "attachment_type VARCHAR(16) NOT NULL DEFAULT '', "
            ... "attachment_redeemed INTEGER NOT NULL DEFAULT 0, "
            ... "expires_at INTEGER NOT NULL DEFAULT 0, "
            ... "read_at INTEGER NOT NULL DEFAULT 0, "
            ... "idempotency_key VARCHAR(128) UNIQUE)");
    }

    g_MailDatabase.Query(SQL_OnMailSchemaReady, query);
}

public void SQL_OnMailSchemaReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[server_mail] Mail schema creation failed: %s", error);
        ScheduleMailReconnect();
        return;
    }

    EnsureMailExpiryColumn();
}

void EnsureMailExpiryColumn()
{
    char query[256];
    if (g_MailDatabaseIsMySql)
    {
        FormatEx(query, sizeof(query),
            "ALTER TABLE %s ADD COLUMN IF NOT EXISTS expires_at INT NOT NULL DEFAULT 0 AFTER gems_redeemed",
            MAIL_TABLE);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "ALTER TABLE %s ADD COLUMN expires_at INTEGER NOT NULL DEFAULT 0",
            MAIL_TABLE);
    }
    g_MailDatabase.Query(SQL_OnMailExpiryColumnReady, query);
}

public void SQL_OnMailExpiryColumnReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0'
        && StrContains(error, "duplicate column", false) == -1
        && StrContains(error, "already exists", false) == -1)
    {
        LogError("[server_mail] Mail expiry schema migration failed: %s", error);
        ScheduleMailReconnect();
        return;
    }

    EnsureMailReadColumn();
}

void EnsureMailReadColumn()
{
    char query[256];
    if (g_MailDatabaseIsMySql)
    {
        FormatEx(query, sizeof(query),
            "ALTER TABLE %s ADD COLUMN IF NOT EXISTS read_at INT NOT NULL DEFAULT 1 AFTER expires_at",
            MAIL_TABLE);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "ALTER TABLE %s ADD COLUMN read_at INTEGER NOT NULL DEFAULT 1",
            MAIL_TABLE);
    }
    g_MailDatabase.Query(SQL_OnMailReadColumnReady, query);
}

public void SQL_OnMailReadColumnReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0'
        && StrContains(error, "duplicate column", false) == -1
        && StrContains(error, "already exists", false) == -1)
    {
        LogError("[server_mail] Mail read-state schema migration failed: %s", error);
        ScheduleMailReconnect();
        return;
    }

    EnsureMailAttachmentTypeColumn();
}

void EnsureMailAttachmentTypeColumn()
{
    char query[256];
    if (g_MailDatabaseIsMySql)
    {
        FormatEx(query, sizeof(query),
            "ALTER TABLE %s ADD COLUMN IF NOT EXISTS attachment_type VARCHAR(16) NOT NULL DEFAULT '' AFTER gems_redeemed",
            MAIL_TABLE);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "ALTER TABLE %s ADD COLUMN attachment_type VARCHAR(16) NOT NULL DEFAULT ''",
            MAIL_TABLE);
    }
    g_MailDatabase.Query(SQL_OnMailAttachmentTypeColumnReady, query);
}

public void SQL_OnMailAttachmentTypeColumnReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0'
        && StrContains(error, "duplicate column", false) == -1
        && StrContains(error, "already exists", false) == -1)
    {
        LogError("[server_mail] Mail attachment-type migration failed: %s", error);
        ScheduleMailReconnect();
        return;
    }

    char query[256];
    if (g_MailDatabaseIsMySql)
    {
        FormatEx(query, sizeof(query),
            "ALTER TABLE %s ADD COLUMN IF NOT EXISTS attachment_redeemed TINYINT NOT NULL DEFAULT 0 AFTER attachment_type",
            MAIL_TABLE);
    }
    else
    {
        FormatEx(query, sizeof(query),
            "ALTER TABLE %s ADD COLUMN attachment_redeemed INTEGER NOT NULL DEFAULT 0",
            MAIL_TABLE);
    }
    g_MailDatabase.Query(SQL_OnMailAttachmentStateColumnReady, query);
}

public void SQL_OnMailAttachmentStateColumnReady(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0'
        && StrContains(error, "duplicate column", false) == -1
        && StrContains(error, "already exists", false) == -1)
    {
        LogError("[server_mail] Mail attachment-state migration failed: %s", error);
        ScheduleMailReconnect();
        return;
    }

    Stimulus_EnsureSchema();
}

void FinishMailSchemaReady()
{
    g_MailDatabaseReady = true;
    char recoveryQuery[256];
    // Preserve at-most-once delivery if the server stops between applying an
    // attachment and persisting its final redeemed state.
    FormatEx(recoveryQuery, sizeof(recoveryQuery),
        "UPDATE %s SET attachment_redeemed = 1 WHERE attachment_redeemed = 2",
        MAIL_TABLE);
    g_MailDatabase.Query(SQL_OnInterruptedAttachmentsRecovered, recoveryQuery);
    Stimulus_BackfillExistingExpiry();
    Stimulus_CleanupExpiredMail();
}

public void SQL_OnInterruptedAttachmentsRecovered(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0] != '\0')
    {
        LogError("[server_mail] Failed to recover interrupted mail attachments: %s", error);
    }
}

bool EscapeMailSql(const char[] input, char[] output, int maxlen)
{
    output[0] = '\0';
    return g_MailDatabaseReady && g_MailDatabase != null
        && g_MailDatabase.Escape(input, output, maxlen);
}

bool GetMailClientIdentity(int client, char[] steamId, int steamLen, char[] name, int nameLen)
{
    steamId[0] = '\0';
    name[0] = '\0';

    if (client == 0)
    {
        strcopy(name, nameLen, "kogasa.tf");
        return true;
    }

    if (!IsMailClient(client)
        || !Kogasa_GetClientSteamId64(client, steamId, steamLen, true)
        || !GetClientName(client, name, nameLen))
    {
        return false;
    }

    TrimString(name);
    return name[0] != '\0';
}

void BuildColoredMailName(int client, const char[] steamId, const char[] fallbackName, char[] output, int maxlen)
{
    output[0] = '\0';
    if (IsMailClient(client)
        && GetFeatureStatus(FeatureType_Native, "Filters_GetChatName") == FeatureStatus_Available
        && Filters_GetChatName(client, output, maxlen)
        && output[0] != '\0')
    {
        return;
    }

    char colorTag[32];
    colorTag[0] = '\0';
    if (steamId[0] != '\0'
        && GetFeatureStatus(FeatureType_Native, "Filters_GetSteamIdColorTag") == FeatureStatus_Available)
    {
        Filters_GetSteamIdColorTag(steamId, colorTag, sizeof(colorTag));
    }

    if (colorTag[0] == '\0')
    {
        strcopy(colorTag, sizeof(colorTag), IsMailClient(client) ? "{teamcolor}" : "{default}");
    }
    Format(output, maxlen, "%s%s", colorTag, fallbackName);
}

void GetCurrencyFormatting(char[] colorTag, int colorLen, char[] currencyName, int nameLen)
{
    strcopy(colorTag, colorLen, "{cyan}");
    strcopy(currencyName, nameLen, "Gems");

    ConVar color = FindConVar("sm_points_store_currency_color");
    if (color != null)
    {
        char rawColor[32];
        color.GetString(rawColor, sizeof(rawColor));
        TrimString(rawColor);
        if (rawColor[0] != '\0')
        {
            Format(colorTag, colorLen, "{%s}", rawColor);
        }
    }

    ConVar currency = FindConVar("sm_points_store_currency_long");
    if (currency != null)
    {
        currency.GetString(currencyName, nameLen);
        TrimString(currencyName);
    }
}

