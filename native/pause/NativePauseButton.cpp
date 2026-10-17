// Isolated native button candidate. Source-ready is not native validation.
// Only actual PauseScreen vft entries are changed. No ASI replacement or inline detour.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstring>
#include <cstdio>
#include <memory>
#include <atomic>
#include <mutex>
#include <unordered_map>
#include <HookTable.h>
#include "ABIContract.h"
#include "PrivateForgeAllocator.h"
extern "C" {
#include <lua.h>
}

struct ModApi {
    std::uint64_t version;
    std::uint8_t gameVariant;
    void* (__cdecl* GetGameHandle)();
    std::uint64_t (__cdecl* GetSymbolAddress)(const char*);
};
namespace {
// Bounded diagnostic only. No logger thread, gameplay state, overlay or native-pass claim.
volatile LONG diagnosticBits;
void trace(const char* event, const char* detail, std::uintptr_t value = 0) noexcept {
    HMODULE ownModule = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&trace), &ownModule)) return;
    wchar_t path[MAX_PATH];
    const DWORD length = GetModuleFileNameW(ownModule, path, MAX_PATH);
    if (!length || length >= MAX_PATH) return;
    DWORD slash = length;
    while (slash && path[slash - 1] != L'\\' && path[slash - 1] != L'/') --slash;
    constexpr wchar_t file[] = L"LocalDuoPauseNative-diagnostic.log";
    if (slash + sizeof(file) / sizeof(file[0]) > MAX_PATH) return;
    std::memcpy(path + slash, file, sizeof(file));
    HANDLE output = CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (output == INVALID_HANDLE_VALUE) return;
    char line[768];
    const int size = std::snprintf(line, sizeof(line), "%s | %s | value=0x%llx | tid=%lu\r\n",
        event, detail ? detail : "", static_cast<unsigned long long>(value), GetCurrentThreadId());
    if (size > 0) { DWORD written; WriteFile(output, line,
        static_cast<DWORD>(size < sizeof(line) ? size : sizeof(line) - 1), &written, nullptr); }
    CloseHandle(output);
}
void traceOnce(LONG bit, const char* event, const char* detail, std::uintptr_t value = 0) noexcept {
    if (!(InterlockedOr(&diagnosticBits, bit) & bit)) trace(event, detail, value);
}
const ModApi* api;
std::uintptr_t gameBase;
volatile LONG ownerThread;
bool installed;
const char* lastError = "Not initialized";
using UpdateFn = void (__fastcall*)(NativePauseLayout*, float, const void*);
using UnaryFn = void (__fastcall*)(NativePauseLayout*);
using DestructorFn = void* (__fastcall*)(NativePauseLayout*, unsigned int);
UpdateFn originalUpdate;
UnaryFn originalExit, originalClear;
UnaryFn nativeResume; // Exact resolved PauseScreen::Resume; not an Exit/GiveUp imitation.
DestructorFn originalDestructor;
using ContainerDestructorFn = void* (__fastcall*)(void*, unsigned int);
ContainerDestructorFn originalContainerDestructor;
using AllocateFn = void* (__cdecl*)(std::size_t, std::size_t);
AllocateFn allocateGame;
using ButtonCtorFn = sgg::GUIComponentButton* (__fastcall*)(void*, sgg::MenuScreen*);
ButtonCtorFn constructButton;
lua_State** mainLua;
int (__cdecl* getTop)(lua_State*);
void (__cdecl* setTop)(lua_State*, int);
void (__cdecl* getGlobal)(lua_State*, const char*);
int (__cdecl* luaType)(lua_State*, int);
int (__cdecl* toBoolean)(lua_State*, int);
int (__cdecl* protectedCall)(lua_State*, int, int, int, int, lua_CFunction);

struct Record {
    NativePauseLayout* menu;
    sgg::GUIComponentButton* button = nullptr;
    std::uint64_t buttonId = 0;
    std::atomic<bool> alive{true}, exiting{false}, nativeDestroyed{false};
    bool callbacksCleared = false;
    bool ownCallbackAdded = false;
    bool queued = false, requested = false, createAttempted = false;
};
std::unordered_map<NativePauseLayout*, std::shared_ptr<Record>> records;
std::recursive_mutex recordMutex;
struct Slot {
    void* volatile* address = nullptr;
    void* original = nullptr;
    void* wrapper = nullptr;
    bool owned = false;
};
Slot slots[5];
struct ActionPointers { void* begin; void* end; void* capacity; };
static_assert(sizeof(ActionPointers) == sizeof(sgg::GUIAction));
ActionPointers actionPointers(sgg::GUIAction& action) {
    ActionPointers pointers; std::memcpy(&pointers, &action, sizeof(pointers)); return pointers;
}
bool actionEmpty(sgg::GUIAction& action) {
    const auto p = actionPointers(action); return !p.begin && !p.end && !p.capacity;
}
bool ownedActionStorage(sgg::GUIAction& action) {
    const auto p = actionPointers(action);
    const auto begin = reinterpret_cast<std::uintptr_t>(p.begin), end = reinterpret_cast<std::uintptr_t>(p.end);
    const auto capacity = reinterpret_cast<std::uintptr_t>(p.capacity);
    return begin && begin <= end && end <= capacity && (end - begin) % sizeof(eastl::function<void()>) == 0 &&
        (capacity - begin) % sizeof(eastl::function<void()>) == 0 && PauseAllocator::OwnsRange(p.begin, capacity - begin);
}

std::uintptr_t resolve(const char* name) {
    const auto value = api ? static_cast<std::uintptr_t>(api->GetSymbolAddress(name)) : 0;
    trace("resolve", name, value); // Startup-only calls; exact actual symbol and returned value.
    return value;
}
bool owner() { return GetCurrentThreadId() == static_cast<DWORD>(InterlockedCompareExchange(&ownerThread, 0, 0)); }
bool actualPause(NativePauseLayout* menu) {
    // Called only at actual native vft entry, or while retained lifecycle is alive.
    return menu && *reinterpret_cast<std::uintptr_t*>(menu) == gameBase + PauseBuild::VTableRVA;
}
std::uint64_t componentId(sgg::GUIComponentButton* button) {
    std::uint64_t id;
    std::memcpy(&id, reinterpret_cast<const unsigned char*>(button) + PauseBuild::NativeComponentIdOffset, sizeof(id));
    return id; // Native field read on a currently parent-registered component, never a generated receipt.
}
bool current(const std::shared_ptr<Record>& record) {
    std::lock_guard<std::recursive_mutex> lock(recordMutex);
    if (!record || !record->alive || record->exiting) return false;
    const auto it = records.find(record->menu);
    return it != records.end() && it->second == record && actualPause(record->menu);
}
bool callBool(const char* name) {
    if (!owner() || !mainLua || !*mainLua) {
        traceOnce(1, "lua-unavailable", name, reinterpret_cast<std::uintptr_t>(mainLua)); return false;
    }
    lua_State* state = *mainLua;
    const int top = getTop(state);
    getGlobal(state, name);
    if (luaType(state, -1) != LUA_TFUNCTION) {
        traceOnce(2, "lua-global-not-function", name, static_cast<std::uintptr_t>(luaType(state, -1)));
        setTop(state, top); return false;
    }
    const int result = protectedCall(state, 0, 1, 0, 0, nullptr);
    const bool accepted = result == LUA_OK && luaType(state, -1) == LUA_TBOOLEAN && toBoolean(state, -1) != 0;
    if (result != LUA_OK) traceOnce(4, "lua-pcall-error", name, static_cast<std::uintptr_t>(result));
    else if (luaType(state, -1) != LUA_TBOOLEAN) traceOnce(8, "lua-result-not-boolean", name, static_cast<std::uintptr_t>(luaType(state, -1)));
    else if (!accepted) traceOnce(16, "lua-actual-false", name);
    else traceOnce(32, "lua-actual-true", name);
    setTop(state, top);
    return accepted; // No fallback, extra Lua API, direct death, or native pause-close imitation.
}
void retire(NativePauseLayout* menu, bool destroying) noexcept {
    std::lock_guard<std::recursive_mutex> lock(recordMutex);
    const auto it = records.find(menu);
    if (it == records.end()) return;
    const auto record = it->second;
    record->alive = false; record->exiting = true;
    if (record->nativeDestroyed) return; // Unknown destruction retained: never inspect a freed self.
    if (!owner()) {
        if (destroying) record->nativeDestroyed = true;
        lastError = "Foreign-thread Pause lifecycle; own cleanup remains quarantined";
        return; // Invalidate before native base, but do not touch a component from the wrong UI thread.
    }
    record->queued = false;
    if (record->button && record->ownCallbackAdded && !record->callbacksCleared) {
        // Before actual Exit/Clear/dtor; never touch stock callbacks or Destroy a component.
        if (menu->GetComponentPosition(record->button) != INVALID_COMPONENT_POS && componentId(record->button) == record->buttonId) {
            auto& action = record->button->GetActivateAction();
            if (actionEmpty(action)) record->callbacksCleared = true;
            else if (ownedActionStorage(action)) {
                action.RemoveAll(); // Own functor destructors + own allocator, before native Exit/Clear/dtor.
                record->callbacksCleared = actionEmpty(action);
                if (!record->callbacksCleared) lastError = "Own callback vector did not become empty";
            } else lastError = "Own callback vector storage changed; refuse foreign deallocation";
        } else {
            lastError = "Own native button left its parent before lifecycle cleanup";
            // Unknown ownership is not authority to dereference or free the stale pointer.
        }
    }
    if (destroying) {
        record->nativeDestroyed = true;
        if (!record->ownCallbackAdded || record->callbacksCleared) records.erase(it);
        // A foreign component removal retains the record and blocks DLL unload; no guessed cleanup.
    }
}
void addButton(const std::shared_ptr<Record>& record) {
    if (!current(record) || record->createAttempted || !callBool("LocalDuoPauseCanEndRun") || !current(record)) return;
    record->createAttempted = true;
    auto* menu = record->menu;
    auto* resume = menu->resumeButton;
    auto* settings = menu->settingsButton;
    auto* giveUp = menu->giveUpButton;
    if (!resume || !settings || !giveUp || settings == giveUp ||
        menu->GetComponentPosition(resume) == INVALID_COMPONENT_POS ||
        menu->GetComponentPosition(settings) == INVALID_COMPONENT_POS ||
        menu->GetComponentPosition(giveUp) == INVALID_COMPONENT_POS) {
        lastError = "Actual native Pause template components unavailable"; return;
    }
    // Read positions only after proving both real stock buttons belong to this Pause.
    const auto settingsPosition = settings->GetLocation();
    const auto giveUpPosition = giveUp->GetLocation();
    const auto finite = [](float value) noexcept {
        return value == value && value >= -3.402823466e+38F && value <= 3.402823466e+38F;
    };
    if (!finite(settingsPosition.mX) || !finite(settingsPosition.mY) ||
        !finite(giveUpPosition.mX) || !finite(giveUpPosition.mY) ||
        giveUpPosition.mY <= settingsPosition.mY) {
        lastError = "Actual native Pause Settings/GiveUp gap unavailable"; return;
    }
    auto position = settingsPosition;
    position.mX = settingsPosition.mX * 0.5f + giveUpPosition.mX * 0.5f;
    position.mY = settingsPosition.mY * 0.5f + giveUpPosition.mY * 0.5f;
    if (!finite(position.mX) || !finite(position.mY) ||
        position.mY <= settingsPosition.mY || position.mY >= giveUpPosition.mY) {
        lastError = "Actual native Pause gap has no representable midpoint"; return;
    }
    void* memory = allocateGame(sizeof(sgg::GUIComponentButton), alignof(sgg::GUIComponentButton));
    if (!memory) { lastError = "Native button allocation failed"; return; }
    auto* button = constructButton(memory, menu);
    if (!button || button != memory) { lastError = "Native button constructor identity mismatch"; return; }
    // Preserve component ownership before configuring. Native Clear/dtor remains its disposer.
    record->button = button;
    button->SetParent(menu);
    menu->AddComponent(button);
    button->Load(&resume->GetComponentData());
    record->buttonId = componentId(button);
    if (!actionEmpty(button->GetActivateAction())) {
        button->Disable(); lastError = "Native constructor provided nonempty action; do not adopt foreign storage"; return;
    }
    button->SetLocation(position);
    button->SetText("Encerrar corrida");
    struct QueueIntent {
        std::weak_ptr<Record> weak;
        void operator()() const noexcept {
            if (!owner()) return;
            if (auto r = weak.lock()) {
                if (r->alive && !r->exiting && !r->requested) r->queued = true;
            }
        }
        // No Lua close/death while the native Action list is being iterated.
    };
    static_assert(eastl::internal::is_functor_inplace_allocatable<QueueIntent, EASTL_FUNCTION_DEFAULT_CAPTURE_SSO_SIZE>::value,
        "Callback capture must use the verified inline EASTL storage, no hidden heap functor");
    record->ownCallbackAdded = true;
    button->GetActivateAction().AddCallBack(QueueIntent{record});
    if (!ownedActionStorage(button->GetActivateAction())) { button->Disable(); lastError = "Callback allocator ownership unavailable"; return; }
    lastError = nullptr;
}
void __fastcall update(NativePauseLayout* menu, float seconds, const void* inputs) {
    traceOnce(512, "update-hook-entered", "actual native wrapper invocation; not acquisition proof", reinterpret_cast<std::uintptr_t>(menu));
    std::shared_ptr<Record> retained;
    if (installed && actualPause(menu)) InterlockedCompareExchange(&ownerThread, static_cast<LONG>(GetCurrentThreadId()), 0);
    if (owner() && installed && actualPause(menu)) {
        traceOnce(64, "actual-pause-update", "verified actual vft and UI owner thread", reinterpret_cast<std::uintptr_t>(menu));
        try {
            std::lock_guard<std::recursive_mutex> lock(recordMutex);
            const auto it = records.find(menu);
            if (it == records.end()) {
                retained = std::make_shared<Record>(); retained->menu = menu;
                records.emplace(menu, retained);
            } else retained = it->second;
        } catch (...) { lastError = "Pause ownership allocation failed"; }
    }
    originalUpdate(menu, seconds, inputs);
    // Original Update may close/clear/destroy. Its hooks invalidate retained BEFORE native base.
    // current() checks the live record first; never dereference a dead self after the base call.
    if (!owner() || !current(retained)) return;
    try {
        addButton(retained);
        if (retained->createAttempted && lastError) traceOnce(128, "button-create-failed", lastError);
        else if (retained->button && retained->ownCallbackAdded) traceOnce(256, "button-created", "actual parent-registered button, callback added; not pixel proof", retained->buttonId);
        if (!current(retained) || !retained->queued || retained->requested) return;
        retained->queued = false;
        if (!callBool("LocalDuoPauseCanEndRun") || !current(retained)) return;
        // Prove that native Resume is available BEFORE arming the Lua intent.
        auto* resume = retained->menu->resumeButton;
        if (!nativeResume || !resume || retained->menu->GetComponentPosition(resume) == INVALID_COMPONENT_POS || !resume->IsUseable()) {
            lastError = "Actual native Resume is unavailable"; return;
        }
        retained->requested = true;
        const bool accepted = callBool("LocalDuoPauseRequestEndRun");
        if (!accepted) {
            if (retained->alive && !retained->exiting) retained->requested = false;
            return;
        }
        if (!current(retained) || !callBool("LocalDuoPauseCanResumeEndRun") || !current(retained)) return;
        if (retained->menu->resumeButton != resume || retained->menu->GetComponentPosition(resume) == INVALID_COMPONENT_POS || !resume->IsUseable()) {
            lastError = "Actual native Resume changed after Lua intent"; return;
        }
        const auto requestedMenu = reinterpret_cast<std::uintptr_t>(retained->menu);
        nativeResume(retained->menu); // Actual stock Resume after native input/action iteration.
        // Resume can synchronously Exit/Clear/destroy. Never inspect menu/button after this call.
        traceOnce(2048, "native-resume-returned", "stock Resume returned; close/unpause/death still require their real callbacks", requestedMenu);
    } catch (...) { lastError = "Own Pause button update failed";
        traceOnce(1024, "update-exception", lastError); }
}
void __fastcall exitScreen(NativePauseLayout* menu) { retire(menu, false); originalExit(menu); }
void __fastcall clearScreen(NativePauseLayout* menu) { retire(menu, false); originalClear(menu); }
void* __fastcall destroyScreen(NativePauseLayout* menu, unsigned int flags) {
    retire(menu, true);
    return originalDestructor(menu, flags);
}
void* __fastcall destroyContainer(void* container, unsigned int flags) {
    // Matching PDB/PE thunk: sub rcx,0x50; jmp Pause scalar-deleting-dtor.
    auto* menu = reinterpret_cast<NativePauseLayout*>(static_cast<unsigned char*>(container) - PauseBuild::ContainerBaseOffset);
    retire(menu, true);
    return originalContainerDestructor(container, flags);
}
bool exchange(Slot& slot, bool install) {
    void* expected = install ? slot.original : slot.wrapper;
    void* next = install ? slot.wrapper : slot.original;
    DWORD oldProtect;
    if (!VirtualProtect(const_cast<void**>(slot.address), sizeof(void*), PAGE_READWRITE, &oldProtect)) return false;
    const auto previous = InterlockedCompareExchangePointer(slot.address, next, expected);
    const bool changed = previous == expected;
    DWORD ignored;
    const bool restored = VirtualProtect(const_cast<void**>(slot.address), sizeof(void*), oldProtect, &ignored) != 0;
    if (changed) slot.owned = install;
    return changed && restored && *slot.address == next;
}
bool buildMatches() {
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(gameBase);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0 || dos->e_lfanew > 0x10000) return false;
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(gameBase + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE || nt->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64 ||
        nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) return false;
    const auto& entry = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_DEBUG];
    if (entry.VirtualAddress >= nt->OptionalHeader.SizeOfImage || entry.Size > 0x10000) return false;
    const auto* debug = reinterpret_cast<const IMAGE_DEBUG_DIRECTORY*>(gameBase + entry.VirtualAddress);
    for (std::size_t i = 0; i < entry.Size / sizeof(*debug); ++i) {
        if (debug[i].Type != IMAGE_DEBUG_TYPE_CODEVIEW || debug[i].SizeOfData < 24 ||
            debug[i].AddressOfRawData + debug[i].SizeOfData > nt->OptionalHeader.SizeOfImage) continue;
        const auto* rsds = reinterpret_cast<const unsigned char*>(gameBase + debug[i].AddressOfRawData);
        if (std::memcmp(rsds, "RSDS", 4) == 0 && std::memcmp(rsds + 4, PauseBuild::CodeViewGUID, 16) == 0 &&
            *reinterpret_cast<const std::uint32_t*>(rsds + 20) == PauseBuild::CodeViewAge) return true;
    }
    return false;
}
bool initializeSymbols() {
    HookTable table{};
    table.luaState = resolve("sgg::ScriptManager::LuaInterface");
    table.vector8x8_push = resolve("?push_back@?$vector@PEAVGUIComponent@sgg@@Vallocator_forge@eastl@@@eastl@@QEAAX$$QEAPEAVGUIComponent@sgg@@@Z");
    table._aligned_malloc = resolve("__imp__aligned_malloc");
    table.GUIComponentButton_GUIComponentButton_MenuScreen = resolve("??0GUIComponentButton@sgg@@QEAA@PEAVMenuScreen@1@@Z");
    mainLua = reinterpret_cast<lua_State**>(table.luaState);
    getTop = reinterpret_cast<decltype(getTop)>(resolve("lua_gettop"));
    setTop = reinterpret_cast<decltype(setTop)>(resolve("lua_settop"));
    getGlobal = reinterpret_cast<decltype(getGlobal)>(resolve("lua_getglobal"));
    luaType = reinterpret_cast<decltype(luaType)>(resolve("lua_type"));
    toBoolean = reinterpret_cast<decltype(toBoolean)>(resolve("lua_toboolean"));
    protectedCall = reinterpret_cast<decltype(protectedCall)>(resolve("lua_pcallk"));
    if (!table.luaState || !table.vector8x8_push || !table._aligned_malloc ||
        !table.GUIComponentButton_GUIComponentButton_MenuScreen || !getTop || !setTop || !getGlobal ||
        !luaType || !toBoolean || !protectedCall) return false;
    allocateGame = *reinterpret_cast<AllocateFn*>(table._aligned_malloc);
    constructButton = reinterpret_cast<ButtonCtorFn>(table.GUIComponentButton_GUIComponentButton_MenuScreen);
    if (!allocateGame) return false;
    HookTable::Instance().Init(table); // This DLL's private SDK table; never another extension's globals.
    return true;
}
bool install() {
    if (installed || !api || !api->GetGameHandle || !api->GetSymbolAddress) return false;
    // Loader thread identity is not UI identity. Pin only the first actual native Pause Update.
    gameBase = reinterpret_cast<std::uintptr_t>(api->GetGameHandle());
    trace("install-game-base", "actual GetGameHandle", gameBase);
    if (!gameBase || !buildMatches() || !initializeSymbols()) { lastError = "Actual native build/API mismatch"; return false; }
    const auto vft = resolve("??_7PauseScreen@sgg@@6BGameScreen@1@@");
    if (vft != gameBase + PauseBuild::VTableRVA) { lastError = "Pause vft symbol mismatch"; return false; }
    const auto containerVft = resolve("??_7PauseScreen@sgg@@6BIGUIComponentContainer@1@@");
    if (containerVft != gameBase + PauseBuild::ContainerVTableRVA) { lastError = "Pause container vft mismatch"; return false; }
    for (const auto& entry : PauseBuild::Entries) if (std::memcmp(reinterpret_cast<const void*>(gameBase + entry.rva), entry.bytes, sizeof(entry.bytes)) != 0) {
        lastError = "Foreign native entry bytes"; return false;
    }
    const auto resumeAddress = resolve("?Resume@PauseScreen@sgg@@QEAAXXZ");
    if (resumeAddress != gameBase + PauseBuild::ResumeRVA) { lastError = "Pause Resume symbol mismatch"; return false; }
    nativeResume = reinterpret_cast<UnaryFn>(resumeAddress); // Entry fingerprint was verified above.
    originalUpdate = reinterpret_cast<UpdateFn>(gameBase + PauseBuild::UpdateRVA);
    originalExit = reinterpret_cast<UnaryFn>(gameBase + PauseBuild::ExitRVA);
    originalClear = reinterpret_cast<UnaryFn>(gameBase + PauseBuild::ClearRVA);
    originalDestructor = reinterpret_cast<DestructorFn>(gameBase + PauseBuild::DestructorRVA);
    originalContainerDestructor = reinterpret_cast<ContainerDestructorFn>(gameBase + PauseBuild::ContainerDestructorRVA);
    slots[0] = {reinterpret_cast<void* volatile*>(vft) + PauseBuild::UpdateSlot, reinterpret_cast<void*>(originalUpdate), reinterpret_cast<void*>(update)};
    slots[1] = {reinterpret_cast<void* volatile*>(vft) + PauseBuild::ExitSlot, reinterpret_cast<void*>(originalExit), reinterpret_cast<void*>(exitScreen)};
    slots[2] = {reinterpret_cast<void* volatile*>(vft) + PauseBuild::ClearSlot, reinterpret_cast<void*>(originalClear), reinterpret_cast<void*>(clearScreen)};
    slots[3] = {reinterpret_cast<void* volatile*>(vft) + PauseBuild::DestructorSlot, reinterpret_cast<void*>(originalDestructor), reinterpret_cast<void*>(destroyScreen)};
    slots[4] = {reinterpret_cast<void* volatile*>(containerVft) + PauseBuild::ContainerDestructorSlot, reinterpret_cast<void*>(originalContainerDestructor), reinterpret_cast<void*>(destroyContainer)};
    for (const auto& slot : slots) if (*slot.address != slot.original) { lastError = "Foreign native vft entry"; return false; }
    for (auto& slot : slots) if (!exchange(slot, true)) {
        for (auto& undo : slots) if (undo.owned) exchange(undo, false);
        lastError = "Native vft CAS/readback failed"; return false;
    }
    installed = true; lastError = nullptr; return true;
}
}
extern "C" __declspec(dllexport) int HadesModInit(const void* value) {
    api = static_cast<const ModApi*>(value);
    trace("init", "actual loader API pointer", reinterpret_cast<std::uintptr_t>(api));
    if (api) { trace("api-version", "actual prefix", api->version);
        trace("api-get-game", "actual function pointer", reinterpret_cast<std::uintptr_t>(api->GetGameHandle));
        trace("api-get-symbol", "actual function pointer", reinterpret_cast<std::uintptr_t>(api->GetSymbolAddress)); }
    return api ? 1 : 0;
}
extern "C" __declspec(dllexport) int HadesModStart() {
    trace("start", "actual loader Start entered");
    const bool result = install();
    trace("install-result", lastError, result ? 1 : 0);
    return result ? 1 : 0;
}
extern "C" __declspec(dllexport) int HadesModStop() {
    std::lock_guard<std::recursive_mutex> lock(recordMutex);
    if ((ownerThread != 0 && !owner()) || !records.empty() || PauseAllocator::OutstandingBlocks() != 0 ||
        PauseAllocator::ForeignFreeRefusals() != 0) return 0;
    bool good = true;
    for (auto& slot : slots) if (slot.owned && !exchange(slot, false)) good = false;
    if (good) installed = false;
    return good ? 1 : 0;
}
// No Lua API is registered. The only requests are the two Main-reserved globals,
// reached through the actual visible native button, deferred past native input iteration.
