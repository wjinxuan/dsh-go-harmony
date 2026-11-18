#ifndef DSH_SENSEVOICE_ENGINE_H
#define DSH_SENSEVOICE_ENGINE_H
#include <atomic>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

class SenseVoiceEngine {
public:
    SenseVoiceEngine();
    ~SenseVoiceEngine();
    void Load(const std::string& models);
    std::string Transcribe(const std::vector<float>& samples, const std::string& language,
        const std::atomic_bool& cancelled);
    void Unload();
private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
#endif
