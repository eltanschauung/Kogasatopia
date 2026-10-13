#if defined _tf2_spread_patterns_included
	#endinput
#endif
#define _tf2_spread_patterns_included

enum TF2SpreadPattern
{
	TF2Spread_Default = 0,
	TF2Spread_Circular15,
	TF2Spread_WideHorizontal20,
};

/**
 * Assigns an engine fixed-spread pattern to a weapon entity.
 */
native void TF2Spread_SetPattern(int weapon, TF2SpreadPattern pattern);

/**
 * Gives a weapon Ambassador-style spread recovery from 0.5 to 1.0 seconds
 * after its previous shot.
 */
native void TF2Spread_SetAmbassadorAccuracy(int weapon, bool enabled);

/**
 * Returns whether an enabled weapon has fully recovered its accuracy.
 */
native bool TF2Spread_IsAmbassadorAccuracyRecovered(int weapon);

/**
 * Replaces a weapon's stock punch-angle recoil while enabled. An enabled zero
 * amount suppresses stock recoil without adding punch angle. Pass false to
 * clear the override.
 * Non-consistent recoil uses TF2's amount - 1 through amount + 1 randomizer.
 */
native void TF2Weapon_SetPunchAngle(int weapon, bool enabled, int amount, bool consistent);


#include <weapons_ext_dependency>
