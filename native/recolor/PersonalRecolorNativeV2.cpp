// OFF pilot companion. No loader call, hook, worker, texture setter or liblua dependency.
// Main must compile/review against the supplied current-build symbol pins.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <cstdio>
#include <bcrypt.h>
#pragma comment(lib,"bcrypt.lib")
#include "NativePins.h"
#if !defined(_MSC_VER) || !defined(_M_X64)
#error This source requires MSVC x64 and the reviewed Windows x64 ABI.
#endif
static_assert(sizeof(void*)==8);

struct lua_State;
using LuaCFunction=int(__cdecl*)(lua_State*);
struct ModApi {
    std::uint64_t version;
    std::uint8_t gameVariant;
    void*(__cdecl* GetGameHandle)();
    std::uint64_t(__cdecl* GetSymbolAddress)(const char*);
}; // Exact existing IModApi prefix; no access beyond these members.
namespace {
void trace(const char* event,const char* detail,std::uintptr_t value=0) noexcept {
    HMODULE own=nullptr;
    if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&trace),&own)) return;
    wchar_t path[MAX_PATH];DWORD n=GetModuleFileNameW(own,path,MAX_PATH);
    if(!n || n>=MAX_PATH) return;
    while(n && path[n-1]!=L'\\' && path[n-1]!=L'/') --n;
    constexpr wchar_t file[]=L"LocalDuoPersonalRecolorNativeV2-diagnostic.log";
    if(n+sizeof(file)/sizeof(file[0])>MAX_PATH) return;
    std::memcpy(path+n,file,sizeof(file));
    HANDLE output=CreateFileW(path,FILE_APPEND_DATA,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(output==INVALID_HANDLE_VALUE) return;
    char line[512];int count=std::snprintf(line,sizeof(line),"%s | %s | value=0x%llx | tid=%lu\r\n",event,
        detail?detail:"",static_cast<unsigned long long>(value),GetCurrentThreadId());
    if(count>0) {DWORD written;WriteFile(output,line,static_cast<DWORD>(count<sizeof(line)?count:sizeof(line)-1),&written,nullptr);}
    CloseHandle(output);
}
// Reads only this process's fixed refused Intern entry and at most two recognized
// E9/FF25 hops. No OpenProcess/RPM/VirtualProtect, execution, scanning or guard acceptance.
bool diagnosticReadable(std::uintptr_t address,std::size_t size,bool executable) noexcept {
    if(!address || !size || size>512 || address>~std::uintptr_t(0)-size) return false;
    const auto end=address+size;
    for(unsigned regions=0;address<end && regions<4;++regions) {
        MEMORY_BASIC_INFORMATION info{};
        if(!VirtualQuery(reinterpret_cast<const void*>(address),&info,sizeof(info)) ||
           info.State!=MEM_COMMIT || (info.Protect&(PAGE_GUARD|PAGE_NOACCESS))) return false;
        const auto protection=info.Protect&0xff;
        const bool executeRead=protection==PAGE_EXECUTE_READ || protection==PAGE_EXECUTE_READWRITE || protection==PAGE_EXECUTE_WRITECOPY;
        const bool dataRead=protection==PAGE_READONLY || protection==PAGE_READWRITE || protection==PAGE_WRITECOPY;
        if(!executeRead && (executable || !dataRead)) return false;
        auto start=reinterpret_cast<std::uintptr_t>(info.BaseAddress);
        if(info.RegionSize>~std::uintptr_t(0)-start) return false;
        const auto next=start+info.RegionSize;
        if(next<=address) return false;
        address=next<end?next:end;
    }
    return address==end;
}
bool diagnosticRead(std::uintptr_t address,void* output,std::size_t size,bool executable=false) noexcept {
    if(!diagnosticReadable(address,size,executable)) return false;
    std::memcpy(output,reinterpret_cast<const void*>(address),size);return true;
}
void diagnosticImage(std::uintptr_t address) noexcept {
    MEMORY_BASIC_INFORMATION info{};
    if(!VirtualQuery(reinterpret_cast<const void*>(address),&info,sizeof(info))) return;
    trace("intern-memory-type","VirtualQuery.Type",info.Type);
    trace("intern-memory-protection","VirtualQuery.Protect",info.Protect);
    const auto image=reinterpret_cast<std::uintptr_t>(info.AllocationBase);
    trace("intern-allocation-base","VirtualQuery.AllocationBase",image);
    if(info.Type!=MEM_IMAGE) {trace("intern-image-owner","not a loaded image");return;}
    wchar_t path[MAX_PATH];const DWORD n=GetModuleFileNameW(reinterpret_cast<HMODULE>(image),path,MAX_PATH);
    if(!n || n>=MAX_PATH) {trace("intern-image-owner","module path unavailable");return;}
    char utf8[1024];const int count=WideCharToMultiByte(CP_UTF8,0,path,static_cast<int>(n),utf8,sizeof(utf8)-1,nullptr,nullptr);
    if(count>0) {utf8[count]=0;trace("intern-image-owner",utf8,image);}
    IMAGE_DOS_HEADER dos{};
    if(!diagnosticRead(image,&dos,sizeof(dos)) || dos.e_magic!=IMAGE_DOS_SIGNATURE ||
       dos.e_lfanew<=0 || dos.e_lfanew>0x1000 || image>~std::uintptr_t(0)-static_cast<unsigned>(dos.e_lfanew)) return;
    IMAGE_NT_HEADERS64 nt{};
    if(!diagnosticRead(image+dos.e_lfanew,&nt,sizeof(nt)) || nt.Signature!=IMAGE_NT_SIGNATURE ||
       nt.OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR64_MAGIC || nt.FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64) return;
    const auto size=nt.OptionalHeader.SizeOfImage;
    if(address<image || address-image>=size) return;
    trace("intern-image-target-rva","address minus actual image base",address-image);
    const auto& directory=nt.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_DEBUG];
    if(!directory.VirtualAddress || directory.VirtualAddress>=size || directory.Size>size-directory.VirtualAddress) return;
    const auto entries=directory.Size/sizeof(IMAGE_DEBUG_DIRECTORY);
    for(std::size_t i=0;i<entries && i<16;++i) {
        IMAGE_DEBUG_DIRECTORY d{};
        if(!diagnosticRead(image+directory.VirtualAddress+i*sizeof(d),&d,sizeof(d))) return;
        if(d.Type!=IMAGE_DEBUG_TYPE_CODEVIEW || d.SizeOfData<24 || d.AddressOfRawData>=size || d.SizeOfData>size-d.AddressOfRawData) continue;
        unsigned char cv[24];
        if(!diagnosticRead(image+d.AddressOfRawData,cv,sizeof(cv)) || std::memcmp(cv,"RSDS",4)) continue;
        GUID guid{};std::uint32_t age=0;std::memcpy(&guid,cv+4,16);std::memcpy(&age,cv+20,4);
        char text[96];std::snprintf(text,sizeof(text),"%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x age=%u",
            static_cast<unsigned>(guid.Data1),static_cast<unsigned>(guid.Data2),static_cast<unsigned>(guid.Data3),
            static_cast<unsigned>(guid.Data4[0]),static_cast<unsigned>(guid.Data4[1]),
            static_cast<unsigned>(guid.Data4[2]),static_cast<unsigned>(guid.Data4[3]),
            static_cast<unsigned>(guid.Data4[4]),static_cast<unsigned>(guid.Data4[5]),
            static_cast<unsigned>(guid.Data4[6]),static_cast<unsigned>(guid.Data4[7]),age);
        trace("intern-image-codeview",text,image);return;
    }
}
bool diagnosticRelative(std::uintptr_t address,unsigned length,std::int32_t displacement,std::uintptr_t& output) noexcept {
    if(address>~std::uintptr_t(0)-length) return false;
    const auto next=address+length;
    const auto distance=displacement<0?static_cast<std::uintptr_t>(-static_cast<std::int64_t>(displacement)):static_cast<std::uintptr_t>(displacement);
    if(displacement<0) {if(next<distance) return false;output=next-distance;}
    else {if(next>~std::uintptr_t(0)-distance) return false;output=next+distance;}
    return output!=0;
}
void diagnoseRefusedIntern(std::uintptr_t entry) noexcept {
    // Called ONLY from the existing exact-Pins::Intern byte-refusal Init path.
    trace("intern-diagnostic-only","refusal remains; max 2 recognized jump hops",entry);
    auto address=entry;
    std::uintptr_t previous[3]{};
    for(unsigned hop=0;hop<3;++hop) {
        for(unsigned j=0;j<hop;++j) if(previous[j]==address) {trace("intern-diagnostic-stop","jump cycle",address);return;}
        previous[hop]=address;
        unsigned char bytes[32];
        if(!diagnosticRead(address,bytes,sizeof(bytes),true)) {trace("intern-diagnostic-stop","unreadable/nonexecutable code",address);return;}
        char hex[96];constexpr char digits[]="0123456789abcdef";
        for(unsigned i=0;i<32;++i) {hex[i*3]=digits[bytes[i]>>4];hex[i*3+1]=digits[bytes[i]&15];hex[i*3+2]=i==31?0:' ';}
        trace("intern-code32",hex,address);trace("intern-hop-index","observation only",hop);
        diagnosticImage(address);
        if(hop==2) {trace("intern-diagnostic-stop","bounded hop limit",address);return;}
        std::uintptr_t target=0;
        if(bytes[0]==0xe9) {
            std::int32_t displacement;std::memcpy(&displacement,bytes+1,4);
            if(!diagnosticRelative(address,5,displacement,target)) return;
            trace("intern-jump-e9","decoded relative destination",target);
        } else if(bytes[0]==0xff && bytes[1]==0x25) {
            std::int32_t displacement;std::memcpy(&displacement,bytes+2,4);
            std::uintptr_t slot=0;
            if(!diagnosticRelative(address,6,displacement,slot) || !diagnosticRead(slot,&target,sizeof(target))) {
                trace("intern-diagnostic-stop","unreadable FF25 pointer slot",slot);return;
            }
            trace("intern-jump-ff25-slot","read-only pointer slot",slot);
            trace("intern-jump-ff25-target","decoded indirect destination",target);
        } else {trace("intern-diagnostic-stop","not a recognized E9/FF25 entry",address);return;}
        if(!target) return;
        address=target;
    }
}

constexpr char kGlobal[]="LocalDuoPersonalRecolorInspectV2";
constexpr char kLuaTexture[]="GR2/TheNormalnijMods_Coop_PersonalCrimsonV2_Color512";
constexpr char kNativeTexture[]="GR2\\TheNormalnijMods_Coop_PersonalCrimsonV2_Color512";
constexpr int kRegistry=-1001000, kMainThread=1; // Actual Lua 5.2 constants.
const ModApi* api;
std::uintptr_t base;
lua_State* currentMain;
DWORD createdThread;
bool resolved=false, started=false, registered=false;
struct Handle { std::uint32_t id=0; };
static_assert(sizeof(Handle)==4);
using Lookup=Handle*(__fastcall*)(void*,Handle*,std::uint32_t,const char*,bool);
Lookup lookup;
std::uint32_t(__cdecl* internName)(const char*,std::uint64_t);
void** instance;
const std::uint32_t* missingGuid;
bool(__fastcall* valid)(const Handle*);
void*(__fastcall* texture)(Handle*);
int(__fastcall* width)(const Handle*);
int(__fastcall* height)(const Handle*);
int(__cdecl* getTop)(lua_State*);
void(__cdecl* setTop)(lua_State*,int);
void(__cdecl* rawGetI)(lua_State*,int,int);
lua_State*(__cdecl* toThread)(lua_State*,int);
void(__cdecl* pushClosure)(lua_State*,LuaCFunction,int);
void(__cdecl* setGlobal)(lua_State*,const char*);
void(__cdecl* createTable)(lua_State*,int,int);
void(__cdecl* pushBool)(lua_State*,int);
void(__cdecl* pushInt)(lua_State*,std::ptrdiff_t);
const char*(__cdecl* pushString)(lua_State*,const char*,std::size_t);
void(__cdecl* setField)(lua_State*,int,const char*);

bool buildMatches() {
    if (!base) return false;
    auto dos=reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>0x1000) return false;
    auto nt=reinterpret_cast<const IMAGE_NT_HEADERS64*>(base+dos->e_lfanew);
    if(nt->Signature!=IMAGE_NT_SIGNATURE || nt->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64 ||
       nt->OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR64_MAGIC) return false;
    const auto size=nt->OptionalHeader.SizeOfImage;
    const auto& entry=nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_DEBUG];
    if(!entry.VirtualAddress || entry.Size<sizeof(IMAGE_DEBUG_DIRECTORY) ||
       entry.VirtualAddress>=size || entry.Size>size-entry.VirtualAddress) return false;
    auto debug=reinterpret_cast<const IMAGE_DEBUG_DIRECTORY*>(base+entry.VirtualAddress);
    constexpr unsigned char guid[]={0x5b,0xd0,0x00,0x0d,0x96,0xe7,0x16,0x4b,0xb4,0x4c,0xa1,0x31,0x53,0x5c,0xac,0xab};
    for(std::size_t i=0;i<entry.Size/sizeof(*debug);++i) {
        const auto& d=debug[i];
        if(d.Type!=IMAGE_DEBUG_TYPE_CODEVIEW || d.SizeOfData<24 || d.AddressOfRawData>=size ||
           d.SizeOfData>size-d.AddressOfRawData) continue;
        auto cv=reinterpret_cast<const unsigned char*>(base+d.AddressOfRawData);
        std::uint32_t age;std::memcpy(&age,cv+20,4);
        if(!std::memcmp(cv,"RSDS",4) && !std::memcmp(cv+4,guid,16) && age==1) return true;
    }
    return false;
}
// Narrow compatibility with ONE primary-source ROM detour actually observed.
// No detour is executed here. The returned callable remains the original entry,
// so legitimate ROM interning/extended tables are preserved rather than bypassed.
bool romDiskSHA256(const wchar_t* path) noexcept {
    constexpr unsigned char expected[]={0x0e,0xc3,0x82,0x38,0xee,0xbb,0x00,0x37,0x40,0xed,0x31,0x1f,0xcf,0xa4,0xec,0xdf,0xba,0x25,0x9f,0x36,0x75,0xa9,0xaa,0xb4,0x46,0x10,0x43,0x67,0xe4,0xae,0xa9,0x4d};
    HANDLE file=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_FLAG_SEQUENTIAL_SCAN,nullptr);
    if(file==INVALID_HANDLE_VALUE) return false;
    LARGE_INTEGER size{};
    if(!GetFileSizeEx(file,&size) || size.QuadPart!=11691520ull) {CloseHandle(file);return false;}
    BCRYPT_ALG_HANDLE algorithm=nullptr;BCRYPT_HASH_HANDLE hash=nullptr;
    bool ok=BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_SHA256_ALGORITHM,nullptr,0)>=0;
    if(ok) ok=BCryptCreateHash(algorithm,&hash,nullptr,0,nullptr,0,0)>=0;
    unsigned char buffer[16384];DWORD got=0;
    std::uint64_t total=0;
    while(ok) {
        if(!ReadFile(file,buffer,sizeof(buffer),&got,nullptr)) {ok=false;break;}
        if(!got) break;
        total+=got;
        if(total>11691520ull || BCryptHashData(hash,buffer,got,0)<0) {ok=false;break;}
    }
    unsigned char digest[32]{};
    if(ok) ok=total==11691520ull && BCryptFinishHash(hash,digest,sizeof(digest),0)>=0 && !std::memcmp(digest,expected,sizeof(expected));
    if(hash) BCryptDestroyHash(hash);
    if(algorithm) BCryptCloseAlgorithmProvider(algorithm,0);
    CloseHandle(file);return ok;
}
bool exactRomCodeView(std::uintptr_t image,std::uintptr_t target) noexcept {
    IMAGE_DOS_HEADER dos{};IMAGE_NT_HEADERS64 nt{};
    if(!diagnosticRead(image,&dos,sizeof(dos)) || dos.e_magic!=IMAGE_DOS_SIGNATURE || dos.e_lfanew<=0 || dos.e_lfanew>0x1000 ||
       !diagnosticRead(image+dos.e_lfanew,&nt,sizeof(nt)) || nt.Signature!=IMAGE_NT_SIGNATURE ||
       nt.OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR64_MAGIC || nt.FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64) return false;
    const auto size=nt.OptionalHeader.SizeOfImage;
    if(target<image || target-image!=0x29caf0 || target-image>=size) return false;
    const auto& d=nt.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_DEBUG];
    if(!d.VirtualAddress || d.VirtualAddress>=size || d.Size>size-d.VirtualAddress) return false;
    constexpr unsigned char guid[]={0xea,0x95,0xbc,0x1f,0x35,0x82,0x11,0x4d,0x9c,0x25,0x2b,0x36,0x66,0xdd,0xf2,0x72};
    for(std::size_t i=0;i<d.Size/sizeof(IMAGE_DEBUG_DIRECTORY) && i<16;++i) {
        IMAGE_DEBUG_DIRECTORY entry{};
        if(!diagnosticRead(image+d.VirtualAddress+i*sizeof(entry),&entry,sizeof(entry))) return false;
        if(entry.Type!=IMAGE_DEBUG_TYPE_CODEVIEW || entry.SizeOfData<24 || entry.AddressOfRawData>=size || entry.SizeOfData>size-entry.AddressOfRawData) continue;
        unsigned char cv[24];std::uint32_t age=0;
        if(!diagnosticRead(image+entry.AddressOfRawData,cv,sizeof(cv))) return false;
        std::memcpy(&age,cv+20,4);
        if(!std::memcmp(cv,"RSDS",4) && !std::memcmp(cv+4,guid,16) && age==1) return true;
    }
    return false;
}
bool exactRomInternDetour(std::uintptr_t entry) noexcept {
    constexpr unsigned char stock32[]={0x48,0x89,0x5c,0x24,0x18,0x48,0x89,0x6c,0x24,0x20,0x56,0x57,0x41,0x54,0x41,0x56,0x41,0x57,0x48,0x83,0xec,0x40,0x48,0x8b,0xda,0x48,0x8b,0xe9,0x48,0x85,0xc9,0x0f};
    constexpr unsigned char target32[]={0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c,0x24,0x10,0x56,0x57,0x41,0x56,0x48,0x83,0xec,0x20,0x48,0x8b,0xda,0x48,0x8b,0xf1,0x4c,0x8d,0x35,0xb1,0x66,0x82,0x00,0x4c};
    constexpr unsigned char patchedTail[]={0x89,0x6c,0x66,0x90};
    unsigned char actual[32];MEMORY_BASIC_INFORMATION origin{};
    if(!VirtualQuery(reinterpret_cast<const void*>(entry),&origin,sizeof(origin)) || origin.Type!=MEM_IMAGE ||
       reinterpret_cast<std::uintptr_t>(origin.AllocationBase)!=base || entry!=base+Pins::Intern.rva ||
       !diagnosticRead(entry,actual,sizeof(actual),true) || actual[0]!=0xff || actual[1]!=0x25 ||
       std::memcmp(actual+6,patchedTail,sizeof(patchedTail)) || std::memcmp(actual+10,stock32+10,22)) return false;
    std::int32_t relative;std::memcpy(&relative,actual+2,4);
    std::uintptr_t slot=0,target=0;
    if(!diagnosticRelative(entry,6,relative,slot) || !diagnosticRead(slot,&target,sizeof(target))) return false;
    MEMORY_BASIC_INFORMATION owner{};
    if(!VirtualQuery(reinterpret_cast<const void*>(target),&owner,sizeof(owner)) || owner.Type!=MEM_IMAGE) return false;
    const auto image=reinterpret_cast<std::uintptr_t>(owner.AllocationBase);
    if(!exactRomCodeView(image,target)) return false;
    unsigned char body[32];
    if(!diagnosticRead(target,body,sizeof(body),true) || std::memcmp(body,target32,sizeof(body))) return false;
    wchar_t gamePath[MAX_PATH],romPath[MAX_PATH];
    const DWORD gn=GetModuleFileNameW(reinterpret_cast<HMODULE>(base),gamePath,MAX_PATH);
    const DWORD rn=GetModuleFileNameW(reinterpret_cast<HMODULE>(image),romPath,MAX_PATH);
    if(!gn || gn>=MAX_PATH || !rn || rn>=MAX_PATH) return false;
    DWORD slash=gn;while(slash && gamePath[slash-1]!=L'\\' && gamePath[slash-1]!=L'/') --slash;
    constexpr wchar_t name[]=L"d3d12.dll";
    if(!slash || slash+sizeof(name)/sizeof(name[0])>MAX_PATH) return false;
    std::memcpy(gamePath+slash,name,sizeof(name));
    if(CompareStringOrdinal(gamePath,-1,romPath,-1,TRUE)!=CSTR_EQUAL || !romDiskSHA256(romPath)) return false;
    // Do not accept a changed pointer or bytes after file hashing. No cached lease.
    std::uintptr_t recheck=0;unsigned char entryAgain[32],targetAgain[32];
    if(!diagnosticRead(slot,&recheck,sizeof(recheck)) || recheck!=target ||
       !diagnosticRead(entry,entryAgain,sizeof(entryAgain),true) || std::memcmp(entryAgain,actual,sizeof(actual)) ||
       !diagnosticRead(target,targetAgain,sizeof(targetAgain),true) || std::memcmp(targetAgain,target32,sizeof(target32))) return false;
    trace("intern-rom-recognized","fixed ROM SHA/CodeView/RVA/prologue and exact FF25 patch",target);
    return true;
}

std::uintptr_t resolve(const Pins::Symbol& pin) {
    auto p=static_cast<std::uintptr_t>(api->GetSymbolAddress(pin.name));
    if(p!=base+pin.rva) {trace("resolve-rva-refused",pin.name,p);return 0;}
    if(pin.code && std::memcmp(reinterpret_cast<void*>(p),pin.bytes,sizeof(pin.bytes))) {
        if(&pin==&Pins::Intern && exactRomInternDetour(p)) return p;
        trace("resolve-bytes-refused",pin.name,p);
        if(&pin==&Pins::Intern) diagnoseRefusedIntern(p);
        return 0;
    }
    return p;
}
template<class T> bool bind(T& out,const Pins::Symbol& pin) {
    out=reinterpret_cast<T>(resolve(pin));return out!=nullptr;
}
void boolean(lua_State* L,const char* key,bool value) {pushBool(L,value?1:0);setField(L,-2,key);}
void integer(lua_State* L,const char* key,int value) {pushInt(L,value);setField(L,-2,key);}
void string(lua_State* L,const char* key,const char* value) {pushString(L,value,std::strlen(value));setField(L,-2,key);}

int __cdecl inspect(lua_State* L) {
    // Single synchronous observation only. Lua's reviewed resource posthook is
    // the sole authored caller; it captures this closure privately during Bind.
    const int top=getTop(L);
    bool context=false;
    if(resolved && started && L && currentMain && GetCurrentThreadId()==createdThread && top==0) {
        rawGetI(L,kRegistry,kMainThread);
        context=toThread(L,-1)==currentMain;
        setTop(L,top);
    }
    bool handleValid=false,fallback=true,resourcePresent=false;
    int w=0,h=0;
    if(context && instance && *instance && missingGuid) {
        void* manager=*instance;
        // Intern the fixed package spelling; package AD names use backslashes.
        // Native hash GUIDs are intern IDs, not guessed CRC/FNV values.
        const auto id=internName(kNativeTexture,sizeof(kNativeTexture)-1);
        Handle own{},missing{};
        lookup(manager,&own,id,kNativeTexture,false);
        lookup(manager,&missing,*missingGuid,nullptr,false);
        handleValid=valid(&own);
        const bool missingValid=valid(&missing);
        void* object=handleValid?texture(&own):nullptr;
        void* missingObject=missingValid?texture(&missing):nullptr;
        // Require the actual fallback object too: unknown fallback is refusal.
        fallback=!missingValid || !missingObject || own.id==missing.id || object==missingObject;
        if(handleValid && object && !fallback && *instance==manager) {
            w=width(&own);h=height(&own);
            void* forgeResource=nullptr;
            std::memcpy(&forgeResource,static_cast<unsigned char*>(object)+120,sizeof(forgeResource));
            if(forgeResource) {
                std::uintptr_t descriptor=0;void* dxResource=nullptr;
                std::memcpy(&descriptor,forgeResource,sizeof(descriptor));
                std::memcpy(&dxResource,static_cast<unsigned char*>(forgeResource)+8,sizeof(dxResource));
                resourcePresent=dxResource && descriptor && descriptor!=~std::uintptr_t(0);
            }
            // No handle retained beyond this callback. Recheck native generation
            // and pointer after the bounded observations; no unload/free calls.
            handleValid=valid(&own) && texture(&own)==object && *instance==manager;
            if(!handleValid) resourcePresent=false;
        }
    }
    trace("inspect-context",context?"accepted":"refused",reinterpret_cast<std::uintptr_t>(currentMain));
    trace("inspect-observation",fallback?"fallback-or-unknown":"private-object",
        (handleValid?1u:0u)|(resourcePresent?2u:0u));
    trace("inspect-dimensions","width-high32-height-low32",(static_cast<std::uintptr_t>(static_cast<std::uint32_t>(w))<<32)|static_cast<std::uint32_t>(h));
    setTop(L,top);
    createTable(L,0,9);
    boolean(L,"ContextValid",context);
    boolean(L,"HandleValid",handleValid);
    boolean(L,"Fallback",fallback);
    boolean(L,"ResourcePresent",resourcePresent);
    integer(L,"Width",w);integer(L,"Height",h);
    string(L,"TextureName",kLuaTexture);
    boolean(L,"NativeVisualValidated",false);
    // NativeLoadReturned is deliberately NOT fabricated here. Lua records that
    // its actual protected stock LoadPackages call returned before inspection.
    return 1;
}
}
extern "C" __declspec(dllexport) bool __cdecl HadesModInit(const ModApi* value) {
    api=value;
    trace("init","API version",api?api->version:0);    if(!api || api->version<1 || !api->GetGameHandle || !api->GetSymbolAddress) return false;
    base=reinterpret_cast<std::uintptr_t>(api->GetGameHandle());
    trace("game-base","GetGameHandle actual",base);
    if(!buildMatches()) {trace("build-refused","CodeView/build check");return false;}
    resolved=bind(internName,Pins::Intern) && bind(instance,Pins::AssetInstance) && bind(missingGuid,Pins::MissingGuid) &&
        bind(lookup,Pins::GetTexture) && bind(valid,Pins::IsValid) && bind(texture,Pins::HandleTexture) &&
        bind(width,Pins::Width) && bind(height,Pins::Height) && bind(getTop,Pins::GetTop) && bind(setTop,Pins::SetTop) &&
        bind(rawGetI,Pins::RawGetI) && bind(toThread,Pins::ToThread) && bind(pushClosure,Pins::PushClosure) &&
        bind(setGlobal,Pins::SetGlobal) && bind(createTable,Pins::CreateTable) && bind(pushBool,Pins::PushBool) &&
        bind(pushInt,Pins::PushInt) && bind(pushString,Pins::PushString) && bind(setField,Pins::SetField);
    trace("init-result","resolved",resolved?1:0);
    return resolved; // Resolves only. No texture, string intern or asset-manager query.
}
extern "C" __declspec(dllexport) bool __cdecl HadesModStart() {started=resolved;trace("start","resolved",started?1:0);return started;}
extern "C" __declspec(dllexport) void __cdecl HadesModLuaCreated(lua_State* L) {
    currentMain=nullptr;createdThread=0;
    trace("lua-created","actual state",reinterpret_cast<std::uintptr_t>(L));
    if(!resolved || !started || !L) {trace("lua-created-refused","state/start unavailable");return;}
    const int top=getTop(L);
    rawGetI(L,kRegistry,kMainThread);
    lua_State* main=toThread(L,-1);
    setTop(L,top);
    if(main!=L) {trace("lua-created-refused","registry main differs",reinterpret_cast<std::uintptr_t>(main));return;}
    currentMain=main;createdThread=GetCurrentThreadId();
    pushClosure(L,inspect,0);setGlobal(L,kGlobal);setTop(L,top);
    registered=true;trace("lua-registered","actual main state",reinterpret_cast<std::uintptr_t>(currentMain));
}
extern "C" __declspec(dllexport) bool __cdecl HadesModStop() {
    // Lua can retain our closure. Never let the loader unload this DLL beneath it.
    if(registered) return false; // Normal game restart required, no forced cleanup.
    started=false;return true;
}
