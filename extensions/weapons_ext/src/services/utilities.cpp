// SPDX-License-Identifier: GPL-3.0-or-later
// Native port of nosoop's TF2 Utils 1.4.0 (see THIRD_PARTY.md).
#include "engine.h"
#include "shared_client_cache.h"
#include <array>
#include <algorithm>
#include <bitset>
#include <cstdlib>
#include <vector>

namespace weapons_services { namespace {
IGameConfig *config;
void (*speed)(void *);
int (*maxAmmo)(void *,int,int);
int (*buffedHealth)(void *,bool,bool);
CBaseEntity *(*loadout)(void *,int,bool);
void (*burn)(void *,CBaseEntity *,CBaseEntity *,float);
void (*bleed)(void *,CBaseEntity *,CBaseEntity *,float,int,bool,int);
bool (*immunePush)(void *);
bool (*respawnRoom)(CBaseEntity *,const Vector &,bool);
void (*startLag)(void *,CBaseEntity *,void *);
void (*finishLag)(void *,CBaseEntity *);
void *lagManager;
const char **conditionNames;
int conditionCount;
int shared,wearables,objects,healers,healerCount,currentCommand,respawnOverride,lastDamage;
int conditionData,conditionStride,conditionDuration,conditionProvider;
int burnDuration,bleedList,bleedStride,bleedAttacker,bleedWeapon,bleedNext,bleedEnd,bleedDamage,bleedPermanent,bleedCustom,outer,alwaysValid;
int takeHealthSlot,maxHealthSlot,switchSlot,shootSlot,isWeaponSlot,isWearableSlot,equipSlot,slotSlot,idSlot,clipSlot,canAttackSlot;
std::array<int,5> conditionBits;
int alternateBits,lifeState;
std::vector<int> dot;
std::bitset<129> queuedSpeed,queuedRespawn;
std::array<cell_t,129> pendingRefs;
std::array<float,129> pendingRespawn;
bool frameHook;
SendOffsets offsets;
weapons_ext::SharedClientCache<128> sharedClients;
bool InCondition(CBaseEntity *entity,int condition) {
    if (condition<0 || condition>=conditionCount || condition/32>=5) return false;
    uint32_t mask=1u<<(condition%32);
    int offset=conditionBits[condition/32];
    return (offset>=0 && (Field<uint32_t>(entity,offset)&mask))
        || (condition<32 && alternateBits>=0 && (Field<uint32_t>(entity,alternateBits)&mask));
}
void *Shared(CBaseEntity *entity) { return reinterpret_cast<uint8_t *>(entity)+shared; }
void *Cond(IPluginContext *ctx,CBaseEntity *entity,int condition,bool mustExist) {
    if (condition<0 || condition>=conditionCount) { ctx->ThrowNativeError("Invalid condition %d",condition); return nullptr; }
    if (!InCondition(entity,condition)) {
        if(mustExist) ctx->ThrowNativeError("Client is not in condition %d",condition);
        return nullptr;
    }
    auto *memory=Field<uint8_t *>(Shared(entity),conditionData);
    if(!memory) { ctx->ThrowNativeError("Missing condition data"); return nullptr; }
    return memory+condition*conditionStride;
}
int Count(void *base,int offset) { return Field<int>(base,offset+12); }
void *Element(IPluginContext *ctx,void *base,int offset,int index,int stride) {
    int count=Count(base,offset);
    if(index<0 || index>=count || count>65536) { ctx->ThrowNativeError("Invalid vector index %d (count %d)",index,count); return nullptr; }
    auto *data=Field<uint8_t *>(base,offset);
    if(!data) { ctx->ThrowNativeError("Missing vector storage"); return nullptr; }
    return data+index*stride;
}
CBaseEntity *Weapon(IPluginContext *ctx,cell_t ref,bool nullable=false) {
    auto *entity=Entity(ctx,ref,false,nullable);
    if(entity && !Virtual<bool>(entity,isWeaponSlot)) { ctx->ThrowNativeError("Entity is not a weapon"); return nullptr; }
    return entity;
}
CBaseEntity *Wearable(IPluginContext *ctx,cell_t ref) {
    auto *entity=Entity(ctx,ref);
    if(entity && !Virtual<bool>(entity,isWearableSlot)) { ctx->ThrowNativeError("Entity is not a wearable"); return nullptr; }
    return entity;
}
void Frame(bool simulating) {
    if(!simulating || (queuedSpeed.none() && queuedRespawn.none())) return;
    for(int i=1;i<=playerhelpers->GetMaxClients() && i<129;++i) {
        if(!queuedSpeed[i] && !queuedRespawn[i]) continue;
        auto *entity=gamehelpers->ReferenceToEntity(pendingRefs[i]);
        if(!entity || Index(entity)!=i) { queuedSpeed.reset(i); queuedRespawn.reset(i); continue; }
        if(queuedSpeed[i]) { queuedSpeed.reset(i); speed(entity); }
        if(queuedRespawn[i] && Field<uint8_t>(entity,lifeState)!=0) {
            queuedRespawn.reset(i); Field<float>(entity,respawnOverride)=pendingRespawn[i];
        }
    }
}
void Queue(CBaseEntity *entity) {
    pendingRefs[Index(entity)]=gamehelpers->EntityToReference(entity);
    if(!frameHook) { g_pSM->AddGameFrameHook(Frame); frameHook=true; }
}
cell_t UpdateSpeed(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); if(!entity) return 0;
    int index=Index(entity);
    if(p[2]) { queuedSpeed.reset(index); speed(entity); }
    else { Queue(entity); queuedSpeed.set(index); }
    return 0;
}
cell_t TakeHealth(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); return entity ? Virtual<int,float,int>(entity,takeHealthSlot,sp_ctof(p[2]),p[3]) : 0;
}
cell_t MaxAmmo(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); if(!entity) return 0;
    if(p[2]<0 || p[2]>31) return ctx->ThrowNativeError("Invalid ammo index");
    return maxAmmo(entity,p[2],p[3]>=1 && p[3]<=9 ? p[3] : -1);
}
cell_t MaxHealth(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1]); return entity ? Virtual<int>(entity,maxHealthSlot) : 0;
}
cell_t MaxBoost(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); return entity ? buffedHealth(Shared(entity),p[2]!=0,p[3]!=0) : 0;
}
cell_t Switch(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); auto *weapon=Weapon(ctx,p[2],true);
    if(!entity || (!weapon && p[2]!=-1)) return 0;
    return Virtual<bool,CBaseEntity *,int>(entity,switchSlot,weapon,0);
}
cell_t Equip(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); auto *wearable=Wearable(ctx,p[2]);
    if(!entity || !wearable) return 0;
    int outerOffset=offsets.Get(wearable,"m_hOuter");
    if(outerOffset<0 || HandleIndex(Field<uint32_t>(wearable,outerOffset))!=Index(wearable))
        return ctx->ThrowNativeError("Wearable must be spawned before equipping");
    Virtual<void,CBaseEntity *>(entity,equipSlot,wearable);
    int ownerOffset=offsets.Get(wearable,"m_hOwnerEntity");
    if(ownerOffset<0 || HandleIndex(Field<uint32_t>(wearable,ownerOffset))!=Index(entity))
        return ctx->ThrowNativeError("Wearable equip failed; check gamedata");
    return 0;
}
cell_t AlwaysValid(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Wearable(ctx,p[1]); if(entity) Field<bool>(entity,alwaysValid)=p[2]!=0; return 0;
}
template<bool Wearables> cell_t VectorCount(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); return entity ? Count(entity,Wearables ? wearables : objects) : 0;
}
template<bool Wearables> cell_t VectorEntity(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); if(!entity) return -1;
    void *element=Element(ctx,entity,Wearables ? wearables : objects,p[2],4);
    return element ? HandleIndex(Field<uint32_t>(element,0)) : -1;
}
cell_t Healer(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); if(!entity) return -1;
    int count=Field<int>(entity,healerCount);
    if(p[2]<0 || p[2]>=count) return ctx->ThrowNativeError("Invalid healer index");
    auto *data=Field<uint8_t *>(entity,healers);
    return data ? HandleIndex(Field<uint32_t>(data,p[2]*36)) : -1;
}
cell_t LastDamage(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); return entity ? sp_ftoc(Field<float>(entity,lastDamage)) : 0;
}
template<bool WearableType> cell_t IsType(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1]); return entity ? Virtual<bool>(entity,WearableType ? isWearableSlot : isWeaponSlot) : 0;
}
enum WeaponOperation { Slot,ID,Clip,CanAttack };
template<WeaponOperation Op> cell_t WeaponValue(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Weapon(ctx,p[1]); if(!entity) return 0;
    if(Op==CanAttack) return Virtual<bool>(entity,canAttackSlot);
    return Virtual<int>(entity,Op==Slot ? slotSlot : Op==ID ? idSlot : clipSlot);
}
cell_t Loadout(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); return entity ? Index(loadout(entity,p[2],p[3]!=0)) : -1;
}
cell_t ShootPosition(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); if(!entity) return 0;
    Vector value=Virtual<Vector>(entity,shootSlot);
    cell_t *dest=nullptr; if(ctx->LocalToPhysAddr(p[2],&dest)) return 0;
    for(int i=0;i<3;++i) dest[i]=sp_ftoc(value[i]); return 0;
}
cell_t RespawnRoom(IPluginContext *ctx,const cell_t *p) {
    cell_t *source=nullptr; if(ctx->LocalToPhysAddr(p[1],&source)) return 0;
    if(source==ctx->GetNullRef(SP_NULL_VECTOR)) return ctx->ThrowNativeError("NULL_VECTOR is not a respawn-room origin");
    Vector origin(sp_ctof(source[0]),sp_ctof(source[1]),sp_ctof(source[2]));
    auto *entity=Entity(ctx,p[2],false,true); if(!entity && p[2]!=-1) return 0;
    return respawnRoom(entity,origin,p[3]!=0);
}
cell_t ImmunePush(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); return entity ? immunePush(Shared(entity)) : 0;
}
cell_t ConditionCount(IPluginContext *,const cell_t *) { return conditionCount; }
cell_t ConditionName(IPluginContext *ctx,const cell_t *p) {
    if(p[1]<0 || p[1]>=conditionCount) return ctx->ThrowNativeError("Invalid condition");
    if(p[3]<=0) return 0; size_t written=0;
    ctx->StringToLocalUTF8(p[2],p[3],conditionNames[p[1]] ? conditionNames[p[1]] : "",&written); return written;
}
template<bool Provider,bool Set> cell_t ConditionValue(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); if(!entity) return Provider ? -1 : 0;
    void *data=Cond(ctx,entity,p[2],Set); if(!data) return Provider ? -1 : 0;
    int offset=Provider ? conditionProvider : conditionDuration;
    if(Set) {
        uint32_t value=p[3];
        if(Provider) { auto *provider=Entity(ctx,p[3]); if(!provider) return 0; value=EntityHandle(provider); }
        Field<uint32_t>(data,offset)=value; return 0;
    }
    uint32_t value=Field<uint32_t>(data,offset); return Provider ? HandleIndex(value) : cell_t(value);
}
template<bool Set> cell_t BurnDuration(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); if(!entity || !InCondition(entity,22)) return 0;
    if(Set) { Field<float>(Shared(entity),burnDuration)=sp_ctof(p[2]); return 0; }
    return sp_ftoc(Field<float>(Shared(entity),burnDuration));
}
cell_t Ignite(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); auto *attacker=Entity(ctx,p[2],true,true); auto *weapon=Weapon(ctx,p[4],true);
    if(!entity || (!attacker && p[2]!=-1) || (!weapon && p[4]!=-1)) return 0;
    burn(Shared(entity),attacker,weapon,sp_ctof(p[3])); return 0;
}
cell_t BleedCount(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); return entity ? Count(Shared(entity),bleedList) : 0;
}
enum BleedOperation { Attacker,WeaponRef,Next,Duration,Damage,Custom };
template<BleedOperation Op> cell_t BleedValue(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); if(!entity) return 0;
    void *data=Element(ctx,Shared(entity),bleedList,p[2],bleedStride); if(!data) return 0;
    if(Op==Attacker || Op==WeaponRef) return HandleIndex(Field<uint32_t>(data,Op==Attacker ? bleedAttacker : bleedWeapon));
    if(Op==Damage || Op==Custom) return Field<int>(data,Op==Damage ? bleedDamage : bleedCustom);
    if(Op==Duration && Field<bool>(data,bleedPermanent)) return sp_ftoc(-1.0f);
    return sp_ftoc(Field<float>(data,Op==Next ? bleedNext : bleedEnd)-gpGlobals->curtime);
}
cell_t MakeBleed(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); auto *attacker=Entity(ctx,p[2],true); auto *weapon=Weapon(ctx,p[4],true);
    if(!entity || !attacker || (!weapon && p[4]!=-1)) return -1;
    float duration=sp_ctof(p[3]); bleed(Shared(entity),attacker,weapon,duration,p[5],duration==-1.0f,p[6]);
    int count=Count(Shared(entity),bleedList);
    for(int i=0;i<count;++i) {
        void *data=Element(ctx,Shared(entity),bleedList,i,bleedStride); if(!data) return -1;
        if(HandleIndex(Field<uint32_t>(data,bleedAttacker))==Index(attacker)
            && HandleIndex(Field<uint32_t>(data,bleedWeapon))==Index(weapon)) return i;
    }
    return -1;
}
template<bool Set> cell_t RespawnOverride(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); if(!entity) return 0;
    if(!Set) return sp_ftoc(Field<float>(entity,respawnOverride));
    int index=Index(entity);
    if(Field<uint8_t>(entity,lifeState)!=0) { queuedRespawn.reset(index); Field<float>(entity,respawnOverride)=sp_ctof(p[2]); }
    else if(sp_ctof(p[2])==-1.0f) queuedRespawn.reset(index);
    else { Queue(entity); pendingRespawn[index]=sp_ctof(p[2]); queuedRespawn.set(index); }
    return 0;
}
cell_t DOT(IPluginContext *,const cell_t *p) { return std::find(dot.begin(),dot.end(),p[1])!=dot.end(); }
cell_t FromShared(IPluginContext *ctx,const cell_t *p) {
    int client=sharedClients.Find(reinterpret_cast<void *>(uint32_t(p[1])));
    if(!client) return ctx->ThrowNativeError("Unknown player shared address");
    auto *entity=gamehelpers->ReferenceToEntity(client);
    if(!entity || uint32_t(uintptr_t(Shared(entity)))!=uint32_t(p[1])) return ctx->ThrowNativeError("Stale player shared address");
    return client;
}
template<bool Start> cell_t LagComp(IPluginContext *ctx,const cell_t *p) {
    auto *entity=Entity(ctx,p[1],true); if(!entity) return 0;
    if(Start) {
        void *command=Field<void *>(entity,currentCommand);
        if(!command) return ctx->ThrowNativeError("Lag compensation requires a current user command");
        startLag(lagManager,entity,command);
    }
    else finishLag(lagManager,entity);
    return 0;
}
sp_nativeinfo_t natives[]={
    {"WeaponsUtil_UpdatePlayerSpeed",UpdateSpeed},{"WeaponsUtil_TakeHealth",TakeHealth},
    {"WeaponsUtil_GetPlayerMaxAmmo",MaxAmmo},{"WeaponsUtil_GetEntityMaxHealth",MaxHealth},
    {"WeaponsUtil_GetPlayerMaxHealthBoost",MaxBoost},{"WeaponsUtil_SetPlayerActiveWeapon",Switch},
    {"WeaponsUtil_EquipPlayerWearable",Equip},{"WeaponsUtil_SetWearableAlwaysValid",AlwaysValid},
    {"WeaponsUtil_GetPlayerWearableCount",VectorCount<true>},{"WeaponsUtil_GetPlayerWearable",VectorEntity<true>},
    {"WeaponsUtil_GetPlayerObjectCount",VectorCount<false>},{"WeaponsUtil_GetPlayerObject",VectorEntity<false>},
    {"WeaponsUtil_GetPlayerHealer",Healer},{"WeaponsUtil_GetPlayerLastDamageReceivedTime",LastDamage},
    {"WeaponsUtil_IsEntityWeapon",IsType<false>},{"WeaponsUtil_IsEntityWearable",IsType<true>},
    {"WeaponsUtil_GetWeaponSlot",WeaponValue<Slot>},{"WeaponsUtil_GetWeaponID",WeaponValue<ID>},
    {"WeaponsUtil_GetWeaponMaxClip",WeaponValue<Clip>},{"WeaponsUtil_CanWeaponAttack",WeaponValue<CanAttack>},
    {"WeaponsUtil_GetPlayerLoadoutEntity",Loadout},{"WeaponsUtil_GetPlayerShootPosition",ShootPosition},
    {"WeaponsUtil_IsPointInRespawnRoom",RespawnRoom},{"WeaponsUtil_IsPlayerImmuneToPushback",ImmunePush},
    {"WeaponsUtil_GetConditionCount",ConditionCount},{"WeaponsUtil_GetConditionName",ConditionName},
    {"WeaponsUtil_GetPlayerConditionDuration",ConditionValue<false,false>},{"WeaponsUtil_SetPlayerConditionDuration",ConditionValue<false,true>},
    {"WeaponsUtil_GetPlayerConditionProvider",ConditionValue<true,false>},{"WeaponsUtil_SetPlayerConditionProvider",ConditionValue<true,true>},
    {"WeaponsUtil_GetPlayerBurnDuration",BurnDuration<false>},{"WeaponsUtil_SetPlayerBurnDuration",BurnDuration<true>},
    {"WeaponsUtil_IgnitePlayer",Ignite},{"WeaponsUtil_GetPlayerActiveBleedCount",BleedCount},
    {"WeaponsUtil_GetPlayerBleedAttacker",BleedValue<Attacker>},{"WeaponsUtil_GetPlayerBleedWeapon",BleedValue<WeaponRef>},
    {"WeaponsUtil_GetPlayerBleedNextDamageTick",BleedValue<Next>},{"WeaponsUtil_GetPlayerBleedDuration",BleedValue<Duration>},
    {"WeaponsUtil_GetPlayerBleedDamage",BleedValue<Damage>},{"WeaponsUtil_GetPlayerBleedCustomDamageType",BleedValue<Custom>},
    {"WeaponsUtil_MakePlayerBleed",MakeBleed},{"WeaponsUtil_GetPlayerRespawnTimeOverride",RespawnOverride<false>},
    {"WeaponsUtil_SetPlayerRespawnTimeOverride",RespawnOverride<true>},{"WeaponsUtil_IsCustomDamageTypeDOT",DOT},
    {"WeaponsUtil_GetPlayerFromSharedAddress",FromShared},{"WeaponsUtil_StartLagCompensation",LagComp<true>},
    {"WeaponsUtil_FinishLagCompensation",LagComp<false>},{nullptr,nullptr}
};
class Utilities final : public SDKExtension,public IClientListener {
public:
    bool SDK_OnLoad(char *error,size_t length,bool) override {
        if(!OpenConfig("tf2.utils.nosoop",config,error,length)) return false;
#define BIND(variable,key) variable=Symbol<decltype(variable)>(config,key); if(!variable) { std::snprintf(error,length,"Utilities: missing %s",key); return false; }
        BIND(speed,"CTFPlayer::TeamFortress_SetSpeed()"); BIND(maxAmmo,"CTFPlayer::GetMaxAmmo()");
        BIND(buffedHealth,"CTFPlayerShared::GetMaxBuffedHealth()"); BIND(loadout,"CTFPlayer::GetEntityForLoadoutSlot()");
        BIND(burn,"CTFPlayerShared::Burn()"); BIND(bleed,"CTFPlayerShared::MakeBleed()");
        BIND(immunePush,"CTFPlayerShared::IsImmuneToPushback()"); BIND(respawnRoom,"PointInRespawnRoom()");
        BIND(startLag,"CLagCompensationManager::StartLagCompensation()"); BIND(finishLag,"CLagCompensationManager::FinishLagCompensation()");
#undef BIND
#define SLOT(variable,key) if(!Offset(config,key,variable)) { std::snprintf(error,length,"Utilities: missing %s",key); return false; }
        SLOT(takeHealthSlot,"CBaseEntity::TakeHealth()"); SLOT(maxHealthSlot,"CBaseEntity::GetMaxHealth()");
        SLOT(switchSlot,"CBaseCombatCharacter::Weapon_Switch()"); SLOT(shootSlot,"CBaseCombatCharacter::Weapon_ShootPosition()");
        SLOT(isWeaponSlot,"CBaseEntity::IsBaseCombatWeapon()"); SLOT(isWearableSlot,"CBaseEntity::IsWearable()");
        SLOT(equipSlot,"CTFPlayer::EquipWearable()"); SLOT(slotSlot,"CBaseCombatWeapon::GetSlot()");
        SLOT(idSlot,"CTFWeaponBase::GetWeaponID()"); SLOT(clipSlot,"CTFWeaponBase::GetMaxClip1()"); SLOT(canAttackSlot,"CTFWeaponBase::CanAttack()");
        SLOT(burnDuration,"CTFPlayerShared::m_flBurnDuration"); SLOT(bleedList,"CTFPlayerShared::m_BleedList");
        SLOT(bleedStride,"sizeof(BleedStruct_t)"); SLOT(bleedAttacker,"BleedStruct_t::m_hAttacker"); SLOT(bleedWeapon,"BleedStruct_t::m_hWeapon");
        SLOT(bleedNext,"BleedStruct_t::m_flNextTickTime"); SLOT(bleedEnd,"BleedStruct_t::m_flExpireTime"); SLOT(bleedDamage,"BleedStruct_t::m_nDamage");
        SLOT(bleedPermanent,"BleedStruct_t::m_bPermanent"); SLOT(bleedCustom,"BleedStruct_t::m_nCustomDamageType");
        SLOT(conditionStride,"sizeof(TFCondInfo_t)"); SLOT(conditionDuration,"TFCondInfo_t::m_flDuration"); SLOT(conditionProvider,"TFCondInfo_t::m_hProvider");
        SLOT(outer,"CTFPlayerShared::m_pOuter"); SLOT(alwaysValid,"CEconWearable::m_bAlwaysValid"); SLOT(lastDamage,"CTFPlayer::m_flLastDamageTime");
#undef SLOT
#define SEND(variable,key) variable=SendOffset("CTFPlayer",key); if(variable<0) { std::snprintf(error,length,"Utilities: missing sendprop %s",key); return false; }
        SEND(shared,"m_Shared"); SEND(wearables,"m_hMyWearables"); SEND(healerCount,"m_nNumHealers");
        SEND(lifeState,"m_lifeState"); SEND(alternateBits,"_condition_bits");
        const char *bits[]={"m_nPlayerCond","m_nPlayerCondEx","m_nPlayerCondEx2","m_nPlayerCondEx3","m_nPlayerCondEx4"};
        for(int i=0;i<5;++i) { SEND(conditionBits[i],bits[i]); }
#undef SEND
        conditionData=SendOffset("CTFPlayer","m_ConditionData")-shared;
        if(conditionData<=0 && !Offset(config,"CTFPlayerShared::m_ConditionData",conditionData)) return false;
        healers=healerCount+12;
        const char *addressKeys[]={"offsetof(CTFPlayer::m_aObjects)","offsetof(CTFPlayer::m_pCurrentCommand)","offsetof(CTFPlayer::m_flRespawnTimeOverride)"};
        int *addressOffsets[]={&objects,&currentCommand,&respawnOverride};
        for(int i=0;i<3;++i) {
            void *address=nullptr;
            if(!config->GetAddress(addressKeys[i],&address) || !address || (*addressOffsets[i]=Field<int>(address,0))<=0 || *addressOffsets[i]>=65536) {
                std::snprintf(error,length,"Utilities: invalid instruction-derived %s",addressKeys[i]); return false;
            }
        }
        void *countAddress=nullptr,*namesAddress=nullptr;
        if(!config->GetAddress("&TF_COND_LAST",&countAddress) || !countAddress
            || (conditionCount=Field<int>(countAddress,0))<=0 || conditionCount>160
            || !config->GetAddress("g_aConditionNames",&namesAddress) || !namesAddress
            || !config->GetAddress("g_LagCompensationManager",&lagManager) || !lagManager) {
            std::snprintf(error,length,"Utilities: invalid condition/lag compensation addresses"); return false;
        }
        conditionNames=static_cast<const char **>(namesAddress);
        const char *values=config->GetKeyValue("DOTDamageTypes"); if(!values) return false;
        for(char *end=nullptr;*values;values=end) {
            long value=std::strtol(values,&end,16); if(end==values) break; if(value) dot.push_back(int(value));
        }
        sharesys->AddNatives(myself,natives); weapons_ext::Clients().Add(this);
        for(int i=1;i<=playerhelpers->GetMaxClients();++i) OnClientPutInServer(i);
        return true;
    }
    void OnClientPutInServer(int client) override {
        auto *entity=gamehelpers->ReferenceToEntity(client);
        if(entity) sharedClients.Put(Shared(entity),client);
    }
    void OnClientDisconnecting(int client) override { sharedClients.Remove(client); }
    void OnClientDisconnected(int client) override { if(client<129) { sharedClients.Remove(client); queuedSpeed.reset(client); queuedRespawn.reset(client); } }
    void OnCoreMapEnd() override { queuedSpeed.reset(); queuedRespawn.reset(); }
    void SDK_OnUnload() override {
        weapons_ext::Clients().Remove(this); if(frameHook) { g_pSM->RemoveGameFrameHook(Frame); frameHook=false; }
        queuedSpeed.reset(); queuedRespawn.reset(); dot.clear();
        if(config) { gameconfs->CloseGameConfigFile(config); config=nullptr; }
    }
} module;
}}
SDKExtension &UtilitiesModule() { return weapons_services::module; }
