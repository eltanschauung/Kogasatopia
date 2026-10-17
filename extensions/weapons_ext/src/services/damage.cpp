// SPDX-License-Identifier: GPL-3.0-or-later
// Based on nosoop's SM-TFOnTakeDamage 1.3.3. Native hook owner; no provider plugin.
#include "engine.h"
#include "damage_info.h"
#include <CDetour/detours.h>
#include <igameevents.h>
#include <cstddef>
#include <ISDKTools.h>

// Shared SDKTools dependency already owned by the merged TF2Tools module.
extern SourceMod::ISDKTools *g_pSDKTools;

namespace weapons_services { namespace {
IGameConfig *config;
CDetour *damageDetour,*aliveDetour,*rulesDetour,*buildingDetour;
IForward *damageForward,*postForward,*rulesForward,*buildingForward;
IGameEventManager2 *events;
bool eventHook;
using ModifyRules=bool (*)(void *,DamageInfo &,CBaseEntity *,bool);
ModifyRules modifyRules;
thread_local DamageClassificationContext classificationProbe;
// Scope is restored after nested/reentrant damage; an unrelated hurt event can
// never inherit the most recent hit's mini-crit context as in the old plugin.
thread_local int critContext=-1;
void Forward(IForward *forward,int victim,DamageInfo &info,bool post=false) {
    if(!forward || !forward->GetFunctionCount()) return;
    cell_t attacker=HandleIndex(info.attacker),inflictor=HandleIndex(info.inflictor),weapon=HandleIndex(info.weapon);
    cell_t type=info.type,crit=info.crit;
    float damage=info.damage;
    cell_t force[3],position[3];
    for(int i=0;i<3;++i) { force[i]=sp_ftoc(info.force[i]); position[i]=sp_ftoc(info.position[i]); }
    forward->PushCell(victim);
    if(post) {
        forward->PushCell(attacker); forward->PushCell(inflictor); forward->PushFloat(damage);
        forward->PushCell(type); forward->PushCell(weapon);
    } else {
        forward->PushCellByRef(&attacker); forward->PushCellByRef(&inflictor); forward->PushFloatByRef(&damage);
        forward->PushCellByRef(&type); forward->PushCellByRef(&weapon);
    }
    forward->PushArray(force,3,post ? 0 : SM_PARAM_COPYBACK); forward->PushArray(position,3,post ? 0 : SM_PARAM_COPYBACK);
    forward->PushCell(info.custom);
    if(post) forward->PushCell(crit); else forward->PushCellByRef(&crit);
    cell_t result=Pl_Continue;
    if(forward->Execute(&result)!=SP_ERROR_NONE || post || result<=Pl_Continue) return;
    // Preserve the old API: any non-Continue action commits edits, not cancellation.
    // Changing that to block damage would alter existing consumers' semantics.
    info.attacker=EntityHandle(gamehelpers->ReferenceToEntity(attacker));
    info.inflictor=EntityHandle(gamehelpers->ReferenceToEntity(inflictor));
    info.weapon=EntityHandle(gamehelpers->ReferenceToEntity(weapon));
    info.damage=damage; info.crit=crit;
    info.type=crit==2 ? type|(1<<20) : type&~(1<<20);
    for(int i=0;i<3;++i) { info.force[i]=sp_ctof(force[i]); info.position[i]=sp_ctof(position[i]); }
}
class CritScope {
    int previous_;
public:
    explicit CritScope(int value):previous_(critContext) { critContext=value; }
    ~CritScope() { critContext=previous_; }
};
void ForwardBuilding(int building,DamageInfo &info) {
    if(!buildingForward || !buildingForward->GetFunctionCount()) return;
    float damage=info.damage;
    buildingForward->PushCell(building);
    buildingForward->PushCell(HandleIndex(info.attacker));
    buildingForward->PushCell(HandleIndex(info.inflictor));
    buildingForward->PushFloatByRef(&damage);
    buildingForward->PushCell(info.type);
    buildingForward->PushCell(HandleIndex(info.weapon));
    buildingForward->PushCell(info.custom);
    buildingForward->PushCell(info.crit);
    cell_t result=Pl_Continue;
    if(buildingForward->Execute(&result)==SP_ERROR_NONE && result>Pl_Continue)
        info.damage=damage;
    // Only damage is writable. Do not run Forward()'s player-only crit/flag
    // normalization: observers see effective classification plus original flags.
}
void ClassifyBuilding(CBaseEntity *building,DamageInfo &scratch) {
    void *rules=g_pSDKTools ? g_pSDKTools->GetGameRules() : nullptr;
    if(!rules || !modifyRules) return;
    DamageClassificationScope scope(classificationProbe,scratch,building);
    // Call the game's real entry point. Our detour below still runs the game
    // logic, but does not publish the scratch probe as a player rules event.
    // The boolean result is not a building damage veto; only crit is retained.
    modifyRules(rules,scratch,building,true);
}
}
}
using weapons_services::DamageInfo;
DETOUR_DECL_MEMBER1(Weapons_BuildingDamage,int,const DamageInfo &,input) {
    auto *entity=reinterpret_cast<CBaseEntity *>(this);
    if(!weapons_services::buildingForward || !weapons_services::buildingForward->GetFunctionCount())
        return DETOUR_MEMBER_CALL(Weapons_BuildingDamage)(input);
    return weapons_services::WithBuildingDamage(gamehelpers->GetEntityClassname(entity),input,
        [entity](DamageInfo &scratch) { weapons_services::ClassifyBuilding(entity,scratch); },
        [entity](DamageInfo &info) { weapons_services::ForwardBuilding(weapons_services::Index(entity),info); },
        [this](const DamageInfo &info) { return DETOUR_MEMBER_CALL(Weapons_BuildingDamage)(info); });
}
DETOUR_DECL_MEMBER1(Weapons_PlayerDamage,int,const DamageInfo &,input) {
    // The old provider edited the passed CTakeDamageInfo in place. Preserve it
    // so all downstream SDKHooks and rules callbacks see the same information.
    auto &info=const_cast<DamageInfo &>(input);
    weapons_services::Forward(weapons_services::damageForward,weapons_services::Index(reinterpret_cast<CBaseEntity *>(this)),info);
    int result=DETOUR_MEMBER_CALL(Weapons_PlayerDamage)(input);
    weapons_services::Forward(weapons_services::postForward,weapons_services::Index(reinterpret_cast<CBaseEntity *>(this)),info,true);
    return result;
}
DETOUR_DECL_MEMBER1(Weapons_PlayerDamageAlive,int,const DamageInfo &,info) {
    weapons_services::CritScope scope(info.crit);
    return DETOUR_MEMBER_CALL(Weapons_PlayerDamageAlive)(info);
}
DETOUR_DECL_MEMBER3(Weapons_ModifyDamageRules,bool,DamageInfo &,info,CBaseEntity *,victim,bool,allowDamage) {
    bool result=DETOUR_MEMBER_CALL(Weapons_ModifyDamageRules)(info,victim,allowDamage);
    if(result && !weapons_services::classificationProbe.Matches(info,victim))
        weapons_services::Forward(weapons_services::rulesForward,weapons_services::Index(victim),info);
    return result;
}
SH_DECL_HOOK2(IGameEventManager2,FireEvent,SH_NOATTRIB,0,bool,IGameEvent *,bool);
namespace weapons_services { namespace {
class Damage final : public SDKExtension {
    bool FireEvent(IGameEvent *event,bool) {
        if(event && critContext==1 && !std::strcmp(event->GetName(),"player_hurt") && event->GetInt("bonuseffect")==4) {
            event->SetInt("minicrit",1); event->SetInt("bonuseffect",1);
        }
        RETURN_META_VALUE(MRES_IGNORED,true);
    }
public:
    bool SDK_OnMetamodLoad(ISmmAPI *api,char *,size_t,bool) override {
        events=static_cast<IGameEventManager2 *>(api->GetEngineFactory()(INTERFACEVERSION_GAMEEVENTSMANAGER2,nullptr));
        return events!=nullptr;
    }
    bool SDK_OnLoad(char *error,size_t length,bool) override {
        if(!OpenConfig(WEAPONS_GAMECONFIG_NAME,config,error,length)) return false;
        modifyRules=Symbol<ModifyRules>(config,"CTFGameRules::ApplyOnDamageModifyRules()");
        if(!modifyRules) { std::snprintf(error,length,"Weapons building crit classification binding failed"); return false; }
        damageForward=forwards->CreateForward("Weapons_OnTakeDamage",ET_Event,10,nullptr,Param_Cell,Param_CellByRef,Param_CellByRef,Param_FloatByRef,Param_CellByRef,Param_CellByRef,Param_Array,Param_Array,Param_Cell,Param_CellByRef);
        postForward=forwards->CreateForward("Weapons_OnTakeDamagePost",ET_Ignore,10,nullptr,Param_Cell,Param_Cell,Param_Cell,Param_Float,Param_Cell,Param_Cell,Param_Array,Param_Array,Param_Cell,Param_Cell);
        rulesForward=forwards->CreateForward("Weapons_OnTakeDamageModifyRules",ET_Event,10,nullptr,Param_Cell,Param_CellByRef,Param_CellByRef,Param_FloatByRef,Param_CellByRef,Param_CellByRef,Param_Array,Param_Array,Param_Cell,Param_CellByRef);
        buildingForward=forwards->CreateForward("Weapons_OnBuildingTakeDamage",ET_Event,8,nullptr,Param_Cell,Param_Cell,Param_Cell,Param_FloatByRef,Param_Cell,Param_Cell,Param_Cell,Param_Cell);
        CDetourManager::Init(g_pSM->GetScriptingEngine(),config);
        damageDetour=DETOUR_CREATE_MEMBER(Weapons_PlayerDamage,"CTFPlayer::OnTakeDamage()");
        aliveDetour=DETOUR_CREATE_MEMBER(Weapons_PlayerDamageAlive,"CTFPlayer::OnTakeDamage_Alive()");
        rulesDetour=DETOUR_CREATE_MEMBER(Weapons_ModifyDamageRules,"CTFGameRules::ApplyOnDamageModifyRules()");
        buildingDetour=DETOUR_CREATE_MEMBER(Weapons_BuildingDamage,"CBaseObject::OnTakeDamage()");
        if(!damageDetour || !aliveDetour || !rulesDetour || !buildingDetour) { std::snprintf(error,length,"Weapons damage detour creation failed"); return false; }
        damageDetour->EnableDetour(); aliveDetour->EnableDetour(); rulesDetour->EnableDetour();
        buildingDetour->EnableDetour();
        SH_ADD_HOOK(IGameEventManager2,FireEvent,events,SH_MEMBER(this,&Damage::FireEvent),false); eventHook=true;
        return true;
    }
    void SDK_OnUnload() override {
        if(eventHook) { SH_REMOVE_HOOK(IGameEventManager2,FireEvent,events,SH_MEMBER(this,&Damage::FireEvent),false); eventHook=false; }
        for(CDetour **hook:{&buildingDetour,&rulesDetour,&aliveDetour,&damageDetour}) if(*hook) { (*hook)->Destroy(); *hook=nullptr; }
        for(IForward **forward:{&buildingForward,&rulesForward,&postForward,&damageForward}) if(*forward) { forwards->ReleaseForward(*forward); *forward=nullptr; }
        if(config) { gameconfs->CloseGameConfigFile(config); config=nullptr; }
        critContext=-1;
        classificationProbe={};
        modifyRules=nullptr;
    }
} module;
}}
SDKExtension &DamageModule() { return weapons_services::module; }
