// SPDX-License-Identifier: GPL-3.0-or-later
#include "smsdk_ext.h"
#include "eiface.h"
class RestoreScoreDisplay final : public SDKExtension, public IClientListener, public IPluginsListener {
public:
    bool SDK_OnMetamodLoad(ISmmAPI *, char *, size_t, bool) override;
    bool SDK_OnLoad(char *, size_t, bool) override;
    void SDK_OnUnload() override;
    void OnClientConnected(int client) override;
    void OnClientDisconnected(int client) override;
    void OnPluginUnloaded(IPlugin *) override;
    void OnPluginPauseChange(IPlugin *, bool) override;
};
