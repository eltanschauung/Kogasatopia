#include <weapons_ext_dependency>
/**
 * Unified Weapons native player and Engineer-building damage forwards.
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

/**
 * Called at CBaseObject::OnTakeDamage() entry, before building-specific rules,
 * only for obj_sentrygun, obj_dispenser and obj_teleporter (both ends).
 *
 * damage is pre-multiplier input. Weapons owns the single 1.35x/3x crit policy;
 * other listeners must not apply those multipliers again. CritType is the real
 * CTakeDamageInfo field, NOT inferred from DMG_CRIT or player conditions.
 * Only damage can be edited. Crit classification, flags, attribution, vectors
 * and custom damage remain untouched. Return Plugin_Changed to commit damage.
 * As with the player forward, actions commit edits rather than cancel damage.
 * The caller's record is never mutated or reused for another building.
 */
forward Action Weapons_OnBuildingTakeDamage(int building, int attacker, int inflictor,
        float &damage, int damagetype, int weapon, int damagecustom, CritType critType);
