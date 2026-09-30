// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <cstddef>
#include <cstdint>
#include <vector>
namespace spray_geometry {
struct Point { double x=0,y=0; };
struct Plane { double x=0,y=0,d=0; }; // Inside: x*p.x + y*p.y <= d.
using Polygon=std::vector<Point>;
using Polygons=std::vector<Polygon>;
constexpr double HalfSize=32;
constexpr size_t MaxPolygons=128, MaxVertices=1024;
Polygon Square();
Polygon Clip(const Polygon &,const Plane &);
double Area(const Polygon &);
bool AddDisjoint(Polygons &,const Polygon &);
struct Model {std::vector<uint8_t> mdl,vvd,vtx;};
// Generated files retain the template skeleton and use bounded triangle lists.
bool BuildModel(const Polygons &,Model &);
}
