#include "shell_probe.h"
#include <cerrno>
#include <chrono>
#include <csignal>
#include <fcntl.h>
#include <poll.h>
#ifdef __APPLE__
#include <util.h>
#else
#include <pty.h>
#endif
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

std::string ShellProbeResult::Json() const
{
    return "{\"ptyError\":" + std::to_string(ptyError) + ",\"spawnError\":" + std::to_string(spawnError) +
        ",\"exitCode\":" + std::to_string(exitCode) + ",\"timedOut\":" + (timedOut ? "true" : "false") +
        ",\"handshake\":" + (handshake ? "true" : "false") + "}";
}
ShellProbeResult ProbeLocalShell(const char* shell)
{
    ShellProbeResult result;
    int master, slave;
    if (openpty(&master, &slave, nullptr, nullptr, nullptr) != 0) { result.ptyError = errno; return result; }
    const int flags = fcntl(master, F_GETFL);
    if (flags < 0 || fcntl(master, F_SETFD, FD_CLOEXEC) < 0 || fcntl(slave, F_SETFD, FD_CLOEXEC) < 0 ||
        fcntl(master, F_SETFL, flags | O_NONBLOCK) < 0) {
        result.ptyError = errno; close(master); close(slave); return result;
    }
    posix_spawn_file_actions_t actions;
    int error = posix_spawn_file_actions_init(&actions);
    bool initialized = error == 0;
    for (int fd = 0; !error && fd <= 2; ++fd) error = posix_spawn_file_actions_adddup2(&actions, slave, fd);
    if (!error) error = posix_spawn_file_actions_addclose(&actions, master);
    if (!error && slave > 2) error = posix_spawn_file_actions_addclose(&actions, slave);
    char command[] = "test -t 0 && printf dsh-shell-ok";
    char flag[] = "-c", path[] = "PATH=/system/bin:/usr/bin:/bin", term[] = "TERM=xterm";
    char* args[] = {const_cast<char*>(shell), flag, command, nullptr};
    char* env[] = {path, term, nullptr};
    pid_t pid = -1;
    if (!error) error = posix_spawn(&pid, shell, &actions, nullptr, args, env);
    if (initialized) posix_spawn_file_actions_destroy(&actions);
    close(slave);
    if (error) { result.spawnError = error; close(master); return result; }
    std::string output;
    bool exited = false;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
    while (std::chrono::steady_clock::now() < deadline) {
        pollfd descriptor{master, POLLIN, 0};
        poll(&descriptor, 1, 100);
        char buffer[256]; ssize_t n;
        while ((n = read(master, buffer, sizeof(buffer))) > 0) {
            if (output.size() < 4096) output.append(buffer, static_cast<size_t>(n));
        }
        int status = 0;
        const auto waited = waitpid(pid, &status, WNOHANG);
        if (waited == pid) {
            result.exitCode = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
            exited = true; break;
        }
        if (waited == 0 && (descriptor.revents & POLLHUP)) usleep(10000);
        if (waited < 0 && errno != EINTR) { exited = true; result.exitCode = -errno; break; }
    }
    if (!exited) {
        result.timedOut = true;
        kill(pid, SIGKILL);
        int status; while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    }
    close(master);
    result.handshake = result.exitCode == 0 && output.find("dsh-shell-ok") != std::string::npos;
    return result;
}
