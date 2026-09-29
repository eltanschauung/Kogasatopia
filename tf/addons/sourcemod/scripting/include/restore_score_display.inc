#if defined _restore_score_display_included
 #endinput
#endif
#define _restore_score_display_included
native int RSDisplay_ApiVersion();
native void RSDisplay_Set(int client, int restoredScore, int adjustment);
native void RSDisplay_Reset();
native int RSDisplay_Calculate(int rawScore, int restoredScore, int adjustment);
// Read-only diagnostic: invoke the actual score serializer for a resource row.
native int RSDisplay_ReadSerialized(int resource, int client);
// Encoder-call count and most recent value, excluding ReadSerialized calls.
native int RSDisplay_NetworkSample(int client, int &lastValue);
public Extension __ext_restore_score_display =
{
    name = "Restore Score Display",
    file = "restore_score.ext",
    autoload = 1,
    required = 1
};
