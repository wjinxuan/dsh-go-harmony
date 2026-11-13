#include "node_engine.h"

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

napi_value Init(napi_env env, napi_value exports)
{
    const napi_property_descriptor properties[] = {
        {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"status", nullptr, Status, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
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
