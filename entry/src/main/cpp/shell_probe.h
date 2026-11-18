#ifndef DSH_SHELL_PROBE_H
#define DSH_SHELL_PROBE_H
#include <string>
struct ShellProbeResult {
    int ptyError = 0;
    int spawnError = 0;
    int exitCode = -1;
    bool timedOut = false;
    bool handshake = false;
    std::string Json() const;
};
ShellProbeResult ProbeLocalShell(const char* shell = "/system/bin/sh");
#endif
