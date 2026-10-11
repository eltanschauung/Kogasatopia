#if defined _instant_sprays_optional_included
 #endinput
#endif
#define _instant_sprays_optional_included

// Does not autoload or require Instant Sprays. Mark this native optional in
// AskPluginLoad2 and check FeatureStatus_Available before calling it.
// original=true returns the pre-canonicalization image identity for moderation.
native bool ISprays_GetDecalFile(int client, char[] filename, int maxlen, bool original = false);
// Clear a viewer's native decal without changing the saved placement/audience.
native bool ISprays_ClearViewer(int client, int viewer);
forward void ISprays_OnSprayChanged(int client);
// Called for preview/clipped-model visibility as well as final decal replay.
// Returning Plugin_Handled or Plugin_Stop hides the spray from this viewer.
forward Action ISprays_CanSeeSpray(int client, int viewer);
