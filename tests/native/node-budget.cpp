#include "node_budget.h"
#include <iostream>
constexpr uint64_t GiB = 1024ULL * 1024 * 1024;
static_assert(NodeOldSpaceMiB(0) == 512);
static_assert(NodeOldSpaceMiB(GiB) == 512);
static_assert(NodeOldSpaceMiB(3 * GiB) == 768);
static_assert(NodeOldSpaceMiB(5 * GiB) == 1280);
static_assert(NodeOldSpaceMiB(9 * GiB) == 2048);
static_assert(NodeOldSpaceMiB(5 * GiB - 1) == 1152);
int main() {
  for (uint64_t physical : {0ULL, GiB, 3 * GiB, 5 * GiB - 1, 5 * GiB, 9 * GiB})
    std::cout << NodeOldSpaceMiB(physical) << '\n';
}
