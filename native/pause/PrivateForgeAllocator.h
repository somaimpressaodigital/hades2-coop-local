#pragma once
#include <cstddef>
namespace PauseAllocator {
bool OwnsRange(const void* pointer, std::size_t bytes) noexcept;
std::size_t OutstandingBlocks() noexcept;
std::size_t ForeignFreeRefusals() noexcept;
}
