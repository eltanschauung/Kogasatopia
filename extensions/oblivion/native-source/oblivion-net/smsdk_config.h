// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef OBLIVION_NET_CONFIG_H
#define OBLIVION_NET_CONFIG_H
#define SMEXT_CONF_NAME "Oblivion Network"
#define SMEXT_CONF_DESCRIPTION "TF2 recipient transmission and server-browser filtering"
#define SMEXT_CONF_VERSION "0.2.2"
#define SMEXT_CONF_AUTHOR "Codex"
#define SMEXT_CONF_URL ""
#define SMEXT_CONF_LOGTAG "OBLIVION_NET"
#define SMEXT_CONF_LICENSE "GPL"
#define SMEXT_CONF_DATESTRING __DATE__
#define SMEXT_LINK(name) SDKExtension *g_pExtensionIface = name;
#define SMEXT_CONF_METAMOD
#define SMEXT_ENABLE_FORWARDSYS
#define SMEXT_ENABLE_GAMEHELPERS
#define SMEXT_ENABLE_PLAYERHELPERS
#endif
