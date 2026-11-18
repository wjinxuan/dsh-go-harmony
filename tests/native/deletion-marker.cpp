#include "deletion_marker.h"
#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
namespace fs = std::filesystem;
int main() {
    char pattern[] = "/tmp/dsh-deletion-marker-XXXXXX";
    const std::string temp = mkdtemp(pattern), root = temp + "/sessions";
    const std::string slot = root + "/.dsh-go-lifecycle/" + std::string(64, 'a');
    const std::string target = slot + "/deleted.json", stage = slot + "/.01234567-89ab-cdef-0123-456789abcdef.tmp";
    fs::create_directories(slot);
    std::ofstream(stage) << "first";
    assert(PublishDeletionMarkerAt(root, stage, target) == 0);
    assert(!fs::exists(stage)); assert(fs::file_size(target) == 5);
    std::ofstream(stage) << "must stay";
    assert(PublishDeletionMarkerAt(root, stage, target) == -1 && errno == EEXIST);
    assert(fs::file_size(stage) == 9 && fs::file_size(target) == 5);
    assert(PublishDeletionMarkerAt(root, stage, slot + "/other.json") == -1 && errno == EINVAL);
    assert(PublishDeletionMarkerAt(root, stage + std::string("\0x", 2), target) == -1 && errno == EINVAL);
    assert(PublishDeletionMarkerAt(root, stage, root + "/.dsh-go-lifecycle/../deleted.json") == -1 && errno == EINVAL);
    assert(PublishDeletionMarkerAt(root, stage, temp + "/deleted.json") == -1 && errno == EINVAL);
    fs::remove(stage); fs::create_symlink(target, stage);
    assert(PublishDeletionMarkerAt(root, stage, target) == -1 && errno == EINVAL);
    fs::remove_all(slot); fs::create_directories(temp + "/outside"); fs::create_directory_symlink(temp + "/outside", slot);
    assert(PublishDeletionMarkerAt(root, stage, target) == -1);
    assert(fs::is_empty(temp + "/outside"));
    fs::remove_all(root + "/.dsh-go-lifecycle"); fs::create_directory_symlink(temp + "/outside", root + "/.dsh-go-lifecycle");
    assert(PublishDeletionMarkerAt(root, stage, target) == -1);
    fs::remove_all(temp);
    std::cout << "PASS native deletion tombstone: atomic no-overwrite, staged regular file, bounded private path, and directory/symlink refusal\n";
}
