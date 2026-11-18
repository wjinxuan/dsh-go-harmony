#include <iostream>
#if __has_include("recall_marker.h")
#include "recall_marker.h"
#include <cassert>
#include <filesystem>
#include <fstream>
namespace fs = std::filesystem;

int main()
{
    char pattern[] = "/tmp/dsh-recall-marker-XXXXXX";
    const std::string temp = mkdtemp(pattern), data = temp + "/data";
    const std::string directory = data + "/companion/recall-sessions";
    const std::string uuid = "01234567-89ab-4def-8123-456789abcdef";
    const std::string stage = directory + "/.recall-" + uuid + ".tmp";
    const std::string target = directory + "/" + std::string(64, 'a') + ".json";
    const std::string probe = directory + "/.probe-" + uuid + ".tmp";
    fs::create_directories(directory);
    std::ofstream(stage) << "first";
    assert(PublishRecallMarkerAt(data, stage, target) == 0);
    assert(!fs::exists(stage) && fs::file_size(target) == 5);
    std::ofstream(stage) << "must stay";
    assert(PublishRecallMarkerAt(data, stage, target) == -1 && errno == EEXIST);
    assert(fs::file_size(stage) == 9 && fs::file_size(target) == 5);
    assert(PublishRecallMarkerAt(data, stage, probe) == 0);
    assert(!fs::exists(stage) && fs::file_size(probe) == 9);
    assert(PublishRecallMarkerAt(data, stage, target) == -1 && errno == ENOENT);
    std::ofstream(stage) << std::string(4097, 'x');
    assert(PublishRecallMarkerAt(data, stage, target) == -1 && errno == EINVAL);
    std::ofstream(stage) << std::string(4096, 'x');
    fs::remove(probe);
    assert(PublishRecallMarkerAt(data, stage, probe) == 0);
    std::ofstream(stage) << "safe";
    for (const auto& invalid : {directory + "/other.json", directory + "/" + std::string(64, 'A') + ".json",
        directory + "/../recall-sessions/" + std::string(64, 'a') + ".json", temp + "/" + std::string(64, 'a') + ".json",
        directory + "/.probe-invalid.tmp", target + std::string("\0x", 2)}) {
        assert(PublishRecallMarkerAt(data, stage, invalid) == -1 && errno == EINVAL);
    }
    for (const auto& invalid : {directory + "/.recall-invalid.tmp", directory + "/.probe-" + uuid + ".tmp",
        directory + "/nested/.recall-" + uuid + ".tmp", stage + std::string("\0x", 2)}) {
        assert(PublishRecallMarkerAt(data, invalid, target) == -1 && errno == EINVAL);
    }
    fs::remove(stage); fs::create_symlink(target, stage);
    assert(PublishRecallMarkerAt(data, stage, target) == -1 && errno == EINVAL);
    fs::remove(stage); fs::create_directory(stage);
    assert(PublishRecallMarkerAt(data, stage, target) == -1 && errno == EINVAL);
    fs::remove_all(stage); std::ofstream(stage) << "safe";
    fs::remove(probe); fs::create_symlink(temp + "/missing", probe);
    assert(PublishRecallMarkerAt(data, stage, probe) == -1 && errno == EEXIST);
    assert(fs::is_symlink(probe) && !fs::exists(temp + "/missing") && fs::file_size(stage) == 4);
    fs::create_directories(temp + "/outside");
    fs::remove_all(directory); fs::create_directory_symlink(temp + "/outside", directory);
    assert(PublishRecallMarkerAt(data, stage, target) == -1);
    assert(fs::is_empty(temp + "/outside"));
    fs::remove_all(data + "/companion"); fs::create_directory_symlink(temp + "/outside", data + "/companion");
    assert(PublishRecallMarkerAt(data, stage, target) == -1);
    assert(fs::is_empty(temp + "/outside"));
    fs::remove_all(data); fs::create_directory_symlink(temp + "/outside", data);
    assert(PublishRecallMarkerAt(data, stage, target) == -1);
    assert(fs::is_empty(temp + "/outside"));
    fs::remove_all(temp);
    std::cout << "PASS native Recall marker: publish/probe, no replacement, missing/oversize, bounded paths, regular source, target and directory symlink refusal\n";
}
#else
int main() { std::cerr << "FAIL native Recall marker publication helper is unavailable\n"; return 1; }
#endif
