#pragma once
#include <algorithm>
#include <cerrno>
#include <fcntl.h>
#include <stdio.h>
#include <string>
#include <string_view>
#include <sys/stat.h>
#include <unistd.h>

// Only the private lifecycle tombstone may use the hardlink fallback.
inline int PublishDeletionMarkerAt(const std::string& root, std::string_view stage, std::string_view target)
{
    const std::string prefix = root + "/.dsh-go-lifecycle/";
    const auto hex = [](char c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'); };
    const auto invalid = [] { errno = EINVAL; return -1; };
    if (root.empty() || root.front() != '/' || root.find('\0') != std::string::npos ||
        stage.size() >= 4096 || target.size() >= 4096 || stage.find('\0') != std::string_view::npos ||
        target.find('\0') != std::string_view::npos || !target.starts_with(prefix) ||
        target.size() != prefix.size() + 64 + 13 || !target.ends_with("/deleted.json")) return invalid();
    const auto digest = target.substr(prefix.size(), 64);
    if (!std::all_of(digest.begin(), digest.end(), hex)) return invalid();
    const std::string parent = prefix + std::string(digest) + "/";
    if (!stage.starts_with(parent) || stage.size() != parent.size() + 41) return invalid();
    const auto name = stage.substr(parent.size());
    if (name.front() != '.' || !name.ends_with(".tmp")) return invalid();
    const auto uuid = name.substr(1, 36);
    for (size_t i = 0; i < uuid.size(); i++) {
        if (i == 8 || i == 13 || i == 18 || i == 23) { if (uuid[i] != '-') return invalid(); }
        else if (!hex(uuid[i])) return invalid();
    }
    const int boundary = open(root.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (boundary < 0) return -1;
    const int control = openat(boundary, ".dsh-go-lifecycle", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    int error = errno; close(boundary);
    if (control < 0) { errno = error; return -1; }
    const int slot = openat(control, std::string(digest).c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    error = errno; close(control);
    if (slot < 0) { errno = error; return -1; }
    struct stat info {};
    int result = fstatat(slot, std::string(name).c_str(), &info, AT_SYMLINK_NOFOLLOW);
    if (result == 0 && !S_ISREG(info.st_mode)) { errno = EINVAL; result = -1; }
    if (result == 0) {
        do {
#ifdef __APPLE__
            result = renameatx_np(slot, std::string(name).c_str(), slot, "deleted.json", RENAME_EXCL);
#else
            result = renameat2(slot, std::string(name).c_str(), slot, "deleted.json", RENAME_NOREPLACE);
#endif
        } while (result < 0 && errno == EINTR);
    }
    error = errno; close(slot); errno = error;
    return result;
}
