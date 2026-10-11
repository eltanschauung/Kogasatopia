// SPDX-License-Identifier: GPL-3.0-or-later
#include "spray_policy.h"
#include "spray_delivery.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

using Bytes = std::vector<uint8_t>;
unsigned checks;
void Check(bool condition, const char *label) {
    ++checks;
    if (!condition) { std::fprintf(stderr, "FAIL: %s\n", label); std::exit(1); }
}
void Put16(Bytes &b, size_t at, uint16_t n) { b[at]=uint8_t(n); b[at+1]=uint8_t(n>>8); }
void Put32(Bytes &b, size_t at, uint32_t n) { for(unsigned i=0;i<4;++i)b[at+i]=uint8_t(n>>(8*i)); }
Bytes Texture(unsigned minor=2, unsigned format=0, unsigned pixels=4096) {
    const unsigned header=minor>=3?88:80;
    Bytes b(header+pixels,0);
    b[0]='V';b[1]='T';b[2]='F';Put32(b,4,7);Put32(b,8,minor);Put32(b,12,header);
    Put16(b,16,32);Put16(b,18,32);Put16(b,24,1);Put16(b,63,1);
    Put32(b,52,format);b[56]=1;Put32(b,57,0xffffffffu);
    if(minor>=3){Put32(b,68,1);b[80]=0x30;Put32(b,84,header);}
    return b;
}
bool Valid(const Bytes &b) { std::string error;return sprays::ValidTexture(b,error); }
int main() {
    spray_delivery::Audience audience,filtered;
    audience.Add(2,1002);filtered.Add(4,1004);filtered.Add(2,1002);
    audience.Merge(filtered);
    Check(audience.members.size()==2&&audience.Contains(2,1002)&&audience.Contains(4,1004),
          "per-viewer re-sends retain every accepted recipient exactly once");
    Check(!audience.Contains(3,1003),"a muted recipient is never added by aggregation");
    Check(!audience.Contains(2,2002),"a new connection in an old slot cannot see a prior placement");
    filtered.Add(2,2002);audience.Merge(filtered);
    Check(audience.members.size()==2&&audience.Contains(2,2002)&&!audience.Contains(2,1002),
          "explicitly accepted new connections replace stale serials");
    audience.Add(0,10);audience.Add(7,0);
    Check(audience.members.size()==2,"invalid recipients cannot enter the audience");
    std::string path;
    for(const auto *good:{"materials/vgui/logos/My Spray.vtf", "materials\\vgui\\logos\\nested\\Bird.VTF", "materials/decals/spraylogo.vtf"})
        Check(sprays::SelectedPath(good,path),"legitimate selected path");
    Check(path=="materials/decals/spraylogo.vtf","stock path preserved");
    for(const auto *bad:{"", "../materials/vgui/logos/a.vtf", "C:/materials/vgui/logos/a.vtf", "/materials/vgui/logos/a.vtf",
                        "materials/vgui/logos/../a.vtf", "materials/vgui/logos/a.vtf:stream", "materials/vgui/logos/a.vmt",
                        "materials/vgui/logos/a.vtf;quit", "materials/vgui/logos//a.vtf", "materials/vgui/logos/./a.vtf",
                        "materials/vgui/logos/a\n.vtf", "materials/vgui/logos/a*.vtf", "cfg/a.vtf"})
        Check(!sprays::SelectedPath(bad,path)&&path.empty(),"reject unsafe or unrelated path");
    Check(!sprays::SelectedPath("materials/vgui/logos/"+std::string(241,'a')+".vtf",path),"path length bounded");
    for(unsigned minor=0;minor<=5;++minor)Check(Valid(Texture(minor)),"valid supported VTF revision");
    Check(Valid(Texture(2,13,512)),"DXT1 block size");
    Check(Valid(Texture(2,15,1024)),"DXT5 block size");
    auto b=Texture();b.pop_back();Check(!Valid(b),"truncated pixels rejected");
    b=Texture();b[0]='X';Check(!Valid(b),"bad magic rejected");
    b=Texture();Put32(b,8,6);Check(!Valid(b),"unknown version rejected");
    b=Texture();Put32(b,12,64);Check(!Valid(b),"missing depth header rejected");
    b=Texture();Put16(b,16,0);Check(!Valid(b),"zero dimension rejected");
    b=Texture();Put16(b,16,31);Check(Valid(b),"bounded non-power-of-two textures are supported");
    b=Texture(1,13,522240);Put16(b,16,1020);Put16(b,18,1024);Check(Valid(b),"cropped high-resolution DXT1 spray accepted");
    b.pop_back();Check(!Valid(b),"truncated cropped high-resolution spray rejected");
    b=Texture(1,13,520192);Put16(b,16,508);Put16(b,18,512);Put16(b,24,4);Check(Valid(b),"cropped animated DXT1 spray accepted");
    b=Texture();Put16(b,16,4096);Check(!Valid(b),"oversized dimension rejected");
    b=Texture();Put16(b,24,0);Check(!Valid(b),"zero frames rejected");
    b=Texture();Put16(b,26,1);Check(!Valid(b),"frame index outside animation rejected");
    b=Texture();Put16(b,63,2);Check(!Valid(b),"volume texture rejected");
    b=Texture();Put32(b,20,0x4000);Check(!Valid(b),"cubemap rejected");
    b=Texture();b[56]=7;Check(!Valid(b),"impossible mip count rejected");
    b=Texture();Put32(b,52,0xffffffffu);Check(!Valid(b),"unsupported format rejected");
    b=Texture();b.resize(sprays::MaxBytes+1);Check(!Valid(b),"upload size cap");
    b=Texture(3);Put32(b,68,33);Check(!Valid(b),"resource count cap");
    b=Texture(3);b[80]=1;Check(!Valid(b),"missing image resource rejected");
    b=Texture(3);Put32(b,84,10);Check(!Valid(b),"resource cannot alias header");
    b=Texture(3);Put32(b,84,0xffffffffu);Check(!Valid(b),"resource cannot exceed file");
    b=Texture(3);b[83]=2;Check(!Valid(b),"inline image data rejected");
    b=Texture(3);b.insert(b.begin()+88,8,0);Put32(b,12,96);Put32(b,68,2);Put32(b,84,96);
    b[88]='K';b[89]='V';b[90]='D';Put32(b,92,uint32_t(b.size()));
    Check(!Valid(b),"truncated auxiliary resource rejected");
    b.insert(b.end(),{4,0,0,0,'t','e','s','t'});Check(Valid(b),"bounded auxiliary resource accepted");
    Put32(b,b.size()-8,1000);Check(!Valid(b),"auxiliary length overflow rejected");
    b=Texture(2,0,8192);Put16(b,24,2);Put16(b,26,1);Check(Valid(b),"animated RGBA accepted");
    b=Texture(2,0,262144);Put16(b,16,256);Put16(b,18,256);Check(Valid(b),"large RGBA spray accepted");
    const std::string known="123456789";Bytes data(known.begin(),known.end());
    Check(sprays::Crc(data)==0x340bc6d9u,"Source non-finalized CRC golden vector");
    Check(sprays::Hex(0x340bc6d9u)=="d9c60b34","CRC filename byte order");
    Check(sprays::CachePath(0x340bc6d9u)=="user_custom/d9/d9c60b34.dat","CRC cache path");
    b=Texture(2,0,262144);Put16(b,16,256);Put16(b,18,256);auto original=b;
    sprays::CanonicalTexture(b);Check(Valid(b),"canonical texture remains valid");
    Check(b.size()==original.size()&&std::equal(b.begin(),b.begin()+28,original.begin())
        &&std::equal(b.begin()+32,b.end(),original.begin()+32),"canonicalization changes reserved padding only");
    Check(sprays::Crc(b)!=sprays::Crc(original),"canonical texture avoids stale renderer cache key");
    auto stable=b;sprays::CanonicalTexture(b);Check(b==stable,"canonical texture identity is stable");
    // Every prefix of a valid image must fail until all required bytes arrive.
    b=Texture(3);for(size_t length=0;length<b.size();++length)
        Check(!Valid(Bytes(b.begin(),b.begin()+length)),"truncated resource texture prefix");
    std::printf("Passed %u policy checks\n",checks);
}
