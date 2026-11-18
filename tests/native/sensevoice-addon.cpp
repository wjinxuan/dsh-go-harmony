#include "sensevoice_bridge.h"
#include <cstdlib>
NODE_MODULE_INIT() {
    const char* root = std::getenv("DSH_SENSEVOICE_TEST_HOME");
    if (!root || !InstallSenseVoice(context, root)) {
        context->GetIsolate()->ThrowException(v8::Exception::Error(
            v8::String::NewFromUtf8Literal(context->GetIsolate(), "Missing native test home")));
    }
}
