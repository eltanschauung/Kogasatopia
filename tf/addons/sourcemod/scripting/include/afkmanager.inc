#if defined _AFKMANAGER_INCLUDED
    #endinput
#endif
#define _AFKMANAGER_INCLUDED

/**
 * Last real activity from a human client's buttons, mouse, spectator camera
 * commands, or voice. Uses GetEngineTime(), not Unix or map time.
 * Returns 0.0 if no activity has been observed since connect/map/plugin start,
 * or if the client is not a human in game. Idle-time bookkeeping does not count.
 */
native float AFKManager_GetLastActivityTime(int client);

/**
 * Called when an AFK kick is about to be performed.
 *
 * @param client    Client index.
 * @returns         Return Plugin_Continue to continue the kick, return a
 *                  higher value to block the kick. When blocked, it will
 *                  reset the internal AFK time for the client and will
 *                  get called again when the client continues to be AFK.
 */
forward Action OnAFKKick(int client);

/**
 * Called when an AFK player has been switched to spectator.
 * @param client   Client index.
 */
forward void OnAFKSwitch(int client);

public SharedPlugin __pl_afkmanager = {
    name = "afkmanager",
    file = "afkmanager.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_afkmanager_SetNTVOptional() {
    MarkNativeAsOptional("AFKManager_GetLastActivityTime");
}
#endif
