// SPDX-License-Identifier: GPL-3.0-or-later
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <instant_sprays>
#define VERSION "1.4.0"

public Plugin myinfo={name="Instant Sprays",author="Codex",description="Instant local spray changes with background synchronization",version=VERSION,url=""};
ConVar g_Enabled,g_Upload,g_Download;
QueryCookie g_Cookies[MAXPLAYERS+1][5];
int g_Bits[MAXPLAYERS+1],g_Serial[MAXPLAYERS+1],g_Token[MAXPLAYERS+1],g_Sprite[MAXPLAYERS+1];
int g_Surface[MAXPLAYERS+1];
int g_DecalSurface[MAXPLAYERS+1],g_ReplayContextRepairs;
bool g_DecalRecorded[MAXPLAYERS+1],g_Sharing[MAXPLAYERS+1];
float g_DecalOrigin[MAXPLAYERS+1][3];
int g_PreviewOwner[2049];
bool g_Query[MAXPLAYERS+1],g_Allowed[MAXPLAYERS+1],g_First[MAXPLAYERS+1],g_Force[MAXPLAYERS+1],g_Manual[MAXPLAYERS+1];
bool g_ViewAllowed[MAXPLAYERS+1];
bool g_DownloadAllowed[MAXPLAYERS+1],g_Guarded[MAXPLAYERS+1],g_Public[MAXPLAYERS+1];
int g_SurfaceViewer[MAXPLAYERS+1][MAXPLAYERS+1];
float g_NextSurfacePoll[MAXPLAYERS+1];
bool g_QueuedKey[MAXPLAYERS+1],g_ReplayKey[MAXPLAYERS+1],g_HasCooldown[MAXPLAYERS+1],g_Placed[MAXPLAYERS+1];
float g_NextQuery[MAXPLAYERS+1],g_QueryTime[MAXPLAYERS+1],g_Notice[MAXPLAYERS+1];
float g_Position[MAXPLAYERS+1][3],g_Angles[MAXPLAYERS+1][3];
char g_Queried[MAXPLAYERS+1][PLATFORM_MAX_PATH],g_Selected[MAXPLAYERS+1][PLATFORM_MAX_PATH];
char g_Requested[MAXPLAYERS+1][PLATFORM_MAX_PATH],g_Active[MAXPLAYERS+1][PLATFORM_MAX_PATH];
char g_Failed[MAXPLAYERS+1][PLATFORM_MAX_PATH],g_PlacementPath[MAXPLAYERS+1][PLATFORM_MAX_PATH];
char g_Material[MAXPLAYERS+1][PLATFORM_MAX_PATH];
static const char g_Settings[][]={"cl_logofile","cl_allowupload","cl_allowdownload","cl_downloadfilter","cl_spraydisable"};

bool Human(int c){return c>0&&c<=MaxClients&&IsClientInGame(c)&&!IsFakeClient(c);}
bool ReplaySpray(int c){
    if(!Human(c)||!g_DecalRecorded[c])return false;
    int entity=g_DecalSurface[c]==0?0:EntRefToEntIndex(g_DecalSurface[c]);
    if(entity<0)return false;
    // SDKTools TE hooks read the registered, shared CTEPlayerDecal object,
    // not the copied sender buffer retained by the native extension. Rebuild
    // that object so moderation and re-sends see THIS player's saved placement.
    TE_Start("Player Decal");
    float previous[3];TE_ReadVector("m_vecOrigin",previous);
    if(TE_ReadNum("m_nPlayer")!=c||TE_ReadNum("m_nEntity")!=entity
       ||GetVectorDistance(previous,g_DecalOrigin[c])>0.01)g_ReplayContextRepairs++;
    TE_WriteNum("m_nPlayer",c);TE_WriteNum("m_nEntity",entity);
    TE_WriteVector("m_vecOrigin",g_DecalOrigin[c]);
    return ISprays_Replay(c);
}
void RemovePreview(int c){
    int e=EntRefToEntIndex(g_Sprite[c]);if(e>MaxClients&&IsValidEntity(e))RemoveEntity(e);g_Sprite[c]=INVALID_ENT_REFERENCE;
    g_Public[c]=false;for(int i=1;i<=MaxClients;i++)g_SurfaceViewer[c][i]=0;
}
void ReleaseKey(int c){if(g_QueuedKey[c]){g_ReplayKey[c]=Human(c)&&IsPlayerAlive(c);g_QueuedKey[c]=false;}}
void Notice(int c,const char[] text){
    if(Human(c)&&(g_Manual[c]||GetEngineTime()>=g_Notice[c])){
        PrintToChat(c,"[Sprays] %s",text);g_Notice[c]=GetEngineTime()+30.0;
    }
}
void Stop(int c){
    if(g_Token[c]>0)ISprays_Cancel(c,g_Token[c]);g_Token[c]=0;
    ISprays_EnablePreview(c,false);RemovePreview(c);g_Placed[c]=false;g_Query[c]=false;
    g_Guarded[c]=false;
    g_QueuedKey[c]=false;g_ReplayKey[c]=false;g_Force[c]=false;g_Manual[c]=false;
    g_DecalRecorded[c]=false;g_Sharing[c]=false;
}
void Initialize(int c,bool fresh){
    Stop(c);g_Serial[c]=GetClientSerial(c);g_First[c]=fresh;g_NextQuery[c]=0.0;g_Notice[c]=0.0;
    g_ViewAllowed[c]=false;g_Allowed[c]=false;g_DownloadAllowed[c]=false;
    g_Selected[c][0]=0;g_Requested[c][0]=0;g_Active[c][0]=0;g_Failed[c][0]=0;g_Material[c][0]=0;
    g_HasCooldown[c]=FindDataMapInfo(c,"m_flNextDecalTime")!=-1;
}
void QuerySettings(int c,bool force=false){
    if((g_Query[c]&&!force)||(!force&&GetEngineTime()<g_NextQuery[c]))return;
    g_Query[c]=true;g_Bits[c]=0;g_Allowed[c]=true;g_DownloadAllowed[c]=true;g_QueryTime[c]=GetEngineTime();g_NextQuery[c]=g_QueryTime[c]+0.75;
    for(int i=0;i<sizeof(g_Settings);i++){
        g_Cookies[c][i]=QueryClientConVar(c,g_Settings[i],SettingsReply,g_Serial[c]);
        if(g_Cookies[c][i]==QUERYCOOKIE_FAILED){g_Query[c]=false;ReleaseKey(c);return;}
    }
}
void StartUpload(int c){
    if(g_Token[c]>0||!g_Selected[c][0])return;
    if(!g_Force[c]&&(StrEqual(g_Selected[c],g_Active[c])||StrEqual(g_Selected[c],g_Failed[c])))return;
    int token=ISprays_Request(c,g_Selected[c],g_Force[c]);
    if(token==0)return; // Temporary transport throttle: retry on the next poll.
    g_Force[c]=false;
    if(token<1){strcopy(g_Failed[c],sizeof(g_Failed[]),g_Selected[c]);Notice(c,"Could not refresh this spray. Your existing spray still works.");ISprays_EnablePreview(c,false);return;}
    g_Token[c]=token;strcopy(g_Requested[c],sizeof(g_Requested[]),g_Selected[c]);
    if(!g_Sharing[c])PrintToChat(c,"[Sprays] Sharing your new spray with other players...");
    g_Sharing[c]=true;
}
public void OnPluginStart(){
    if(GetEngineVersion()!=Engine_TF2||ISprays_ApiVersion()!=7)SetFailState("Requires TF2 and the matching Instant Sprays extension (API 7).");
    g_Upload=FindConVar("sv_allowupload");g_Download=FindConVar("sv_allowdownload");
    if(g_Upload==null||g_Download==null)SetFailState("TF2 file-transfer settings are unavailable.");
    g_Enabled=CreateConVar("sm_instant_sprays_enabled","1","Refresh selected sprays without reconnecting.",FCVAR_NONE,true,0.0,true,1.0);
    g_Enabled.AddChangeHook(EnabledChanged);
    CreateConVar("sm_instant_sprays_version",VERSION,"Instant Sprays version",FCVAR_NOTIFY|FCVAR_DONTRECORD);
    AutoExecConfig(true,"instant_sprays");
    RegConsoleCmd("sm_refreshspray",Refresh,"Force a refresh after replacing a spray under the same filename.");
    RegAdminCmd("sm_instant_sprays_status",Status,ADMFLAG_ROOT);
    HookEvent("player_death",Died,EventHookMode_Post);
    CreateTimer(0.05,Poll,_,TIMER_REPEAT);
    for(int c=1;c<=MaxClients;c++){g_Sprite[c]=INVALID_ENT_REFERENCE;if(Human(c))Initialize(c,false);}
}
public void OnClientPutInServer(int c){if(Human(c))Initialize(c,true);}
public void OnClientDisconnect(int c){Stop(c);}
public void OnMapStart(){for(int c=1;c<=MaxClients;c++)if(Human(c))Initialize(c,true);}
public void OnMapEnd(){for(int c=1;c<=MaxClients;c++)Stop(c);}
public void OnPluginEnd(){for(int c=1;c<=MaxClients;c++)Stop(c);}
public void OnPluginPauseChange(bool paused){if(paused)for(int c=1;c<=MaxClients;c++)Stop(c);}
public void EnabledChanged(ConVar convar,const char[] oldValue,const char[] value){if(!g_Enabled.BoolValue)for(int c=1;c<=MaxClients;c++)Stop(c);}
public void Died(Event event,const char[] name,bool dontBroadcast){
    int c=GetClientOfUserId(event.GetInt("userid"));if(c>0&&!IsPlayerAlive(c)){g_QueuedKey[c]=false;g_ReplayKey[c]=false;}
}
public Action OnPlayerRunCmd(int c,int &buttons,int &impulse,float velocity[3],float angles[3],int &weapon){
    if(!Human(c)||!g_Enabled.BoolValue)return Plugin_Continue;
    if(g_ReplayKey[c]){g_ReplayKey[c]=false;if(IsPlayerAlive(c)){impulse=201;return Plugin_Changed;}return Plugin_Continue;}
    if(impulse!=201||!IsPlayerAlive(c))return Plugin_Continue;
    if(g_HasCooldown[c]&&GetEntPropFloat(c,Prop_Data,"m_flNextDecalTime")>GetGameTime())return Plugin_Continue;
    // A failed selection is retryable on the next deliberate spray press.
    g_Failed[c][0]=0;
    // Only wait for the settings round trip, never for the image upload.
    g_QueuedKey[c]=true;QuerySettings(c,true);impulse=0;return Plugin_Changed;
}
public void SettingsReply(QueryCookie cookie,int c,ConVarQueryResult result,const char[] name,const char[] value,any serial){
    if(!Human(c)||GetClientFromSerial(serial)!=c||!g_Query[c])return;
    int field=-1;for(int i=0;i<sizeof(g_Settings);i++)if(StrEqual(name,g_Settings[i])){field=i;break;}
    if(field<0||cookie!=g_Cookies[c][field])return;
    if(result!=ConVarQuery_Okay){g_Query[c]=false;ReleaseKey(c);return;}
    if(field==0)strcopy(g_Queried[c],sizeof(g_Queried[]),value);
    else if((field==1||field==2)&&StringToInt(value)==0)g_Allowed[c]=false;
    else if(field==3&&(StrEqual(value,"none",false)||StrEqual(value,"mapsonly",false)))g_Allowed[c]=false;
    else if(field==4)g_ViewAllowed[c]=StringToInt(value)==0;
    if((field==2&&StringToInt(value)==0)||(field==3&&(StrEqual(value,"none",false)||StrEqual(value,"mapsonly",false))))g_DownloadAllowed[c]=false;
    g_Bits[c]|=1<<field;if(g_Bits[c]!=31)return;g_Query[c]=false;
    if(!g_ViewAllowed[c])RemovePreview(c);
    if(!g_Allowed[c]||!g_Upload.BoolValue||!g_Download.BoolValue){
        if(g_Manual[c])Notice(c,"Spray uploads/downloads are disabled in your client or on the server.");
        if(g_Token[c]>0){ISprays_Cancel(c,g_Token[c]);g_Token[c]=0;}
        RemovePreview(c);g_Placed[c]=false;
        ISprays_EnablePreview(c,false);g_Manual[c]=false;g_Force[c]=false;ReleaseKey(c);return;
    }
    bool changed=!StrEqual(g_Queried[c],g_Selected[c]);
    if(changed){g_Failed[c][0]=0;g_Placed[c]=false;RemovePreview(c);strcopy(g_Selected[c],sizeof(g_Selected[]),g_Queried[c]);}
    int prepared=ISprays_Watch(c,g_Selected[c],g_First[c]);g_First[c]=false;
    if(prepared<1){
        ISprays_EnablePreview(c,false);RemovePreview(c);g_Placed[c]=false;
        if(g_Manual[c])Notice(c,"Use a VTF spray inside materials/vgui/logos.");
        g_Manual[c]=false;ReleaseKey(c);return;
    }
    if(prepared==2)strcopy(g_Active[c],sizeof(g_Active[]),g_Selected[c]);
    ISprays_EnablePreview(c,g_Force[c]||(!StrEqual(g_Selected[c],g_Active[c])&&!StrEqual(g_Selected[c],g_Failed[c])));
    StartUpload(c);ReleaseKey(c);
}
public bool SurfaceFilter(int entity,int mask,any c){return entity==0||entity>MaxClients;}
public Action PreviewTransmit(int entity,int recipient){
    int index=EntRefToEntIndex(entity);
    int owner=index>0&&index<sizeof(g_PreviewOwner)?GetClientFromSerial(g_PreviewOwner[index]):0;
    if(!owner||!Human(recipient)||!g_ViewAllowed[recipient]||!ISprays_CanReceive(owner,recipient))return Plugin_Handled;
    if(g_Public[owner])return g_SurfaceViewer[owner][recipient]==GetClientSerial(recipient)?Plugin_Continue:Plugin_Handled;
    return owner==recipient?Plugin_Continue:Plugin_Handled;
}
public void OnEntityDestroyed(int entity){if(entity>0&&entity<sizeof(g_PreviewOwner))g_PreviewOwner[entity]=0;}
void DrawPreview(int c){
    if(!g_ViewAllowed[c]||!g_Placed[c]||!StrEqual(g_PlacementPath[c],g_Selected[c]))return;
    char material[PLATFORM_MAX_PATH];if(ISprays_Preview(c,material,sizeof(material))!=1)return;
    if(EntRefToEntIndex(g_Sprite[c])!=INVALID_ENT_REFERENCE)return;
    char model[PLATFORM_MAX_PATH];strcopy(model,sizeof(model),material);
    if(!IsModelPrecached(model)){
        int table=FindStringTable("modelprecache");
        if(table<0||GetStringTableNumStrings(table)>=GetStringTableMaxStrings(table)-32)return;
    }
    if(GetEntityCount()>=GetMaxEntities()-32)return;
    if(!PrecacheModel(model,false))return;
    int e=CreateEntityByName("prop_dynamic_override");if(e==-1)return;
    if(e>=sizeof(g_PreviewOwner)){RemoveEntity(e);return;}
    DispatchKeyValue(e,"model",model);DispatchKeyValue(e,"solid","0");DispatchKeyValue(e,"targetname","instant_sprays_preview");
    DispatchKeyValue(e,"DefaultAnim","idle");DispatchKeyValue(e,"disableshadows","1");DispatchKeyValue(e,"disablereceiveshadows","1");
    DispatchKeyValue(e,"DisableBoneFollowers","1");
    DispatchSpawn(e);ActivateEntity(e);g_PreviewOwner[e]=GetClientSerial(c);SDKHook(e,SDKHook_SetTransmit,PreviewTransmit);
    g_Public[c]=false;
    SetEntPropEnt(e,Prop_Send,"m_hOwnerEntity",c);
    SetEntityRenderColor(e,255,255,255,255);
    SetEntPropFloat(e,Prop_Send,"m_flModelScale",1.0);SetVariantString("idle");AcceptEntityInput(e,"SetAnimation");
    ISprays_ClearPrevious(c);
    SetEntityMoveType(e,MOVETYPE_NONE);TeleportEntity(e,g_Position[c],g_Angles[c],NULL_VECTOR);
    int surface=EntRefToEntIndex(g_Surface[c]);
    if(surface>0&&IsValidEntity(surface)){SetVariantString("!activator");AcceptEntityInput(e,"SetParent",surface);}
    g_Sprite[c]=EntIndexToEntRef(e);strcopy(g_Material[c],sizeof(g_Material[]),material);
}
void SurfaceNormal(int c,const float origin[3],float normal[3],float view[3]){
    float eye[3],direction[3],end[3];GetClientEyePosition(c,eye);GetClientEyeAngles(c,view);
    MakeVectorFromPoints(eye,origin,direction);NormalizeVector(direction,direction);
    for(int i=0;i<3;i++)end[i]=origin[i]+direction[i]*4.0;
    Handle trace=TR_TraceRayFilterEx(eye,end,MASK_SOLID_BRUSHONLY,RayType_EndPoint,SurfaceFilter,c);
    if(TR_DidHit(trace))TR_GetPlaneNormal(trace,normal);else{for(int i=0;i<3;i++)normal[i]=-direction[i];}
    delete trace;
}
public int ISprays_ShouldGuardSurface(int c,const float origin[3],int entity){
    if(!Human(c)||!g_Enabled.BoolValue||!g_ViewAllowed[c]||!g_Allowed[c]||entity!=0)return 0;
    float normal[3],view[3];SurfaceNormal(c,origin,normal,view);
    if(FloatAbs(normal[2])>0.5)return 0;
    // Native PlayerDecal's terrain branch uses the texture's broad bounding
    // volume instead of the wall's plane. Keep the clipped mesh when terrain
    // is below an upright world face. 1024 covers the accepted 2048px maximum.
    float start[3],end[3];
    for(int i=0;i<3;i++)start[i]=end[i]=origin[i]+normal[i];
    end[2]-=1024.0;
    Handle trace=TR_TraceRayFilterEx(start,end,MASK_SOLID_BRUSHONLY,RayType_EndPoint,SurfaceFilter,c);
    bool guarded=TR_DidHit(trace)&&TR_GetDisplacementFlags(trace)!=0;delete trace;
    return guarded?1:0;
}
void DrawSurfaceFinal(int c){
    if(!g_Guarded[c]||!g_Placed[c]||g_Token[c]>0||!StrEqual(g_Selected[c],g_Active[c])||GetEngineTime()<g_NextSurfacePoll[c])return;
    g_NextSurfacePoll[c]=GetEngineTime()+0.2;
    int e=EntRefToEntIndex(g_Sprite[c]);if(e<=MaxClients||!IsValidEntity(e))return;
    char model[PLATFORM_MAX_PATH];
    bool ready=true;int delivered;
    for(int recipient=1;recipient<=MaxClients;recipient++){
        g_SurfaceViewer[c][recipient]=0;
        if(!Human(recipient)||!g_ViewAllowed[recipient]||!g_DownloadAllowed[recipient])continue;
        int state=ISprays_SurfaceModel(c,recipient,model,sizeof(model));
        if(state==0)ready=false;
        else if(state==1){g_SurfaceViewer[c][recipient]=GetClientSerial(recipient);delivered++;}
    }
    // Precache only after the original audience has the tiny model files;
    // sending the string-table entry first can cache an error model.
    if(!ready||delivered==0)return;
    if(!g_Public[c]){
        if(!IsModelPrecached(model)){
            int table=FindStringTable("modelprecache");
            if(table<0||GetStringTableNumStrings(table)>=GetStringTableMaxStrings(table)-32)return;
            if(!PrecacheModel(model,false))return;
        }
        SetEntityModel(e,model);g_Public[c]=true;
    }
}
public void ISprays_OnSprayPlaced(int c,const float origin[3],int entity,bool suppressed,bool guarded){
    if(!Human(c)||!g_Enabled.BoolValue)return;RemovePreview(c);g_Placed[c]=suppressed;g_Guarded[c]=guarded;g_NextSurfacePoll[c]=0.0;
    g_DecalRecorded[c]=true;g_DecalSurface[c]=entity>0?EntIndexToEntRef(entity):0;
    for(int axis=0;axis<3;axis++)g_DecalOrigin[c][axis]=origin[axis];
    if(!suppressed)return;
    // A late per-viewer replay may have been captured just before handoff.
    if(!guarded&&g_Token[c]==0&&StrEqual(g_Selected[c],g_Active[c])){
        ReplaySpray(c);g_Placed[c]=false;return;
    }
    strcopy(g_PlacementPath[c],sizeof(g_PlacementPath[]),g_Selected[c]);g_Surface[c]=entity>0?EntIndexToEntRef(entity):INVALID_ENT_REFERENCE;
    float normal[3],view[3],direction[3];SurfaceNormal(c,origin,normal,view);
    for(int i=0;i<3;i++){g_Position[c][i]=origin[i]+normal[i]*0.2;direction[i]=-normal[i];}
    GetVectorAngles(direction,g_Angles[c]);if(FloatAbs(normal[2])>0.98)g_Angles[c][1]=view[1];
    if(!ISprays_SetSurface(c,origin,g_Angles[c],entity)){
        g_Guarded[c]=false;
        if(StrEqual(g_Selected[c],g_Active[c])){ReplaySpray(c);g_Placed[c]=false;}
        return;
    }
    DrawPreview(c);
}
public Action Poll(Handle timer){
    if(!g_Enabled.BoolValue)return Plugin_Continue;
    for(int c=1;c<=MaxClients;c++)if(Human(c)){
        if(g_Query[c]&&GetEngineTime()-g_QueryTime[c]>2.0){g_Query[c]=false;ReleaseKey(c);}
        QuerySettings(c);DrawPreview(c);DrawSurfaceFinal(c);
        if(g_Token[c]<1)continue;
        int crc;char reason[192];int state=ISprays_Status(c,g_Token[c],crc,reason,sizeof(reason));
        if(state==2||state<0||state==0){
            ISprays_Cancel(c,g_Token[c]);g_Token[c]=0;
            if(state==2){
                if(StrEqual(g_Requested[c],g_Selected[c])){
                    strcopy(g_Active[c],sizeof(g_Active[]),g_Requested[c]);ISprays_EnablePreview(c,false);
                    if(g_Placed[c]&&!g_Guarded[c]&&StrEqual(g_PlacementPath[c],g_Requested[c])){ReplaySpray(c);g_Placed[c]=false;RemovePreview(c);}
                    if(g_Manual[c]||g_Sharing[c])PrintToChat(c,"[Sprays] Your new spray is ready for other players.");
                    g_Sharing[c]=false;
                }
            }else{
                strcopy(g_Failed[c],sizeof(g_Failed[]),g_Requested[c]);Notice(c,reason[0]?reason:"Spray refresh ended before completion.");
                LogMessage("Spray refresh failed for client %d (%s): %s",c,g_Requested[c],reason);
                ISprays_EnablePreview(c,false);
                if(g_Placed[c])ReplaySpray(c);
                g_Placed[c]=false;RemovePreview(c);
                g_Sharing[c]=false;
            }
            g_Manual[c]=false;StartUpload(c);
        }
    }
    return Plugin_Continue;
}
public Action Refresh(int c,int args){
    if(!Human(c)){ReplyToCommand(c,"Use this command while connected as a player.");return Plugin_Handled;}
    if(!g_Enabled.BoolValue){ReplyToCommand(c,"[Sprays] Instant Sprays is disabled.");return Plugin_Handled;}
    if(g_Token[c]>0){ReplyToCommand(c,"[Sprays] Your spray is already synchronizing; you can keep spraying.");return Plugin_Handled;}
    g_Manual[c]=true;g_Force[c]=true;g_Failed[c][0]=0;QuerySettings(c,true);return Plugin_Handled;
}
public Action Status(int c,int args){
    ReplyToCommand(c,"[Instant Sprays] %s; enabled=%d; replay-context repairs=%d",VERSION,g_Enabled.BoolValue,g_ReplayContextRepairs);
    for(int i=1;i<=MaxClients;i++)if(Human(i)){
        int crc,requests,changes,repairs;int phase=ISprays_Inspect(i,crc,requests,changes,repairs);
        ReplyToCommand(c,"[Instant Sprays] %N: native=%d crc=%08x uploads=%d changes=%d local=%d terrain_guard=%d shared=%d",i,phase,crc,requests,changes,EntRefToEntIndex(g_Sprite[i])>MaxClients,g_Guarded[i],g_Public[i]);
        char reason[192];ISprays_LastError(i,reason,sizeof(reason));if(reason[0])ReplyToCommand(c,"  Last failure: %s",reason);
    }return Plugin_Handled;
}

// A client reply is a reliable round trip through the same game connection.
// Tokens and connection serials are checked again in the native transport.
public void ISprays_OnClearBarrier(int client,int token){
    if(!Human(client))return;
    QueryClientConVar(client,"cl_spraydisable",ClearBarrierReply,token);
}
public void ClearBarrierReply(QueryCookie cookie,int client,ConVarQueryResult result,const char[] name,const char[] value,any token){
    if(Human(client))ISprays_BarrierAck(client,token,result==ConVarQuery_Okay);
}
