#if defined _enhanced_sprays_optional_included
 #endinput
#endif
#define _enhanced_sprays_optional_included

// Does not autoload or require enhanced_sprays. Mark this native optional in
// AskPluginLoad2 and check FeatureStatus_Available before calling it.
// original=true returns the pre-canonicalization image identity for moderation.
native bool ESprays_GetDecalFile(int client, char[] filename, int maxlen, bool original = false);
// Clear a viewer's native decal without changing the saved placement/audience.
native bool ESprays_ClearViewer(int client, int viewer);
forward void ESprays_OnSprayChanged(int client);
// Called for preview/clipped-model visibility as well as final decal replay.
// Returning Plugin_Handled or Plugin_Stop hides the spray from this viewer.
forward Action ESprays_CanSeeSpray(int client, int viewer);
