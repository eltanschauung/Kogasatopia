#pragma once
#define SMEXT_CONF_NAME "weapons_ext"
#define SMEXT_CONF_DESCRIPTION "Unified TF2 inventory, equipment, conditions and ballistics"
#define SMEXT_CONF_VERSION "2.1.0"
#define SMEXT_CONF_AUTHOR "Hombre; AlliedModders LLC; Asher Baker; AzuiSleet; FlaminSarge; nosoop; AndrewBetson; rtldg; pufftwitt"
#define SMEXT_CONF_URL "https://github.com/eltanschauung/Kogasatopia"
#define SMEXT_CONF_LOGTAG "weapons_ext"
#define SMEXT_CONF_LICENSE "GPL-3.0"
#define SMEXT_CONF_DATESTRING __DATE__
#define SMEXT_CONF_METAMOD
#define SMEXT_ENABLE_FORWARDSYS
#define SMEXT_ENABLE_HANDLESYS
#define SMEXT_ENABLE_PLAYERHELPERS
#define SMEXT_ENABLE_GAMECONF
#define SMEXT_ENABLE_GAMEHELPERS
#define SMEXT_ENABLE_TIMERSYS
#define SMEXT_ENABLE_PLUGINSYS
#define SMEXT_ENABLE_MEMUTILS
// Components are not separate extension interfaces. Only extension.cpp exports
// g_pExtensionIface, smsdk_ext and Metamod's entry points once.
#define SMEXT_LINK(component)
