/** Isolated-server binding contract. Constructs hooks/patches but never enables them. */
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <dhooks>
#include <sourcescramble>
public Plugin myinfo = {name="Weapons Gamedata Contract",author="Hombre",version="1.0"};
int checks, failures;
public void OnPluginStart() { RegAdminCmd("sm_weapons_gamedata_contract",Contract,ADMFLAG_ROOT); }
void Check(bool okay,const char[] key) {
    checks++;
    if (!okay) { failures++; PrintToServer("[WeaponsGamedataContract] FAIL %s",key); }
}
void Hook(GameData conf,const char[] key,bool virtualHook) {
    Handle hook;
    if (virtualHook) hook=DynamicHook.FromConf(conf,key);
    else hook=DynamicDetour.FromConf(conf,key);
    Check(hook!=null,key); delete hook;
}
void Patch(GameData conf,const char[] key) {
    MemoryPatch patch=MemoryPatch.CreateFromConf(conf,key);
    Check(patch!=null && patch.Validate(),key); delete patch;
}
public Action Contract(int client,int args) {
    if (client!=0) return Plugin_Handled;
    checks=0; failures=0;
    GameData conf=new GameData("weapons.games");
    if (conf==null) SetFailState("Missing consolidated gamedata");
    Hook(conf,"CTFWeaponBase::PrimaryAttack",true);
    Hook(conf,"CTFWeaponBase::SecondaryAttack",true);
    Hook(conf,"CTFPlayer::GetLoadoutItem()",false);
    Hook(conf,"CTFPlayer::ManageRegularWeapons()",false);
    Hook(conf,"CTFPlayer::TeamFortress_CalculateMaxSpeed",false);
    Hook(conf,"CObjectCartDispenser::DispenseMetal",true);
    Hook(conf,"CTFWeaponBase::CanFireCriticalShot",true);
    Hook(conf,"CTFLunchBox::ApplyBiteEffects",false);
    Hook(conf,"CTFStunBall::ApplyBallImpactEffectOnVictim",true);
    Hook(conf,"CTFPlayerShared::StunPlayer",false);
    Hook(conf,"CTFPlayerShared::Burn",false);
    Hook(conf,"CTFPlayer::GiveAmmoWithSource",false);
    Hook(conf,"CTFWeaponBase::Deploy",true);
    Hook(conf,"CTFWeaponBase::ItemPostFrame",true);
    Hook(conf,"CTFPlayer::ValidateWearables",false);
    Hook(conf,"CTFPlayer::ValidateWeapons",false);
    Hook(conf,"CBaseCombatWeapon::GiveTo",false);
    Hook(conf,"CEconWearable::GiveTo",false);
    Hook(conf,"CEconEntity::GiveTo",false);
    Hook(conf,"CTFWeaponBase::UpdateExtraWearables",false);
    Hook(conf,"CTFPlayer::PostInventoryApplication",false);
    Hook(conf,"CBaseEntity::PrecacheModel",false);
    Hook(conf,"CTFPlayer::GiveNamedItem",false);
    Hook(conf,"CTFKnife::PrimaryAttack",false);
    Hook(conf,"IsFixedWeaponSpreadEnabled",false);
    Hook(conf,"CTFGameRules::ApplyOnDamageModifyRules()",false);
    Patch(conf,"CTFPlayer::ApplyPunchImpulseX_FakeFullyChargedCondition");
    Patch(conf,"CObjectSentrygun::OnWrenchHit_CustomShieldRepair");
    Patch(conf,"CObjectSentrygun::OnWrenchHit_CustomShieldShellRefill");
    Patch(conf,"CObjectSentrygun::OnWrenchHit_CustomShieldRocketRefill");
    Patch(conf,"CObjectSentrygun::OnTakeDamage_CustomShieldDamageTaken");
    Patch(conf,"CTFProjectile_Arrow::BuildingHealingArrow_CustomShieldRepair");
    Patch(conf,"CTFWeaponBaseMelee::CalcIsAttackCriticalHelper_AllowOverride");
    delete conf;
    PrintToServer("[WeaponsGamedataContract] checks=%d failures=%d",checks,failures);
    return Plugin_Handled;
}
