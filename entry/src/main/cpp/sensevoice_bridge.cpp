#include "sensevoice_bridge.h"
#include "sensevoice_engine.h"
#include <uv.h>
#include <cmath>
#include <stdexcept>

namespace {
struct State {
    SenseVoiceEngine engine;
    std::string models;
    std::atomic_bool cancelled{false};
    bool busy = false;
    bool closing = false;
    void (*closed)(void*) = nullptr;
    void* closedArg = nullptr;
    node::AsyncCleanupHookHandle cleanup;
};
struct Work {
    uv_work_t request{};
    State* state;
    v8::Isolate* isolate;
    v8::Global<v8::Context> context;
    v8::Global<v8::Promise::Resolver> resolver;
    int operation;
    std::vector<float> samples;
    std::string language, result, error;
};
void FinishClose(State* state)
{
    const auto closed = state->closed;
    void* arg = state->closedArg;
    delete state;
    closed(arg);
}
void Cleanup(void* arg, void (*closed)(void*), void* closedArg)
{
    auto* state = static_cast<State*>(arg);
    state->closing = true;
    state->cancelled.store(true);
    state->closed = closed;
    state->closedArg = closedArg;
    if (!state->busy) FinishClose(state);
}
void Execute(uv_work_t* request)
{
    auto* work = static_cast<Work*>(request->data);
    try {
        if (work->state->cancelled.load()) throw std::runtime_error("SenseVoice operation cancelled");
        if (work->operation == 0) work->state->engine.Load(work->state->models);
        else if (work->operation == 1) work->result = work->state->engine.Transcribe(
            work->samples, work->language, work->state->cancelled);
        else work->state->engine.Unload();
    } catch (const std::exception& error) { work->error = error.what(); }
    catch (...) { work->error = "SenseVoice native inference failed"; }
}
void Complete(uv_work_t* request, int status)
{
    std::unique_ptr<Work> work(static_cast<Work*>(request->data));
    State* state = work->state;
    state->busy = false;
    if (!state->closing) {
        v8::HandleScope handles(work->isolate);
        auto context = work->context.Get(work->isolate);
        v8::Context::Scope contextScope(context);
        node::CallbackScope callbacks(work->isolate, context->Global(), {0, 0});
        auto resolver = work->resolver.Get(work->isolate);
        if (state->cancelled.load() || status != 0) work->error = "SenseVoice operation cancelled";
        if (!work->error.empty()) {
            auto message = v8::String::NewFromUtf8(work->isolate, work->error.c_str()).ToLocalChecked();
            resolver->Reject(context, v8::Exception::Error(message)).FromMaybe(false);
        } else {
            auto text = v8::String::NewFromUtf8(work->isolate, work->result.c_str()).ToLocalChecked();
            resolver->Resolve(context, text).FromMaybe(false);
        }
    }
    work.reset();
    if (state->closing) FinishClose(state);
}
void Queue(const v8::FunctionCallbackInfo<v8::Value>& args, int operation)
{
    auto* isolate = args.GetIsolate();
    auto context = isolate->GetCurrentContext();
    auto* state = static_cast<State*>(args.Data().As<v8::External>()->Value());
    const auto fail = [isolate](const char* message) {
        isolate->ThrowException(v8::Exception::Error(v8::String::NewFromUtf8(isolate, message).ToLocalChecked()));
    };
    if (state->busy || state->closing) { fail("SenseVoice is busy or stopping"); return; }
    auto work = std::make_unique<Work>();
    work->state = state;
    work->isolate = isolate;
    work->operation = operation;
    if (operation == 1) {
        if (args.Length() != 2 || !args[0]->IsFloat32Array() || !args[1]->IsString()) {
            fail("Expected PCM float samples and language"); return;
        }
        auto input = args[0].As<v8::Float32Array>();
        if (input->Length() == 0 || input->Length() > 120 * 16000) { fail("Invalid PCM length"); return; }
        work->samples.resize(input->Length());
        if (input->CopyContents(work->samples.data(), input->ByteLength()) != input->ByteLength()) {
            fail("Detached PCM buffer"); return;
        }
        for (float sample : work->samples) if (!std::isfinite(sample) || sample < -1 || sample > 1) {
            fail("Invalid PCM sample"); return;
        }
        v8::String::Utf8Value language(isolate, args[1]);
        work->language.assign(*language, language.length());
    } else if (args.Length() != 0) { fail("Unexpected SenseVoice arguments"); return; }
    auto resolver = v8::Promise::Resolver::New(context).ToLocalChecked();
    args.GetReturnValue().Set(resolver->GetPromise());
    work->context.Reset(isolate, context);
    work->resolver.Reset(isolate, resolver);
    work->request.data = work.get();
    state->cancelled.store(false);
    state->busy = true;
    const int code = uv_queue_work(node::GetCurrentEventLoop(isolate), &work->request, Execute, Complete);
    if (code != 0) {
        state->busy = false;
        resolver->Reject(context, v8::Exception::Error(
            v8::String::NewFromUtf8Literal(isolate, "Cannot schedule SenseVoice inference"))).FromMaybe(false);
    } else work.release();
}
void Load(const v8::FunctionCallbackInfo<v8::Value>& args) { Queue(args, 0); }
void Transcribe(const v8::FunctionCallbackInfo<v8::Value>& args) { Queue(args, 1); }
void Unload(const v8::FunctionCallbackInfo<v8::Value>& args) { Queue(args, 2); }
void Cancel(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    static_cast<State*>(args.Data().As<v8::External>()->Value())->cancelled.store(true);
}
}

bool InstallSenseVoice(v8::Local<v8::Context> context, const std::string& dataRoot)
{
    auto* isolate = context->GetIsolate();
    auto state = std::make_unique<State>();
    state->models = dataRoot + "/speech-to-text/sensevoice/models";
    auto external = v8::External::New(isolate, state.get());
    auto object = v8::Object::New(isolate);
    const std::pair<const char*, v8::FunctionCallback> methods[] = {
        {"load", Load}, {"transcribe", Transcribe}, {"unload", Unload}, {"cancel", Cancel}
    };
    for (const auto& [name, callback] : methods) {
        v8::Local<v8::Function> function;
        if (!v8::Function::New(context, callback, external).ToLocal(&function) ||
            !object->Set(context, v8::String::NewFromUtf8(isolate, name).ToLocalChecked(), function).FromMaybe(false)) return false;
    }
    if (!context->Global()->Set(context, v8::String::NewFromUtf8Literal(isolate, "dshSenseVoiceNative"), object).FromMaybe(false)) return false;
    state->cleanup = node::AddEnvironmentCleanupHook(isolate, Cleanup, state.get());
    state.release();
    return true;
}
