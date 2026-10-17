// Local implementation only. Upstream allocator_forge_simple_impl.cpp is not linked.
#include <EASTL-forge1.51/allocator_forge.h>
#include <malloc.h>
#include <cstddef>
#include <mutex>
#include <unordered_map>
#include "PrivateForgeAllocator.h"
namespace {
std::mutex allocationMutex;
std::unordered_map<void*, std::size_t> allocations;
std::size_t refusedForeignFree = 0;
void* allocateOwned(std::size_t bytes, std::size_t alignment) {
    if (alignment < sizeof(void*)) alignment = sizeof(void*);
    if ((alignment & (alignment - 1)) != 0) return nullptr;
    const auto actualBytes = bytes ? bytes : 1;
    void* pointer = _aligned_malloc(actualBytes, alignment); // Correct size, alignment order.
    if (!pointer) return nullptr;
    try {
        std::lock_guard<std::mutex> lock(allocationMutex);
        allocations.emplace(pointer, actualBytes);
    } catch (...) { _aligned_free(pointer); return nullptr; }
    return pointer;
}
}
namespace PauseAllocator {
bool OwnsRange(const void* pointer, std::size_t bytes) noexcept {
    if (!pointer) return bytes == 0;
    std::lock_guard<std::mutex> lock(allocationMutex);
    const auto it = allocations.find(const_cast<void*>(pointer));
    return it != allocations.end() && bytes <= it->second;
}
std::size_t OutstandingBlocks() noexcept {
    std::lock_guard<std::mutex> lock(allocationMutex); return allocations.size();
}
std::size_t ForeignFreeRefusals() noexcept {
    std::lock_guard<std::mutex> lock(allocationMutex); return refusedForeignFree;
}
}
namespace eastl {
void* allocator_forge::allocate(size_t bytes, int) {
    return allocateOwned(bytes, alignof(std::max_align_t));
}
void* allocator_forge::allocate(size_t bytes, size_t alignment, size_t offset, int) {
    if (!alignment || offset % alignment != 0) return nullptr;
    return allocateOwned(bytes, alignment);
}
void allocator_forge::deallocate(void* pointer, size_t) {
    if (!pointer) return;
    {
        std::lock_guard<std::mutex> lock(allocationMutex);
        const auto it = allocations.find(pointer);
        if (it == allocations.end()) { ++refusedForeignFree; return; } // Never free a foreign CRT/game block.
        allocations.erase(it);
    }
    _aligned_free(pointer); // Every successful overload above uses the matching aligned allocator.
}
allocator_forge gDefaultAllocatorForge;
allocator_forge* gpDefaultAllocatorForge = &gDefaultAllocatorForge;
allocator_forge* GetDefaultAllocatorForge() { return gpDefaultAllocatorForge; }
allocator_forge* SetDefaultAllocatorForge(allocator_forge* value) {
    auto* previous = gpDefaultAllocatorForge; gpDefaultAllocatorForge = value; return previous;
}
}
