#if defined _weapons_view_included
#endinput
#endif
#define _weapons_view_included
#include <weapons_ext_dependency>
native void WeaponsView_SetPreference(int client, int fov);
native void WeaponsView_SetLimits(int minimum, int maximum);
native void WeaponsView_SetCentered(int client, bool centered);
native void WeaponsView_ReconcileInventory(int client);
native void WeaponsView_ReconcileWeapon(int client, int weapon);
native bool WeaponsView_SetZoom(int client, int fov, float duration);
native void WeaponsView_Reset();
