#pragma once
#include <algorithm>
#include <cstdint>
// Fixed dsh-Go PerformanceRules.oldSpaceMiB; V8 old space is not process RSS.
constexpr uint64_t NodeOldSpaceMiB(uint64_t physicalBytes)
{
    return std::clamp<uint64_t>((physicalBytes / (1024 * 1024) / 4 / 128) * 128, 512, 2048);
}
