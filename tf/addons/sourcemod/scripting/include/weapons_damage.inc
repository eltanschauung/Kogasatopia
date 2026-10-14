#include <weapons_ext_dependency>
/**
 * Include description here.
 */

#if defined __weapons_damage_included
	#endinput
#endif

#define __weapons_damage_included

enum CritType {
	CritType_None = 0,
	CritType_MiniCrit,
	CritType_Crit
};

/**
 * Called before the CTFPlayer::OnTakeDamage() function is called.
 *
 * Note that the crit type may be further altered after this forward (when the game calls
 * CTFGameRules::ApplyOnDamageModifyRules(), which checks for attributes including
 * "minicrits_become_crits").
 */
forward Action Weapons_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage,
		int &damagetype, int &weapon, float damageForce[3], float damagePosition[3],
		int damagecustom, CritType &critType);

forward void Weapons_OnTakeDamagePost(int victim, int attacker, int inflictor, float damage,
		int damagetype, int weapon, const float damageForce[3], const float damagePosition[3],
		int damagecustom, CritType critType);

/**
 * Called after the conditional crit modifier attributes have been applied.
 *
 * At this point it seems that crit damage multipliers are finalized, so changing the `critType`
 * will not change the damage.
 */
forward Action Weapons_OnTakeDamageModifyRules(int victim, int &attacker, int &inflictor,
		float &damage, int &damagetype, int &weapon, float damageForce[3],
		float damagePosition[3], int damagecustom, CritType &critType);
