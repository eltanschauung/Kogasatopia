// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "engine.h"
namespace weapons_services {
bool SetAttribute(CBaseEntity *entity, int definition, float value);
void InvalidateAttributeDefinitions();
}
