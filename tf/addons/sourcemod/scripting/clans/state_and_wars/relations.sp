void ResolveActiveWarsForDeletedClan(int clanId)
{
    if (g_bActiveWarCacheReady)
    {
        int warIndex = FindActiveWarIndexByClan(clanId);
        while (warIndex != -1)
        {
            ActiveClanWar war;
            g_hActiveWars.GetArray(warIndex, war);

            int winnerClanId = (war.clanIdA == clanId) ? war.clanIdB : war.clanIdA;
            if (!FinalizeClanWarSync(war.warId, war.clanIdA, war.clanIdB, war.scoreA, war.scoreB, winnerClanId, ClanWarStatus_Surrendered))
            {
                break;
            }

            warIndex = FindActiveWarIndexByClan(clanId);
        }
        return;
    }

    int warId = 0;
    int clanIdA = 0;
    int clanIdB = 0;
    int scoreA = 0;
    int scoreB = 0;

    while (GetActiveClanWarForClanSync(clanId, warId, clanIdA, clanIdB, scoreA, scoreB))
    {
        int winnerClanId = (clanIdA == clanId) ? clanIdB : clanIdA;
        if (!FinalizeClanWarSync(warId, clanIdA, clanIdB, scoreA, scoreB, winnerClanId, ClanWarStatus_Surrendered))
        {
            break;
        }
    }
}

void SetParentRelation(int clanIdA, int clanIdB, int requesterUserId = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    Transaction txn = new Transaction();
    char query[256];

    FormatEx(query, sizeof(query), "DELETE FROM clan_relations WHERE clan_id_a = %d AND relation_type = 3", clanIdA);
    txn.AddQuery(query);

    FormatEx(query, sizeof(query),
        "INSERT INTO clan_relations (clan_id_a, clan_id_b, relation_type, created_at) VALUES (%d, %d, 3, %d)",
        clanIdA,
        clanIdB,
        GetTime());
    txn.AddQuery(query);

    DataPack pack = new DataPack();
    pack.WriteCell(requesterUserId);
    pack.WriteCell(clanIdA);
    pack.WriteCell(clanIdB);

    g_Database.Execute(txn, SQLTxn_OnSetParentSuccess, SQLTxn_OnSetParentFailure, pack);
}

void ClearParentRelation(int clanIdA, int requesterUserId = 0)
{
    if (!EnsureDatabaseReady())
    {
        return;
    }

    char query[256];
    FormatEx(query, sizeof(query), "DELETE FROM clan_relations WHERE clan_id_a = %d AND relation_type = 3", clanIdA);
    g_Database.Query(SQL_OnClearParentRelation, query, requesterUserId);
}

public void SQL_GenericQueryCallback(Database db, DBResultSet results, const char[] error, any data)
{
    if (error[0])
    {
        LogError("[Clans] SQL query failed: %s", error);
        HandleDatabaseConnectionLoss(error);
    }
}

