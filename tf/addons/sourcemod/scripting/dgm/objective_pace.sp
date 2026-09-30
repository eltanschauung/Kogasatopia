// Symmetric modes compare like-for-like objectives. Attack/defend uses attack
// progress and the clock; the defenders' initial CP ownership is not a lead.
float g_ObjectivePaceStarted,g_ObjectiveStartProgress,g_ObjectiveLastProgress,g_ObjectiveLastAdvance;
float g_ObjectiveSampleTime[12],g_ObjectiveSampleProgress[12];
int g_ObjectiveSampleCount,g_ObjectiveSampleHead,g_ObjectiveSourceRef=INVALID_ENT_REFERENCE;
int g_ObjectiveAttackingTeam=3;
char g_ObjectiveLeaderReason[96];

void DGM_ResetObjectivePace()
{
    g_ObjectivePaceStarted=0.0;g_ObjectiveSampleCount=0;g_ObjectiveSampleHead=0;
    g_ObjectiveSourceRef=INVALID_ENT_REFERENCE;g_ObjectiveLeaderReason[0]='\0';
}

public void DGM_PrimeObjectivePace(any data)
{
    if(GameRules_GetRoundState()!=RoundState_RoundRunning
        || GameRules_GetProp("m_bInWaitingForPlayers",1)!=0 || GameRules_GetProp("m_bInSetup",1)!=0)return;
    int red,blue,neutral,total;DGM_GetObjectiveLeaderValue(red,blue,neutral,total);
}

int DGM_GetAttackingRoleTeam()
{
    int entity=-1;
    while((entity=FindEntityByClassname(entity,"tf_team"))!=-1)
        if(HasEntProp(entity,Prop_Send,"m_iRole") && GetEntProp(entity,Prop_Send,"m_iRole")==2)
        {
            int team=GetEntProp(entity,Prop_Send,"m_iTeamNum");
            if(team==2 || team==3)return team;
        }
    return 3;
}

bool DGM_GetCartProgress(int team,float &progress,int &reference)
{
    int entity=-1;bool found;progress=0.0;reference=INVALID_ENT_REFERENCE;
    while((entity=FindEntityByClassname(entity,"team_train_watcher"))!=-1)
    {
        if(GetEntProp(entity,Prop_Send,"m_iTeamNum")!=team
            || !HasEntProp(entity,Prop_Send,"m_flTotalProgress")
            || (HasEntProp(entity,Prop_Data,"m_bDisabled") && GetEntProp(entity,Prop_Data,"m_bDisabled",1)))continue;
        float value=GetEntPropFloat(entity,Prop_Send,"m_flTotalProgress");
        if(value<0.0)value=0.0;if(value>1.0)value=1.0;
        if(!found || value>progress){progress=value;reference=EntIndexToEntRef(entity);found=true;}
    }
    return found;
}

DGMObjectiveLeader DGM_EvaluateAttackPace(int attacker, float elapsed, float remaining,
    float progress, float rate, float stalled, bool recentCapture)
{
    DGMObjectiveLeader attackLead=attacker==2?DGMObjectiveLeader_Red:DGMObjectiveLeader_Blue;
    DGMObjectiveLeader defendLead=attacker==2?DGMObjectiveLeader_Blue:DGMObjectiveLeader_Red;
    if(recentCapture)
    {strcopy(g_ObjectiveLeaderReason,sizeof(g_ObjectiveLeaderReason),"attacking team captured recently");return attackLead;}
    if(elapsed<15.0 || remaining<0.0)
    {strcopy(g_ObjectiveLeaderReason,sizeof(g_ObjectiveLeaderReason),"not enough live-round timing data");return DGMObjectiveLeader_Tie;}
    float finish=rate>0.00001?(1.0-progress)/rate:999999.0;
    if(rate>0.00001 && finish<remaining*0.85)
    {strcopy(g_ObjectiveLeaderReason,sizeof(g_ObjectiveLeaderReason),"attack pace is ahead of the remaining clock");return attackLead;}
    if((remaining<=45.0 && finish>remaining*1.25) || stalled>=45.0)
    {strcopy(g_ObjectiveLeaderReason,sizeof(g_ObjectiveLeaderReason),"attack is stalled or running out of time");return defendLead;}
    strcopy(g_ObjectiveLeaderReason,sizeof(g_ObjectiveLeaderReason),"no clear pace advantage");
    return DGMObjectiveLeader_Tie;
}

DGMObjectiveLeader DGM_PaceAdvantage(int attacker,float progress,int reference)
{
    g_ObjectiveAttackingTeam=attacker;
    if(GameRules_GetRoundState()!=RoundState_RoundRunning || GameRules_GetProp("m_bInSetup",1)!=0
        || GameRules_GetProp("m_bInWaitingForPlayers",1)!=0)return DGMObjectiveLeader_Tie;
    float now=GetEngineTime();
    if(g_ObjectivePaceStarted<=0.0 || g_ObjectiveSourceRef!=reference)
    {
        g_ObjectivePaceStarted=now;g_ObjectiveStartProgress=progress;
        g_ObjectiveLastProgress=progress;g_ObjectiveLastAdvance=now;
        g_ObjectiveSourceRef=reference;g_ObjectiveSampleCount=0;g_ObjectiveSampleHead=0;
    }
    if(progress>g_ObjectiveLastProgress+0.001)g_ObjectiveLastAdvance=now;
    g_ObjectiveLastProgress=progress;
    float elapsed=now-g_ObjectivePaceStarted,remaining=DGM_GetHudRoundTimerRemaining();
    float baselineTime=g_ObjectivePaceStarted,baselineProgress=g_ObjectiveStartProgress;
    bool foundRecentSample;
    for(int i=0;i<g_ObjectiveSampleCount;i++)
        if(now-g_ObjectiveSampleTime[i]<=30.0 && now-g_ObjectiveSampleTime[i]>=10.0
            && (!foundRecentSample || g_ObjectiveSampleTime[i]<baselineTime))
        {baselineTime=g_ObjectiveSampleTime[i];baselineProgress=g_ObjectiveSampleProgress[i];foundRecentSample=true;}
    int previous=(g_ObjectiveSampleHead+11)%12;
    if(g_ObjectiveSampleCount==0 || now-g_ObjectiveSampleTime[previous]>=3.0)
    {
        g_ObjectiveSampleTime[g_ObjectiveSampleHead]=now;g_ObjectiveSampleProgress[g_ObjectiveSampleHead]=progress;
        g_ObjectiveSampleHead=(g_ObjectiveSampleHead+1)%12;if(g_ObjectiveSampleCount<12)g_ObjectiveSampleCount++;
    }
    float interval=now-baselineTime;
    float rate=interval>0.0?(progress-baselineProgress)/interval:0.0;
    bool recentCapture=g_iCaptureIntervalCount>0 && g_iCaptureTeam[g_iCaptureIntervalCount-1]==attacker
        && GetTime()-g_iLastCaptureTimestamp<=30;
    return DGM_EvaluateAttackPace(attacker,elapsed,remaining,progress,rate,now-g_ObjectiveLastAdvance,recentCapture);
}

DGMObjectiveLeader DGM_PayloadLeader(bool race,int &red,int &blue,int &neutral,int &total)
{
    float redProgress,blueProgress;int redRef,blueRef;
    bool haveRed=DGM_GetCartProgress(2,redProgress,redRef),haveBlue=DGM_GetCartProgress(3,blueProgress,blueRef);
    if(!haveRed && !haveBlue)return DGMObjectiveLeader_None;
    red=RoundToNearest(redProgress*100.0);blue=RoundToNearest(blueProgress*100.0);neutral=0;total=100;
    if(race || (haveRed && haveBlue))
    {
        if(!haveRed || !haveBlue)return DGMObjectiveLeader_Tie;
        strcopy(g_ObjectiveLeaderReason,sizeof(g_ObjectiveLeaderReason),"relative cart progress");
        if(FloatAbs(redProgress-blueProgress)<0.03)return DGMObjectiveLeader_Tie;
        return redProgress>blueProgress?DGMObjectiveLeader_Red:DGMObjectiveLeader_Blue;
    }
    return haveBlue?DGM_PaceAdvantage(3,blueProgress,blueRef):DGM_PaceAdvantage(2,redProgress,redRef);
}

DGMObjectiveLeader DGM_FlagCaptureLeader(int &red,int &blue,int &neutral,int &total)
{
    bool haveRed,haveBlue;int entity=-1;
    while((entity=FindEntityByClassname(entity,"tf_team"))!=-1)
    {
        if(!HasEntProp(entity,Prop_Send,"m_nFlagCaptures"))continue;
        int team=GetEntProp(entity,Prop_Send,"m_iTeamNum"),captures=GetEntProp(entity,Prop_Send,"m_nFlagCaptures");
        if(team==2){red=captures;haveRed=true;}else if(team==3){blue=captures;haveBlue=true;}
    }
    if(!haveRed || !haveBlue)return DGMObjectiveLeader_None;
    neutral=0;total=red+blue;
    strcopy(g_ObjectiveLeaderReason,sizeof(g_ObjectiveLeaderReason),"flag captures this round");
    return red==blue?DGMObjectiveLeader_Tie:(red>blue?DGMObjectiveLeader_Red:DGMObjectiveLeader_Blue);
}
