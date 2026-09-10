void AddClanHistoryEntry(int clanId, const char[] fmt, any ...)
{
    if (clanId <= 0 || !EnsureDatabaseReady())
    {
        return;
    }

    char summary[CLAN_HISTORY_SUMMARY_MAXLEN + 1];
    char escapedSummary[SQL_CLAN_HISTORY_SUMMARY_MAXLEN];
    VFormat(summary, sizeof(summary), fmt, 3);
    CRemoveTags(summary, sizeof(summary));
    TrimString(summary);

    if (!summary[0])
    {
        return;
    }

    EscapeSql(summary, escapedSummary, sizeof(escapedSummary));

    char query[768];
    FormatEx(query, sizeof(query),
        "INSERT INTO clan_history (clan_id, summary, created_at) VALUES (%d, '%s', %d)",
        clanId,
        escapedSummary,
        GetTime());

    g_Database.Query(SQL_GenericQueryCallback, query);
}

bool FinalizeClanWarSync(int warId, int clanIdA, int clanIdB, int scoreA, int scoreB, int winnerClanId, ClanWarStatus status)
{
    if (warId <= 0 || clanIdA <= 0 || clanIdB <= 0)
    {
        return false;
    }

    int warIndex = FindActiveWarIndexByWarId(warId);
    if (warIndex == -1 && !EnsureActiveWarCacheEntryForWarIdSync(warId, warIndex))
    {
        return false;
    }

    ActiveClanWar war;
    g_hActiveWars.GetArray(warIndex, war);

    if (war.finalizePending)
    {
        return true;
    }

    char historyLabelA[96];
    char historyLabelB[96];
    char announceLabelA[96];
    char announceLabelB[96];

    clanIdA = war.clanIdA;
    clanIdB = war.clanIdB;
    scoreA = war.scoreA;
    scoreB = war.scoreB;

    strcopy(historyLabelA, sizeof(historyLabelA), war.historyLabelA);
    strcopy(historyLabelB, sizeof(historyLabelB), war.historyLabelB);
    strcopy(announceLabelA, sizeof(announceLabelA), war.announceLabelA);
    strcopy(announceLabelB, sizeof(announceLabelB), war.announceLabelB);

    if (!historyLabelA[0])
    {
        FormatEx(historyLabelA, sizeof(historyLabelA), "[%d]", clanIdA);
    }
    if (!historyLabelB[0])
    {
        FormatEx(historyLabelB, sizeof(historyLabelB), "[%d]", clanIdB);
    }
    if (!announceLabelA[0])
    {
        FormatEx(announceLabelA, sizeof(announceLabelA), "[%d]", clanIdA);
    }
    if (!announceLabelB[0])
    {
        FormatEx(announceLabelB, sizeof(announceLabelB), "[%d]", clanIdB);
    }

    war.writeDirty = false;
    war.finalizePending = true;
    war.finalizeWritePending = false;
    war.finalizeWinnerClanId = winnerClanId;
    war.finalizeStatus = status;
    war.finalizeFinishedAt = GetTime();
    g_hActiveWars.SetArray(warIndex, war);

    int stolenA = (war.instanceId > 0) ? GetClanWarStolenTotalSync(war.instanceId, clanIdA) : 0;
    int stolenB = (war.instanceId > 0) ? GetClanWarStolenTotalSync(war.instanceId, clanIdB) : 0;

    if (status == ClanWarStatus_Expired)
    {
        AddClanHistoryEntry(clanIdA, "War with %s expired at %d-%d", historyLabelB, scoreA, scoreB);
        AddClanHistoryEntry(clanIdB, "War with %s expired at %d-%d", historyLabelA, scoreB, scoreA);
    }
    else if (winnerClanId == clanIdA)
    {
        AddClanHistoryEntry(clanIdA, "Won war vs %s (%d-%d, %d Gems stolen)", historyLabelB, scoreA, scoreB, stolenA);
        AddClanHistoryEntry(clanIdB, "Lost war vs %s (%d-%d, %d Gems stolen)", historyLabelA, scoreB, scoreA, stolenB);
    }
    else if (winnerClanId == clanIdB)
    {
        AddClanHistoryEntry(clanIdA, "Lost war vs %s (%d-%d, %d Gems stolen)", historyLabelB, scoreA, scoreB, stolenA);
        AddClanHistoryEntry(clanIdB, "Won war vs %s (%d-%d, %d Gems stolen)", historyLabelA, scoreB, scoreA, stolenB);
    }

    if (status == ClanWarStatus_Expired)
    {
        CPrintToChatAll("{gold}[Clans]{default} War between %s and %s expired. Final score: %d-%d", announceLabelA, announceLabelB, scoreA, scoreB);
    }
    else if (winnerClanId == clanIdA)
    {
        CPrintToChatAll("{gold}[Clans]{default} %s won the war against %s! Final score: %d-%d. %s stole {lightgreen}%d Gems{default}!", announceLabelA, announceLabelB, scoreA, scoreB, announceLabelA, stolenA);
    }
    else if (winnerClanId == clanIdB)
    {
        CPrintToChatAll("{gold}[Clans]{default} %s won the war against %s! Final score: %d-%d. %s stole {lightgreen}%d Gems{default}!", announceLabelB, announceLabelA, scoreB, scoreA, announceLabelB, stolenB);
    }

    if (war.instanceId > 0)
    {
        UpdateClanWarInstanceFinalState(war.instanceId, war.scoreA, war.scoreB, winnerClanId, status, war.finalizeFinishedAt);
    }

    if (g_bDatabaseReady)
    {
        FlushPendingClanWarPersistenceSync();
    }

    return true;
}

void BroadcastClanWarScoreUpdate(const char[] scoringLabel, const char[] otherLabel, int scoringClanId, int otherClanId, int scoringScore, int otherScore, int warInstanceId, int attacker, int victim)
{
    if ((scoringScore % 5) != 0)
    {
        return;
    }

    char attackerLabel[512];
    char victimLabel[512];
    BuildWarPlayerLabel(attacker, attackerLabel, sizeof(attackerLabel));
    BuildWarPlayerLabel(victim, victimLabel, sizeof(victimLabel));

    bool stolenAlert = ((scoringScore % 10) == 0);
    bool broadcastOutsiders = stolenAlert;

    int leaderScore = (scoringScore >= otherScore) ? scoringScore : otherScore;
    int trailingScore = (scoringScore >= otherScore) ? otherScore : scoringScore;
    int leaderClanId = (scoringScore >= otherScore) ? scoringClanId : otherClanId;
    int leaderStolen = 0;
    if (stolenAlert && warInstanceId > 0)
    {
        leaderStolen = GetClanWarStolenTotalSync(warInstanceId, leaderClanId);
    }
    char leaderLabel[96];
    char trailingLabel[96];
    strcopy(leaderLabel, sizeof(leaderLabel), (scoringScore >= otherScore) ? scoringLabel : otherLabel);
    strcopy(trailingLabel, sizeof(trailingLabel), (scoringScore >= otherScore) ? otherLabel : scoringLabel);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
        {
            continue;
        }

        bool isParticipant = IsConnectedClientInClan(i, scoringClanId) || IsConnectedClientInClan(i, otherClanId);
        if (!isParticipant && !broadcastOutsiders)
        {
            continue;
        }

        ClansCPrintToChatExWrapped(i, attacker, "%s killed %s!", attackerLabel, victimLabel);
        if (stolenAlert)
        {
            CPrintToChat(i, "{gold}[Clans]{default} %s is beating %s %d-%d and has stolen {lightgreen}%d Gems{default} so far!!!", leaderLabel, trailingLabel, leaderScore, trailingScore, leaderStolen);
        }
        else
        {
            CPrintToChat(i, "{gold}[Clans]{default} %s's score: %d | %s's score: %d", scoringLabel, scoringScore, otherLabel, otherScore);
        }
    }
}

void CleanupExpiredWars()
{
    if (!g_bActiveWarCacheReady || g_hActiveWars == null)
    {
        return;
    }

    int now = GetTime();
    for (int i = g_hActiveWars.Length - 1; i >= 0; i--)
    {
        ActiveClanWar war;
        g_hActiveWars.GetArray(i, war);
        if (war.finalizePending || war.expiresAt > now)
        {
            continue;
        }

        FinalizeClanWarSync(
            war.warId,
            war.clanIdA,
            war.clanIdB,
            war.scoreA,
            war.scoreB,
            0,
            ClanWarStatus_Expired);
    }
}

