#if defined _oblivion_included
 #endinput
#endif
#define _oblivion_included

/** Directional: true when viewer must not perceive subject. */
native bool Oblivion_IsHidden(int viewer, int subject);
/** Symmetric: false when either direction of oblivion exists. */
native bool Oblivion_CanInteract(int first, int second);
/** For join/quit alerts, including subjects not currently in a client slot. */
native bool Oblivion_IsSteamHidden(int viewer, const char[] steamId);
/** Tag otherwise ownerless custom particles/props with their creating player. */
native bool Oblivion_RegisterEntityOwner(int entity, int owner);
/** Refresh recipient/voice caches after the saved matrix changes. */
forward void Oblivion_OnStateChanged();

stock bool Oblivion_ShouldHide(int viewer, int subject)
{
    return GetFeatureStatus(FeatureType_Native, "Oblivion_IsHidden") == FeatureStatus_Available
        && Oblivion_IsHidden(viewer, subject);
}

stock bool Oblivion_InteractionBlocked(int first, int second)
{
    return GetFeatureStatus(FeatureType_Native, "Oblivion_CanInteract") == FeatureStatus_Available
        && !Oblivion_CanInteract(first, second);
}

public SharedPlugin __pl_oblivion =
{
    name = "oblivion",
    file = "oblivion.smx",
    required = 0
};

public void __pl_oblivion_SetNTVOptional()
{
    MarkNativeAsOptional("Oblivion_IsHidden");
    MarkNativeAsOptional("Oblivion_CanInteract");
    MarkNativeAsOptional("Oblivion_IsSteamHidden");
    MarkNativeAsOptional("Oblivion_RegisterEntityOwner");
}
