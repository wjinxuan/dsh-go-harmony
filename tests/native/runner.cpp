#include "node_engine.h"

#include <chrono>
#include <thread>

int main(int argc, char** argv)
{
    if (argc != 3 || StartLocalEngine(argv[1], argv[2]) != 0) return 64;
    for (int status = LocalEngineStatus(); status == -1; status = LocalEngineStatus()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(25));
    }
    return LocalEngineStatus();
}
