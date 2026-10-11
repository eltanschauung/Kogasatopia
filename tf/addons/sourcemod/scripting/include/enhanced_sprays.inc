#if defined _enhanced_sprays_included
 #endinput
#endif
#define _enhanced_sprays_included
native int ESprays_ApiVersion();
// Validated metadata cached once per CRC. False while the signon/upload file is unavailable.
native bool ESprays_GetTextureInfo(int client,int &width,int &height,int &frames,int &crc);
// Creates an immutable material for this texture/scale; never overwrites another spray.
native bool ESprays_PrepareResize(int client,float scale,char[] material,int maxlen,char[] texture,int textureMaxlen);
// Shared, bounded per-connection delivery. Identical requests reuse a token.
native int ESprays_RequestAsset(int recipient,const char[] path,int timeoutSeconds=20);
// 1 pending, 2 delivered, -1 failed, 0 unknown/expired connection.
native int ESprays_AssetStatus(int recipient,int token);
// Shared moderation policy, independent of a normal player-decal audience.
native bool ESprays_CanView(int owner,int recipient);
forward void ESprays_OnAssetReady(int recipient,int token,const char[] path,bool success);
// Returns a positive request token, 0 if unavailable, or -1 for an unsafe path.
native int ESprays_Request(int client,const char[] selectedSpray,bool forceUpload=false);
// 0 idle, 1 uploading, 2 ready, 3 validating, 4 distributing, 6 material warmup, 7 clearing, -1 failed.
native int ESprays_Status(int client,int token,int &crc,char[] reason,int maxlen);
native void ESprays_Cancel(int client,int token);
native int ESprays_Inspect(int client,int &crc,int &requests,int &changes,int &metadataRepairs);
native int ESprays_Watch(int client,const char[] selectedSpray,bool associateSignonSpray=false);
native int ESprays_Preview(int client,char[] material,int maxlen);
native void ESprays_EnablePreview(int client,bool enabled);
native bool ESprays_Replay(int client);
native bool ESprays_SetSurface(int client,const float origin[3],const float angles[3],int entity);
// Original recipients only. 1 = texture/model delivered, 0 = pending, -1 = unavailable.
native int ESprays_SurfaceModel(int client,int recipient,char[] model,int maxlen);
native void ESprays_ClearPrevious(int client);
native bool ESprays_CanReceive(int client,int recipient);
native void ESprays_LastError(int client,char[] reason,int maxlen);
#include <enhanced_sprays_optional>
forward void ESprays_OnSprayPlaced(int client,const float origin[3],int entity,bool suppressed,bool guarded);
forward int ESprays_ShouldGuardSurface(int client,const float origin[3],int entity);
public Extension __ext_enhanced_sprays={name="enhanced_sprays",file="enhanced_sprays.ext",autoload=1,required=1};

// Controller-only acknowledgement of a native transport barrier.
native void ESprays_BarrierAck(int client,int token,bool okay);
forward void ESprays_OnClearBarrier(int client,int token);
