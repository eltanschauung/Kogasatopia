#define CHECKLAG_SCOPE_LIMIT 128
#define CHECKLAG_SCOPE_WINDOW 5.0
StringMap g_LagScopeIndexes;
char g_LagScopeNames[CHECKLAG_SCOPE_LIMIT][160];
float g_LagScopeTotal[CHECKLAG_SCOPE_LIMIT],g_LagScopePeak[CHECKLAG_SCOPE_LIMIT];
float g_LagScopeStarted[CHECKLAG_SCOPE_LIMIT],g_LagScopeUpdated[CHECKLAG_SCOPE_LIMIT];
int g_LagScopeCalls[CHECKLAG_SCOPE_LIMIT],g_LagScopeCount;
float g_LastFrameAt,g_PeakFrameGap;

public any Native_CheckLagRecordScope(Handle plugin, int params)
{
    if (g_LagScopeIndexes == null) return 0;
    char filename[80],scope[72],key[160];
    GetPluginFilename(plugin,filename,sizeof(filename));GetNativeString(1,scope,sizeof(scope));
    float duration=GetNativeCell(2);
    if (!scope[0] || !(duration >= 0.0 && duration < 60000.0)) return 0;
    float now=GetEngineTime();
    FormatEx(key,sizeof(key),"%s / %s",filename,scope);
    int index;
    if (!g_LagScopeIndexes.GetValue(key,index))
    {
        if (g_LagScopeCount >= CHECKLAG_SCOPE_LIMIT) return 0;
        index=g_LagScopeCount++;g_LagScopeIndexes.SetValue(key,index);
        strcopy(g_LagScopeNames[index],sizeof(g_LagScopeNames[]),key);
        g_LagScopeStarted[index]=now;g_LagScopeTotal[index]=0.0;
        g_LagScopePeak[index]=0.0;g_LagScopeCalls[index]=0;
    }
    if (now-g_LagScopeStarted[index] >= CHECKLAG_SCOPE_WINDOW)
    {
        g_LagScopeStarted[index]=now;g_LagScopeTotal[index]=0.0;
        g_LagScopePeak[index]=0.0;g_LagScopeCalls[index]=0;
    }
    g_LagScopeUpdated[index]=now;g_LagScopeTotal[index]+=duration;g_LagScopeCalls[index]++;
    if (duration>g_LagScopePeak[index])g_LagScopePeak[index]=duration;
    return 0;
}

public void OnGameFrame()
{
    float now=GetEngineTime(),gap=now-g_LastFrameAt;g_LastFrameAt=now;
    if (now<g_RoundQuietUntil || gap<0.0 || gap>10.0) return;
    if (gap>g_PeakFrameGap)g_PeakFrameGap=gap;
}

int CheckLag_RecentMeasuredScope()
{
    int best=-1;float now=GetEngineTime();
    for(int i=0;i<g_LagScopeCount;i++)
        if(g_LagScopeCalls[i]>0 && now-g_LagScopeUpdated[i]<CHECKLAG_SCOPE_WINDOW
            && (best<0 || g_LagScopePeak[i]>g_LagScopePeak[best]))best=i;
    return best;
}

public Action Command_LagDetails(int client,int args)
{
    ReplyToCommand(client,"[CheckLag] Peak server frame gap: %.1f ms. Recent instrumented scopes (inclusive times):",g_PeakFrameGap*1000.0);
    bool shown[CHECKLAG_SCOPE_LIMIT];float now=GetEngineTime();
    for(int rank=0;rank<8;rank++)
    {
        int best=-1;
        for(int i=0;i<g_LagScopeCount;i++)
            if(!shown[i] && g_LagScopeCalls[i]>0 && now-g_LagScopeUpdated[i]<CHECKLAG_SCOPE_WINDOW
                && (best<0 || g_LagScopeTotal[i]>g_LagScopeTotal[best]))best=i;
        if(best<0)break;shown[best]=true;
        ReplyToCommand(client,"  %s: %.2f ms total / %d calls; %.2f ms peak",g_LagScopeNames[best],g_LagScopeTotal[best],g_LagScopeCalls[best],g_LagScopePeak[best]);
    }
    if(CheckLag_RecentMeasuredScope()<0)
        ReplyToCommand(client,"  No recent instrumented scopes. Use 'sm prof' for full SourceMod profiling; other plugins, engine or I/O can still cause stalls.");
    float loss,choke;
    for(int c=1;c<=MaxClients;c++)if(IsClientInGame(c)&&!IsFakeClient(c))
    {
        float l=GetClientAvgLoss(c,NetFlow_Outgoing),h=GetClientAvgChoke(c,NetFlow_Outgoing);
        if(l>loss)loss=l;if(h>choke)choke=h;
    }
    ReplyToCommand(client,"[CheckLag] Worst outgoing loss %.1f%%; choke %.1f%%. CPU timings do not identify network faults.",loss*100.0,choke*100.0);
    return Plugin_Handled;
}
