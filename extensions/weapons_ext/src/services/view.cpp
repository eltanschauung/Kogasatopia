// SPDX-License-Identifier: GPL-3.0-or-later
// FOV policy inspired by AndrewBetson's TF-FOV; native engine integration.
// Projectile centering math: rtldg & pufftwitt (2020, permissive notice in THIRD_PARTY.md).
#include "attributes.h"
#include <CDetour/detours.h>
#include <mathlib/mathlib.h>
#include <array>
#include <algorithm>

namespace weapons_services { namespace {
IGameConfig *config;
CDetour *fovDetour,*defaultDetour,*shootDetour;
bool (*setFOV)(void *,CBaseEntity *,int,float,int);
std::array<int,129> preferred;
std::array<bool,129> centered,customZoom;
int minimum=20,maximum=160;
int fovOffset,defaultOffset,activeOffset,eyeOffset,condOffset,alternateOffset;
int flipSlot,slotSlot;
SendOffsets offsets;
bool Zoomed(CBaseEntity *player,int client) {
    return customZoom[client] || (Field<uint32_t>(player,condOffset)&2u) || (Field<uint32_t>(player,alternateOffset)&2u);
}
void ApplyFOV(CBaseEntity *player,int client) {
    if(preferred[client]<0 || Zoomed(player,client)) return;
    int value=std::max(minimum,std::min(maximum,preferred[client]));
    Field<int>(player,fovOffset)=value; Field<int>(player,defaultOffset)=value;
}
void ClearZoomOwner(CBaseEntity *player) {
    int offset=DataOffset(player,"m_hZoomOwner");
    if(offset>=0) Field<uint32_t>(player,offset)=0xffffffffu;
}
void ApplyCenterWeapon(CBaseEntity *weapon,int client) {
    const char *name=gamehelpers->GetEntityClassname(weapon);
    if(!name || std::strncmp(name,"tf_weapon_",10)) return;
    int slot=Virtual<int>(weapon,slotSlot); if(slot<0 || slot>2) return;
    int definition=offsets.Get(weapon,"m_iItemDefinitionIndex");
    bool original=definition>=0 && Field<uint16_t>(weapon,definition)==513;
    SetAttribute(weapon,289,centered[client] || original ? 1.0f : 0.0f);
}
void ApplyCenter(CBaseEntity *player,int client) {
    void *weapons=offsets.Member(player,"m_hMyWeapons"); if(!weapons) return;
    for(int i=0;i<48;++i) {
        int index=HandleIndex(Field<uint32_t>(weapons,i*4));
        auto *weapon=gamehelpers->ReferenceToEntity(index);
        if(!weapon) continue;
        ApplyCenterWeapon(weapon,client);
    }
}
cell_t Preference(IPluginContext *ctx,const cell_t *p) {
    auto *player=Entity(ctx,p[1],true); if(!player) return 0;
    int client=Index(player); preferred[client]=p[2]<0 ? -1 : std::max(minimum,std::min(maximum,p[2]));
    ApplyFOV(player,client); return 0;
}
cell_t Limits(IPluginContext *ctx,const cell_t *p) {
    if(p[1]<10 || p[2]>999 || p[1]>=p[2]) return ctx->ThrowNativeError("Invalid FOV limits");
    minimum=p[1]; maximum=p[2];
    for(int i=1;i<=playerhelpers->GetMaxClients();++i) {
        auto *player=gamehelpers->ReferenceToEntity(i);
        if(player && preferred[i]>=0) ApplyFOV(player,i);
    }
    return 0;
}
cell_t Center(IPluginContext *ctx,const cell_t *p) {
    auto *player=Entity(ctx,p[1],true); if(!player) return 0;
    int client=Index(player); centered[client]=p[2]!=0; ApplyCenter(player,client); return 0;
}
cell_t Inventory(IPluginContext *ctx,const cell_t *p) {
    auto *player=Entity(ctx,p[1],true); if(player) ApplyCenter(player,Index(player)); return 0;
}
cell_t ReconcileWeapon(IPluginContext *ctx,const cell_t *p) {
    auto *player=Entity(ctx,p[1],true); auto *weapon=Entity(ctx,p[2]);
    if(player && weapon) ApplyCenterWeapon(weapon,Index(player)); return 0;
}
cell_t Zoom(IPluginContext *ctx,const cell_t *p) {
    auto *player=Entity(ctx,p[1],true); if(!player) return 0;
    int client=Index(player); bool previous=customZoom[client]; customZoom[client]=p[2]>0;
    if(!setFOV(player,player,p[2],sp_ctof(p[3]),0)) { customZoom[client]=previous; return 0; }
    return 1;
}
cell_t Reset(IPluginContext *,const cell_t *) {
    preferred.fill(-1); centered.fill(false); customZoom.fill(false); return 0;
}
sp_nativeinfo_t natives[]={
    {"WeaponsView_SetPreference",Preference},{"WeaponsView_SetLimits",Limits},
    {"WeaponsView_SetCentered",Center},{"WeaponsView_ReconcileInventory",Inventory},
    {"WeaponsView_ReconcileWeapon",ReconcileWeapon},
    {"WeaponsView_SetZoom",Zoom},{"WeaponsView_Reset",Reset},{nullptr,nullptr}
};
}}
DETOUR_DECL_MEMBER4(Weapons_SetFOV,bool,CBaseEntity *,requester,int,fov,float,rate,int,start) {
    auto *player=reinterpret_cast<CBaseEntity *>(this);
    int client=weapons_services::Index(player);
    if(client<1 || client>=129 || weapons_services::preferred[client]<0)
        return DETOUR_MEMBER_CALL(Weapons_SetFOV)(requester,fov,rate,start);
    bool reset=fov==0;
    if(reset) fov=std::max(weapons_services::minimum,std::min(weapons_services::maximum,weapons_services::preferred[client]));
    bool success=DETOUR_MEMBER_CALL(Weapons_SetFOV)(requester,fov,rate,start);
    if(success && reset) weapons_services::ClearZoomOwner(player);
    else if(success && rate<=0.0f) weapons_services::ApplyFOV(player,client);
    return success;
}
DETOUR_DECL_MEMBER1(Weapons_SetDefaultFOV,void,int,fov) {
    DETOUR_MEMBER_CALL(Weapons_SetDefaultFOV)(fov);
    int client=weapons_services::Index(reinterpret_cast<CBaseEntity *>(this));
    if(client>0 && client<129) weapons_services::ApplyFOV(reinterpret_cast<CBaseEntity *>(this),client);
}
DETOUR_DECL_MEMBER0(Weapons_ShootPosition,Vector) {
    Vector result=DETOUR_MEMBER_CALL(Weapons_ShootPosition)();
    auto *player=reinterpret_cast<CBaseEntity *>(this);
    int client=weapons_services::Index(player);
    if(client<1 || client>=129 || !weapons_services::centered[client]) return result;
    auto *weapon=gamehelpers->ReferenceToEntity(weapons_services::HandleIndex(weapons_services::Field<uint32_t>(player,weapons_services::activeOffset)));
    if(!weapon) return result;
    const char *name=gamehelpers->GetEntityClassname(weapon);
    if(!name || (std::strcmp(name,"tf_weapon_grenadelauncher") && std::strcmp(name,"tf_weapon_pipebomblauncher"))) return result;
    QAngle angles(weapons_services::Field<float>(player,weapons_services::eyeOffset),weapons_services::Field<float>(player,weapons_services::eyeOffset+4),0.0f);
    Vector right; AngleVectors(angles,nullptr,&right,nullptr);
    bool flipped=weapons_services::Virtual<bool>(weapon,weapons_services::flipSlot);
    return result-right*(flipped ? -8.0f : 8.0f);
}
namespace weapons_services { namespace {
class View final : public SDKExtension,public IClientListener {
public:
    bool SDK_OnLoad(char *error,size_t length,bool) override {
        preferred.fill(-1);
        if(!OpenConfig("weapons.services",config,error,length)) return false;
        setFOV=Symbol<decltype(setFOV)>(config,"CBasePlayer::SetFOV");
        const char *props[]={"m_iFOV","m_iDefaultFOV","m_hActiveWeapon","m_angEyeAngles[0]","m_nPlayerCond","_condition_bits"};
        int *values[]={&fovOffset,&defaultOffset,&activeOffset,&eyeOffset,&condOffset,&alternateOffset};
        for(int i=0;i<6;++i) if((*values[i]=SendOffset("CTFPlayer",props[i]))<0) { std::snprintf(error,length,"View: missing %s",props[i]); return false; }
        if(!setFOV || !Offset(config,"IsViewModelFlipped",flipSlot) || !Offset(config,"GetSlot",slotSlot)) { std::snprintf(error,length,"View: missing engine calls"); return false; }
        CDetourManager::Init(g_pSM->GetScriptingEngine(),config);
        fovDetour=DETOUR_CREATE_MEMBER(Weapons_SetFOV,"CBasePlayer::SetFOV");
        defaultDetour=DETOUR_CREATE_MEMBER(Weapons_SetDefaultFOV,"CBasePlayer::SetDefaultFOV");
        shootDetour=DETOUR_CREATE_MEMBER(Weapons_ShootPosition,"CBasePlayer::Weapon_ShootPosition");
        if(!fovDetour || !defaultDetour || !shootDetour) { std::snprintf(error,length,"Weapons view detour creation failed"); return false; }
        fovDetour->EnableDetour(); defaultDetour->EnableDetour(); shootDetour->EnableDetour();
        sharesys->AddNatives(myself,natives); weapons_ext::Clients().Add(this); return true;
    }
    void OnClientDisconnected(int client) override { if(client<129) { preferred[client]=-1; centered[client]=false; customZoom[client]=false; } }
    void OnCoreMapEnd() override { customZoom.fill(false); }
    void SDK_OnUnload() override {
        weapons_ext::Clients().Remove(this);
        for(CDetour **hook:{&shootDetour,&defaultDetour,&fovDetour}) if(*hook) { (*hook)->Destroy(); *hook=nullptr; }
        if(config) { gameconfs->CloseGameConfigFile(config); config=nullptr; }
        preferred.fill(-1); centered.fill(false); customZoom.fill(false);
    }
} module;
}}
SDKExtension &ViewModule() { return weapons_services::module; }
