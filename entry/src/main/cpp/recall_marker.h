#pragma once
#include <algorithm>
#include <cerrno>
#include <fcntl.h>
#include <stdio.h>
#include <string>
#include <string_view>
#include <sys/stat.h>
#include <unistd.h>

// Recall's hardlink fallback is confined to the private session-tag directory.
// The caller fsyncs the staged content and parent directory and cleans the stage.
inline int PublishRecallMarkerAt(const std::string& data, std::string_view stage, std::string_view target)
{
    const auto invalid = [] { errno = EINVAL; return -1; };
    const auto hex = [](char c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'); };
    const auto uuid = [hex](std::string_view value) {
        if (value.size() != 36) return false;
        for (size_t i = 0; i < value.size(); i++) {
            if (i == 8 || i == 13 || i == 18 || i == 23) { if (value[i] != '-') return false; }
            else if (!hex(value[i])) return false;
        }
        return true;
    };
    const std::string prefix = data + "/companion/recall-sessions/";
    if (data.empty() || data.front() != '/' || data.back() == '/' || data.find('\0') != std::string::npos ||
        stage.size() >= 4096 || target.size() >= 4096 || stage.find('\0') != std::string_view::npos ||
        target.find('\0') != std::string_view::npos || !stage.starts_with(prefix) || !target.starts_with(prefix)) return invalid();
    const auto source = stage.substr(prefix.size()), destination = target.substr(prefix.size());
    if (source.size() != 48 || !source.starts_with(".recall-") || !source.ends_with(".tmp") ||
        !uuid(source.substr(8, 36))) return invalid();
    const bool marker = destination.size() == 69 && destination.ends_with(".json") &&
        std::all_of(destination.begin(), destination.begin() + 64, hex);
    const bool probe = destination.size() == 47 && destination.starts_with(".probe-") &&
        destination.ends_with(".tmp") && uuid(destination.substr(7, 36));
    if (!marker && !probe) return invalid();

    const int boundary = open(data.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (boundary < 0) return -1;
    const int companion = openat(boundary, "companion", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    int error = errno; close(boundary);
    if (companion < 0) { errno = error; return -1; }
    const int directory = openat(companion, "recall-sessions", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    error = errno; close(companion);
    if (directory < 0) { errno = error; return -1; }
    struct stat info {};
    int result = fstatat(directory, std::string(source).c_str(), &info, AT_SYMLINK_NOFOLLOW);
    if (result == 0 && (!S_ISREG(info.st_mode) || info.st_size < 0 || info.st_size > 4096)) {
        errno = EINVAL; result = -1;
    }
    if (result == 0) {
        do {
#ifdef __APPLE__
            result = renameatx_np(directory, std::string(source).c_str(), directory, std::string(destination).c_str(), RENAME_EXCL);
#else
            result = renameat2(directory, std::string(source).c_str(), directory, std::string(destination).c_str(), RENAME_NOREPLACE);
#endif
        } while (result < 0 && errno == EINTR);
    }
    error = errno; close(directory); errno = error;
    return result;
}
