void CleanupExpiredInvites()
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    int now = GetTime();
    char query[256];
    FormatEx(query, sizeof(query), "DELETE FROM clan_invites WHERE expires_at <= %d", now);
    g_Database.Query(SQL_GenericQueryCallback, query);
}

public Action Timer_CleanupExpiredInvites(Handle timer, any data)
{
    CleanupExpiredInvites();
    CleanupExpiredWars();
    return Plugin_Continue;
}

public Action Timer_FlushClanWarDeltas(Handle timer, any data)
{
    FlushPendingClanWarPersistenceSync();
    return Plugin_Continue;
}

stock void GetClanById(int clanId, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT id, name, tag, owner, is_open, created_at FROM clans WHERE id = %d LIMIT 1",
        clanId);
    g_Database.Query(callback, query, data);
}

void GetClanInfoById(int clanId, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT c.id, c.name, c.tag, c.owner, COALESCE(c.`desc`, ''), ("
        ... "SELECT COUNT(1) FROM clan_members cm WHERE cm.clan_id = c.id"
        ... ") + ("
        ... "SELECT COUNT(1) "
        ... "FROM clan_members cm_child "
        ... "INNER JOIN clan_relations cr ON cr.clan_id_a = cm_child.clan_id "
        ... "WHERE cr.relation_type = 3 AND cr.clan_id_b = c.id"
        ... ") AS member_count, "
        ... "(SELECT COALESCE(SUM(COALESCE(pb.balance, 0)), 0) "
        ... "FROM clan_members cm "
        ... "LEFT JOIN points_store_balances pb ON pb.steamid64 = cm.steamid64 "
        ... "WHERE cm.clan_id = c.id "
        ... "OR cm.clan_id IN (SELECT cr.clan_id_a FROM clan_relations cr WHERE cr.relation_type = 3 AND cr.clan_id_b = c.id)) AS cached_gems "
        ... "FROM clans c "
        ... "WHERE c.id = %d "
        ... "LIMIT 1",
        clanId);
    g_Database.Query(callback, query, data);
}

void QueryClanGemsById(int clanId, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char query[1024];
    FormatEx(query, sizeof(query),
        "SELECT c.id, c.name, "
        ... "COALESCE(SUM(COALESCE(pb.balance, 0)), 0) "
        ... "FROM clans c "
        ... "LEFT JOIN clan_members cm "
        ... "ON (cm.clan_id = c.id "
        ... "OR cm.clan_id IN (SELECT cr.clan_id_a FROM clan_relations cr WHERE cr.relation_type = 3 AND cr.clan_id_b = c.id)) "
        ... "LEFT JOIN points_store_balances pb ON pb.steamid64 = cm.steamid64 "
        ... "WHERE c.id = %d "
        ... "GROUP BY c.id, c.name "
        ... "LIMIT 1",
        clanId);
    g_Database.Query(callback, query, data);
}

void QueryClanMembersListForClient(int userId, int clanId, const char[] clanName)
{
    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT cm.steamid64, cm.rank, cm.joined_at, COALESCE(cst.tag, '') "
        ... "FROM clan_members cm "
        ... "LEFT JOIN clan_sub_tags cst ON cst.clan_id = cm.clan_id AND cst.steamid64 = cm.steamid64 "
        ... "WHERE cm.clan_id = %d "
        ... "ORDER BY cm.joined_at ASC, cm.rank DESC, cm.steamid64 ASC",
        clanId);

    DataPack pack = new DataPack();
    pack.WriteCell(userId);
    pack.WriteCell(clanId);
    pack.WriteString(clanName);

    g_Database.Query(SQL_OnClanMembersList, query, pack);
}

void GetClanByPlayer(const char[] steamid64, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT c.id, c.name, c.tag, c.owner, c.is_open, c.created_at, cm.rank, cm.joined_at "
        ... "FROM clans c "
        ... "INNER JOIN clan_members cm ON cm.clan_id = c.id "
        ... "WHERE cm.steamid64 = '%s' "
        ... "LIMIT 1",
        escapedSteam);

    g_Database.Query(callback, query, data);
}

void IsPlayerInClan(const char[] steamid64, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT clan_id, rank FROM clan_members WHERE steamid64 = '%s' LIMIT 1",
        escapedSteam);
    g_Database.Query(callback, query, data);
}

stock void GetClanMembers(int clanId, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT steamid64, rank, joined_at FROM clan_members WHERE clan_id = %d ORDER BY rank DESC, joined_at ASC",
        clanId);
    g_Database.Query(callback, query, data);
}

public void SQL_OnAnnounceClanInviteToMembers(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    char clanName[CLAN_NAME_MAXLEN + 1];
    char inviterSteam[STEAMID64_MAXLEN];
    char targetSteam[STEAMID64_MAXLEN];
    pack.ReadString(clanName, sizeof(clanName));
    pack.ReadString(inviterSteam, sizeof(inviterSteam));
    pack.ReadString(targetSteam, sizeof(targetSteam));
    delete pack;

    if (error[0])
    {
        LogError("[Clans] Invite announcement member query failed: %s", error);
        return;
    }

    if (results == null)
    {
        return;
    }

    char inviterName[MAX_NAME_LENGTH * 2];
    char targetName[MAX_NAME_LENGTH * 2];
    ResolvePlayerDisplayName(inviterSteam, inviterName, sizeof(inviterName));
    ResolvePlayerDisplayName(targetSteam, targetName, sizeof(targetName));

    while (results.FetchRow())
    {
        char memberSteam[STEAMID64_MAXLEN];
        results.FetchString(0, memberSteam, sizeof(memberSteam));

        int member = Kogasa_FindClientBySteamId64(memberSteam);
        if (member <= 0 || !IsClientInGame(member))
        {
            continue;
        }

        PrintToChat(member, "[Clans] %s invited %s to '%s'.", inviterName, targetName, clanName);
    }
}

public void SQL_OnAnnounceClanInviteAcceptedToMembers(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    char clanName[CLAN_NAME_MAXLEN + 1];
    char accepterSteam[STEAMID64_MAXLEN];
    pack.ReadString(clanName, sizeof(clanName));
    pack.ReadString(accepterSteam, sizeof(accepterSteam));
    delete pack;

    if (error[0])
    {
        LogError("[Clans] Invite accept announcement member query failed: %s", error);
        return;
    }

    if (results == null)
    {
        return;
    }

    char accepterName[MAX_NAME_LENGTH * 2];
    ResolvePlayerDisplayName(accepterSteam, accepterName, sizeof(accepterName));

    while (results.FetchRow())
    {
        char memberSteam[STEAMID64_MAXLEN];
        results.FetchString(0, memberSteam, sizeof(memberSteam));

        int member = Kogasa_FindClientBySteamId64(memberSteam);
        if (member <= 0 || !IsClientInGame(member))
        {
            continue;
        }

        PrintToChat(member, "[Clans] %s accepted an invite to '%s'.", accepterName, clanName);
    }
}

void CreateClan(const char[] ownerSteamId64, const char[] name, int requesterUserId = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedOwner[SQL_STEAMID64_MAXLEN];
    char escapedName[SQL_CLAN_NAME_MAXLEN];
    EscapeSql(ownerSteamId64, escapedOwner, sizeof(escapedOwner));
    EscapeSql(name, escapedName, sizeof(escapedName));

    char lastInsertExpr[32];
    if (IsMySql())
    {
        strcopy(lastInsertExpr, sizeof(lastInsertExpr), "LAST_INSERT_ID()");
    }
    else
    {
        strcopy(lastInsertExpr, sizeof(lastInsertExpr), "last_insert_rowid()");
    }
    int now = GetTime();

    Transaction txn = new Transaction();

    char query[512];
    FormatEx(query, sizeof(query),
        "INSERT INTO clans (name, tag, owner, is_open, created_at) VALUES ('%s', NULL, '%s', 0, %d)",
        escapedName,
        escapedOwner,
        now);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query),
        "INSERT INTO clan_members (clan_id, steamid64, rank, joined_at) VALUES (%s, '%s', %d, %d)",
        lastInsertExpr,
        escapedOwner,
        view_as<int>(ClanRank_Owner),
        now);
    txn.AddQuery(query);

    DataPack pack = new DataPack();
    pack.WriteCell(requesterUserId);
    pack.WriteString(name);
    pack.WriteString(ownerSteamId64);

    g_Database.Execute(txn, SQLTxn_OnCreateClanSuccess, SQLTxn_OnCreateClanFailure, pack);
}

void DeleteClan(int clanId, int requesterUserId = 0, bool refundOwner = false)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    ResolveActiveWarsForDeletedClan(clanId);

    Transaction txn = new Transaction();
    char query[256];

    FormatEx(query, sizeof(query), "DELETE FROM clan_relations WHERE clan_id_a = %d OR clan_id_b = %d", clanId, clanId);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query), "DELETE FROM clan_invites WHERE clan_id = %d", clanId);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query), "DELETE FROM clan_sub_tags WHERE clan_id = %d", clanId);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query), "DELETE FROM clan_members WHERE clan_id = %d", clanId);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query), "DELETE FROM clans WHERE id = %d", clanId);
    txn.AddQuery(query);

    DataPack pack = new DataPack();
    pack.WriteCell(requesterUserId);
    pack.WriteCell(refundOwner ? 1 : 0);
    pack.WriteCell(clanId);

    g_Database.Execute(txn, SQLTxn_OnDeleteClanSuccess, SQLTxn_OnDeleteClanFailure, pack);
}

void AddClanMember(int clanId, const char[] steamid64, SQLQueryCallback callback, any data = 0, ClanRank rank = ClanRank_Member)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[256];
    FormatEx(query, sizeof(query),
        "INSERT INTO clan_members (clan_id, steamid64, rank, joined_at) VALUES (%d, '%s', %d, %d)",
        clanId,
        escapedSteam,
        view_as<int>(rank),
        GetTime());
    g_Database.Query(callback, query, data);
}

void SetClanTag(int clanId, const char[] tag, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedTag[SQL_CLAN_TAG_MAXLEN];
    EscapeSql(tag, escapedTag, sizeof(escapedTag));

    char query[384];
    FormatEx(query, sizeof(query),
        "UPDATE clans SET tag = '%s' WHERE id = %d",
        escapedTag,
        clanId);
    g_Database.Query(callback, query, data);
}

void SetClanDescription(int clanId, const char[] description, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedDescription[SQL_CLAN_DESC_MAXLEN];
    EscapeSql(description, escapedDescription, sizeof(escapedDescription));

    char query[512];
    FormatEx(query, sizeof(query),
        "UPDATE clans SET `desc` = '%s' WHERE id = %d",
        escapedDescription,
        clanId);
    g_Database.Query(callback, query, data);
}

void SetClanName(int clanId, const char[] name, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedName[SQL_CLAN_NAME_MAXLEN];
    EscapeSql(name, escapedName, sizeof(escapedName));

    char query[384];
    FormatEx(query, sizeof(query),
        "UPDATE clans SET name = '%s' WHERE id = %d",
        escapedName,
        clanId);
    g_Database.Query(callback, query, data);
}

void SetClanSubTag(int clanId, const char[] steamid64, const char[] tag, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    char escapedTag[SQL_CLAN_SUB_TAG_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));
    EscapeSql(tag, escapedTag, sizeof(escapedTag));

    char query[384];
    FormatEx(query, sizeof(query),
        "REPLACE INTO clan_sub_tags (clan_id, steamid64, tag, created_at) VALUES (%d, '%s', '%s', %d)",
        clanId,
        escapedSteam,
        escapedTag,
        GetTime());
    g_Database.Query(callback, query, data);
}

void SetClanOpen(int clanId, bool isOpen, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char query[128];
    FormatEx(query, sizeof(query),
        "UPDATE clans SET is_open = %d WHERE id = %d",
        isOpen ? 1 : 0,
        clanId);
    g_Database.Query(callback, query, data);
}

void CreateInvite(int clanId, const char[] steamid64, const char[] inviter, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    char escapedInviter[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));
    EscapeSql(inviter, escapedInviter, sizeof(escapedInviter));

    char query[384];
    FormatEx(query, sizeof(query),
        "INSERT INTO clan_invites (clan_id, steamid64, invited_by, expires_at) VALUES (%d, '%s', '%s', %d)",
        clanId,
        escapedSteam,
        escapedInviter,
        GetTime() + INVITE_EXPIRE_SECONDS);
    g_Database.Query(callback, query, data);
}

void DeleteInvite(int inviteId, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char query[128];
    FormatEx(query, sizeof(query), "DELETE FROM clan_invites WHERE id = %d", inviteId);
    g_Database.Query(callback, query, data);
}

void GetPendingInvites(const char[] steamid64, SQLQueryCallback callback, any data = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char escapedSteam[SQL_STEAMID64_MAXLEN];
    EscapeSql(steamid64, escapedSteam, sizeof(escapedSteam));

    char query[512];
    FormatEx(query, sizeof(query),
        "SELECT i.id, i.clan_id, c.name, c.tag, i.invited_by, i.expires_at "
        ... "FROM clan_invites i "
        ... "INNER JOIN clans c ON c.id = i.clan_id "
        ... "WHERE i.steamid64 = '%s' AND i.expires_at > %d "
        ... "ORDER BY i.expires_at ASC",
        escapedSteam,
        GetTime());
    g_Database.Query(callback, query, data);
}

