// SPDX-License-Identifier: GPL-3.0-or-later
#include "preview_surface.h"
#include "engine/IEngineTrace.h"
#include "engine/ivmodelinfo.h"
#include "engine/ICollideable.h"
#include "gametrace.h"
#include "bspflags.h"
#include <cmath>

namespace spray_geometry {
namespace {
struct Basis {Vector x,y,z;};
Basis Axes(const QAngle &a){
    constexpr double rad=3.14159265358979323846/180;
    double sp=std::sin(a.x*rad),cp=std::cos(a.x*rad),sy=std::sin(a.y*rad),cy=std::cos(a.y*rad),sr=std::sin(a.z*rad),cr=std::cos(a.z*rad);
    return {Vector(float(cp*cy),float(cp*sy),float(-sp)),
            Vector(float(sr*sp*cy-cr*sy),float(sr*sp*sy+cr*cy),float(sr*cp)),
            Vector(float(cr*sp*cy+sr*sy),float(cr*sp*sy-sr*cy),float(cr*cp))};
}
Vector Rotate(const Vector &v,const Basis &b){return b.x*v.x+b.y*v.y+b.z*v.z;}
Polygon OnPlanes(const Vector &origin,const Basis &basis,const CUtlVector<Vector4D> &planes){
    Polygon p=Square();
    for(int i=0;i<planes.Count()&&!p.empty();++i){
        const auto &plane=planes[i];Vector n(plane.x,plane.y,plane.z);
        Plane projected{DotProduct(n,basis.y),DotProduct(n,basis.z),plane.w-DotProduct(n,origin)};
        // Trace end positions include Source's small collision epsilon.
        if(std::abs(projected.x)+std::abs(projected.y)<1e-4){if(projected.d<-.25)return {};continue;}
        p=Clip(p,projected);
    }
    return p;
}
bool Supported(IEngineTrace *trace,ICollideable *target,const Vector &p,const Vector &normal){
    Ray_t ray;ray.Init(p+normal*.5f,p-normal*.5f);trace_t hit;
    trace->ClipRayToCollideable(ray,MASK_SOLID_BRUSHONLY,target,&hit);
    return hit.fraction<1&&!hit.startsolid&&!hit.allsolid
        && !(hit.surface.flags&(SURF_SKY|SURF_SKY2D|SURF_NODRAW|SURF_NODECALS))
        && DotProduct(hit.plane.normal,normal)>.995f&&(hit.endpos-p).LengthSqr()<.0625f;
}
}
bool Surface(IEngineTrace *trace,IVModelInfo *models,ICollideable *target,bool world,
             const Vector &origin,const QAngle &angles,Polygons &out){
    out.clear();if(!target||!target->GetCollisionModel()||models->GetModelType(target->GetCollisionModel())!=1)return false;
    const auto basis=Axes(angles);Vector normal=-basis.x;
    if(!Supported(trace,target,origin,normal))return false;
    if(world){
        Vector extent;
        for(int a=0;a<3;++a)extent[a]=float(HalfSize*(std::abs(basis.y[a])+std::abs(basis.z[a]))+1);
        CUtlVector<int> brushes;trace->GetBrushesInAABB(origin-extent,origin+extent,&brushes,MASK_SOLID_BRUSHONLY);
        if(brushes.Count()>512)return false;
        for(int i=0;i<brushes.Count();++i){
            CUtlVector<Vector4D> planes;int contents=0;
            if(!trace->GetBrushInfo(brushes[i],&planes,&contents)||!(contents&MASK_SOLID_BRUSHONLY)||planes.Count()>96)continue;
            bool coplanar=false;
            for(int j=0;j<planes.Count();++j){auto &v=planes[j];Vector n(v.x,v.y,v.z);
                if(DotProduct(n,normal)>.999f&&std::abs(DotProduct(n,origin)-v.w)<.25f){coplanar=true;break;}}
            if(!coplanar)continue;
            auto p=OnPlanes(origin,basis,planes);if(p.empty())continue;
            Point center;for(auto v:p){center.x+=v.x;center.y+=v.y;}center.x/=p.size();center.y/=p.size();
            if(!Supported(trace,target,origin+basis.y*float(center.x)+basis.z*float(center.y),normal))continue;
            if(!AddDisjoint(out,p)){out.clear();return false;}
        }
    }else{
        // The brush's face planes partition its volume into convex cells. Use
        // the cell containing the hit point, so even concave doors never get a
        // floating square across an opening. Parent motion is handled by Source.
        const auto model=target->GetCollisionModel();int count=models->GetBrushModelPlaneCount(model);
        if(count<=0||count>512)return false;
        auto modelBasis=Axes(target->GetCollisionAngles());Vector offset=target->GetCollisionOrigin();
        Vector inside=origin-normal*.10f;CUtlVector<Vector4D> planes;
        for(int i=0;i<count;++i){
            cplane_t plane;Vector unused;models->GetBrushModelPlane(model,i,plane,&unused);
            Vector n=Rotate(plane.normal,modelBasis);float d=plane.dist+DotProduct(n,offset);
            if(DotProduct(n,inside)>d){n=-n;d=-d;}
            planes.AddToTail(Vector4D(n.x,n.y,n.z,d));
        }
        auto p=OnPlanes(origin,basis,planes);if(!p.empty())out.push_back(std::move(p));
    }
    size_t vertices=0;for(const auto &p:out)vertices+=p.size();
    if(vertices>MaxVertices){out.clear();return false;}
    return !out.empty();
}
}
