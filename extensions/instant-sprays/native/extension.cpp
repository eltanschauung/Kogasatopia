// SPDX-License-Identifier: GPL-3.0-or-later
#include "smsdk_ext.h"
#include "spray_policy.h"
#include "spray_delivery.h"
#include "filesystem_hooks.h"
#include "preview_model.h"
#include "preview_geometry.h"
#include "preview_surface.h"
#include "engine/IEngineTrace.h"
#include "engine/ivmodelinfo.h"
#include "engine/ICollideable.h"
#include "eiface.h"
#include "cdll_int.h"
#include "inetchannel.h"
#include "inetmsghandler.h"
#include "networkstringtabledefs.h"
#include "filesystem.h"
#include "irecipientfilter.h"
#include "dt_send.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <climits>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <vector>

SH_DECL_HOOK2_void(INetChannelHandler,PacketStart,SH_NOATTRIB,0,int,int);
SH_DECL_HOOK0_void(INetChannelHandler,PacketEnd,SH_NOATTRIB,0);
SH_DECL_HOOK1_void(INetChannel,SetFileTransmissionMode,SH_NOATTRIB,0,bool);
SH_DECL_HOOK2_void(INetChannelHandler,FileReceived,SH_NOATTRIB,0,const char *,unsigned int);
SH_DECL_HOOK2_void(INetChannelHandler,FileDenied,SH_NOATTRIB,0,const char *,unsigned int);
SH_DECL_HOOK2_void(INetChannelHandler,FileRequested,SH_NOATTRIB,0,const char *,unsigned int);
SH_DECL_HOOK2_void(INetChannelHandler,FileSent,SH_NOATTRIB,0,const char *,unsigned int);
SH_DECL_HOOK3_void(INetworkStringTable,SetStringUserData,SH_NOATTRIB,0,int,int,const void *);
SH_DECL_HOOK0_void(IServerGameDLL,LevelShutdown,SH_NOATTRIB,0);
SH_DECL_HOOK3_void(IServerGameDLL,ServerActivate,SH_NOATTRIB,0,edict_t *,int,int);
SH_DECL_HOOK5_void(IVEngineServer,PlaybackTempEntity,SH_NOATTRIB,0,IRecipientFilter &,float,const void *,const SendTable *,int);

class InstantSprays final : public SDKExtension,public IClientListener,public IPluginsListener {
public:
    bool SDK_OnMetamodLoad(ISmmAPI *,char *,size_t,bool) override;
    bool SDK_OnLoad(char *,size_t,bool) override;
    void SDK_OnUnload() override;
    void OnClientPutInServer(int) override;
    void OnClientDisconnecting(int) override;
    void OnPluginUnloaded(IPlugin *) override;
};
InstantSprays g_Sprays;
SMEXT_LINK(&g_Sprays);

namespace {
constexpr int Slots=SM_MAXPLAYERS+1;
enum Phase {Idle=0,Uploading=1,Ready=2,Processing=3,Distributing=4,Warming=6,AwaitClear=7,Failed=-1};
IVEngineServer *serverEngine;
IEngineTrace *engineTrace;
IVModelInfo *modelInfo;
IServerGameDLL *serverDll;
INetworkStringTableContainer *tables;
INetworkStringTable *userinfo;
IFileSystem *files;
IBaseFileSystem *baseFiles;
const CGlobalVars *globals;
IGameConfig *queueConfig;
class FileQueue {public:bool Contains(const char *);};
using FileQueueMethod=bool(FileQueue::*)(const char *);
FileQueueMethod fileWaiting=nullptr;
IPluginContext *owner;
std::filesystem::path incomingRoot;
std::vector<int> globalHooks;
int tableHook;
bool publishing;
bool replaying;
IForward *placedForward,*guardForward,*visibleForward,*changedForward,*barrierForward;
uint64_t sequence;
int nextToken;

struct Download {unsigned transfer=0;bool pending=false;};
struct ModelDelivery {double settle=0,deadline=0,hardDeadline=0;bool ready=false,failed=false;std::set<unsigned> transfers;};
class Recipients final : public IRecipientFilter {
public:
    std::vector<int> members;
    bool reliable=false,init=false;
    bool IsReliable() const override{return reliable;}
    bool IsInitMessage() const override{return init;}
    int GetRecipientCount() const override{return int(members.size());}
    int GetRecipientIndex(int slot) const override{return slot>=0&&slot<int(members.size())?members[slot]:-1;}
};
struct Placement {
    std::vector<uint8_t> data;
    const SendTable *table=nullptr;
    int classId=0,client=0,entity=0,entityRef=-1;
    Vector origin{};
    spray_delivery::Audience audience;
    bool suppress=false,guard=false;
};
std::vector<std::unique_ptr<Placement>> placementStack;
Recipients noRecipients; // Must outlive every post-hook in the current engine call.
struct Client {
    INetChannel *net=nullptr;
    INetChannelHandler *handler=nullptr;
    unsigned serial=0,transfer=0;
    std::vector<int> hooks;
    std::set<std::string> requested;
    std::map<std::string,uint32_t> known;
    std::map<uint32_t,uint32_t> originalCrcs;
    std::set<std::string> previewPaths,previewDelivered;
    std::set<uint32_t> readyTextures,readyCaches;
    std::map<std::string,ModelDelivery> surfaceDownloads;
    spray_geometry::Model surfaceMesh;
    std::string surfaceModel;
    std::vector<std::string> surfaceAssets;
    std::set<unsigned> surfaceCleared;
    uint32_t surfaceCrc=0;
    std::string selected,error,cache;

    std::set<std::string> fastFiles;
    bool backgroundMode=true,fastMode=false,fastControlled=false;
    double fastCredit=0;
    std::string cacheIdentity;
    std::array<unsigned,Slots> barrier{};int barrierStage=0;double barrierNext=0;
    std::string wanted,previewMaterial;
    std::vector<std::string> previewAssets;
    double previewSettle=0,previewDeadline=0,hardDeadline=0;
    bool previewReady=false,previewEnabled=false,previewFailed=false,placementDirty=false;
    std::set<unsigned> previewTransfers;
    int lastProgress=0;
    int lastOutboundProgress=0,lastOutboundTotal=0;
    bool outboundMoved=false;
    Placement placement;
    std::filesystem::path incoming;
    uint32_t activeCrc=0,targetCrc=0,originalCrc=0;
    unsigned char marker=1;
    int token=0;
    Phase phase=Idle;
    double deadline=0,settle=0,lastRequest=0;
    unsigned requests=0,changes=0,repairs=0;
    std::array<Download,Slots> downloads{};
};
std::array<Client,Slots> clients;
std::set<std::string> mapPreviewModels;
struct CachedAssets {std::vector<uint8_t> key;std::vector<std::string> names;};
std::map<std::string,CachedAssets> mapAssets;
struct Route {
    std::string original;
    std::filesystem::path temporary;
    std::string redirectedName;
    FileHandle_t handle=nullptr;
    size_t written=0;
    bool claimed=false,rejected=false;
};
struct Packet {INetChannel *net;int client;Route route;};
thread_local std::vector<Packet> packets;
double Now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
class SlowOperation {
    const char *name;double start;
public:
    explicit SlowOperation(const char *operation):name(operation),start(Now()){}
    ~SlowOperation(){
        const double now=Now(),elapsed=now-start;
        if(elapsed<.02)return;
        static std::map<std::string,double> nextLog;
        if(now<nextLog[name])return;
        nextLog[name]=now+5;
        smutils->LogMessage(myself,"Slow spray operation: %s took %.1f ms",name,elapsed*1000);
    }
};
void ArmFastFile(int client,const char *name){
    auto &c=clients[client];if(!c.net)return;
    c.fastFiles.insert(name);
    c.fastControlled=true;
}
bool QueueFile(int client,const char *name,unsigned transfer){
    SlowOperation timing("queueing file transfer");
    // Let TF2 schedule file fragments alongside its normal game snapshots.
    // Extra Transmit calls can consume the channel's budget before snapshots.
    auto net=clients[client].net;if(!net)return false;
    ArmFastFile(client,name);
    return net->SendFile(name,transfer);
}
bool WaitingForFile(int client,const std::string &name){
    auto net=clients[client].net;if(!net)return true;
    if(fileWaiting)return (reinterpret_cast<FileQueue *>(net)->*fileWaiting)(name.c_str());
    return net->HasPendingReliableData();
}
bool WaitingForFiles(int client,const std::vector<std::string> &names){
    for(const auto &name:names)if(WaitingForFile(client,name))return true;
    return false;
}
std::string GamePath(const std::string &name){char out[1024];smutils->BuildPath(Path_Game,out,sizeof(out),"%s",name.c_str());return out;}
uint32_t Swap(uint32_t n){return (n>>24)|((n>>8)&0xff00)|((n<<8)&0xff0000)|(n<<24);}
void RemoveIncoming(const std::filesystem::path &path) {
    if(path.empty()||path.parent_path()!=incomingRoot)return;
    std::error_code error;std::filesystem::remove(path,error);
}
bool Current(int client) {
    if(client<1||client>=Slots)return false;
    auto player=playerhelpers->GetGamePlayer(client);
    return player&&player->IsInGame()&&!player->IsFakeClient()&&player->GetSerial()==clients[client].serial;
}
void LoadSelectionCache(int client){
    auto &c=clients[client];if(!c.cacheIdentity.empty())return;
    auto player=playerhelpers->GetGamePlayer(client);
    auto identity=player?player->GetSteamId64():0;if(!identity)return;
    c.cacheIdentity=std::to_string(identity);
    auto path=incomingRoot.parent_path()/"selections"/(c.cacheIdentity+".txt");
    std::error_code ec;auto size=std::filesystem::file_size(path,ec);if(ec||size>65536)return;
    std::ifstream input(path);std::string version;std::getline(input,version);if(version!="IS_CACHE_1")return;
    uint32_t crc=0,original=0;std::string selected,normalized;
    for(unsigned i=0;i<128&&input>>crc>>original>>std::quoted(selected);++i){
        if(crc&&sprays::SelectedPath(selected,normalized)&&selected==normalized){
            c.known.emplace(selected,crc);c.originalCrcs.emplace(crc,original?original:crc);
        }
    }
}
void SaveSelectionCache(int client){
    auto &c=clients[client];if(c.cacheIdentity.empty())return;
    auto directory=incomingRoot.parent_path()/"selections";std::error_code ec;
    std::filesystem::create_directories(directory,ec);if(ec)return;
    auto path=directory/(c.cacheIdentity+".txt");
    // These small, replaceable hints are never trusted as image contents; a
    // cache hit must pass the normal bounded VTF validation before publication.
    std::ofstream output(path,std::ios::trunc);if(!output)return;
    output<<"IS_CACHE_1\n";unsigned count=0;
    for(auto &entry:c.known){
        if(++count>128)break;
        auto original=c.originalCrcs.find(entry.second);
        output<<entry.second<<' '<<(original==c.originalCrcs.end()?entry.second:original->second)<<' '<<std::quoted(entry.first)<<'\n';
    }
}
bool Visible(int client,int recipient) {
    if(!Current(client)||!Current(recipient))return false;
    cell_t result=0;visibleForward->PushCell(client);visibleForward->PushCell(recipient);
    visibleForward->Execute(&result);return result==0;
}
int FromHandler(INetChannelHandler *handler){for(int i=1;i<Slots;++i)if(clients[i].handler==handler)return i;return 0;}
void Fail(Client &c,const char *reason){RemoveIncoming(c.incoming);c.incoming.clear();c.phase=Failed;c.error=reason;c.downloads={};}
bool ReadInfo(int client,player_info_t &copy,bool &swapped) {
    if(!userinfo||!Current(client)||client>userinfo->GetNumStrings())return false;
    int size=0;auto raw=userinfo->GetStringUserData(client-1,&size);
    player_info_t actual{};
    if(!raw||size!=sizeof(copy)||!serverEngine->GetPlayerInfo(client,&actual))return false;
    std::memcpy(&copy,raw,sizeof(copy));swapped=false;
    if(copy.userID!=actual.userID){if(Swap(copy.userID)!=static_cast<uint32_t>(actual.userID))return false;swapped=true;}
    return true;
}
bool ApplyInfo(int client) {
    auto &c=clients[client];player_info_t info{};bool swapped;
    if(!ReadInfo(client,info,swapped))return false;
    const auto encoded=swapped?Swap(c.activeCrc):c.activeCrc;
    if(info.customFiles[0]==encoded)return true;
    info.customFiles[0]=encoded;info.filesDownloaded=c.marker;
    const bool locked=serverEngine->LockNetworkStringTables(false);
    publishing=true;userinfo->SetStringUserData(client-1,sizeof(info),&info);publishing=false;
    serverEngine->LockNetworkStringTables(locked);return true;
}
bool ReadDisk(const std::filesystem::path &path,std::vector<uint8_t> &bytes) {
    std::ifstream input(path,std::ios::binary|std::ios::ate);
    if(!input)return false;
    auto size=input.tellg();if(size<0||size>sprays::MaxBytes)return false;
    bytes.resize(static_cast<size_t>(size));input.seekg(0);
    if(!bytes.empty())input.read(reinterpret_cast<char *>(bytes.data()),bytes.size());
    return bool(input);
}
bool Cache(const std::filesystem::path &source,const std::vector<uint8_t> &data,const std::string &name) {
    // Never overwrite a CRC collision or silently serve different bytes from
    // an earlier GAME search path.
    if(baseFiles->FileExists(name.c_str(),"GAME")) {
        auto handle=baseFiles->Open(name.c_str(),"rb","GAME");if(!handle)return false;
        unsigned size=baseFiles->Size(handle);bool equal=size==data.size();
        if(equal){std::vector<uint8_t> previous(size);equal=baseFiles->Read(previous.data(),size,handle)==int(size)&&previous==data;}
        baseFiles->Close(handle);return equal;
    }
    auto dest=std::filesystem::path(GamePath("download/"+name));std::error_code error;
    std::filesystem::create_directories(dest.parent_path(),error);if(error)return false;
    return std::filesystem::copy_file(source,dest,std::filesystem::copy_options::none,error)&&!error;
}
int PropOffset(const SendTable *table,const char *name);
void ClearOwnerDecal(int client,const Placement &p,bool everyone=false,int recipient=0) {
    if(!p.table||p.data.empty()||!Current(client))return;
    auto data=p.data;
    int entityOffset=PropOffset(p.table,"m_nEntity");
    if(entityOffset<0||size_t(entityOffset)+sizeof(int)>data.size())return;
    // PlayerDecalShoot first removes old decals with this player's userdata,
    // then declines to project onto a studio model. The player's own entity is
    // a valid studio-model target, so this clears only their existing spray.
    // This internal clear is not another spray placement/moderation event.
    std::memcpy(data.data()+entityOffset,&client,sizeof(client));
    Recipients onlyOwner;onlyOwner.reliable=true;
    if(everyone){for(int i=1;i<Slots;++i)if(Current(i))onlyOwner.members.push_back(i);}
    else onlyOwner.members.push_back(recipient?recipient:client);
    SH_CALL(serverEngine,&IVEngineServer::PlaybackTempEntity)(onlyOwner,0.0f,data.data(),p.table,p.classId);
}
void QueryBarrier(Client &c){
    c.barrier={};
    for(int peer=1;peer<Slots;++peer)if(Current(peer)){
        c.barrier[peer]=clients[peer].serial;
        barrierForward->PushCell(peer);barrierForward->PushCell(c.token);barrierForward->Execute(nullptr);
    }
}
bool BarrierPending(Client &c){
    bool pending=false;
    for(int peer=1;peer<Slots;++peer)if(c.barrier[peer]){
        if(!Current(peer)||clients[peer].serial!=c.barrier[peer])c.barrier[peer]=0;
        else pending=true;
    }
    return pending;
}
void Publish(int client,uint32_t crc) {
    auto &c=clients[client];
    player_info_t info{};bool swapped;
    if(!ReadInfo(client,info,swapped)){Fail(c,"TF2 player-info layout is unavailable.");return;}
    const uint32_t before=swapped?Swap(info.customFiles[0]):info.customFiles[0];
    // Queue the targeted clear before advertising a CRC whose DAT may still be
    // downloading. Reliable message order keeps the old usable material for it.
    c.activeCrc=crc;c.cache=sprays::CachePath(crc);c.marker=static_cast<unsigned char>(info.filesDownloaded%254+1);
    if(!ApplyInfo(client)){Fail(c,"Could not publish the new spray.");return;}
    auto identity=c.originalCrcs.find(crc);c.originalCrc=identity==c.originalCrcs.end()?crc:identity->second;
    changedForward->PushCell(client);changedForward->Execute(nullptr);
    c.downloads={};
    if(before==crc){c.phase=Ready;return;}
    ++c.changes;
    double grace=.35;
    for(int i=1;i<Slots;++i)if(Current(i)&&clients[i].net)
        grace=std::max(grace,.25+4.0*clients[i].net->GetAvgLatency(FLOW_OUTGOING));
    c.settle=Now()+std::min(grace,2.0);c.deadline=Now()+30.0;c.hardDeadline=Now()+180;c.phase=Distributing;
    c.barrierStage=0;c.barrierNext=Now()+.04;
}
bool CacheTexture(std::vector<uint8_t> &data,uint32_t &crc){
    SlowOperation timing("preparing spray texture");
    sprays::CanonicalTexture(data);crc=sprays::Crc(data);if(!crc)return false;
    auto copy=incomingRoot/("texture_"+std::to_string(++sequence)+".vtf");
    {std::ofstream f(copy,std::ios::binary);f.write(reinterpret_cast<const char *>(data.data()),data.size());if(!f){RemoveIncoming(copy);return false;}}
    bool ok=Cache(copy,data,sprays::CachePath(crc))&&Cache(copy,data,"materials/temp/"+sprays::Hex(crc)+".vtf");
    RemoveIncoming(copy);return ok;
}
void PreparePublication(int client,uint32_t crc){
    auto &c=clients[client];c.targetCrc=crc;c.cache=sprays::CachePath(crc);
    c.downloads={};
    // Clear the old decal under its still-valid CRC. Two acknowledged client
    // queries, separated by game frames, let that clear execute before the
    // new userinfo arrives. The client can then request only a missing DAT.
    ClearOwnerDecal(client,c.placement,true);
    c.barrier={};c.barrierStage=0;c.barrierNext=Now()+.04;
    c.deadline=Now()+15;c.phase=AwaitClear;
}
void Complete(int client) {
    auto &c=clients[client];std::vector<uint8_t> data;std::string reason;
    if(!ReadDisk(c.incoming,data)){Fail(c,"Could not read the uploaded spray.");return;}
    if(!sprays::ValidTexture(data,reason)){Fail(c,reason.c_str());return;}
    uint32_t crc=0,original=sprays::Crc(data);
    if(!CacheTexture(data,crc)){Fail(c,"Spray cache write failed or its identifier conflicts with another file.");return;}
    c.originalCrcs[crc]=original;c.known[c.selected]=crc;SaveSelectionCache(client);RemoveIncoming(c.incoming);c.incoming.clear();
    if(!c.wanted.empty()&&c.wanted!=c.selected){c.phase=Ready;return;}
    PreparePublication(client,crc);
}
bool WriteSurfaceAssets(int client,const std::string &path,const spray_geometry::Model &mesh,
                       std::string &model,std::vector<std::string> &names,const std::string &audience="") {
    SlowOperation timing("preparing surface assets");
    auto &c=clients[client];
    std::vector<uint8_t> key(path.begin(),path.end());key.push_back(0);
    key.insert(key.end(),audience.begin(),audience.end());key.push_back(0);
    key.insert(key.end(),mesh.vvd.begin(),mesh.vvd.end());key.insert(key.end(),mesh.vtx.begin(),mesh.vtx.end());
    uint32_t checksum=sprays::Crc(key);std::string hex=sprays::Hex(checksum);
    std::string stem="instant_sprays/v7/"+hex;
    model="models/"+stem+".mdl";
    if(c.previewPaths.size()>=128&&!c.previewPaths.count(model))return false;
    if(mapPreviewModels.size()>=192&&!mapPreviewModels.count(model))return false;
    mapPreviewModels.insert(model);
    c.previewPaths.insert(model);
    auto cached=mapAssets.find(model);
    if(cached!=mapAssets.end()){
        if(cached->second.key!=key)return false; // Reject a checksum collision.
        names=cached->second.names;return true;
    }
    const auto texture=path.substr(10,path.size()-14);
    const std::string body="\"UnlitGeneric\"\n{\n\"$basetexture\" \""+texture+"\"\n"
        "\"$model\" \"1\"\n\"$nocull\" \"1\"\n"
        "\"$translucent\" \"1\"\n\"Proxies\" { \"AnimatedTexture\" { \"animatedTextureVar\" \"$basetexture\" "
        "\"animatedTextureFrameNumVar\" \"$frame\" \"animatedTextureFrameRate\" \"5\" } }\n}\n";
    std::vector<std::pair<std::string,std::vector<uint8_t>>> assets;
    assets.push_back({"materials/"+stem+".vmt",{body.begin(),body.end()}});
    auto addModel=[&](const char *suffix,const uint8_t *bytes,size_t size,size_t checksumOffset,bool names){
        std::vector<uint8_t> data(bytes,bytes+size);
        if(names)for(auto offset:preview_model::MdlNames)std::memcpy(data.data()+offset,hex.data(),8);
        for(int i=0;i<4;++i)data[checksumOffset+i]=uint8_t(checksum>>(8*i));
        assets.push_back({"models/"+stem+suffix,std::move(data)});
    };
    addModel(".vvd",mesh.vvd.data(),mesh.vvd.size(),8,false);
    addModel(".dx90.vtx",mesh.vtx.data(),mesh.vtx.size(),16,false);
    addModel(".mdl",mesh.mdl.data(),mesh.mdl.size(),8,true);
    for(const auto &asset:assets){
        auto temporary=incomingRoot/("asset_"+std::to_string(++sequence)+".bin");
        {std::ofstream file(temporary,std::ios::binary);file.write(reinterpret_cast<const char *>(asset.second.data()),asset.second.size());if(!file){RemoveIncoming(temporary);return false;}}
        bool ready=Cache(temporary,asset.second,asset.first);RemoveIncoming(temporary);if(!ready)return false;
        names.push_back(asset.first);
    }
    mapAssets.emplace(model,CachedAssets{std::move(key),names});
    return true;
}
bool PreparePreview(int client,const std::string &path,const spray_geometry::Model &mesh) {
    auto &c=clients[client];std::string model;std::vector<std::string> assets;
    // Other clients may have cached an unavailable owner-only model during
    // signon. A new connection must never reuse that model-precache identity.
    if(!WriteSurfaceAssets(client,path,mesh,model,assets,"owner:"+std::to_string(c.serial)))return false;
    c.previewAssets=assets;
    if(c.previewMaterial==model)return true;
    if(c.previewDelivered.count(model)){c.previewMaterial=model;c.previewReady=true;c.previewFailed=false;c.previewTransfers.clear();return true;}
    c.previewMaterial=model;c.previewReady=false;c.previewFailed=false;c.previewTransfers.clear();
    c.previewSettle=Now()+std::max(.15,4.0*c.net->GetAvgLatency(FLOW_OUTGOING));c.previewDeadline=Now()+15;
    for(const auto &asset:assets){
        auto id=static_cast<unsigned>(++sequence);c.previewTransfers.insert(id);
        if(!QueueFile(client,asset.c_str(),id)){c.previewFailed=true;return false;}
    }
    return true;
}
int PropOffset(const SendTable *table,const char *name) {
    for(int i=0;i<table->GetNumProps();++i){const auto prop=const_cast<SendTable *>(table)->GetProp(i);
        if(!strcmp(prop->GetName(),name))return prop->GetOffset();
    }return -1;
}
Packet *Context() {
    if(packets.empty())return nullptr;
    auto &p=packets.back();
    return Current(p.client)&&clients[p.client].net==p.net?&p:nullptr;
}
bool IncomingName(const char *name,const char *pathID) {
    auto p=Context();return p&&name&&pathID&&!strcmp(pathID,"download")
        &&clients[p->client].requested.count(name)!=0;
}
// Only spray_files' game-thread gate may enter these upload policy callbacks.
// TF2 opens/compresses outgoing files on worker threads, where SourceHook's
// shared context stack and SourceMod's player helpers must never be touched.
bool UploadExists(const char *name,const char *pathID,bool &result){
    if(!IncomingName(name,pathID))return false;
    auto p=Context();if(!p->route.claimed)RemoveIncoming(p->route.temporary);
    p->route=Route{};p->route.original=name;
    p->route.temporary=incomingRoot/("upload_"+std::to_string(clients[p->client].serial)+"_"+std::to_string(++sequence)+".vtf");
    result=false;return true;
}
bool UploadOpen(const char *&name,const char *options,const char *&pathID){
    auto p=Context();
    if(!p||!IncomingName(name,pathID)||!options||!strchr(options,'w')||p->route.original!=name||p->route.temporary.empty())return false;
    p->route.redirectedName=p->route.temporary.string();
    name=p->route.redirectedName.c_str();pathID=nullptr;return true;
}
void UploadOpened(void *handle){auto p=Context();if(p)p->route.handle=handle;}
bool UploadWrite(int size,void *handle,int &result){
    auto p=Context();
    if(p&&handle&&p->route.handle==handle){
        if(size<0||size>int(sprays::MaxBytes)||p->route.written+size>sprays::MaxBytes){p->route.rejected=true;result=0;return true;}
        p->route.written+=size;
    }
    return false;
}
void UploadClosed(void *handle){auto p=Context();if(p&&p->route.handle==handle)p->route.handle=nullptr;}
bool UploadDirectory(const char *path,const char *pathID){
    auto p=Context();
    if(p&&path&&pathID&&!strcmp(pathID,"download")&&!p->route.temporary.empty()){
        std::string directory=path;while(!directory.empty()&&(directory.back()=='/'||directory.back()=='\\'))directory.pop_back();
        auto slash=p->route.original.find_last_of('/');
        return slash!=std::string::npos&&directory==p->route.original.substr(0,slash);
    }
    return false;
}
class Hooks {
public:
    void FileMode(bool background){
        auto net=META_IFACEPTR(INetChannel);
        for(auto &c:clients)if(c.net==net){
            c.backgroundMode=background;
            if(c.fastControlled)RETURN_META_NEWPARAMS(MRES_IGNORED,&INetChannel::SetFileTransmissionMode,(!c.fastMode));
            break;
        }
        RETURN_META(MRES_IGNORED);
    }
    void PacketBegin(int,int){
        // PacketStart precedes fragment completion in the stock engine. Avoid
        // wrapping ProcessPacket itself, which can dispatch plugin-unload commands.
        for(auto &p:packets)if(!p.route.claimed)RemoveIncoming(p.route.temporary);
        packets.clear();
        int client=FromHandler(META_IFACEPTR(INetChannelHandler));
        if(client)packets.push_back({clients[client].net,client,{}});
        RETURN_META(MRES_IGNORED);
    }
    void PacketEnd(){
        for(auto &p:packets)if(!p.route.claimed)RemoveIncoming(p.route.temporary);
        packets.clear();
        RETURN_META(MRES_IGNORED);
    }
    void Received(const char *name,unsigned transfer) {
        int client=FromHandler(META_IFACEPTR(INetChannelHandler));auto p=Context();
        if(client&&name&&clients[client].requested.count(name)){
            auto &c=clients[client];
            if(c.phase==Uploading&&c.transfer==transfer&&c.selected==name){
                if(!p||p->client!=client||p->route.original!=name||p->route.temporary.empty()||p->route.rejected)
                    Fail(c,"Spray upload was oversized or could not be isolated.");
                else {c.incoming=p->route.temporary;p->route.claimed=true;c.phase=Processing;}
            }
            RETURN_META(MRES_SUPERCEDE);
        }
        RETURN_META(MRES_IGNORED);
    }
    void Denied(const char *name,unsigned transfer){
        int client=FromHandler(META_IFACEPTR(INetChannelHandler));
        if(client&&clients[client].previewTransfers.count(transfer))clients[client].previewFailed=true;
        if(client)for(auto &entry:clients[client].surfaceDownloads)
            if(entry.second.transfers.count(transfer))entry.second.failed=true;
        if(client&&name&&clients[client].phase==Uploading&&clients[client].transfer==transfer&&clients[client].selected==name)
            Fail(clients[client],"Client declined the spray upload or could not find the file.");
        RETURN_META(MRES_IGNORED);
    }
    void Requested(const char *name,unsigned transfer){
        int recipient=FromHandler(META_IFACEPTR(INetChannelHandler));
        if(recipient&&name)for(auto &c:clients)if(c.cache==name&&c.activeCrc){
            ArmFastFile(recipient,name);
            if(c.phase==Distributing)c.downloads[recipient]={transfer,true};
        }
        RETURN_META(MRES_IGNORED);
    }
    void SprayBefore(IRecipientFilter &filter,float delay,const void *sender,const SendTable *table,int classId){
        if(replaying||!table||strcmp(table->GetName(),"DT_TEPlayerDecal"))RETURN_META(MRES_IGNORED);
        placementStack.push_back(nullptr);
        int po=PropOffset(table,"m_nPlayer"),eo=PropOffset(table,"m_nEntity"),vo=PropOffset(table,"m_vecOrigin");
        if(po<0||eo<0||vo<0)RETURN_META(MRES_IGNORED);
        auto bytes=static_cast<const uint8_t *>(sender);int client;std::memcpy(&client,bytes+po,sizeof(client));
        if(!Current(client))RETURN_META(MRES_IGNORED);
        auto placement=std::make_unique<Placement>();auto &p=*placement;
        p.client=client;p.table=table;p.classId=classId;p.suppress=clients[client].previewEnabled;
        std::memcpy(&p.entity,bytes+eo,sizeof(p.entity));std::memcpy(&p.origin,bytes+vo,sizeof(p.origin));
        if(owner&&!clients[client].wanted.empty()){
            cell_t point[3]={sp_ftoc(p.origin.x),sp_ftoc(p.origin.y),sp_ftoc(p.origin.z)},guard=0;
            guardForward->PushCell(client);guardForward->PushArray(point,3);guardForward->PushCell(p.entity);
            guardForward->Execute(&guard);p.guard=guard!=0;p.suppress|=p.guard;
        }
        if(p.entity>0)p.entityRef=gamehelpers->IndexToReference(p.entity);
        const auto size=std::max({po+int(sizeof(int)),eo+int(sizeof(int)),vo+int(sizeof(Vector))});
        p.data.assign(bytes,bytes+size);
        for(int i=0;i<filter.GetRecipientCount();++i){int recipient=filter.GetRecipientIndex(i);
            if(Current(recipient))p.audience.Add(recipient,clients[recipient].serial);
        }
        placementStack.back()=std::move(placement);
        // Keep the original call (with an empty recipient filter). Later hooks
        // may veto it; the post-hook only creates a preview when nobody did.
        if(p.suppress)RETURN_META_NEWPARAMS(MRES_HANDLED,&IVEngineServer::PlaybackTempEntity,(noRecipients,delay,sender,table,classId));
        RETURN_META(MRES_IGNORED);
    }
    void SprayAfter(IRecipientFilter &,float,const void *sender,const SendTable *table,int){
        if(replaying||!table||strcmp(table->GetName(),"DT_TEPlayerDecal")||placementStack.empty())RETURN_META(MRES_IGNORED);
        auto saved=std::move(placementStack.back());placementStack.pop_back();
        if(!saved)RETURN_META(MRES_IGNORED);
        auto &p=*saved;
        if(META_RESULT_STATUS>=MRES_SUPERCEDE||!Current(p.client))RETURN_META(MRES_IGNORED);
        // Preserve property changes made by other accepted temp-entity hooks.
        std::memcpy(p.data.data(),sender,p.data.size());
        std::memcpy(&p.entity,p.data.data()+PropOffset(table,"m_nEntity"),sizeof(p.entity));
        std::memcpy(&p.origin,p.data.data()+PropOffset(table,"m_vecOrigin"),sizeof(p.origin));
        if(p.entity>0)p.entityRef=gamehelpers->IndexToReference(p.entity);
        if(p.audience.members.empty())RETURN_META(MRES_IGNORED);
        auto &c=clients[p.client];
        if(c.placement.table==p.table&&c.placement.classId==p.classId
           &&c.placement.guard==p.guard&&c.placement.suppress==p.suppress&&c.placement.data==p.data)
            c.placement.audience.Merge(p.audience);
        else c.placement=p;
        // Dispatch once next frame, after per-viewer moderation re-sends finish.
        c.placementDirty=true;
        RETURN_META(MRES_IGNORED);
    }
    void Sent(const char *name,unsigned transfer){
        int recipient=FromHandler(META_IFACEPTR(INetChannelHandler));
        if(recipient&&name)for(auto &c:clients)if(c.phase==Distributing&&c.cache==name&&c.downloads[recipient].transfer==transfer)
            c.downloads[recipient].pending=false;
        RETURN_META(MRES_IGNORED);
    }
    void Info(int index,int,const void *){
        if(!publishing&&index>=0&&index+1<Slots&&clients[index+1].activeCrc){
            player_info_t info{};bool swapped;int client=index+1;
            if(ReadInfo(client,info,swapped)&&(swapped?Swap(info.customFiles[0]):info.customFiles[0])!=clients[client].activeCrc)
                if(ApplyInfo(client))++clients[client].repairs;
        }
        RETURN_META(MRES_IGNORED);
    }
    void Shutdown();
    void Activate(edict_t *,int,int);
} hooks;

void ClearClient(int client){
    auto &c=clients[client];
    if(c.net&&c.fastControlled)SH_CALL(c.net,&INetChannel::SetFileTransmissionMode)(c.backgroundMode);
    for(int hook:c.hooks)if(hook)SH_REMOVE_HOOK_ID(hook);
    RemoveIncoming(c.incoming);c=Client{};
    for(auto &state:clients)state.downloads[client]={};
}
void BindClient(int client) {
    if(client<1||client>=Slots)return;
    auto player=playerhelpers->GetGamePlayer(client);
    if(!player||!player->IsInGame()||player->IsFakeClient())return;
    auto net=static_cast<INetChannel *>(serverEngine->GetPlayerNetInfo(client));
    if(!net||!net->GetMsgHandler())return;
    if(clients[client].net==net&&clients[client].serial==player->GetSerial())return;
    ClearClient(client);auto &c=clients[client];c.net=net;c.handler=net->GetMsgHandler();c.serial=player->GetSerial();
    c.hooks={
        SH_ADD_HOOK(INetChannel,SetFileTransmissionMode,c.net,SH_MEMBER(&hooks,&Hooks::FileMode),false),
        SH_ADD_HOOK(INetChannelHandler,PacketStart,c.handler,SH_MEMBER(&hooks,&Hooks::PacketBegin),false),
        SH_ADD_HOOK(INetChannelHandler,PacketEnd,c.handler,SH_MEMBER(&hooks,&Hooks::PacketEnd),true),
        SH_ADD_HOOK(INetChannelHandler,FileReceived,c.handler,SH_MEMBER(&hooks,&Hooks::Received),false),
        SH_ADD_HOOK(INetChannelHandler,FileDenied,c.handler,SH_MEMBER(&hooks,&Hooks::Denied),false),
        SH_ADD_HOOK(INetChannelHandler,FileRequested,c.handler,SH_MEMBER(&hooks,&Hooks::Requested),false),
        SH_ADD_HOOK(INetChannelHandler,FileSent,c.handler,SH_MEMBER(&hooks,&Hooks::Sent),false)};
    for(int hook:c.hooks)if(!hook){ClearClient(client);return;}
}
void BindTable(){
    if(tableHook){SH_REMOVE_HOOK_ID(tableHook);tableHook=0;}
    userinfo=tables->FindTable("userinfo");
    if(userinfo)tableHook=SH_ADD_HOOK(INetworkStringTable,SetStringUserData,userinfo,SH_MEMBER(&hooks,&Hooks::Info),true);
}
void StopMap(){
    if(tableHook){SH_REMOVE_HOOK_ID(tableHook);tableHook=0;}userinfo=nullptr;
    for(int i=1;i<Slots;++i)ClearClient(i);
    for(auto &p:packets)if(!p.route.claimed)RemoveIncoming(p.route.temporary);
    packets.clear();
    placementStack.clear();
    mapPreviewModels.clear();
    mapAssets.clear();
}
void Hooks::Shutdown(){StopMap();RETURN_META(MRES_IGNORED);}
void Hooks::Activate(edict_t *,int,int){BindTable();RETURN_META(MRES_IGNORED);}
void Frame(bool){
    SlowOperation timing("spray frame processing");
    // Malformed packets can leave without PacketEnd. File routing must never
    // survive into unrelated game-frame filesystem work.
    for(auto &p:packets)if(!p.route.claimed)RemoveIncoming(p.route.temporary);
    packets.clear();
    double now=Now();bool processed=false;
    for(int i=1;i<Slots;++i){auto &c=clients[i];
        if(c.net&&Current(i)){
            for(auto f=c.fastFiles.begin();f!=c.fastFiles.end();){
                if(!WaitingForFile(i,*f))f=c.fastFiles.erase(f);else ++f;
            }
            if(c.fastControlled&&c.fastFiles.empty()){
                SH_CALL(c.net,&INetChannel::SetFileTransmissionMode)(c.backgroundMode);
                c.fastMode=false;c.fastControlled=false;c.fastCredit=0;
            }else if(c.fastControlled){
                // At most the normal scheduler's four 256-byte fragments per
                // packet. Reserve bandwidth for snapshots; lower-rate or
                // choking clients retain more background-mode packets.
                const double rate=c.net->GetDataRate();
                const double packetsPerSecond=1.0/std::max(double(globals->interval_per_tick),.001);
                const double fileBudget=std::max(0.0,rate-std::max(16384.0,rate*.35));
                double fraction=std::clamp((fileBudget/(256.0*packetsPerSecond)-1.0)/3.0,0.0,1.0);
                if(c.net->GetAvgChoke(FLOW_OUTGOING)>.03f)fraction=0;
                c.fastCredit=std::min(c.fastCredit+fraction,2.0);
                bool fast=!c.backgroundMode||c.fastCredit>=1.0;
                if(c.fastCredit>=1.0)c.fastCredit-=1.0;
                if(fast!=c.fastMode){SH_CALL(c.net,&INetChannel::SetFileTransmissionMode)(!fast);c.fastMode=fast;}
            }
            if(c.placementDirty){
                c.placementDirty=false;const auto p=c.placement;
                cell_t origin[3]={sp_ftoc(p.origin.x),sp_ftoc(p.origin.y),sp_ftoc(p.origin.z)};
                placedForward->PushCell(i);placedForward->PushArray(origin,3);placedForward->PushCell(p.entity);
                placedForward->PushCell(p.suppress?1:0);placedForward->PushCell(p.guard?1:0);placedForward->Execute(nullptr);
            }
            int receivedOut=0,totalOut=0;c.net->GetStreamProgress(FLOW_OUTGOING,&receivedOut,&totalOut);
            c.outboundMoved=receivedOut!=c.lastOutboundProgress||totalOut!=c.lastOutboundTotal;
            c.lastOutboundProgress=receivedOut;c.lastOutboundTotal=totalOut;
            if(!c.previewReady&&!c.previewFailed&&!c.previewMaterial.empty()&&now>=c.previewSettle&&!WaitingForFiles(i,c.previewAssets)){
                c.previewReady=true;c.previewDelivered.insert(c.previewMaterial);
            }
            if(c.phase==Uploading){int received=0,total=0;
                c.net->GetStreamProgress(FLOW_INCOMING,&received,&total);
                if(received>c.lastProgress)c.deadline=std::min(now+20.0,c.hardDeadline);
                // An earlier signon file may finish ahead of this request.
                // Restart the progress counter when the next file begins.
                c.lastProgress=received;
            }
        }
        if(c.phase==Processing&&!processed){processed=true;if(Current(i))Complete(i);else Fail(c,"Player left before upload completed.");}
        else if(c.phase==Uploading&&now>c.deadline)Fail(c,"Spray upload timed out.");
        else if(c.phase==AwaitClear){
            if(now>=c.deadline){Fail(c,"Client did not acknowledge the spray clear.");continue;}
            if((c.barrierStage==0||c.barrierStage==2)&&now>=c.barrierNext){++c.barrierStage;QueryBarrier(c);}
            if((c.barrierStage==1||c.barrierStage==3)&&!BarrierPending(c)){
                if(c.barrierStage==1){c.barrierStage=2;c.barrierNext=now+.05;}
                else if(!c.wanted.empty()&&c.wanted!=c.selected)c.phase=Ready;
                else Publish(i,c.targetCrc);
            }
        }
        else if(c.phase==Distributing){bool pending=false;
            if(c.barrierStage==0&&now>=c.barrierNext){c.barrierStage=1;QueryBarrier(c);}
            pending=c.barrierStage==0||BarrierPending(c);
            for(int recipient=1;recipient<Slots;++recipient){auto &d=c.downloads[recipient];
                // Only this image's DAT matters; another player's queued file
                // or ordinary reliable traffic must not hold up its handoff.
                if(d.pending&&Current(recipient)&&clients[recipient].outboundMoved)c.deadline=std::min(now+30.0,c.hardDeadline);
                if(d.pending&&(!Current(recipient)||!WaitingForFile(recipient,c.cache))){
                    d.pending=false;if(Current(recipient))clients[recipient].readyCaches.insert(c.activeCrc);
                }
                pending|=d.pending;
            }
            if(now>=c.deadline&&pending){Fail(c,"Spray delivery stalled.");continue;}
            if(now>=c.settle&&!pending){
                for(int peer=1;peer<Slots;++peer)if(Current(peer))clients[peer].readyCaches.insert(c.activeCrc);
                if(!c.placement.data.empty()){
                    // Creating a normal player decal first materializes DAT as
                    // VTF. The studio-model target clears without projecting.
                    ClearOwnerDecal(i,c.placement,true);
                    double grace=.25;
                    for(int peer=1;peer<Slots;++peer)if(Current(peer)&&clients[peer].net)
                        grace=std::max(grace,.15+2.0*clients[peer].net->GetAvgLatency(FLOW_OUTGOING));
                    c.settle=now+std::min(grace,2.0);c.phase=Warming;
                }else c.phase=Ready;
            }
        }
        else if(c.phase==Warming&&now>=c.settle)c.phase=Ready;
    }
}
bool Claim(IPluginContext *context){if(owner&&owner!=context){context->ThrowNativeError("Instant Sprays already has a controlling plugin");return false;}owner=context;return true;}
cell_t Api(IPluginContext *,const cell_t *){return 7;}
cell_t Request(IPluginContext *context,const cell_t *params){
    if(!Claim(context))return 0;
    int client=params[1];char *input;context->LocalToString(params[2],&input);std::string path;
    if(!sprays::SelectedPath(input,path))return -1;
    BindClient(client);if(!Current(client)||!clients[client].net||!userinfo||!tableHook)return 0;
    auto &c=clients[client];LoadSelectionCache(client);
    if(c.phase==Uploading||c.phase==Processing||c.phase==Distributing||c.phase==Warming||c.phase==AwaitClear)return 0;
    if(!params[3]){auto found=c.known.find(path);if(found!=c.known.end()&&baseFiles->FileExists(sprays::CachePath(found->second).c_str(),"GAME")){
        c.selected=path;c.error.clear();nextToken=nextToken>=INT_MAX?1:nextToken+1;c.token=nextToken;
        auto handle=baseFiles->Open(sprays::CachePath(found->second).c_str(),"rb","GAME");
        std::vector<uint8_t> data;std::string why;uint32_t crc=0;
        if(handle){auto size=baseFiles->Size(handle);if(size<=sprays::MaxBytes){data.resize(size);if(baseFiles->Read(data.data(),size,handle)!=int(size))data.clear();}baseFiles->Close(handle);}
        const uint32_t oldCrc=found->second;
        if(!sprays::ValidTexture(data,why)||!CacheTexture(data,crc)){Fail(c,"Cached spray is unavailable; use !refreshspray to upload it again.");return c.token;}
        auto original=c.originalCrcs.find(oldCrc);c.originalCrcs[crc]=original==c.originalCrcs.end()?oldCrc:original->second;
        c.known[path]=crc;PreparePublication(client,crc);return c.token;
    }}
    if(Now()-c.lastRequest<1.0)return 0;
    if(c.requested.size()>=128&&!c.requested.count(path)){
        nextToken=nextToken>=INT_MAX?1:nextToken+1;c.token=nextToken;
        Fail(c,"Too many distinct spray selections in this connection.");return c.token;
    }
    c.selected=path;c.requested.insert(path);c.error.clear();c.lastRequest=Now();
    nextToken=nextToken>=INT_MAX?1:nextToken+1;c.token=nextToken;
    c.phase=Uploading;c.deadline=Now()+20;c.hardDeadline=Now()+180;c.lastProgress=0;
    c.transfer=c.net->RequestFile(path.c_str());++c.requests;return c.token;
}
cell_t Status(IPluginContext *context,const cell_t *params){
    int client=params[1];if(client<1||client>=Slots||clients[client].token!=params[2])return Idle;
    auto &c=clients[client];cell_t *crc;context->LocalToPhysAddr(params[3],&crc);*crc=static_cast<cell_t>(c.activeCrc);
    context->StringToLocalUTF8(params[4],params[5],c.error.c_str(),nullptr);return c.phase;
}
cell_t Cancel(IPluginContext *context,const cell_t *params){
    if(owner&&context!=owner)return context->ThrowNativeError("Not the controlling plugin");
    int client=params[1];if(client>0&&client<Slots&&clients[client].token==params[2]){auto &c=clients[client];RemoveIncoming(c.incoming);c.incoming.clear();c.phase=Idle;c.downloads={};}return 0;
}
cell_t Inspect(IPluginContext *context,const cell_t *params){
    int client=params[1];if(client<1||client>=Slots)return 0;
    auto &c=clients[client];cell_t values[]={static_cast<cell_t>(c.activeCrc),static_cast<cell_t>(c.requests),static_cast<cell_t>(c.changes),static_cast<cell_t>(c.repairs)};
    for(int i=0;i<4;++i){cell_t *out;context->LocalToPhysAddr(params[i+2],&out);*out=values[i];}return c.phase;
}
cell_t Watch(IPluginContext *context,const cell_t *params){
    if(!Claim(context))return 0;
    int client=params[1];char *input;context->LocalToString(params[2],&input);std::string path;
    if(!sprays::SelectedPath(input,path))return -1;
    BindClient(client);if(!Current(client)||!clients[client].net)return 0;
    auto &c=clients[client];LoadSelectionCache(client);
    if(c.wanted!=path){c.previewMaterial.clear();c.previewReady=false;}
    c.wanted=path;bool associated=false;
    if(params[3]&&!c.requests){player_info_t info{};bool swapped;
        if(ReadInfo(client,info,swapped)){uint32_t crc=swapped?Swap(info.customFiles[0]):info.customFiles[0];
            // The signon upload can still be arriving when PutInServer runs.
            // Its announced CRC already identifies the initial selection; do
            // not start a second upload just because its DAT is not written yet.
            if(crc){
                auto found=c.known.find(path);
                bool same=false;
                if(found!=c.known.end()){
                    auto original=c.originalCrcs.find(found->second);
                    same=original!=c.originalCrcs.end()&&original->second==crc;
                }
                if(!same)c.known[path]=crc;
                associated=true;
            }
        }
    }
    return associated?2:1;
}
cell_t Surface(IPluginContext *context,const cell_t *params){
    SlowOperation timing("clipping spray surface");
    if(!Claim(context))return 0;
    int client=params[1],entity=params[4];if(!Current(client)||entity<0)return 0;
    auto edict=gamehelpers->EdictOfIndex(entity);if(!edict||edict->IsFree())return 0;
    cell_t *point,*angles;context->LocalToPhysAddr(params[2],&point);context->LocalToPhysAddr(params[3],&angles);
    Vector origin(sp_ctof(point[0]),sp_ctof(point[1]),sp_ctof(point[2]));
    QAngle facing(sp_ctof(angles[0]),sp_ctof(angles[1]),sp_ctof(angles[2]));
    auto &c=clients[client];c.previewMaterial.clear();c.previewReady=false;
    c.surfaceMesh={};c.surfaceModel.clear();c.surfaceAssets.clear();c.surfaceCleared.clear();c.surfaceCrc=0;
    spray_geometry::Polygons polygons;spray_geometry::Model mesh;
    if(!spray_geometry::Surface(engineTrace,modelInfo,edict->GetCollideable(),entity==0,origin,facing,polygons)
        ||!spray_geometry::BuildModel(polygons,mesh))return 0;
    if(!PreparePreview(client,c.wanted,mesh))return 0;
    c.surfaceMesh=std::move(mesh);return 1;
}
cell_t SurfaceModel(IPluginContext *context,const cell_t *params){
    if(!Claim(context))return -1;
    int client=params[1],recipient=params[2];
    if(!Current(client)||!Current(recipient))return -1;
    auto &c=clients[client];auto &peer=clients[recipient];auto &p=c.placement;
    if(!p.audience.Contains(recipient,peer.serial)||!Visible(client,recipient)
       ||c.surfaceMesh.mdl.empty()||!peer.net)return -1;
    if(c.surfaceModel.empty()){
        auto found=c.known.find(c.wanted);if(found==c.known.end()||!found->second)return 0;
        uint32_t crc=found->second;const auto texture="materials/temp/"+sprays::Hex(crc)+".vtf";
        if(!baseFiles->FileExists(texture.c_str(),"GAME")){
            auto handle=baseFiles->Open(sprays::CachePath(crc).c_str(),"rb","GAME");if(!handle)return 0;
            auto size=baseFiles->Size(handle);std::vector<uint8_t> data;std::string why;
            if(size<=sprays::MaxBytes){data.resize(size);if(baseFiles->Read(data.data(),size,handle)!=int(size))data.clear();}
            baseFiles->Close(handle);
            if(!sprays::ValidTexture(data,why)||sprays::Crc(data)!=crc)return -1;
            auto temporary=incomingRoot/("surface_"+std::to_string(++sequence)+".vtf");
            {std::ofstream f(temporary,std::ios::binary);f.write(reinterpret_cast<const char *>(data.data()),data.size());if(!f){RemoveIncoming(temporary);return -1;}}
            bool ok=Cache(temporary,data,texture);RemoveIncoming(temporary);if(!ok)return -1;
        }
        // A later joiner may have seen earlier model-precache entries before
        // downloading them. A changed audience gets a fresh immutable model.
        std::string model,audience="shared:";std::vector<std::string> assets;
        for(auto member:p.audience.members)audience+=std::to_string(member.second)+":";
        if(!WriteSurfaceAssets(client,texture,c.surfaceMesh,model,assets,audience))return -1;
        c.surfaceModel=model;c.surfaceAssets=std::move(assets);c.surfaceCrc=crc;
    }
    context->StringToLocalUTF8(params[3],params[4],c.surfaceModel.c_str(),nullptr);
    auto found=peer.surfaceDownloads.find(c.surfaceModel);
    if(found==peer.surfaceDownloads.end()){
        ModelDelivery d;d.settle=Now()+std::max(.15,4.0*peer.net->GetAvgLatency(FLOW_OUTGOING));d.deadline=Now()+60;d.hardDeadline=Now()+180;
        auto send=[&](const std::string &name){auto id=static_cast<unsigned>(++sequence);d.transfers.insert(id);if(!QueueFile(recipient,name.c_str(),id))d.failed=true;};
        if(!peer.readyTextures.count(c.surfaceCrc)){
            if(peer.readyCaches.count(c.surfaceCrc)){
                ClearOwnerDecal(client,p,false,recipient);
                d.settle=Now()+std::max(.25,4.0*peer.net->GetAvgLatency(FLOW_OUTGOING));
            }else send("materials/temp/"+sprays::Hex(c.surfaceCrc)+".vtf");
        }
        for(const auto &name:c.surfaceAssets)send(name);
        peer.surfaceDownloads.emplace(c.surfaceModel,std::move(d));return 0;
    }
    auto &d=found->second;
    if(!d.ready&&peer.outboundMoved)d.deadline=std::min(Now()+60.0,d.hardDeadline);
    if(!d.ready&&Now()>d.deadline)d.failed=true;
    if(d.failed)return -1;
    if(!d.ready&&Now()>=d.settle&&!WaitingForFiles(recipient,c.surfaceAssets)
       &&!WaitingForFile(recipient,"materials/temp/"+sprays::Hex(c.surfaceCrc)+".vtf")){
        d.ready=true;peer.readyTextures.insert(c.surfaceCrc);
    }
    if(!d.ready)return 0;
    // Remove the recipient's older native spray before exposing the clipped
    // model. This remains one spray, and the original temp-entity audience is
    // retained rather than broadcasting a previously hidden placement.
    if(c.surfaceCleared.insert(peer.serial).second)ClearOwnerDecal(client,p,false,recipient);
    return 1;
}
cell_t ClearPrevious(IPluginContext *context,const cell_t *params){
    if(!Claim(context))return 0;
    int client=params[1];
    if(Current(client))ClearOwnerDecal(client,clients[client].placement);
    return 0;
}
cell_t LastError(IPluginContext *context,const cell_t *params){
    int client=params[1];if(!Current(client))return 0;
    context->StringToLocalUTF8(params[2],params[3],clients[client].error.c_str(),nullptr);return 1;
}
cell_t Preview(IPluginContext *context,const cell_t *params){
    int client=params[1];if(!Current(client))return -1;auto &c=clients[client];
    context->StringToLocalUTF8(params[2],params[3],c.previewMaterial.c_str(),nullptr);
    return c.previewFailed?-1:c.previewReady?1:Now()>c.previewDeadline?-1:0;
}
cell_t CanReceive(IPluginContext *,const cell_t *params){
    int client=params[1],recipient=params[2];
    return Current(client)&&Current(recipient)
        &&clients[client].placement.audience.Contains(recipient,clients[recipient].serial)&&Visible(client,recipient);
}
cell_t DecalFile(IPluginContext *context,const cell_t *params){
    context->StringToLocalUTF8(params[2],params[3],"",nullptr);
    int client=params[1];if(!Current(client))return 0;
    auto &c=clients[client];uint32_t crc=params[4]?c.originalCrc:c.activeCrc;
    if(!crc){player_info_t info{};bool swapped;if(ReadInfo(client,info,swapped))crc=swapped?Swap(info.customFiles[0]):info.customFiles[0];}
    if(!crc)return 0;
    if(params[4]){auto original=c.originalCrcs.find(crc);if(original!=c.originalCrcs.end())crc=original->second;}
    context->StringToLocalUTF8(params[2],params[3],sprays::Hex(crc).c_str(),nullptr);return 1;
}
cell_t ClearViewer(IPluginContext *,const cell_t *params){
    int client=params[1],recipient=params[2];
    if(!Current(client)||!Current(recipient)||!clients[client].placement.table)return 0;
    // Moderation clears must not become the sprayer's new placement for every
    // other viewer. Mesh visibility is checked through the moderation forward.
    ClearOwnerDecal(client,clients[client].placement,false,recipient);return 1;
}
cell_t EnablePreview(IPluginContext *context,const cell_t *params){
    if(!Claim(context))return 0;
    int client=params[1];if(Current(client))clients[client].previewEnabled=params[2]!=0;return 0;
}
cell_t Replay(IPluginContext *context,const cell_t *params){
    if(!Claim(context))return 0;
    int client=params[1];if(!Current(client))return 0;auto p=clients[client].placement;
    if(!p.table||p.data.empty())return 0;
    if(p.entity>0&&gamehelpers->ReferenceToIndex(p.entityRef)!=p.entity)return 0;
    Recipients filter;filter.reliable=true;
    for(auto member:p.audience.members){int recipient=member.first;
        if(Current(recipient)&&clients[recipient].serial==member.second&&Visible(client,recipient))filter.members.push_back(recipient);
    }
    if(filter.members.empty())return 0;
    replaying=true;serverEngine->PlaybackTempEntity(filter,0.0f,p.data.data(),p.table,p.classId);replaying=false;return 1;
}
cell_t BarrierAck(IPluginContext *context,const cell_t *params){
    if(owner!=context)return context->ThrowNativeError("Not the controlling plugin");
    int peer=params[1],token=params[2];if(!Current(peer))return 0;
    for(auto &c:clients)if(c.token==token&&(c.phase==AwaitClear||c.phase==Distributing)&&c.barrier[peer]==clients[peer].serial){
        if(params[3])c.barrier[peer]=0;
        return 1;
    }
    return 0;
}
sp_nativeinfo_t natives[]={{"ISprays_BarrierAck",BarrierAck},{"ISprays_ApiVersion",Api},{"ISprays_Request",Request},{"ISprays_Status",Status},{"ISprays_Cancel",Cancel},{"ISprays_Inspect",Inspect},
    {"ISprays_Watch",Watch},{"ISprays_Preview",Preview},{"ISprays_EnablePreview",EnablePreview},{"ISprays_Replay",Replay},
    {"ISprays_SetSurface",Surface},{"ISprays_SurfaceModel",SurfaceModel},{"ISprays_ClearPrevious",ClearPrevious},{"ISprays_LastError",LastError},{"ISprays_CanReceive",CanReceive},{"ISprays_GetDecalFile",DecalFile},{"ISprays_ClearViewer",ClearViewer},{nullptr,nullptr}};
}

bool InstantSprays::SDK_OnMetamodLoad(ISmmAPI *ismm,char *error,size_t maxlen,bool){
    GET_V_IFACE_CURRENT(GetEngineFactory,serverEngine,IVEngineServer,INTERFACEVERSION_VENGINESERVER);
    GET_V_IFACE_CURRENT(GetEngineFactory,engineTrace,IEngineTrace,INTERFACEVERSION_ENGINETRACE_SERVER);
    GET_V_IFACE_CURRENT(GetEngineFactory,modelInfo,IVModelInfo,VMODELINFO_SERVER_INTERFACE_VERSION);
    GET_V_IFACE_CURRENT(GetServerFactory,serverDll,IServerGameDLL,INTERFACEVERSION_SERVERGAMEDLL);
    GET_V_IFACE_CURRENT(GetEngineFactory,tables,INetworkStringTableContainer,INTERFACENAME_NETWORKSTRINGTABLESERVER);
    GET_V_IFACE_CURRENT(GetFileSystemFactory,files,IFileSystem,FILESYSTEM_INTERFACE_VERSION);
    baseFiles=static_cast<IBaseFileSystem *>(files);globals=ismm->GetCGlobals();return true;
}
bool InstantSprays::SDK_OnLoad(char *error,size_t length,bool){
    incomingRoot=GamePath("addons/sourcemod/data/instant_sprays/incoming");std::error_code ec;
    std::filesystem::create_directories(incomingRoot,ec);
    if(ec){snprintf(error,length,"Cannot create the isolated spray-upload directory");return false;}
    char configError[256];void *queueAddress=nullptr;
    if(gameconfs->LoadGameConfigFile("instant_sprays.games",&queueConfig,configError,sizeof(configError))
       &&queueConfig->GetMemSig("CNetChan::IsFileInWaitingList",&queueAddress)&&queueAddress)
        std::memcpy(&fileWaiting,&queueAddress,sizeof(queueAddress));
    smutils->LogMessage(myself,"Transfer completion tracking: %s",fileWaiting?"per file":"whole-channel fallback");
    const spray_files::Targets fsTargets{
        SH_GET_ORIG_VFNPTR_ENTRY(baseFiles,&IBaseFileSystem::FileExists),
        SH_GET_ORIG_VFNPTR_ENTRY(baseFiles,&IBaseFileSystem::Open),
        SH_GET_ORIG_VFNPTR_ENTRY(baseFiles,&IBaseFileSystem::Write),
        SH_GET_ORIG_VFNPTR_ENTRY(baseFiles,&IBaseFileSystem::Close),
        SH_GET_ORIG_VFNPTR_ENTRY(files,&IFileSystem::CreateDirHierarchy)};
    if(!spray_files::Install(fsTargets,{UploadExists,UploadOpen,UploadOpened,UploadWrite,UploadClosed,UploadDirectory},error,length)){
        if(queueConfig)gameconfs->CloseGameConfigFile(queueConfig);
        queueConfig=nullptr;fileWaiting=nullptr;return false;
    }
    sequence=static_cast<uint64_t>(Now()*1000000);
    globalHooks={
        SH_ADD_HOOK(IServerGameDLL,LevelShutdown,serverDll,SH_MEMBER(&hooks,&Hooks::Shutdown),false),
        SH_ADD_HOOK(IServerGameDLL,ServerActivate,serverDll,SH_MEMBER(&hooks,&Hooks::Activate),true),
        SH_ADD_HOOK(IVEngineServer,PlaybackTempEntity,serverEngine,SH_MEMBER(&hooks,&Hooks::SprayBefore),false),
        SH_ADD_HOOK(IVEngineServer,PlaybackTempEntity,serverEngine,SH_MEMBER(&hooks,&Hooks::SprayAfter),true)};
    for(int hook:globalHooks)if(!hook){for(int h:globalHooks)if(h)SH_REMOVE_HOOK_ID(h);globalHooks.clear();spray_files::Uninstall();if(queueConfig)gameconfs->CloseGameConfigFile(queueConfig);queueConfig=nullptr;fileWaiting=nullptr;snprintf(error,length,"Cannot install spray transport hooks");return false;}
    sharesys->AddNatives(myself,natives);sharesys->RegisterLibrary(myself,"instant_sprays");
    barrierForward=forwards->CreateForward("ISprays_OnClearBarrier",ET_Ignore,2,nullptr,Param_Cell,Param_Cell);
    placedForward=forwards->CreateForward("ISprays_OnSprayPlaced",ET_Ignore,5,nullptr,Param_Cell,Param_Array,Param_Cell,Param_Cell,Param_Cell);
    guardForward=forwards->CreateForward("ISprays_ShouldGuardSurface",ET_Event,3,nullptr,Param_Cell,Param_Array,Param_Cell);
    visibleForward=forwards->CreateForward("ISprays_CanSeeSpray",ET_Hook,2,nullptr,Param_Cell,Param_Cell);
    changedForward=forwards->CreateForward("ISprays_OnSprayChanged",ET_Ignore,1,nullptr,Param_Cell);
    playerhelpers->AddClientListener(this);plsys->AddPluginsListener(this);smutils->AddGameFrameHook(Frame);
    if(smutils->IsMapRunning()){BindTable();for(int i=1;i<=globals->maxClients;++i)BindClient(i);}return true;
}
void InstantSprays::SDK_OnUnload(){if(barrierForward)forwards->ReleaseForward(barrierForward);barrierForward=nullptr;spray_files::Uninstall();if(queueConfig)gameconfs->CloseGameConfigFile(queueConfig);queueConfig=nullptr;fileWaiting=nullptr;smutils->RemoveGameFrameHook(Frame);playerhelpers->RemoveClientListener(this);plsys->RemovePluginsListener(this);StopMap();for(int h:globalHooks)if(h)SH_REMOVE_HOOK_ID(h);globalHooks.clear();if(placedForward)forwards->ReleaseForward(placedForward);if(guardForward)forwards->ReleaseForward(guardForward);if(visibleForward)forwards->ReleaseForward(visibleForward);if(changedForward)forwards->ReleaseForward(changedForward);placedForward=nullptr;guardForward=nullptr;visibleForward=nullptr;changedForward=nullptr;owner=nullptr;}
void InstantSprays::OnClientPutInServer(int client){BindClient(client);}
void InstantSprays::OnClientDisconnecting(int client){if(client>0&&client<Slots)ClearClient(client);}
void InstantSprays::OnPluginUnloaded(IPlugin *plugin){if(plugin->GetBaseContext()==owner){for(auto &c:clients){RemoveIncoming(c.incoming);c.incoming.clear();c.phase=Idle;c.activeCrc=0;c.originalCrc=0;c.previewEnabled=false;c.placementDirty=false;c.placement={};c.downloads={};}owner=nullptr;}}
