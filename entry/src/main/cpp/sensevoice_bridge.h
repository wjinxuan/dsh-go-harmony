#ifndef DSH_SENSEVOICE_BRIDGE_H
#define DSH_SENSEVOICE_BRIDGE_H
#include <node.h>
#include <string>
bool InstallSenseVoice(v8::Local<v8::Context> context, const std::string& dataRoot);
#endif
