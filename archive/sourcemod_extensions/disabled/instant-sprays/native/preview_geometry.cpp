// SPDX-License-Identifier: GPL-3.0-or-later
#include "preview_geometry.h"
#include "preview_model.h"
#include <algorithm>
#include <cmath>
#include <cstring>

namespace spray_geometry {
namespace {
constexpr double Epsilon=1e-7;
bool Same(Point a,Point b){return std::abs(a.x-b.x)+std::abs(a.y-b.y)<1e-5;}
Polygon Clean(Polygon p){
    Polygon result;
    for(auto v:p)if(result.empty()||!Same(result.back(),v))result.push_back(v);
    if(result.size()>1&&Same(result.front(),result.back()))result.pop_back();
    if(result.size()<3||Area(result)<1e-5)result.clear();
    return result;
}
uint32_t Read(const std::vector<uint8_t> &v,size_t at){uint32_t n;std::memcpy(&n,v.data()+at,4);return n;}
void Int(std::vector<uint8_t> &v,size_t at,uint32_t n){std::memcpy(v.data()+at,&n,4);}
void Float(std::vector<uint8_t> &v,size_t at,float n){std::memcpy(v.data()+at,&n,4);}
Polygons Subtract(const Polygon &a,const Polygon &b){
    Polygons outside;Polygon pending=a;
    for(size_t i=0;i<b.size()&&!pending.empty();++i){
        auto from=b[i],to=b[(i+1)%b.size()];
        Plane edge{to.y-from.y,from.x-to.x,0};edge.d=edge.x*from.x+edge.y*from.y;
        auto piece=Clip(pending,{-edge.x,-edge.y,-edge.d});
        if(!piece.empty())outside.push_back(std::move(piece));
        pending=Clip(pending,edge);
    }
    return outside;
}
}
Polygon Square(){return {{-HalfSize,-HalfSize},{HalfSize,-HalfSize},{HalfSize,HalfSize},{-HalfSize,HalfSize}};}
double Area(const Polygon &p){
    double area=0;for(size_t i=0;i<p.size();++i){auto a=p[i],b=p[(i+1)%p.size()];area+=a.x*b.y-b.x*a.y;}
    return area*.5;
}
Polygon Clip(const Polygon &p,const Plane &plane){
    Polygon result;if(p.empty())return result;
    Point previous=p.back();double previousDistance=plane.x*previous.x+plane.y*previous.y-plane.d;
    for(auto current:p){
        double distance=plane.x*current.x+plane.y*current.y-plane.d;
        bool previousInside=previousDistance<=Epsilon,inside=distance<=Epsilon;
        if(inside!=previousInside){
            double t=previousDistance/(previousDistance-distance);
            result.push_back({previous.x+t*(current.x-previous.x),previous.y+t*(current.y-previous.y)});
        }
        if(inside)result.push_back(current);
        previous=current;previousDistance=distance;
    }
    return Clean(std::move(result));
}
bool AddDisjoint(Polygons &accepted,const Polygon &candidate){
    if(candidate.empty())return true;
    Polygons pending{candidate};
    for(const auto &existing:accepted){
        Polygons next;
        for(const auto &piece:pending){
            auto parts=Subtract(piece,existing);next.insert(next.end(),parts.begin(),parts.end());
            if(next.size()+accepted.size()>MaxPolygons)return false;
        }
        pending=std::move(next);if(pending.empty())break;
    }
    if(accepted.size()+pending.size()>MaxPolygons)return false;
    accepted.insert(accepted.end(),pending.begin(),pending.end());return true;
}
bool BuildModel(const Polygons &input,Model &out){
    Polygons polygons=input;double area=0;size_t count=0,indexCount=0;
    for(const auto &p:polygons){
        if(p.size()<3||Area(p)<=0)return false;
        for(auto v:p)if(!std::isfinite(v.x)||!std::isfinite(v.y)||std::abs(v.x)>HalfSize+.01||std::abs(v.y)>HalfSize+.01)return false;
        area+=Area(p);count+=p.size();indexCount+=(p.size()-2)*3;
    }
    if(!count||count>MaxVertices||polygons.size()>MaxPolygons||area>4*HalfSize*HalfSize+.05)return false;
    // Adjacent coplanar brush faces need no unique asset when their union fills
    // the square. This keeps the usual case at one cached model per image.
    if(std::abs(area-4*HalfSize*HalfSize)<.01){polygons={Square()};count=4;indexCount=6;}
    out.mdl.assign(preview_model::Mdl,preview_model::Mdl+sizeof(preview_model::Mdl));
    size_t body=Read(out.mdl,236),model=body+Read(out.mdl,body+12),mesh=model+Read(out.mdl,model+76);
    if(mesh+116>out.mdl.size())return false;
    Int(out.mdl,model+80,uint32_t(count));Int(out.mdl,mesh+8,uint32_t(count));
    Int(out.mdl,model+108,0);Int(out.mdl,model+112,0);Int(out.mdl,mesh+48,0);
    for(int lod=0;lod<8;++lod)Int(out.mdl,mesh+52+lod*4,uint32_t(count));
    out.vvd.assign(preview_model::Vvd,preview_model::Vvd+64);out.vvd.resize(64+count*64,0);
    for(int lod=0;lod<8;++lod)Int(out.vvd,16+lod*4,uint32_t(count));
    Int(out.vvd,56,64);Int(out.vvd,60,uint32_t(64+count*48));
    // optimize.h packed layout: one body, model, LOD, mesh, strip group, strip.
    constexpr size_t group=73,strip=98,vertices=125;
    size_t indices=vertices+9*count,boneChanges=indices+2*indexCount;
    out.vtx.assign(preview_model::Vtx,preview_model::Vtx+vertices);out.vtx.resize(boneChanges+16,0);
    Int(out.vtx,group,uint32_t(count));Int(out.vtx,group+12,uint32_t(indices-group));
    Int(out.vtx,group+8,uint32_t(indexCount));Int(out.vtx,strip,uint32_t(indexCount));
    Int(out.vtx,strip+8,uint32_t(count));Int(out.vtx,strip+23,uint32_t(boneChanges-strip));
    Int(out.vtx,24,uint32_t(boneChanges+8)); // Per-LOD material replacement list follows the bone state.
    // Hardware bone zero uses skeleton bone zero. Preserve the compiler's
    // second reserved bone-state entry as well as its declared entry count.
    size_t oldBoneChanges=98+Read(std::vector<uint8_t>(preview_model::Vtx,preview_model::Vtx+sizeof(preview_model::Vtx)),121);
    if(oldBoneChanges+16>sizeof(preview_model::Vtx))return false;
    std::memcpy(out.vtx.data()+boneChanges,preview_model::Vtx+oldBoneChanges,16);
    size_t vertex=0,index=0;
    for(const auto &p:polygons){
        size_t first=vertex;
        for(auto point:p){
            size_t at=64+vertex*48;
            Float(out.vvd,at,1);out.vvd[at+15]=1;
            Float(out.vvd,at+20,float(point.x));Float(out.vvd,at+24,float(point.y));Float(out.vvd,at+28,-1);
            Float(out.vvd,at+40,float((HalfSize-point.x)/(2*HalfSize)));
            Float(out.vvd,at+44,float((HalfSize-point.y)/(2*HalfSize)));
            size_t tangent=64+count*48+vertex*16;
            Float(out.vvd,tangent+4,-1);Float(out.vvd,tangent+12,1);
            at=vertices+vertex*9;out.vtx[at]=0;out.vtx[at+1]=1;out.vtx[at+2]=2;out.vtx[at+3]=1;
            out.vtx[at+4]=uint8_t(vertex);out.vtx[at+5]=uint8_t(vertex>>8);
            ++vertex;
        }
        for(size_t i=1;i+1<p.size();++i)for(size_t v:{first,first+i,first+i+1}){
            out.vtx[indices+2*index]=uint8_t(v);out.vtx[indices+2*index+1]=uint8_t(v>>8);++index;
        }
    }
    return true;
}
}
