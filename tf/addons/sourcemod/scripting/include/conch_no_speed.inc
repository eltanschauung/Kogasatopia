#if defined _conch_no_speed_included
	#endinput
#endif
#define _conch_no_speed_included

native void TF2ConchNoSpeed_AddRegenBuff(int client, float duration, int provider = 0);
native void TF2ConchNoSpeed_RemoveRegenBuff(int client);
native bool TF2ConchNoSpeed_IsRegenBuffActive(int client);


#include <weapons_ext_dependency>
