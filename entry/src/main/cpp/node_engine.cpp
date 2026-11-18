#include "node_engine.h"
#include "node_budget.h"
#include "deletion_marker.h"
#include "recall_marker.h"
#ifdef DSH_ENABLE_SENSEVOICE
#include "sensevoice_bridge.h"
#endif

#include <hilog/log.h>
#include <node.h>
#include <uv.h>

#include <algorithm>
#include <cerrno>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string_view>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

#include <mutex>
#include <thread>
#include <vector>

namespace {

struct Engine {
    std::mutex mutex;
    node::Environment* environment = nullptr;
    bool active = false;
    bool stopping = false;
    int exitCode = 0;
};

Engine& GetEngine()
{
    static auto* engine = new Engine;
    return *engine;
}

const auto& InitializeNode()
{
    using namespace node::ProcessInitializationFlags;
    // Match the fixed upstream PerformanceRules.oldSpaceMiB budget. This is V8 old
    // space only; it does not include native ASR, ArkUI or shared array buffers.
    const uint64_t heapMiB = NodeOldSpaceMiB(uv_get_total_memory());
    static const auto initialized = node::InitializeOncePerProcess(
        {"dsh-node", "--jitless", "--expose-internals", "--max-old-space-size=" + std::to_string(heapMiB)},
        {kNoDefaultSignalHandling, kNoStdioInitialization, kDisableNodeOptionsEnv,
         kNoParseGlobalDebugVariables, kNoAdjustResourceLimits, kNoUseLargePages});
    return initialized;
}

void TryLock(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    if (args.Length() != 1 || !args[0]->IsInt32() || args[0].As<v8::Int32>()->Value() < 0) {
        args.GetIsolate()->ThrowException(v8::Exception::TypeError(
            v8::String::NewFromUtf8Literal(args.GetIsolate(), "Expected an open file descriptor")));
        return;
    }
    const int fd = args[0].As<v8::Int32>()->Value();
    int result;
    do {
        result = flock(fd, LOCK_EX | LOCK_NB);
    } while (result < 0 && errno == EINTR);
    if (result == 0) {
        args.GetReturnValue().Set(true);
    } else if (errno == EWOULDBLOCK || errno == EAGAIN) {
        args.GetReturnValue().Set(false);
    } else {
        const auto reason = "Session file lock failed (" + std::to_string(errno) + ")";
        args.GetIsolate()->ThrowException(v8::Exception::Error(
            v8::String::NewFromUtf8(args.GetIsolate(), reason.c_str()).ToLocalChecked()));
    }
}

bool ReadAbsolutePath(const v8::String::Utf8Value& text, std::string_view& path)
{
    if (!*text || text.length() == 0 || text.length() >= 4096) {
        return false;
    }
    path = std::string_view(*text, text.length());
    return path.front() == '/' && path.back() != '/' && path.find('\0') == std::string_view::npos;
}

bool IsStagedLog(std::string_view stage, std::string_view final)
{
    if (!stage.starts_with(final) || stage.size() != final.size() + 17) {
        return false;
    }
    const auto name = final.substr(final.rfind('/') + 1);
    if (!name.starts_with("session.") || (!name.ends_with(".jsonl") && !name.ends_with(".jsonl.zstd"))) {
        return false;
    }
    const auto suffix = stage.substr(final.size());
    const auto nonce = suffix.substr(1, 12);
    return suffix.front() == '.' && suffix.ends_with(".tmp") &&
        std::all_of(nonce.begin(), nonce.end(), [](char c) {
            return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
        });
}

void PublishFile(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    auto* isolate = args.GetIsolate();
    const auto invalidPaths = [isolate] {
        isolate->ThrowException(v8::Exception::TypeError(
            v8::String::NewFromUtf8Literal(isolate, "Expected same-directory staged session log paths")));
    };
    if (args.Length() != 2 || !args[0]->IsString() || !args[1]->IsString()) {
        invalidPaths();
        return;
    }
    const v8::String::Utf8Value stageText(isolate, args[0]);
    const v8::String::Utf8Value finalText(isolate, args[1]);
    std::string_view stage;
    std::string_view final;
    if (!ReadAbsolutePath(stageText, stage) || !ReadAbsolutePath(finalText, final) || !IsStagedLog(stage, final)) {
        invalidPaths();
        return;
    }

    int result;
    do {
        result = renameat2(AT_FDCWD, *stageText, AT_FDCWD, *finalText, RENAME_NOREPLACE);
    } while (result < 0 && errno == EINTR);
    if (result < 0) {
        const int error = uv_translate_sys_error(errno);
        isolate->ThrowException(node::UVException(isolate, error, "renameat2", nullptr, *stageText, *finalText));
    }
}

void PublishDeletionMarker(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    auto* isolate = args.GetIsolate();
    if (args.Length() != 2 || !args[0]->IsString() || !args[1]->IsString() || !args.Data()->IsString()) {
        isolate->ThrowException(v8::Exception::TypeError(v8::String::NewFromUtf8Literal(isolate, "Expected private staged deletion marker paths")));
        return;
    }
    const v8::String::Utf8Value stage(isolate, args[0]), target(isolate, args[1]), root(isolate, args.Data());
    if (!*stage || !*target || !*root || PublishDeletionMarkerAt(std::string(*root, root.length()),
        std::string_view(*stage, stage.length()), std::string_view(*target, target.length())) < 0) {
        isolate->ThrowException(node::UVException(isolate, uv_translate_sys_error(errno), "renameat2"));
    }
}

void PublishRecallMarker(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    auto* isolate = args.GetIsolate();
    if (args.Length() != 2 || !args[0]->IsString() || !args[1]->IsString() || !args.Data()->IsString()) {
        isolate->ThrowException(v8::Exception::TypeError(v8::String::NewFromUtf8Literal(isolate, "Expected private staged Recall marker paths")));
        return;
    }
    const v8::String::Utf8Value stage(isolate, args[0]), target(isolate, args[1]), data(isolate, args.Data());
    if (!*stage || !*target || !*data) {
        isolate->ThrowException(node::UVException(isolate, UV_EINVAL, "renameat2"));
        return;
    }
    if (PublishRecallMarkerAt(std::string(*data, data.length()), std::string_view(*stage, stage.length()),
        std::string_view(*target, target.length())) < 0) {
        isolate->ThrowException(node::UVException(isolate, uv_translate_sys_error(errno), "renameat2"));
    }
}

class ScopedFd {
public:
    explicit ScopedFd(int value) : value_(value) {}
    ~ScopedFd() { if (value_ >= 0) close(value_); }
    int get() const { return value_; }
    void reset(int value) { if (value_ >= 0) close(value_); value_ = value; }
private:
    int value_;
};

bool IsUuid(std::string_view value)
{
    if (value.size() != 36) return false;
    for (size_t i = 0; i < value.size(); ++i) {
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if (value[i] != '-') return false;
        } else if (!((value[i] >= 'a' && value[i] <= 'f') || (value[i] >= '0' && value[i] <= '9'))) {
            return false;
        }
    }
    return true;
}

void PublishWorkspaceFile(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    auto* isolate = args.GetIsolate();
    const auto invalid = [isolate] {
        isolate->ThrowException(v8::Exception::TypeError(
            v8::String::NewFromUtf8Literal(isolate, "Expected a staged file inside the local workspace")));
    };
    if (args.Length() != 2 || !args[0]->IsString() || !args[1]->IsString() || !args.Data()->IsString()) {
        invalid();
        return;
    }
    const v8::String::Utf8Value stageText(isolate, args[0]);
    const v8::String::Utf8Value finalText(isolate, args[1]);
    const v8::String::Utf8Value rootText(isolate, args.Data());
    std::string_view stage, final;
    if (!ReadAbsolutePath(stageText, stage) || !ReadAbsolutePath(finalText, final)) {
        invalid();
        return;
    }
    const std::string parent(final.substr(0, final.rfind('/')));
    const std::string name(final.substr(final.rfind('/') + 1));
    const std::string stagePrefix = parent + "/." + name + "." + std::to_string(getpid()) + ".";
    const std::string stageSuffix = ".tmpdir/" + name + ".tmp";
    if (name == "." || name == ".." || !stage.starts_with(stagePrefix) || !stage.ends_with(stageSuffix) ||
        stage.size() != stagePrefix.size() + 36 + stageSuffix.size() ||
        !IsUuid(stage.substr(stagePrefix.size(), 36))) {
        invalid();
        return;
    }
    char rootResolved[PATH_MAX], parentResolved[PATH_MAX];
    if (!realpath(*rootText, rootResolved) || !realpath(parent.c_str(), parentResolved)) {
        const int error = uv_translate_sys_error(errno);
        isolate->ThrowException(node::UVException(isolate, error, "realpath"));
        return;
    }
    const std::string root(rootResolved), canonicalParent(parentResolved);
    if (canonicalParent != root && !canonicalParent.starts_with(root + "/")) {
        invalid();
        return;
    }
    // Directory descriptors keep publication inside the trusted root if path names change.
    ScopedFd destination(open(root.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    size_t offset = root.size() + 1;
    while (destination.get() >= 0 && offset < canonicalParent.size()) {
        const size_t end = canonicalParent.find('/', offset);
        const auto component = canonicalParent.substr(offset, end == std::string::npos ? end : end - offset);
        destination.reset(openat(destination.get(), component.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
        if (end == std::string::npos) break;
        offset = end + 1;
    }
    const std::string stageDirectory(stage.substr(parent.size() + 1, stage.rfind('/') - parent.size() - 1));
    ScopedFd source(destination.get() < 0 ? -1 :
        openat(destination.get(), stageDirectory.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    struct stat info {};
    const std::string stagedName = name + ".tmp";
    int result = -1;
    if (source.get() >= 0 && fstatat(source.get(), stagedName.c_str(), &info, AT_SYMLINK_NOFOLLOW) == 0) {
        if (!S_ISREG(info.st_mode)) { invalid(); return; }
        do {
            result = renameat2(source.get(), stagedName.c_str(), destination.get(), name.c_str(), RENAME_NOREPLACE);
        } while (result < 0 && errno == EINTR);
    }
    if (result < 0) {
        const int error = uv_translate_sys_error(errno);
        isolate->ThrowException(node::UVException(isolate, error, "renameat2", nullptr, *stageText, *finalText));
    }
}

void PublishAttachmentFile(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    auto* isolate = args.GetIsolate();
    const auto invalid = [isolate] {
        isolate->ThrowException(v8::Exception::TypeError(
            v8::String::NewFromUtf8Literal(isolate, "Expected a staged private attachment and digest-derived target")));
    };
    if (args.Length() != 2 || !args[0]->IsString() || !args[1]->IsString() || !args.Data()->IsString()) {
        invalid();
        return;
    }
    const v8::String::Utf8Value stageText(isolate, args[0]);
    const v8::String::Utf8Value finalText(isolate, args[1]);
    const v8::String::Utf8Value rootText(isolate, args.Data());
    const std::string root(*rootText);
    const std::string sourcePrefix = root + "/tmp/";
    std::string_view stage, final;
    if (!ReadAbsolutePath(stageText, stage) || !ReadAbsolutePath(finalText, final) ||
        !stage.starts_with(sourcePrefix) || !IsUuid(stage.substr(sourcePrefix.size())) || !final.starts_with(root + "/")) {
        invalid();
        return;
    }
    const auto suffix = final.substr(root.size() + 1);
    const auto separator = suffix.find('/');
    if (separator == std::string_view::npos) { invalid(); return; }
    const auto family = suffix.substr(0, separator);
    if (family != "objects" && family != "file-objects" && family != "files") { invalid(); return; }
    const auto tail = suffix.substr(separator + 1);
    if (tail.size() < 67 || tail[2] != '/' || tail.substr(0, 2) != tail.substr(3, 2) ||
        !std::all_of(tail.begin() + 3, tail.begin() + 67, [](char value) {
            return (value >= '0' && value <= '9') || (value >= 'a' && value <= 'f');
        })) { invalid(); return; }
    if ((family == "files" && (tail.size() < 69 || tail[67] != '/' || tail.substr(68).find('/') != std::string_view::npos)) ||
        (family != "files" && tail.size() != 67)) { invalid(); return; }
    const std::string name(final.substr(final.rfind('/') + 1));
    if (name == "." || name == "..") { invalid(); return; }
    ScopedFd boundary(open(root.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    ScopedFd source(boundary.get() < 0 ? -1 : openat(boundary.get(), "tmp", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    ScopedFd destination(boundary.get() < 0 ? -1 : openat(boundary.get(), std::string(family).c_str(),
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    if (destination.get() >= 0) destination.reset(openat(destination.get(), std::string(tail.substr(0, 2)).c_str(),
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    if (family == "files" && destination.get() >= 0) destination.reset(openat(destination.get(), std::string(tail.substr(3, 64)).c_str(),
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    const std::string stagedName(stage.substr(sourcePrefix.size()));
    struct stat info {};
    int result = -1;
    if (source.get() < 0 || destination.get() < 0) {
        errno = ENOENT;
    } else if (fstatat(source.get(), stagedName.c_str(), &info, AT_SYMLINK_NOFOLLOW) == 0) {
        if (!S_ISREG(info.st_mode)) { invalid(); return; }
        do {
            result = renameat2(source.get(), stagedName.c_str(), destination.get(), name.c_str(), RENAME_NOREPLACE);
        } while (result < 0 && errno == EINTR);
    }
    if (result < 0) isolate->ThrowException(node::UVException(isolate, uv_translate_sys_error(errno), "renameat2"));
}

bool SetGlobal(v8::Local<v8::Context> context, v8::Local<v8::String> name, v8::FunctionCallback callback)
{
    v8::Local<v8::Function> function;
    return v8::Function::New(context, callback).ToLocal(&function) &&
        context->Global()->Set(context, name, function).FromMaybe(false);
}

int RunNode(const std::string& script, const std::string& data)
{
    auto& engine = GetEngine();
    const auto& initialized = InitializeNode();
    if (!initialized || initialized->early_return() || !initialized->platform()) {
        return 20;
    }

    std::vector<std::string> args = {"dsh-node", script, data};
    std::vector<std::string> errors;
    int exitCode = 0;
    const auto flags = static_cast<node::EnvironmentFlags::Flags>(
        node::EnvironmentFlags::kTrackUnmanagedFds | node::EnvironmentFlags::kNoNativeAddons |
        node::EnvironmentFlags::kNoGlobalSearchPaths | node::EnvironmentFlags::kNoCreateInspector);
    auto setup = node::CommonEnvironmentSetup::Create(
        initialized->platform(), &errors, args, initialized->exec_args(), flags);
    if (!setup) {
        return 21;
    }

    auto* isolate = setup->isolate();
    v8::Locker locker(isolate);
    v8::Isolate::Scope isolateScope(isolate);
    v8::HandleScope handleScope(isolate);
    v8::Context::Scope contextScope(setup->context());
    auto* env = setup->env();
    node::SetProcessExitHandler(env, [&exitCode](node::Environment* current, int code) {
        exitCode = code;
        node::Stop(current);
    });
    {
        const std::lock_guard<std::mutex> lock(engine.mutex);
        if (engine.stopping) {
            return 0;
        }
        engine.environment = env;
    }

    int loopCode = 22;
    auto context = setup->context();
    v8::Local<v8::Function> publishWorkspace;
    v8::Local<v8::Function> publishAttachment;
    v8::Local<v8::Function> publishDeletion;
    v8::Local<v8::Function> publishRecall;
    const auto workspace = v8::String::NewFromUtf8(isolate, (data + "/workspace").c_str()).ToLocalChecked();
    const auto attachmentRoot = v8::String::NewFromUtf8(isolate, (data + "/attachments/v1").c_str()).ToLocalChecked();
    const auto sessionRoot = v8::String::NewFromUtf8(isolate, (data + "/sessions").c_str()).ToLocalChecked();
    const auto recallDataRoot = v8::String::NewFromUtf8(isolate, data.c_str()).ToLocalChecked();
    if (
#ifdef DSH_ENABLE_SENSEVOICE
        InstallSenseVoice(context, data) &&
#endif
        SetGlobal(context, v8::String::NewFromUtf8Literal(isolate, "dshHarmonyTryLock"), TryLock) &&
        SetGlobal(context, v8::String::NewFromUtf8Literal(isolate, "dshHarmonyPublishFile"), PublishFile) &&
        v8::Function::New(context, PublishDeletionMarker, sessionRoot).ToLocal(&publishDeletion) &&
        context->Global()->Set(context, v8::String::NewFromUtf8Literal(isolate, "dshHarmonyPublishDeletionMarker"),
            publishDeletion).FromMaybe(false) &&
        v8::Function::New(context, PublishRecallMarker, recallDataRoot).ToLocal(&publishRecall) &&
        context->Global()->Set(context, v8::String::NewFromUtf8Literal(isolate, "dshHarmonyPublishRecallMarker"),
            publishRecall).FromMaybe(false) &&
        v8::Function::New(context, PublishWorkspaceFile, workspace).ToLocal(&publishWorkspace) &&
        context->Global()->Set(context, v8::String::NewFromUtf8Literal(isolate, "dshHarmonyPublishWorkspaceFile"),
            publishWorkspace).FromMaybe(false) &&
        v8::Function::New(context, PublishAttachmentFile, attachmentRoot).ToLocal(&publishAttachment) &&
        context->Global()->Set(context, v8::String::NewFromUtf8Literal(isolate, "dshHarmonyPublishAttachmentFile"),
            publishAttachment).FromMaybe(false)) {
        const auto loaded = node::LoadEnvironment(
            env, "require('node:module').createRequire(process.argv[1])(process.argv[1]);");
        if (!loaded.IsEmpty()) {
            loopCode = node::SpinEventLoop(env).FromMaybe(23);
        }
    }
    {
        const std::lock_guard<std::mutex> lock(engine.mutex);
        engine.environment = nullptr;
        node::Stop(env);
    }
    return exitCode ? exitCode : loopCode;
}

} // namespace

int StartLocalEngine(const std::string& script, const std::string& data)
{
    auto& engine = GetEngine();
    const std::lock_guard<std::mutex> lock(engine.mutex);
    if (engine.active) {
        return 1;
    }
    engine.active = true;
    engine.stopping = false;
    engine.exitCode = 0;
    try {
        std::thread([script, data] {
            const int code = RunNode(script, data);
            auto& current = GetEngine();
            const std::lock_guard<std::mutex> guard(current.mutex);
            current.exitCode = current.stopping ? 0 : code;
            current.active = false;
            OH_LOG_Print(LOG_APP, LOG_INFO, 0, "DSHLocal", "Local engine stopped (%{public}d)", current.exitCode);
        }).detach();
    } catch (...) {
        engine.active = false;
        engine.exitCode = 24;
        return 24;
    }
    return 0;
}

int LocalEngineStatus()
{
    auto& engine = GetEngine();
    const std::lock_guard<std::mutex> lock(engine.mutex);
    return engine.active ? -1 : engine.exitCode;
}

void StopLocalEngine()
{
    auto& engine = GetEngine();
    const std::lock_guard<std::mutex> lock(engine.mutex);
    engine.stopping = true;
    if (engine.environment) {
        node::Stop(engine.environment);
    }
}
