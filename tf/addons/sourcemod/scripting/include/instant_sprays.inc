#if defined _instant_sprays_included
 #endinput
#endif
#define _instant_sprays_included
native int ISprays_ApiVersion();
// Returns a positive request token, 0 if unavailable, or -1 for an unsafe path.
native int ISprays_Request(int client,const char[] selectedSpray,bool forceUpload=false);
// 0 idle, 1 uploading, 2 ready, 3 validating, 4 distributing, 6 material warmup, 7 clearing, -1 failed.
native int ISprays_Status(int client,int token,int &crc,char[] reason,int maxlen);
native void ISprays_Cancel(int client,int token);
native int ISprays_Inspect(int client,int &crc,int &requests,int &changes,int &metadataRepairs);
native int ISprays_Watch(int client,const char[] selectedSpray,bool associateSignonSpray=false);
native int ISprays_Preview(int client,char[] material,int maxlen);
native void ISprays_EnablePreview(int client,bool enabled);
native bool ISprays_Replay(int client);
native bool ISprays_SetSurface(int client,const float origin[3],const float angles[3],int entity);
// Original recipients only. 1 = texture/model delivered, 0 = pending, -1 = unavailable.
native int ISprays_SurfaceModel(int client,int recipient,char[] model,int maxlen);
native void ISprays_ClearPrevious(int client);
native bool ISprays_CanReceive(int client,int recipient);
native void ISprays_LastError(int client,char[] reason,int maxlen);
#include <instant_sprays_optional>
forward void ISprays_OnSprayPlaced(int client,const float origin[3],int entity,bool suppressed,bool guarded);
forward int ISprays_ShouldGuardSurface(int client,const float origin[3],int entity);
public Extension __ext_instant_sprays={name="Instant Sprays",file="instant_sprays.ext",autoload=1,required=1};

// Controller-only acknowledgement of a native transport barrier.
native void ISprays_BarrierAck(int client,int token,bool okay);
forward void ISprays_OnClearBarrier(int client,int token);
