#pragma once
#if !defined(_MSC_VER) || !defined(_M_X64)
#error This candidate requires the verified Microsoft x64 C++ ABI. GNU/MinGW ABI is not admitted.
#endif
#include <cstddef>
#include <cstdint>
#include <hades2/MenuScreen.h>
#include <hades2/GUIComponentButton.h>

// Actual full LF_STRUCTURE/LF_MEMBER records in the matching installed PDB.
// No MainMenu layout or unspecified GetType enum is used to acquire a pause.
struct NativePauseLayout : sgg::MenuScreen {
    int exitConfirmSound;
    bool uploadingCloudSaves;
    Vectormath::Vector2 gameplayCursorLocation;
    bool takeoverAutoUnpause;
    int takeoverCueId;
    sgg::GUIComponentButton* resumeButton;
    sgg::GUIComponentButton* settingsButton;
    sgg::GUIComponentButton* giveUpButton;
    sgg::GUIComponentButton* exitButton;
    sgg::GUIComponentTextBox* lastSaveHint;
    sgg::GUIComponentBox* front;
};
static_assert(sizeof(void*) == 8 && sizeof(long double) == 8);
static_assert(sizeof(sgg::MenuScreen) == 0x2a8);
static_assert(sizeof(sgg::GUIComponent) == 0x540);
static_assert(sizeof(sgg::GUIComponentButton) == 0x5b0);
static_assert(sizeof(sgg::GUIAction) == 0x18);
static_assert(sizeof(eastl::function<void()>) == 0x20);
static_assert(sizeof(NativePauseLayout) == 0x2f0);
// MSVC supports offsetof for this non-standard-layout native ABI contract.
static_assert(offsetof(NativePauseLayout, resumeButton) == 0x2c0);
static_assert(offsetof(NativePauseLayout, settingsButton) == 0x2c8);
static_assert(offsetof(NativePauseLayout, giveUpButton) == 0x2d0);
static_assert(offsetof(NativePauseLayout, exitButton) == 0x2d8);
static_assert(offsetof(NativePauseLayout, lastSaveHint) == 0x2e0);

namespace PauseBuild {
constexpr std::size_t NativeComponentIdOffset = 0x538; // Actual GUIComponent::mId LF_MEMBER.
constexpr std::uintptr_t VTableRVA = 0x4deac0;
constexpr std::uintptr_t UpdateRVA = 0x17fcd0;
constexpr std::uintptr_t ExitRVA = 0x180830;
constexpr std::uintptr_t ResumeRVA = 0x180600; // Actual PauseScreen::Resume in matching PDB/PE.
constexpr std::uintptr_t ClearRVA = 0x140d90;
constexpr std::uintptr_t DestructorRVA = 0x17fbf0;
constexpr std::uintptr_t ContainerVTableRVA = 0x4deaa8, ContainerDestructorRVA = 0x182bb8;
constexpr std::size_t ContainerBaseOffset = 0x50, ContainerDestructorSlot = 1;
// Slots read directly from the PE vft and resolved back to current PDB symbols.
constexpr std::size_t UpdateSlot = 3, ExitSlot = 7, ClearSlot = 8, DestructorSlot = 11;
constexpr std::uint8_t CodeViewGUID[] = {0x5b,0xd0,0x00,0x0d,0x96,0xe7,0x16,0x4b,0xb4,0x4c,0xa1,0x31,0x53,0x5c,0xac,0xab};
constexpr std::uint32_t CodeViewAge = 1;
struct EntryFingerprint { std::uintptr_t rva; std::uint8_t bytes[16]; };
constexpr EntryFingerprint Entries[] = {
 {ResumeRVA,{0x48,0x89,0x5c,0x24,0x10,0x48,0x89,0x6c,0x24,0x18,0x48,0x89,0x74,0x24,0x20,0x57}},
 {UpdateRVA,{0x48,0x89,0x5c,0x24,0x10,0x48,0x89,0x6c,0x24,0x18,0x48,0x89,0x74,0x24,0x20,0x57}},
 {ExitRVA,{0x48,0x8b,0xc4,0x55,0x56,0x48,0x8b,0xec,0x48,0x83,0xec,0x58,0x80,0xb9,0xac,0x02}},
 {ClearRVA,{0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83,0xec,0x20,0x48,0x8b,0x81,0xd0,0x00,0x00}},
 {DestructorRVA,{0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83,0xec,0x20,0x8b,0xda,0x48,0x8b,0xf9,0xe8}},
 {ContainerDestructorRVA,{0x48,0x83,0xe9,0x50,0xe9,0x2f,0xd0,0xff,0xff,0xcc,0xcc,0xcc,0xcc,0xcc,0xcc,0xcc}},
};
}
