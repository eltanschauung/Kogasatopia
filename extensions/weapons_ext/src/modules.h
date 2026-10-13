#pragma once
#include "smsdk_ext.h"
#include <array>

SDKExtension &ItemsModule();
SDKExtension &ToolsModule();
SDKExtension &ConchModule();
SDKExtension &PelletsModule();
SDKExtension &SpreadModule();
SDKExtension &WhitelistModule();
SDKExtension &SentryModule();
void ItemsSeedView(void *view);
size_t PelletSharedTraceTables();

namespace weapons_ext {
// One player-manager registration for all merged features. Internal listeners
// remain independently subscribable (TF2Tools conditions are demand-driven).
class ClientDispatch final : public IClientListener {
public:
    void Add(IClientListener *listener);
    void Remove(IClientListener *listener);
    void OnClientPutInServer(int client) override;
    void OnClientDisconnecting(int client) override;
    void OnClientDisconnected(int client) override;
private:
    std::array<IClientListener *, 8> listeners_{};
};
ClientDispatch &Clients();
}
