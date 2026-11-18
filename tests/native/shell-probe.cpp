#include "shell_probe.h"
#include <cassert>
#include <cerrno>
#include <iostream>
int main() {
    const auto available = ProbeLocalShell("/bin/sh");
    assert(available.ptyError == 0 && available.spawnError == 0 && available.handshake && !available.timedOut);
    const auto absent = ProbeLocalShell("/this-shell-must-not-exist");
    assert(absent.spawnError == ENOENT && !absent.handshake);
    std::cout << available.Json() << '\n' << absent.Json() << '\n';
}
