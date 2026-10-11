#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <profiler>
#include <weapons>
#include <plugin_statistics>

native bool WeaponsDebug_ApplyHats(int client, const char[] state,bool enabled=true);
native bool WeaponsDebug_Reapply(int client);
native bool WeaponsDebug_ReapplyHats(int client);
native int WeaponsDebug_HatCount(int client);
native void WeaponsLoadout_DebugStats(float[] totals, float[] peaks, int size);
native void CheckLagDebug_ObserverCosts(float costs[3]);

#define STRESS_PLAYERS 16
#define STRESS_SLOW_FRAMES 512
public Plugin myinfo = {name="Loadout Stress Laboratory", author="Hombre", description="Debug-only bounded inventory stress and independent frame timing", version="1.0.0"};
static const char g_ClassNames[][] = {"unknown","scout","sniper","soldier","demoman","medic","heavyweapons","pyro","spy","engineer"};
int g_Bots[STRESS_PLAYERS], g_ProfileClass[STRESS_PLAYERS], g_Cursor, g_Operations, g_InventoryEvents;
int g_StartTick, g_EndTick, g_FrameCount, g_OverBudget, g_Over30, g_Over60, g_Over100;
int g_SlowTick[STRESS_SLOW_FRAMES], g_SlowCount;
int g_SlowOperationTick[STRESS_SLOW_FRAMES], g_SlowOperationClass[STRESS_SLOW_FRAMES];
int g_SlowOperationProfile[STRESS_SLOW_FRAMES], g_SlowOperationCount;
float g_SlowOperationMs[STRESS_SLOW_FRAMES];
float g_SlowMs[STRESS_SLOW_FRAMES], g_TotalGap, g_PeakGap, g_OperationPeak;
float g_EndAt;
Profiler g_FrameClock, g_OperationClock;
KeyValues g_Profiles;
File g_Output;
Handle g_WorkTimer, g_ReportTimer, g_SetupTimer;
ConVar g_BatchConVar, g_ForceConVar, g_ClassCycleConVar;
ConVar g_TestHatsConVar,g_TestWeaponsConVar;
bool g_Running, g_Preparing;
bool g_PrimeFrame;
int g_Duration;
char g_Label[64];
int g_OriginalHumanSerial;
int g_PreviousZombie;
int g_PrepareNextBot;

public void OnPluginStart()
{
    g_BatchConVar = CreateConVar("sm_loadoutstress_batch","1","Bots regenerated per 0.1s monitor service",_,true,1.0,true,16.0);
    g_ForceConVar = CreateConVar("sm_loadoutstress_force","0","Force custom equipment recreation on each regeneration",_,true,0.0,true,1.0);
    g_ClassCycleConVar = CreateConVar("sm_loadoutstress_class_cycle","0","Rotate class after each full 16-bot pass",_,true,0.0,true,1.0);
    g_TestHatsConVar = CreateConVar("sm_loadoutstress_hats","1","Replay paired saved custom hats",_,true,0.0,true,1.0);
    g_TestWeaponsConVar = CreateConVar("sm_loadoutstress_weapons","1","Replay paired saved custom weapons",_,true,0.0,true,1.0);
    RegAdminCmd("sm_loadoutstress_start",StartTrial,ADMFLAG_ROOT,"Start labelled bounded 16-bot trial, optional duration 15..300s");
    RegAdminCmd("sm_loadoutstress_stop",StopTrial,ADMFLAG_ROOT);
    HookEvent("post_inventory_application",InventoryApplied,EventHookMode_Post);
    g_FrameClock = new Profiler(); g_OperationClock = new Profiler();
}

public void OnMapEnd() { EndTrial("map_end"); }
public void OnClientPutInServer(int client)
{
    if (!g_Preparing || !NormalBot(client)) return;
    // Creation order + serial ownership, not names: other plugins may rename
    // bots during initialization. Start refuses existing ordinary bots.
    if (g_PrepareNextBot<STRESS_PLAYERS) g_Bots[g_PrepareNextBot++]=GetClientSerial(client);
}
public void OnPluginEnd()
{
    EndTrial("plugin_end");
    delete g_FrameClock; delete g_OperationClock;
}
bool NormalBot(int client)
{
    return client > 0 && IsClientInGame(client) && IsFakeClient(client)
        && !IsClientSourceTV(client) && !IsClientReplay(client);
}
bool ValidLabel(const char[] label)
{
    if (!label[0]) return false;
    for (int i=0;label[i];i++) if (!((label[i]>='a'&&label[i]<='z')||(label[i]>='A'&&label[i]<='Z')||(label[i]>='0'&&label[i]<='9')||label[i]=='_'||label[i]=='-')) return false;
    return true;
}
bool PopulationSafe()
{
    for (int client=1;client<=MaxClients;client++)
        if (IsClientConnected(client) && !IsFakeClient(client)
            && GetClientSerial(client) != g_OriginalHumanSerial) return false;
    return true;
}
public Action StartTrial(int client,int args)
{
    if (g_Running || g_Preparing || args<1) { ReplyToCommand(client,"[Stress] Trial active or label missing."); return Plugin_Handled; }
    GetCmdArg(1,g_Label,sizeof(g_Label));
    if (!ValidLabel(g_Label)) { ReplyToCommand(client,"[Stress] Invalid label."); return Plugin_Handled; }
    int humans;
    for (int target=1;target<=MaxClients;target++) if (IsClientConnected(target)&&!IsFakeClient(target)) { humans++; g_OriginalHumanSerial=GetClientSerial(target); }
    if (humans>1 || GetClientCount(false)+STRESS_PLAYERS>MaxClients) { ReplyToCommand(client,"[Stress] Refused: population/capacity unsafe."); return Plugin_Handled; }
    for (int target=1;target<=MaxClients;target++) if (IsClientConnected(target)) {
        if (NormalBot(target)) { ReplyToCommand(client,"[Stress] Refused: ordinary bots already present.");return Plugin_Handled; }
        char name[64];GetClientName(target,name,sizeof(name));
        if (StrContains(name,"LoadoutStress_")==0) { ReplyToCommand(client,"[Stress] Refused: prior test bots require operator cleanup.");return Plugin_Handled; }
    }
    char durationText[16]; GetCmdArg(2,durationText,sizeof(durationText));
    int duration=args>=2?StringToInt(durationText):60;
    if (duration<15||duration>300) { ReplyToCommand(client,"[Stress] Duration must be 15..300 seconds."); return Plugin_Handled; }
    ConVar stopBots=FindConVar("nb_stop");
    if (stopBots==null) { ReplyToCommand(client,"[Stress] Engine nb_stop unavailable.");return Plugin_Handled; }
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM,path,sizeof(path),"data/kogasatopia_debug_profiles.cfg");
    g_Profiles=new KeyValues("StressProfiles");
    if (!g_Profiles.ImportFromFile(path)) { delete g_Profiles; ReplyToCommand(client,"[Stress] Private profiles missing."); return Plugin_Handled; }
    BuildPath(Path_SM,path,sizeof(path),"data/loadout-stress/%s.log",g_Label);
    if (FileExists(path)) { delete g_Profiles; ReplyToCommand(client,"[Stress] Trial output exists; use a new label."); return Plugin_Handled; }
    g_Output=OpenFile(path,"wt");
    if (g_Output==null) { delete g_Profiles; ReplyToCommand(client,"[Stress] Private output directory unavailable."); return Plugin_Handled; }
    SetFilePermissions(path,384); // SourcePawn numeric literals are decimal: 0600 is NOT octal.
    g_Preparing=true; g_Duration=duration;
    g_PrepareNextBot=0;
    g_PreviousZombie=stopBots.IntValue; stopBots.IntValue=1;
    for (int i=0;i<STRESS_PLAYERS;i++)
    {
        char section[8]; IntToString(i,section,sizeof(section));
        g_Profiles.Rewind();
        if (!g_Profiles.JumpToKey(section)) { EndTrial("invalid_profile"); return Plugin_Handled; }
        g_ProfileClass[i]=g_Profiles.GetNum("class",1);
        if (g_ProfileClass[i]<1||g_ProfileClass[i]>9) { EndTrial("invalid_class"); return Plugin_Handled; }
        ServerCommand("tf_bot_add 1 %s %s easy noquota LoadoutStress_%02d",g_ClassNames[g_ProfileClass[i]],i%2?"blue":"red",i);
    }
    g_SetupTimer=CreateTimer(3.0,PrepareBots,_,TIMER_FLAG_NO_MAPCHANGE);
    ReplyToCommand(client,"[Stress] Preparing 16 bots for %s, %ds. Private cookies are not changed.",g_Label,duration);
    return Plugin_Handled;
}
public Action PrepareBots(Handle timer)
{
    g_SetupTimer=null;
    if (!PopulationSafe()) { EndTrial("population_changed"); return Plugin_Stop; }
    int assigned, invalid, selected;
    for (int i=0;i<STRESS_PLAYERS;i++)
    {
        int target=GetClientFromSerial(g_Bots[i]);
        if (NormalBot(target))
        {
            g_Bots[i]=GetClientSerial(target); assigned++;
            char section[8]; IntToString(i,section,sizeof(section));
            g_Profiles.Rewind(); g_Profiles.JumpToKey(section);
            if (g_TestWeaponsConVar.BoolValue&&g_Profiles.JumpToKey("weapons")&&g_Profiles.GotoFirstSubKey(false))
            {
                do {
                    char key[32],uid[64],parts[2][8];
                    g_Profiles.GetSectionName(key,sizeof(key)); g_Profiles.GetString(NULL_STRING,uid,sizeof(uid));
                    ExplodeString(key,"_",parts,2,8);
                    TFClassType playerClass=view_as<TFClassType>(StringToInt(parts[0]));
                    if (Weapons_IsItemUIDValid(uid)&&Weapons_SetPlayerLoadoutItem(target,playerClass,uid,0)) selected++; else invalid++;
                } while (g_Profiles.GotoNextKey(false));
            }
            g_Profiles.Rewind(); g_Profiles.JumpToKey(section);
            char state[2048];
            if (g_Profiles.JumpToKey("hats")&&g_Profiles.GotoFirstSubKey(false))
            {
                do {
                    char id[64],entry[80]; g_Profiles.GetSectionName(id,sizeof(id));
                    FormatEx(entry,sizeof(entry),"%s:%d,",id,g_Profiles.GetNum(NULL_STRING,0)); StrCat(state,sizeof(state),entry);
                } while (g_Profiles.GotoNextKey(false));
            }
            WeaponsDebug_ApplyHats(target,state,g_TestHatsConVar.BoolValue);
            TF2_SetPlayerClass(target,view_as<TFClassType>(g_ProfileClass[i]),false,true);
            TF2_RespawnPlayer(target);
        }
    }
    if (assigned!=STRESS_PLAYERS) { EndTrial("bot_creation_failed"); return Plugin_Stop; }
    g_Output.WriteLine("start|label=%s|bots=%d|selected=%d|invalid=%d|batch=%d|force=%d|classes=%d|checklag=%d|tick=%d",g_Label,assigned,selected,invalid,g_BatchConVar.IntValue,g_ForceConVar.IntValue,g_ClassCycleConVar.IntValue,FindConVar("sm_checklag_mode").IntValue,GetGameTickCount());
    g_Output.WriteLine("domains|weapons=%d|hats=%d|identity_pairing=same_source_player",g_TestWeaponsConVar.IntValue,g_TestHatsConVar.IntValue);
    float totals[5],peaks[5]; WeaponsLoadout_DebugStats(totals,peaks,5);
    g_Preparing=false; g_Running=true;
    g_EndAt=GetEngineTime()+float(g_Duration);g_PrimeFrame=true;
    g_Cursor=0;g_Operations=0;g_InventoryEvents=0;g_FrameCount=0;g_OverBudget=0;g_Over30=0;g_Over60=0;g_Over100=0;
    g_TotalGap=0.0;g_PeakGap=0.0;g_OperationPeak=0.0;g_SlowCount=0;g_SlowOperationCount=0;
    g_StartTick=GetGameTickCount(); g_EndTick=g_StartTick;
    g_FrameClock.Start();
    g_WorkTimer=CreateTimer(0.1,DoWork,_,TIMER_REPEAT);
    g_ReportTimer=CreateTimer(1.0,Report,_,TIMER_REPEAT);
    PrintToServer("[Stress] Trial %s started: 16 bots, %d saved weapon selections.",g_Label,selected);
    return Plugin_Stop;
}
public Action DoWork(Handle timer)
{
    if (!g_Running) return Plugin_Stop;
    if (GetEngineTime()>=g_EndAt) { g_WorkTimer=null; EndTrial("complete"); return Plugin_Stop; }
    if (!PopulationSafe()||GetMaxEntities()-GetEntityCount()<160||g_Operations>10000) { g_WorkTimer=null; EndTrial("safety_stop"); return Plugin_Stop; }
    for (int operation=0;operation<g_BatchConVar.IntValue;operation++)
    {
        int i=g_Cursor%STRESS_PLAYERS; int target=GetClientFromSerial(g_Bots[i]);
        if (!NormalBot(target)) { g_WorkTimer=null; EndTrial("bot_missing"); return Plugin_Stop; }
        int playerClass=g_ProfileClass[i];
        if (g_ClassCycleConVar.BoolValue) playerClass=(playerClass-1+g_Cursor/STRESS_PLAYERS)%9+1;
        g_OperationClock.Start();
        TF2_SetPlayerClass(target,view_as<TFClassType>(playerClass),false,true);
        if (!IsPlayerAlive(target)) TF2_RespawnPlayer(target);
        if (g_ForceConVar.BoolValue) WeaponsDebug_Reapply(target); else TF2_RegeneratePlayer(target);
        if (g_ForceConVar.BoolValue&&g_TestHatsConVar.BoolValue) WeaponsDebug_ReapplyHats(target);
        int weapon=GetPlayerWeaponSlot(target,g_Cursor%3);
        if (weapon>MaxClients) {
            char className[64];GetEntityClassname(weapon,className,sizeof(className));
            FakeClientCommand(target,"use %s",className);
        }
        g_OperationClock.Stop();
        float ms=g_OperationClock.Time*1000.0;
        if (ms>g_OperationPeak) g_OperationPeak=ms;
        if (ms>=5.0 && g_SlowOperationCount<STRESS_SLOW_FRAMES) {
            int row=g_SlowOperationCount++;
            g_SlowOperationTick[row]=GetGameTickCount();g_SlowOperationClass[row]=playerClass;
            g_SlowOperationProfile[row]=i;g_SlowOperationMs[row]=ms;
        }
        g_Operations++;g_Cursor++;
    }
    return Plugin_Continue;
}
public void OnGameFrame()
{
    if (!g_Running) return;
    g_FrameClock.Stop(); float ms=g_FrameClock.Time*1000.0; g_FrameClock.Start();
    // PrepareBots ran within a frame: its remainder is not a whole frame gap.
    if (g_PrimeFrame) { g_PrimeFrame=false;return; }
    g_FrameCount++;g_TotalGap+=ms;g_EndTick=GetGameTickCount();
    if (ms>g_PeakGap) g_PeakGap=ms;
    if (ms>GetTickInterval()*1100.0) g_OverBudget++;
    if (ms>=30.0) {
        g_Over30++;
        if (g_SlowCount<STRESS_SLOW_FRAMES) { g_SlowTick[g_SlowCount]=g_EndTick;g_SlowMs[g_SlowCount++]=ms; }
    }
    if (ms>=60.0) g_Over60++;
    if (ms>=100.0) g_Over100++;
}
public void InventoryApplied(Event event,const char[] name,bool dontBroadcast)
{
    if (!g_Running) return;
    int target=GetClientOfUserId(event.GetInt("userid"));
    if (!NormalBot(target)) return;
    int serial=GetClientSerial(target);
    for (int i=0;i<STRESS_PLAYERS;i++) if (g_Bots[i]==serial) { g_InventoryEvents++;break; }
}
public Action Report(Handle timer)
{
    if (!g_Running) return Plugin_Stop;
    float totals[5],peaks[5]; WeaponsLoadout_DebugStats(totals,peaks,5);
    float self[3];CheckLagDebug_ObserverCosts(self);
    g_Output.WriteLine("observer|tick=%d|window_ms=1000|root_ms=%.3f|tick_peak_ms=%.3f|record_scope_ms=%.3f",GetGameTickCount(),self[0],self[1],self[2]);
    int equipped,hats;
    for (int i=0;i<STRESS_PLAYERS;i++) {
        int target=GetClientFromSerial(g_Bots[i]);
        if (!NormalBot(target)) continue;
        hats+=WeaponsDebug_HatCount(target);
        for (int slot=0;slot<5;slot++) {
            int weapon=GetPlayerWeaponSlot(target,slot);char uid[64];
            if (weapon>MaxClients&&Weapons_GetItemUIDFromEntity(weapon,uid,sizeof(uid))) equipped++;
        }
    }
    g_Output.WriteLine("coverage|tick=%d|equipped_custom_weapons=%d|equipped_custom_hats=%d",GetGameTickCount(),equipped,hats);
    g_Output.WriteLine("sample|tick=%d|operations=%d|inventory_events=%d|rate=%.3f|entities=%d|native_total=%.3f|native_engine=%.3f|native_policy=%.3f|native_resolver=%.3f|native_sp=%.3f|peak_total=%.3f|peak_engine=%.3f|peak_policy=%.3f|peak_resolver=%.3f|peak_sp=%.3f",GetGameTickCount(),g_Operations,g_InventoryEvents,PluginStats_GetObservedTickrate(),GetEntityCount(),totals[0],totals[1],totals[2],totals[3],totals[4],peaks[0],peaks[1],peaks[2],peaks[3],peaks[4]);
    g_Output.Flush();
    return Plugin_Continue;
}
public Action StopTrial(int client,int args) { EndTrial("operator_stop");ReplyToCommand(client,"[Stress] Stopped and removed only owned test bots.");return Plugin_Handled; }
void EndTrial(const char[] reason)
{
    if (!g_Running&&!g_Preparing) return;
    g_Running=false;g_Preparing=false;
    delete g_WorkTimer;delete g_ReportTimer;delete g_SetupTimer;
    if (g_Output!=null) {
        float rate=g_TotalGap>0.0?float(g_FrameCount)*1000.0/g_TotalGap:0.0;
        g_Output.WriteLine("summary|reason=%s|label=%s|start_tick=%d|end_tick=%d|frames=%d|observed_rate=%.3f|operations=%d|inventory_events=%d|frame_peak_ms=%.3f|operation_peak_ms=%.3f|over_budget=%d|over30=%d|over60=%d|over100=%d",reason,g_Label,g_StartTick,g_EndTick,g_FrameCount,rate,g_Operations,g_InventoryEvents,g_PeakGap,g_OperationPeak,g_OverBudget,g_Over30,g_Over60,g_Over100);
        for (int i=0;i<g_SlowCount;i++) g_Output.WriteLine("slow_frame|tick=%d|ms=%.3f",g_SlowTick[i],g_SlowMs[i]);
        for (int i=0;i<g_SlowOperationCount;i++) g_Output.WriteLine("slow_operation|tick=%d|class=%d|profile=%d|ms=%.3f",g_SlowOperationTick[i],g_SlowOperationClass[i],g_SlowOperationProfile[i],g_SlowOperationMs[i]);
        delete g_Output;
    }
    ConVar stopBots=FindConVar("nb_stop");
    if (stopBots!=null) stopBots.IntValue=g_PreviousZombie;
    for (int i=0;i<STRESS_PLAYERS;i++) {
        int target=GetClientFromSerial(g_Bots[i]);
        if (NormalBot(target)) KickClient(target,"Loadout stress trial finished");
        g_Bots[i]=0;
    }
    delete g_Profiles;
    PrintToServer("[Stress] Trial %s ended: %s, peak frame %.3fms, operations %d.",g_Label,reason,g_PeakGap,g_Operations);
}
