#if defined _oblivion_net_included
 #endinput
#endif
#define _oblivion_net_included

native int OblivionNet_ApiVersion();
native void OblivionNet_GetCounters(int &snapshots, int &removed);
native void OblivionNet_TeamStart();
native int OblivionNet_TeamUpdate(int mirror, int source, const bool[] hidden, int size);
native void OblivionNet_TeamForget(int mirror);
native void OblivionNet_TeamClear();
native void OblivionNet_BrowserBegin(bool enabled, int queryPort);
native void OblivionNet_BrowserPlayer(int slot, const char[] authenticatedIp, const char[] name, int score, float seconds, bool bot);
native void OblivionNet_BrowserHide(int viewer, int subject);
// Adds an IP rule independently of whether its authenticated viewer is online.
native void OblivionNet_BrowserHideAddress(const char[] authenticatedIp, int subject);
native void OblivionNet_BrowserCommit();
native void OblivionNet_BrowserClear();
native bool OblivionNet_BrowserStatus(int &addresses, int &requests, int &lists, int &filtered, int &rows, int &infos);
native void OblivionNet_BrowserTransport(int &sent, int &errors);
forward void OblivionNet_CheckTransmit(int viewer, const int[] entities, int count, bool[] blocked);

public Extension __ext_oblivion_net =
{
    name = "Oblivion Network",
    file = "oblivion_net.ext",
    autoload = 1,
    required = 1
};
