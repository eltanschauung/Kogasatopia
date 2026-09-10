void NormalizeClanWarPair(int firstClanId, int secondClanId, int &clanIdA, int &clanIdB)
{
    if (firstClanId <= secondClanId)
    {
        clanIdA = firstClanId;
        clanIdB = secondClanId;
        return;
    }

    clanIdA = secondClanId;
    clanIdB = firstClanId;
}

void ResetActiveWarCache()
{
    g_bActiveWarCacheReady = false;

    if (g_hActiveWars == null)
    {
        g_hActiveWars = new ArrayList(sizeof(ActiveClanWar));
        return;
    }

    g_hActiveWars.Clear();
}

int FindActiveWarIndexByWarId(int warId)
{
    if (g_hActiveWars == null || warId <= 0)
    {
        return -1;
    }

    ActiveClanWar war;
    for (int i = 0; i < g_hActiveWars.Length; i++)
    {
        g_hActiveWars.GetArray(i, war);
        if (war.warId == warId)
        {
            return i;
        }
    }

    return -1;
}

int FindActiveWarIndexByClan(int clanId)
{
    if (g_hActiveWars == null || clanId <= 0)
    {
        return -1;
    }

    ActiveClanWar war;
    for (int i = 0; i < g_hActiveWars.Length; i++)
    {
        g_hActiveWars.GetArray(i, war);
        if (war.finalizePending)
        {
            continue;
        }

        if (war.clanIdA == clanId || war.clanIdB == clanId)
        {
            return i;
        }
    }

    return -1;
}

int FindActiveWarIndexByPair(int firstClanId, int secondClanId)
{
    if (g_hActiveWars == null || firstClanId <= 0 || secondClanId <= 0 || firstClanId == secondClanId)
    {
        return -1;
    }

    int clanIdA = 0;
    int clanIdB = 0;
    NormalizeClanWarPair(firstClanId, secondClanId, clanIdA, clanIdB);

    ActiveClanWar war;
    for (int i = 0; i < g_hActiveWars.Length; i++)
    {
        g_hActiveWars.GetArray(i, war);
        if (war.finalizePending)
        {
            continue;
        }

        if (war.clanIdA == clanIdA && war.clanIdB == clanIdB)
        {
            return i;
        }
    }

    return -1;
}

bool GetActiveClanWarForClanCached(int clanId, int &warId, int &clanIdA, int &clanIdB, int &scoreA, int &scoreB)
{
    warId = 0;
    clanIdA = 0;
    clanIdB = 0;
    scoreA = 0;
    scoreB = 0;

    if (!g_bActiveWarCacheReady)
    {
        return false;
    }

    int index = FindActiveWarIndexByClan(clanId);
    if (index == -1)
    {
        return false;
    }

    ActiveClanWar war;
    g_hActiveWars.GetArray(index, war);
    warId = war.warId;
    clanIdA = war.clanIdA;
    clanIdB = war.clanIdB;
    scoreA = war.scoreA;
    scoreB = war.scoreB;
    return true;
}

bool GetActiveClanWarByPairCached(int firstClanId, int secondClanId, int &warId, int &clanIdA, int &clanIdB, int &scoreA, int &scoreB)
{
    warId = 0;
    clanIdA = 0;
    clanIdB = 0;
    scoreA = 0;
    scoreB = 0;

    if (!g_bActiveWarCacheReady)
    {
        return false;
    }

    int index = FindActiveWarIndexByPair(firstClanId, secondClanId);
    if (index == -1)
    {
        return false;
    }

    ActiveClanWar war;
    g_hActiveWars.GetArray(index, war);
    warId = war.warId;
    clanIdA = war.clanIdA;
    clanIdB = war.clanIdB;
    scoreA = war.scoreA;
    scoreB = war.scoreB;
    return true;
}

bool ClanWarsRuntimeReady()
{
    return g_cvClanWarsEnabled != null
        && g_cvClanWarsEnabled.BoolValue
        && g_Database != null
        && g_bDatabaseReady
        && g_bActiveWarCacheReady
        && g_hActiveWars != null;
}

bool EnsureClanWarsAvailable(int client = 0)
{
    if (ClanWarsRuntimeReady())
    {
        return true;
    }

    if (client > 0 && IsClientInGame(client))
    {
        PrintToChat(client, "[Clans] Clan wars are temporarily unavailable.");
    }
    return false;
}

bool PopulateActiveWarLabels(ActiveClanWar war)
{
    char clanNameA[CLAN_NAME_MAXLEN + 1];
    char clanTagA[CLAN_TAG_STORE_MAXLEN];
    char ownerNameA[MAX_NAME_LENGTH * 2];
    char clanNameB[CLAN_NAME_MAXLEN + 1];
    char clanTagB[CLAN_TAG_STORE_MAXLEN];
    char ownerNameB[MAX_NAME_LENGTH * 2];
    int memberCount = 0;

    war.announceLabelA[0] = '\0';
    war.announceLabelB[0] = '\0';
    war.historyLabelA[0] = '\0';
    war.historyLabelB[0] = '\0';

    if (!GetClanInfoSummarySync(war.clanIdA, clanNameA, sizeof(clanNameA), clanTagA, sizeof(clanTagA), ownerNameA, sizeof(ownerNameA), memberCount))
    {
        FormatEx(war.announceLabelA, sizeof(war.announceLabelA), "[%d]", war.clanIdA);
        FormatEx(war.historyLabelA, sizeof(war.historyLabelA), "[%d]", war.clanIdA);
        return false;
    }

    if (!GetClanInfoSummarySync(war.clanIdB, clanNameB, sizeof(clanNameB), clanTagB, sizeof(clanTagB), ownerNameB, sizeof(ownerNameB), memberCount))
    {
        BuildClanWarTagLabel(clanTagA, clanNameA, war.announceLabelA, sizeof(war.announceLabelA));
        BuildClanHistoryTagLabel(clanTagA, clanNameA, war.historyLabelA, sizeof(war.historyLabelA));
        FormatEx(war.announceLabelB, sizeof(war.announceLabelB), "[%d]", war.clanIdB);
        FormatEx(war.historyLabelB, sizeof(war.historyLabelB), "[%d]", war.clanIdB);
        return false;
    }

    BuildClanWarTagLabel(clanTagA, clanNameA, war.announceLabelA, sizeof(war.announceLabelA));
    BuildClanWarTagLabel(clanTagB, clanNameB, war.announceLabelB, sizeof(war.announceLabelB));
    BuildClanHistoryTagLabel(clanTagA, clanNameA, war.historyLabelA, sizeof(war.historyLabelA));
    BuildClanHistoryTagLabel(clanTagB, clanNameB, war.historyLabelB, sizeof(war.historyLabelB));
    return true;
}

void UpsertActiveWarCacheEntry(int warId, int clanIdA, int clanIdB, int scoreA, int scoreB, int createdAt, int expiresAt, int instanceId = 0)
{
    if (warId <= 0 || clanIdA <= 0 || clanIdB <= 0)
    {
        return;
    }

    if (g_hActiveWars == null)
    {
        g_hActiveWars = new ArrayList(sizeof(ActiveClanWar));
    }

    int index = FindActiveWarIndexByWarId(warId);
    if (index == -1)
    {
        index = FindActiveWarIndexByPair(clanIdA, clanIdB);
    }

    ActiveClanWar war;
    if (index != -1)
    {
        g_hActiveWars.GetArray(index, war);
    }

    war.warId = warId;
    if (instanceId > 0)
    {
        war.instanceId = instanceId;
    }
    war.clanIdA = clanIdA;
    war.clanIdB = clanIdB;
    war.scoreA = scoreA;
    war.scoreB = scoreB;
    war.createdAt = createdAt;
    war.expiresAt = expiresAt;
    war.writeDirty = false;
    war.writePending = false;
    war.finalizePending = false;
    war.finalizeWritePending = false;
    war.finalizeWinnerClanId = 0;
    war.finalizeStatus = ClanWarStatus_Active;
    war.finalizeFinishedAt = 0;
    PopulateActiveWarLabels(war);

    if (index == -1)
    {
        g_hActiveWars.PushArray(war);
    }
    else
    {
        g_hActiveWars.SetArray(index, war);
    }
}

void RemoveActiveWarCacheIndex(int index)
{
    if (g_hActiveWars == null || index < 0 || index >= g_hActiveWars.Length)
    {
        return;
    }

    g_hActiveWars.Erase(index);
}

bool DispatchActiveWarScoreWrite(int index)
{
    if (!EnsureDatabaseReady() || g_hActiveWars == null || index < 0 || index >= g_hActiveWars.Length)
    {
        return false;
    }

    ActiveClanWar war;
    g_hActiveWars.GetArray(index, war);

    if (war.finalizePending || !war.writeDirty || war.writePending)
    {
        return true;
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "UPDATE clan_wars SET score_a = %d, score_b = %d, expires_at = %d "
        ... "WHERE id = %d AND created_at = %d AND status = %d",
        war.scoreA,
        war.scoreB,
        war.expiresAt,
        war.warId,
        war.createdAt,
        view_as<int>(ClanWarStatus_Active));

    DataPack pack = new DataPack();
    pack.WriteCell(war.warId);
    pack.WriteCell(war.createdAt);
    pack.WriteCell(war.scoreA);
    pack.WriteCell(war.scoreB);
    pack.WriteCell(war.expiresAt);
    pack.WriteCell(war.instanceId);

    war.writePending = true;
    g_hActiveWars.SetArray(index, war);
    g_Database.Query(SQL_OnActiveWarScoreWrite, query, pack);
    return true;
}

public void SQL_OnActiveWarScoreWrite(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int warId = pack.ReadCell();
    int createdAt = pack.ReadCell();
    int scoreA = pack.ReadCell();
    int scoreB = pack.ReadCell();
    int expiresAt = pack.ReadCell();
    int instanceId = pack.ReadCell();
    delete pack;

    bool saved = (!error[0] && results != null && results.AffectedRows > 0);

    int index = FindActiveWarIndexByWarId(warId);
    if (index != -1)
    {
        ActiveClanWar war;
        g_hActiveWars.GetArray(index, war);
        if (war.createdAt == createdAt)
        {
            war.writePending = false;
            if (saved && war.scoreA == scoreA && war.scoreB == scoreB && war.expiresAt == expiresAt)
            {
                war.writeDirty = false;
            }
            else
            {
                war.writeDirty = true;
            }
            g_hActiveWars.SetArray(index, war);
        }
    }

    if (error[0])
    {
        LogError("[Clans] Failed to persist war %d score snapshot: %s", warId, error);
        HandleDatabaseConnectionLoss(error);
    }
    else if (!saved)
    {
        LogError("[Clans] Failed to persist war %d score snapshot: no active row matched id=%d created_at=%d", warId, warId, createdAt);
    }
    else
    {
        DispatchClanWarInstanceScoreWrite(instanceId, createdAt, scoreA, scoreB);
    }
}

void DispatchClanWarInstanceScoreWrite(int instanceId, int createdAt, int scoreA, int scoreB)
{
    if (!EnsureDatabaseReady() || g_Database == null || instanceId <= 0)
    {
        return;
    }

    char query[192];
    FormatEx(query, sizeof(query),
        "UPDATE clan_war_instances SET score_a = %d, score_b = %d WHERE id = %d AND created_at = %d AND status = %d",
        scoreA,
        scoreB,
        instanceId,
        createdAt,
        view_as<int>(ClanWarStatus_Active));

    g_Database.Query(SQL_OnClanWarInstanceScoreWrite, query, instanceId);
}

public void SQL_OnClanWarInstanceScoreWrite(Database db, DBResultSet results, const char[] error, any data)
{
    int instanceId = data;

    if (error[0])
    {
        LogError("[Clans] Failed to persist war instance %d score snapshot: %s", instanceId, error);
        HandleDatabaseConnectionLoss(error);
        return;
    }

    if (results == null || results.AffectedRows <= 0)
    {
        LogError("[Clans] Failed to persist war instance %d score snapshot: no active instance row matched", instanceId);
    }
}

void FlushPendingActiveWarWrites()
{
    if (!EnsureDatabaseReady() || g_hActiveWars == null)
    {
        return;
    }

    for (int i = g_hActiveWars.Length - 1; i >= 0; i--)
    {
        ActiveClanWar war;
        g_hActiveWars.GetArray(i, war);

        if (war.finalizePending)
        {
            DispatchFinalizeActiveWarWrite(i);
            continue;
        }

        DispatchActiveWarScoreWrite(i);
    }
}

bool DispatchFinalizeActiveWarWrite(int index)
{
    if (!EnsureDatabaseReady() || g_hActiveWars == null || index < 0 || index >= g_hActiveWars.Length)
    {
        return false;
    }

    ActiveClanWar war;
    g_hActiveWars.GetArray(index, war);

    if (!war.finalizePending || war.finalizeWritePending)
    {
        return true;
    }

    char winnerValue[16];
    if (war.finalizeWinnerClanId > 0)
    {
        IntToString(war.finalizeWinnerClanId, winnerValue, sizeof(winnerValue));
    }
    else
    {
        strcopy(winnerValue, sizeof(winnerValue), "NULL");
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "UPDATE clan_wars SET score_a = %d, score_b = %d, winner_clan_id = %s, status = %d, finished_at = %d "
        ... "WHERE id = %d AND created_at = %d",
        war.scoreA,
        war.scoreB,
        winnerValue,
        view_as<int>(war.finalizeStatus),
        war.finalizeFinishedAt,
        war.warId,
        war.createdAt);

    DataPack pack = new DataPack();
    pack.WriteCell(war.warId);
    pack.WriteCell(war.createdAt);

    war.finalizeWritePending = true;
    g_hActiveWars.SetArray(index, war);
    g_Database.Query(SQL_OnFinalizeActiveWarWrite, query, pack);
    return true;
}

public void SQL_OnFinalizeActiveWarWrite(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int warId = pack.ReadCell();
    int createdAt = pack.ReadCell();
    delete pack;

    int index = FindActiveWarIndexByWarId(warId);

    if (error[0])
    {
        LogError("[Clans] Failed to finalize war %d: %s", warId, error);
        HandleDatabaseConnectionLoss(error);
        if (index != -1)
        {
            ActiveClanWar war;
            g_hActiveWars.GetArray(index, war);
            if (war.createdAt == createdAt)
            {
                war.finalizeWritePending = false;
                war.finalizePending = true;
                g_hActiveWars.SetArray(index, war);
            }
        }
        return;
    }

    if (index != -1)
    {
        ActiveClanWar war;
        g_hActiveWars.GetArray(index, war);
        if (war.createdAt == createdAt)
        {
            RemoveActiveWarCacheIndex(index);
        }
    }
}

void FlushPendingClanWarPersistenceSync()
{
    FlushPendingActiveWarWrites();
    FlushPendingClanWarKillWritesSync();
}

bool LoadActiveClanWarsCacheSync()
{
    ResetActiveWarCache();

    if (!EnsureDatabaseReady() || g_Database == null)
    {
        return false;
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT id, clan_id_a, clan_id_b, score_a, score_b, created_at, expires_at "
        ... "FROM clan_wars WHERE status = %d",
        view_as<int>(ClanWarStatus_Active));

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to load active war cache: %s", error);
        HandleDatabaseConnectionLoss(error);
        delete results;
        return false;
    }

    ArrayList pendingWars = new ArrayList(sizeof(ActiveClanWar));
    ActiveClanWar loadedWar;
    while (results.FetchRow())
    {
        loadedWar.warId = results.FetchInt(0);
        loadedWar.instanceId = 0;
        loadedWar.clanIdA = results.FetchInt(1);
        loadedWar.clanIdB = results.FetchInt(2);
        loadedWar.scoreA = results.FetchInt(3);
        loadedWar.scoreB = results.FetchInt(4);
        loadedWar.createdAt = results.FetchInt(5);
        loadedWar.expiresAt = results.FetchInt(6);
        loadedWar.writeDirty = false;
        loadedWar.writePending = false;
        loadedWar.finalizePending = false;
        loadedWar.finalizeWritePending = false;
        loadedWar.finalizeWinnerClanId = 0;
        loadedWar.finalizeStatus = ClanWarStatus_Active;
        loadedWar.finalizeFinishedAt = 0;
        loadedWar.announceLabelA[0] = '\0';
        loadedWar.announceLabelB[0] = '\0';
        loadedWar.historyLabelA[0] = '\0';
        loadedWar.historyLabelB[0] = '\0';
        pendingWars.PushArray(loadedWar);
    }

    delete results;

    for (int i = 0; i < pendingWars.Length; i++)
    {
        pendingWars.GetArray(i, loadedWar);
        int instanceId = 0;
        if (!EnsureClanWarInstanceSync(loadedWar.warId, loadedWar.clanIdA, loadedWar.clanIdB, loadedWar.createdAt, instanceId)
            && (!EnsureDatabaseReady() || g_Database == null))
        {
            delete pendingWars;
            ResetActiveWarCache();
            return false;
        }
        UpsertActiveWarCacheEntry(loadedWar.warId, loadedWar.clanIdA, loadedWar.clanIdB, loadedWar.scoreA, loadedWar.scoreB, loadedWar.createdAt, loadedWar.expiresAt, instanceId);
    }

    delete pendingWars;
    g_bActiveWarCacheReady = true;
    return true;
}

bool EnsureActiveWarCacheEntryForWarIdSync(int warId, int &index)
{
    index = FindActiveWarIndexByWarId(warId);
    if (index != -1)
    {
        return true;
    }

    if (!EnsureDatabaseReady() || warId <= 0)
    {
        return false;
    }

    char query[256];
    FormatEx(query, sizeof(query),
        "SELECT id, clan_id_a, clan_id_b, score_a, score_b, created_at, expires_at "
        ... "FROM clan_wars WHERE id = %d AND status = %d LIMIT 1",
        warId,
        view_as<int>(ClanWarStatus_Active));

    DBResultSet results = SQL_Query(g_Database, query);
    if (!HasUsableResultSet(results))
    {
        char error[256];
        SQL_GetError(g_Database, error, sizeof(error));
        LogError("[Clans] Failed to hydrate active war cache for id %d: %s", warId, error);
        HandleDatabaseConnectionLoss(error);
        delete results;
        return false;
    }

    if (!results.FetchRow())
    {
        delete results;
        return false;
    }

    int loadedWarId = results.FetchInt(0);
    int clanIdA = results.FetchInt(1);
    int clanIdB = results.FetchInt(2);
    int scoreA = results.FetchInt(3);
    int scoreB = results.FetchInt(4);
    int createdAt = results.FetchInt(5);
    int expiresAt = results.FetchInt(6);
    int instanceId = 0;
    EnsureClanWarInstanceSync(loadedWarId, clanIdA, clanIdB, createdAt, instanceId);

    UpsertActiveWarCacheEntry(
        loadedWarId,
        clanIdA,
        clanIdB,
        scoreA,
        scoreB,
        createdAt,
        expiresAt,
        instanceId);

    delete results;
    index = FindActiveWarIndexByWarId(warId);
    return (index != -1);
}

