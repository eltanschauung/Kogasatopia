// SPDX-License-Identifier: GPL-3.0-or-later
#include "filesystem_hooks.h"
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <thread>
#include <vector>

#ifdef _MSC_VER
#define NOINLINE __declspec(noinline)
#else
#define NOINLINE __attribute__((noinline))
#endif

std::atomic<unsigned> failures{0},policyCalls{0},wrongThread{0};
std::thread::id mainThread;
std::string uploadName;
bool upload=false;
void Check(bool value){if(!value)++failures;}
void PolicyThread(){++policyCalls;if(std::this_thread::get_id()!=mainThread)++wrongThread;}
class Files {
public:
    NOINLINE bool Exists(const char *name,const char *){return std::filesystem::exists(name);}
    NOINLINE void *Open(const char *name,const char *mode,const char *){return std::fopen(name,mode);}
    NOINLINE int Write(const void *data,int size,void *file){return int(std::fwrite(data,1,size,static_cast<FILE *>(file)));}
    NOINLINE void Close(void *file){std::fclose(static_cast<FILE *>(file));}
    NOINLINE void Directory(const char *name,const char *){std::filesystem::create_directories(name);}
};
template<class F> void *Address(F member){void *p;std::memcpy(&p,&member,sizeof(p));return p;}
bool Exists(const char *,const char *,bool &result){PolicyThread();if(!upload)return false;result=false;return true;}
bool BeforeOpen(const char *&name,const char *,const char *&id){PolicyThread();if(!upload)return false;name=uploadName.c_str();id=nullptr;return true;}
void Opened(void *file){PolicyThread();Check(file!=nullptr);}
bool Write(int size,void *,int &result){PolicyThread();if(size<0){result=0;return true;}return false;}
void Closed(void *){PolicyThread();}
bool Directory(const char *,const char *){PolicyThread();return upload;}

int main(int argc,char **argv){
    if(argc!=2)return 2;
    std::filesystem::path root=argv[1];std::filesystem::create_directories(root);
    const auto sentinel=(root/"shared.vtf").string();
    {std::ofstream f(sentinel);f<<"original";}
    Files files;char error[256];mainThread=std::this_thread::get_id();
    spray_files::Targets targets{Address(&Files::Exists),Address(&Files::Open),Address(&Files::Write),Address(&Files::Close),Address(&Files::Directory)};
    if(!spray_files::Install(targets,{Exists,BeforeOpen,Opened,Write,Closed,Directory},error,sizeof(error))){std::fprintf(stderr,"%s\n",error);return 3;}
    // Match the crash: compression workers open/write/close files while the
    // game thread routes uploads from alternating players sharing a filename.
    std::vector<std::thread> workers;
    for(int worker=0;worker<4;++worker)workers.emplace_back([&,worker]{
        const auto path=(root/("worker-"+std::to_string(worker)+".ztmp")).string();
        for(int i=0;i<1500;++i){
            Check(files.Exists(sentinel.c_str(),nullptr));
            auto *read=static_cast<FILE *>(files.Open(sentinel.c_str(),"rb",nullptr));
            if(read){char text[9]={};Check(std::fread(text,1,8,read)==8&&std::string(text)=="original");files.Close(read);}else ++failures;
            auto *write=files.Open(path.c_str(),"wb",nullptr);
            if(write){Check(files.Write("worker",6,write)==6);files.Close(write);}else ++failures;
        }
    });
    for(int i=0;i<1000;++i){
        upload=true;uploadName=(root/(i%2?"player-two.vtf":"player-one.vtf")).string();
        Check(!files.Exists(sentinel.c_str(),"download"));
        files.Directory((root/"must-not-exist").string().c_str(),"download");
        auto *file=files.Open(sentinel.c_str(),"wb","download");
        if(file){Check(files.Write(i%2?"bravo":"alpha",5,file)==5);files.Close(file);}else ++failures;
        upload=false;
    }
    for(auto &worker:workers)worker.join();
    Check(wrongThread==0&&policyCalls==6000&&spray_files::WorkerCalls()==36000);
    const auto workerCalls=spray_files::WorkerCalls();
    spray_files::Uninstall();
    Check(!std::filesystem::exists(root/"must-not-exist"));
    for(auto pair:{std::make_pair("shared.vtf","original"),std::make_pair("player-one.vtf","alpha"),std::make_pair("player-two.vtf","bravo")}){
        std::ifstream f(root/pair.first);std::string text;f>>text;Check(text==pair.second);
    }
    Check(files.Exists(sentinel.c_str(),nullptr));
    std::printf("Concurrent filesystem test: failures=%u game callbacks=%u worker bypasses=%llu\n",failures.load(),policyCalls.load(),static_cast<unsigned long long>(workerCalls));
    return failures?1:0;
}
