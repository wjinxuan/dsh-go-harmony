#include "node_engine.h"
#include "shell_probe.h"
#include <memory>

#include <napi/native_api.h>

namespace {

bool ReadPath(napi_env env, napi_value value, std::string& path)
{
    size_t size = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &size) != napi_ok || size == 0 || size > 4096) {
        return false;
    }
    path.resize(size + 1);
    if (napi_get_value_string_utf8(env, value, path.data(), path.size(), &size) != napi_ok) {
        return false;
    }
    path.resize(size);
    return path.front() == '/' && path.find('\0') == std::string::npos;
}

napi_value Number(napi_env env, int value)
{
    napi_value result = nullptr;
    napi_create_int32(env, value, &result);
    return result;
}

napi_value Start(napi_env env, napi_callback_info info)
{
    size_t count = 2;
    napi_value values[2] = {};
    std::string script;
    std::string data;
    if (napi_get_cb_info(env, info, &count, values, nullptr, nullptr) != napi_ok || count != 2 ||
        !ReadPath(env, values[0], script) || !ReadPath(env, values[1], data)) {
        napi_throw_type_error(env, nullptr, "Expected absolute local engine paths");
        return nullptr;
    }

    return Number(env, StartLocalEngine(script, data));
}

napi_value Status(napi_env env, napi_callback_info)
{
    return Number(env, LocalEngineStatus());
}

napi_value Stop(napi_env env, napi_callback_info)
{
    StopLocalEngine();
    return Number(env, 0);
}

struct ShellProbeWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string result;
};
napi_value ProbeShell(napi_env env, napi_callback_info)
{
    auto work = std::make_unique<ShellProbeWork>();
    napi_value promise, name;
    if (napi_create_promise(env, &work->deferred, &promise) != napi_ok ||
        napi_create_string_utf8(env, "ShellCapabilityProbe", NAPI_AUTO_LENGTH, &name) != napi_ok ||
        napi_create_async_work(env, nullptr, name,
            [](napi_env, void* data) { static_cast<ShellProbeWork*>(data)->result = ProbeLocalShell().Json(); },
            [](napi_env env, napi_status status, void* data) {
                std::unique_ptr<ShellProbeWork> task(static_cast<ShellProbeWork*>(data));
                napi_value value;
                napi_create_string_utf8(env, task->result.c_str(), task->result.size(), &value);
                if (status == napi_ok) napi_resolve_deferred(env, task->deferred, value);
                else napi_reject_deferred(env, task->deferred, value);
                napi_delete_async_work(env, task->work);
            }, work.get(), &work->work) != napi_ok) {
        napi_throw_error(env, nullptr, "Cannot create shell diagnostic task");
        return nullptr;
    }
    if (napi_queue_async_work(env, work->work) != napi_ok) {
        napi_delete_async_work(env, work->work);
        napi_throw_error(env, nullptr, "Cannot schedule shell diagnostic task");
        return nullptr;
    }
    work.release();
    return promise;
}

napi_value Init(napi_env env, napi_value exports)
{
    const napi_property_descriptor properties[] = {
        {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"status", nullptr, Status, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"probeShell", nullptr, ProbeShell, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}

napi_module module = {1, 0, nullptr, Init, "dshlocal", nullptr, {nullptr}};

} // namespace

extern "C" __attribute__((constructor)) void RegisterDshLocal()
{
    napi_module_register(&module);
}
