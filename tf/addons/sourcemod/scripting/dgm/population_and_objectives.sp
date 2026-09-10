int DGM_CountRealPlayers()
{
    return DGM_CountRealTeamPlayers(2) + DGM_CountRealTeamPlayers(3);
}

int DGM_CountRealTeamPlayers(int team)
{
    if (team != 2 && team != 3)
    {
        return 0;
    }

    int count = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!Client_IsInGame(client) || IsFakeClient(client) || GetClientTeam(client) != team)
        {
            continue;
        }

        count++;
    }

    return count;
}

int DGM_GetServerCapacityValue()
{
    ConVar visibleMaxPlayers = FindConVar("sv_visiblemaxplayers");
    int capacity = 0;
    if (visibleMaxPlayers != null)
    {
        capacity = visibleMaxPlayers.IntValue;
    }

    if (capacity <= 0)
    {
        capacity = MaxClients;
    }

    return capacity;
}

int DGM_CountConnectedHumans()
{
    int count = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientConnected(client) && !IsFakeClient(client))
        {
            count++;
        }
    }

    return count;
}

float DGM_GetPopulationRatioValue(bool inGameOnly = true)
{
    int capacity = DGM_GetServerCapacityValue();
    if (capacity <= 0)
    {
        return 0.0;
    }

    int playerCount = inGameOnly ? DGM_CountRealPlayers() : DGM_CountConnectedHumans();
    return float(playerCount) / float(capacity);
}

bool DGM_CheckServerCapacity(float capacityRatio = 0.50, bool inGameOnly = true)
{
    if (capacityRatio < 0.0)
    {
        capacityRatio = 0.0;
    }
    else if (capacityRatio > 1.0)
    {
        capacityRatio = 1.0;
    }

    if (DGM_GetServerCapacityValue() <= 0)
    {
        return false;
    }

    return DGM_GetPopulationRatioValue(inGameOnly) >= capacityRatio;
}

bool DGM_AreTeamsGameplayReady()
{
    int connectedHumans = DGM_CountConnectedHumans();
    if (connectedHumans <= 0)
    {
        return false;
    }

    return DGM_CountRealPlayers() * 2 > connectedHumans;
}

DGMObjectiveLeader DGM_GetObjectiveLeaderValue(
    int &redOwned,
    int &blueOwned,
    int &neutralOwned,
    int &total)
{
    redOwned = 0;
    blueOwned = 0;
    neutralOwned = 0;
    total = 0;

    if (DGM_IsCurrentKothMode())
    {
        DGMObjectiveLeader kothLeader = DGM_GetKothTimerLeaderValue(redOwned, blueOwned, neutralOwned, total);
        if (kothLeader != DGMObjectiveLeader_None)
        {
            return kothLeader;
        }
    }

    if (!DGM_CountObjectiveResourcePoints(redOwned, blueOwned, neutralOwned, total))
    {
        DGM_CountTeamControlPointEntities(redOwned, blueOwned, neutralOwned, total);
    }

    if (total <= 0)
    {
        return DGMObjectiveLeader_None;
    }

    if (redOwned > blueOwned)
    {
        return DGMObjectiveLeader_Red;
    }

    if (blueOwned > redOwned)
    {
        return DGMObjectiveLeader_Blue;
    }

    return DGMObjectiveLeader_Tie;
}

bool DGM_IsCurrentKothMode()
{
    char gamemodeKey[32];
    return DGM_CopyCurrentGameModeKey(gamemodeKey, sizeof(gamemodeKey))
        && StrEqual(gamemodeKey, "koth", false);
}

DGMObjectiveLeader DGM_GetKothTimerLeaderValue(
    int &redRemaining,
    int &blueRemaining,
    int &neutralOwned,
    int &total)
{
    redRemaining = 0;
    blueRemaining = 0;
    neutralOwned = 0;
    total = 0;

    int redTimer = -1;
    int blueTimer = -1;

    DGM_FindKothTimers(redTimer, blueTimer);
    if (redTimer == -1 || blueTimer == -1)
    {
        return DGMObjectiveLeader_None;
    }

    redRemaining = DGM_GetRoundTimerRemaining(redTimer);
    blueRemaining = DGM_GetRoundTimerRemaining(blueTimer);
    if (redRemaining < 0 || blueRemaining < 0)
    {
        redRemaining = 0;
        blueRemaining = 0;
        return DGMObjectiveLeader_None;
    }

    total = 2;

    if (redRemaining < blueRemaining)
    {
        return DGMObjectiveLeader_Red;
    }

    if (blueRemaining < redRemaining)
    {
        return DGMObjectiveLeader_Blue;
    }

    return DGMObjectiveLeader_Tie;
}

void DGM_FindKothTimers(int &redTimer, int &blueTimer)
{
    redTimer = -1;
    blueTimer = -1;

    int timer = -1;
    while ((timer = FindEntityByClassname(timer, "team_round_timer")) != -1)
    {
        if (!IsValidEntity(timer))
        {
            continue;
        }

        char targetName[64];
        DGM_GetEntityTargetName(timer, targetName, sizeof(targetName));

        if (StrEqual(targetName, "zz_red_koth_timer", false) || StrContains(targetName, "red", false) != -1)
        {
            redTimer = timer;
            continue;
        }

        if (StrEqual(targetName, "zz_blue_koth_timer", false)
            || StrContains(targetName, "blue", false) != -1
            || StrContains(targetName, "blu", false) != -1)
        {
            blueTimer = timer;
            continue;
        }

        int team = DGM_GetEntityTeam(timer);
        if (team == view_as<int>(TFTeam_Red) && redTimer == -1)
        {
            redTimer = timer;
        }
        else if (team == view_as<int>(TFTeam_Blue) && blueTimer == -1)
        {
            blueTimer = timer;
        }
    }
}

void DGM_GetEntityTargetName(int entity, char[] buffer, int maxlen)
{
    buffer[0] = '\0';

    if (maxlen <= 0 || !IsValidEntity(entity) || !HasEntProp(entity, Prop_Data, "m_iName"))
    {
        return;
    }

    GetEntPropString(entity, Prop_Data, "m_iName", buffer, maxlen);
}

int DGM_GetEntityTeam(int entity)
{
    if (!IsValidEntity(entity))
    {
        return view_as<int>(TFTeam_Unassigned);
    }

    if (HasEntProp(entity, Prop_Send, "m_iTeamNum"))
    {
        return GetEntProp(entity, Prop_Send, "m_iTeamNum");
    }

    if (HasEntProp(entity, Prop_Data, "m_iTeamNum"))
    {
        return GetEntProp(entity, Prop_Data, "m_iTeamNum");
    }

    return view_as<int>(TFTeam_Unassigned);
}

int DGM_GetRoundTimerRemaining(int timer)
{
    if (!IsValidEntity(timer))
    {
        return -1;
    }

    char classname[64];
    GetEntityClassname(timer, classname, sizeof(classname));
    if (!StrEqual(classname, "team_round_timer", false))
    {
        return -1;
    }

    float secondsRemaining;

    if (DGM_GetEntityBool(timer, "m_bStopWatchTimer") && DGM_GetEntityBool(timer, "m_bInCaptureWatchState"))
    {
        if (!HasEntProp(timer, Prop_Send, "m_flTotalTime"))
        {
            return -1;
        }

        secondsRemaining = GetEntPropFloat(timer, Prop_Send, "m_flTotalTime");
    }
    else if (DGM_GetEntityBool(timer, "m_bTimerPaused"))
    {
        if (!HasEntProp(timer, Prop_Send, "m_flTimeRemaining"))
        {
            return -1;
        }

        secondsRemaining = GetEntPropFloat(timer, Prop_Send, "m_flTimeRemaining");
    }
    else
    {
        if (!HasEntProp(timer, Prop_Send, "m_flTimerEndTime"))
        {
            return -1;
        }

        secondsRemaining = GetEntPropFloat(timer, Prop_Send, "m_flTimerEndTime") - GetGameTime();
    }

    if (secondsRemaining < 0.0)
    {
        secondsRemaining = 0.0;
    }

    return RoundToNearest(secondsRemaining);
}

bool DGM_GetEntityBool(int entity, const char[] prop)
{
    return HasEntProp(entity, Prop_Send, prop) && GetEntProp(entity, Prop_Send, prop) != 0;
}

int DGM_GetObjectiveLeaderTeamValue()
{
    int redOwned, blueOwned, neutralOwned, total;
    DGMObjectiveLeader leader = DGM_GetObjectiveLeaderValue(redOwned, blueOwned, neutralOwned, total);

    if (leader == DGMObjectiveLeader_Red)
    {
        return view_as<int>(TFTeam_Red);
    }

    if (leader == DGMObjectiveLeader_Blue)
    {
        return view_as<int>(TFTeam_Blue);
    }

    return view_as<int>(TFTeam_Unassigned);
}

bool DGM_CountObjectiveResourcePoints(
    int &redOwned,
    int &blueOwned,
    int &neutralOwned,
    int &total)
{
    int objRes = FindEntityByClassname(-1, "tf_objective_resource");

    if (objRes == -1 || !IsValidEntity(objRes))
    {
        return false;
    }

    if (!HasEntProp(objRes, Prop_Send, "m_iNumControlPoints")
        || !HasEntProp(objRes, Prop_Send, "m_iOwner"))
    {
        return false;
    }

    int cpCount = GetEntProp(objRes, Prop_Send, "m_iNumControlPoints");

    if (cpCount <= 0)
    {
        return false;
    }

    if (cpCount > DGM_MAX_CONTROL_POINTS)
    {
        cpCount = DGM_MAX_CONTROL_POINTS;
    }

    bool haveVisibleProp = HasEntProp(objRes, Prop_Send, "m_bCPIsVisible");

    for (int pass = 0; pass < 2; pass++)
    {
        redOwned = 0;
        blueOwned = 0;
        neutralOwned = 0;
        total = 0;

        bool visibleOnly = (pass == 0 && haveVisibleProp);

        for (int i = 0; i < cpCount; i++)
        {
            if (visibleOnly)
            {
                int visible = GetEntProp(objRes, Prop_Send, "m_bCPIsVisible", 4, i);

                if (visible == 0)
                {
                    continue;
                }
            }

            int owner = GetEntProp(objRes, Prop_Send, "m_iOwner", 4, i);
            DGM_AddObjectiveOwnerToCounts(owner, redOwned, blueOwned, neutralOwned, total);
        }

        if (total > 0 || !haveVisibleProp)
        {
            return total > 0;
        }
    }

    return false;
}

int DGM_GetCurrentControlPointCount()
{
    int objRes = FindEntityByClassname(-1, "tf_objective_resource");

    if (objRes != -1 && IsValidEntity(objRes) && HasEntProp(objRes, Prop_Send, "m_iNumControlPoints"))
    {
        int cpCount = GetEntProp(objRes, Prop_Send, "m_iNumControlPoints");
        if (cpCount > DGM_MAX_CONTROL_POINTS)
        {
            cpCount = DGM_MAX_CONTROL_POINTS;
        }

        if (cpCount > 0)
        {
            return cpCount;
        }
    }

    int redOwned, blueOwned, neutralOwned, total;
    DGM_CountTeamControlPointEntities(redOwned, blueOwned, neutralOwned, total);
    return total;
}

void DGM_CountTeamControlPointEntities(
    int &redOwned,
    int &blueOwned,
    int &neutralOwned,
    int &total)
{
    redOwned = 0;
    blueOwned = 0;
    neutralOwned = 0;
    total = 0;

    int point = -1;

    while ((point = FindEntityByClassname(point, "team_control_point")) != -1)
    {
        if (!IsValidEntity(point))
        {
            continue;
        }

        int owner = DGM_GetControlPointEntityOwner(point);
        DGM_AddObjectiveOwnerToCounts(owner, redOwned, blueOwned, neutralOwned, total);
    }
}

int DGM_GetControlPointEntityOwner(int point)
{
    if (HasEntProp(point, Prop_Send, "m_iTeamNum"))
    {
        return GetEntProp(point, Prop_Send, "m_iTeamNum");
    }

    if (HasEntProp(point, Prop_Data, "m_iTeamNum"))
    {
        return GetEntProp(point, Prop_Data, "m_iTeamNum");
    }

    return view_as<int>(TFTeam_Unassigned);
}

void DGM_AddObjectiveOwnerToCounts(
    int owner,
    int &redOwned,
    int &blueOwned,
    int &neutralOwned,
    int &total)
{
    total++;

    if (owner == view_as<int>(TFTeam_Red))
    {
        redOwned++;
    }
    else if (owner == view_as<int>(TFTeam_Blue))
    {
        blueOwned++;
    }
    else
    {
        neutralOwned++;
    }
}

void DGM_ObjectiveLeaderToString(DGMObjectiveLeader leader, char[] buffer, int maxlen)
{
    bool isKoth = DGM_IsCurrentKothMode();

    switch (leader)
    {
        case DGMObjectiveLeader_Red:
        {
            strcopy(buffer, maxlen, isKoth ? "RED is leading by KOTH timer" : "RED is leading by objective ownership");
        }
        case DGMObjectiveLeader_Blue:
        {
            strcopy(buffer, maxlen, isKoth ? "BLU is leading by KOTH timer" : "BLU is leading by objective ownership");
        }
        case DGMObjectiveLeader_Tie:
        {
            strcopy(buffer, maxlen, isKoth ? "KOTH timers are tied" : "Objective ownership is tied");
        }
        default:
        {
            strcopy(buffer, maxlen, "No objective leader");
        }
    }
}

