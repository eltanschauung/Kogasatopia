// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "preview_geometry.h"
class IEngineTrace;
class IVModelInfo;
class ICollideable;
class Vector;
class QAngle;
namespace spray_geometry {
bool Surface(IEngineTrace *,IVModelInfo *,ICollideable *,bool world,
             const Vector &origin,const QAngle &angles,Polygons &);
}
