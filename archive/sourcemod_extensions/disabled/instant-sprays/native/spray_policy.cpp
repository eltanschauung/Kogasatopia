// SPDX-License-Identifier: GPL-3.0-or-later
#include "spray_policy.h"
#include <algorithm>
#include <array>
#include <cctype>
#include <cstdio>
#include <cstring>
namespace sprays {
namespace {
uint32_t U32(const uint8_t *p){return uint32_t(p[0])|uint32_t(p[1])<<8|uint32_t(p[2])<<16|uint32_t(p[3])<<24;}
uint16_t U16(const uint8_t *p){return uint16_t(p[0])|uint16_t(p[1])<<8;}
uint64_t ImageBytes(uint32_t format,unsigned w,unsigned h) {
    if(format==13||format==20)return uint64_t((w+3)/4)*((h+3)/4)*8;
    if(format==14||format==15)return uint64_t((w+3)/4)*((h+3)/4)*16;
    static const unsigned bytes[]={4,4,3,3,2,1,2,0,1,3,3,4,4,0,0,0,4,2,2,2,0,2};
    return format<std::size(bytes)?uint64_t(w)*h*bytes[format]:0;
}
}
bool SelectedPath(const std::string &input,std::string &canonical) {
    canonical.clear();
    if(input.empty()||input.size()>240)return false;
    std::string p=input;std::replace(p.begin(),p.end(),'\\','/');
    for(unsigned char c:p)if(c<32||c==127)return false;
    if(p.find_first_of(":*?\"<>|;")!=std::string::npos||p.find("..")!=std::string::npos
        ||p.find("//")!=std::string::npos||p.find("/./")!=std::string::npos)return false;
    std::string lower=p;for(auto &c:lower)c=static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    if(lower.rfind("materials/vgui/logos/",0)!=0&&lower!="materials/decals/spraylogo.vtf")return false;
    if(lower.size()<5||lower.substr(lower.size()-4)!=".vtf")return false;
    canonical=std::move(p);return true;
}
bool ValidTexture(const std::vector<uint8_t> &d,std::string &error) {
    auto bad=[&](const char *s){error=s;return false;};
    if(d.size()<64||d.size()>MaxBytes)return bad("Spray must be a VTF no larger than 512 KiB.");
    if(std::memcmp(d.data(),"VTF\0",4))return bad("Selected file is not a VTF texture.");
    const auto major=U32(&d[4]),minor=U32(&d[8]),header=U32(&d[12]);
    if(major!=7||minor>5||header>d.size()||header<64||(minor>=2&&header<65)||(minor>=3&&header<80))
        return bad("Unsupported or incomplete VTF header.");
    unsigned w=U16(&d[16]),h=U16(&d[18]),frames=U16(&d[24]),mips=d[56];
    if(!w||!h||w>2048||h>2048||!frames||frames>256||U16(&d[26])>=frames
        ||!mips||mips>12||(minor>=2&&U16(&d[63])!=1)||(U32(&d[20])&0x4000))
        return bad("Spray must be a supported two-dimensional texture.");
    unsigned maximum=1;for(unsigned size=std::max(w,h);size>1;size>>=1)++maximum;
    if(mips>maximum)return bad("Invalid VTF mip count.");
    uint64_t offset=header;
    if(minor>=3) {
        const uint32_t count=U32(&d[68]);
        if(count>32||uint64_t(80)+8*count>header)return bad("Invalid VTF resource table.");
        bool found=false;
        for(uint32_t i=0;i<count;++i) {
            const auto p=&d[80+8*i];
            if(p[0]==0x30&&!p[1]&&!p[2]) {
                if(found||p[3]&2)return bad("Invalid VTF image resource.");
                found=true;offset=U32(p+4);
            } else if(!(p[3]&2)) {
                const uint64_t where=U32(p+4);
                if(where<header||where>d.size())return bad("VTF resource offset is outside the file.");
                if(p[0]==1&&!p[1]&&!p[2]) {
                    auto low=ImageBytes(U32(&d[57]),d[61],d[62]);
                    if(!d[61]||!d[62]||!low||low>d.size()-where)return bad("VTF thumbnail resource is incomplete.");
                } else {
                    if(d.size()-where<4||U32(&d[static_cast<size_t>(where)])>d.size()-where-4)
                        return bad("VTF resource data is incomplete.");
                }
            }
        }
        if(!found)return bad("VTF image resource is missing.");
    } else if(d[61]||d[62]) {
        if(!d[61]||!d[62])return bad("Invalid VTF thumbnail.");
        auto low=ImageBytes(U32(&d[57]),d[61],d[62]);
        if(!low)return bad("Unsupported VTF thumbnail format.");
        offset+=low;
    }
    if(offset<header||offset>d.size())return bad("VTF image offset is outside the file.");
    uint64_t required=0;const auto format=U32(&d[52]);
    for(unsigned mip=0;mip<mips;++mip) {
        auto bytes=ImageBytes(format,std::max(1u,w>>mip),std::max(1u,h>>mip));
        if(!bytes)return bad("Unsupported spray pixel format.");
        required+=bytes*frames;
        if(required>d.size()-offset)return bad("VTF image data is incomplete.");
    }
    error.clear();return true;
}
void CanonicalTexture(std::vector<uint8_t> &data) {
    if(data.size()>=64)std::memcpy(data.data()+28,"IS14",4);
}
uint32_t Crc(const std::vector<uint8_t> &data) {
    static const auto table=[](){std::array<uint32_t,256> t{};for(unsigned i=0;i<256;++i){auto c=i;for(int j=0;j<8;++j)c=(c>>1)^(0xedb88320u&uint32_t(-int(c&1)));t[i]=c;}return t;}();
    uint32_t crc=0xffffffffu;for(auto b:data)crc=table[(crc^b)&255]^(crc>>8);
    // Source CRC_File omits CRC32_Final; do not complement this result.
    return crc;
}
std::string Hex(uint32_t crc){char hex[9];for(int i=0;i<4;++i)std::snprintf(hex+2*i,3,"%02x",(crc>>(i*8))&255);return hex;}
std::string CachePath(uint32_t crc){auto hex=Hex(crc);return "user_custom/"+hex.substr(0,2)+"/"+hex+".dat";}
}
