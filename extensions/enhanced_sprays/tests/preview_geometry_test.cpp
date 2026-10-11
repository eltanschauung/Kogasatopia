#include "preview_geometry.h"
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <random>
using namespace spray_geometry;
unsigned checks;
void Check(bool ok,const char *message){++checks;if(!ok){std::fprintf(stderr,"FAIL %s\n",message);std::exit(1);}}
uint32_t U(const std::vector<uint8_t> &v,size_t at){Check(at+4<=v.size(),"field in bounds");uint32_t n;std::memcpy(&n,v.data()+at,4);return n;}
float F(const std::vector<uint8_t> &v,size_t at){uint32_t n=U(v,at);float f;std::memcpy(&f,&n,4);return f;}
void Validate(const Model &m){
    auto body=U(m.mdl,236),model=body+U(m.mdl,body+12),mesh=model+U(m.mdl,model+76);
    auto count=U(m.vvd,16),group=73u,strip=98u,first=group+U(m.vtx,group+4),indices=group+U(m.vtx,group+12),numIndices=U(m.vtx,group+8);
    Check(U(m.mdl,model+80)==count&&U(m.mdl,mesh+8)==count,"MDL/VVD vertex counts agree");
    for(int lod=0;lod<8;++lod)Check(U(m.mdl,mesh+52+lod*4)==count,"all MDL LOD counts agree");
    Check(m.vvd.size()==64+count*64&&U(m.vvd,60)==64+count*48,"VVD streams sized correctly");
    Check(U(m.vtx,group)==count&&U(m.vtx,strip+8)==count,"VTX counts agree");
    Check(U(m.vtx,strip)==numIndices&&numIndices%3==0,"triangle list counts agree");
    Check(first+9*count==indices,"VTX vertex stream ends at indices");
    Check(strip+U(m.vtx,strip+23)==indices+numIndices*2,"VTX bone-state offset follows indices");
    auto materials=U(m.vtx,24);Check(materials+8==m.vtx.size()&&U(m.vtx,materials)==0,"material replacement table relocated correctly");
    for(size_t i=0;i<count;++i){
        size_t at=64+i*48;
        Check(F(m.vvd,at+16)==0&&std::abs(F(m.vvd,at+20))<=32.001&&std::abs(F(m.vvd,at+24))<=32.001,"bounded planar positions");
        Check(std::abs(F(m.vvd,at+40)-(32-F(m.vvd,at+20))/64)<1e-6,"U crops without stretching");
        Check(std::abs(F(m.vvd,at+44)-(32-F(m.vvd,at+24))/64)<1e-6,"V crops without stretching");
        Check(size_t(m.vtx[first+i*9+4]|m.vtx[first+i*9+5]<<8)==i,"VTX vertex references match VVD");
    }
    for(size_t i=0;i<numIndices;++i)Check(uint32_t(m.vtx[indices+2*i]|m.vtx[indices+2*i+1]<<8)<count,"triangle references in bounds");
}
int main(int argc,char **argv){
    auto square=Square();Check(Area(square)==4096,"full area");
    auto half=Clip(square,{1,0,0});Check(std::abs(Area(half)-2048)<1e-5,"half-surface clipping");
    auto diagonal=Clip(square,{1,1,0});Check(std::abs(Area(diagonal)-2048)<1e-5,"diagonal clipping");
    Check(Clip(square,{1,0,-33}).empty(),"unsupported surface empty");
    Polygons unioned;Check(AddDisjoint(unioned,half),"add first face");
    Check(AddDisjoint(unioned,half),"overlap accepted");double area=0;for(auto &p:unioned)area+=Area(p);
    Check(std::abs(area-2048)<1e-5,"overlap has no double blending");
    Check(AddDisjoint(unioned,Clip(square,{-1,0,0})),"add adjacent face");
    area=0;for(auto &p:unioned)area+=Area(p);Check(std::abs(area-4096)<1e-5,"adjacent faces join");
    std::mt19937 rng(3187);std::uniform_real_distribution<double> angle(0,6.28),distance(-30,30);
    for(int i=0;i<160;++i){
        double a=angle(rng);Plane plane{std::cos(a),std::sin(a),distance(rng)};auto p=Clip(square,plane);
        Check(!p.empty()&&Area(p)>0&&Area(p)<4096,"random clipped polygon area");
        for(auto v:p)Check(plane.x*v.x+plane.y*v.y<=plane.d+1e-5,"no overhang across clipping plane");
        Model m;Check(BuildModel({p},m),"build clipped model");Validate(m);
    }
    Model full;Check(BuildModel(unioned,full),"build union model");Validate(full);Check(U(full.vvd,16)==4,"full coverage uses shared four-vertex model");
    Check(!BuildModel({},full),"empty mesh rejected");
    Check(!BuildModel({{{0,0},{100,0},{0,100}}},full),"out-of-bounds geometry rejected");
    if(argc>1){
        Model m;Check(BuildModel({Clip(square,{1,.5,0})},m),"export model");
        std::filesystem::path path=argv[1];std::filesystem::create_directories(path);
        for(auto item:{std::make_pair(".mdl",&m.mdl),std::make_pair(".vvd",&m.vvd),std::make_pair(".dx90.vtx",&m.vtx)}){
            std::ofstream file(path/(std::string("00000000")+item.first),std::ios::binary);file.write(reinterpret_cast<const char *>(item.second->data()),item.second->size());
        }
    }
    std::printf("Passed %u geometry checks\n",checks);
}
