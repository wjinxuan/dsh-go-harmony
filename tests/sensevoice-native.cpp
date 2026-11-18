#include "sensevoice_engine.h"
#include <cassert>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
int main(int argc, char** argv) {
    assert(argc == 3);
    std::ifstream input(argv[2], std::ios::binary);
    std::vector<unsigned char> wav((std::istreambuf_iterator<char>(input)), {});
    assert(wav.size() > 44);
    size_t offset = 12, pcm = 0, count = 0;
    const auto u32 = [&wav](size_t i) { return uint32_t(wav[i]) | uint32_t(wav[i+1]) << 8 | uint32_t(wav[i+2]) << 16 | uint32_t(wav[i+3]) << 24; };
    while (offset + 8 <= wav.size()) {
        const auto size = u32(offset + 4);
        assert(offset + 8 + size <= wav.size());
        if (std::string(wav.begin() + offset, wav.begin() + offset + 4) == "data") { pcm = offset + 8; count = size / 2; break; }
        offset += 8 + size + (size & 1);
    }
    assert(count && count <= 120 * 16000);
    std::vector<float> samples(count);
    for (size_t i = 0; i < count; ++i) samples[i] = int16_t(wav[pcm+i*2] | wav[pcm+i*2+1] << 8) / 32768.f;
    SenseVoiceEngine engine;
    engine.Load(argv[1]);
    std::atomic_bool cancelled{false};
    const auto text = engine.Transcribe(samples, "zh", cancelled);
    assert(!text.empty());
    std::cout << text << '\n';
    cancelled.store(true);
    bool rejected = false;
    try { engine.Transcribe(samples, "zh", cancelled); } catch (const std::runtime_error&) { rejected = true; }
    assert(rejected);
    cancelled.store(false);
    assert(engine.Transcribe(std::vector<float>(16000), "auto", cancelled).empty());
    engine.Unload();
    rejected = false;
    try { engine.Transcribe(samples, "zh", cancelled); } catch (const std::runtime_error&) { rejected = true; }
    assert(rejected);
}
