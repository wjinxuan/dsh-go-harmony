#include "sensevoice_engine.h"
#include <sherpa-onnx/c-api/c-api.h>
#include <algorithm>
#include <stdexcept>

namespace {
template<class T, void (*Destroy)(const T*)> using Owned = std::unique_ptr<const T, decltype(Destroy)>;
using Recognizer = Owned<SherpaOnnxOfflineRecognizer, SherpaOnnxDestroyOfflineRecognizer>;
using Detector = Owned<SherpaOnnxVoiceActivityDetector, SherpaOnnxDestroyVoiceActivityDetector>;
void CheckCancelled(const std::atomic_bool& cancelled)
{
    if (cancelled.load()) throw std::runtime_error("SenseVoice operation cancelled");
}
}

struct SenseVoiceEngine::Impl {
    std::string model, tokens;
    SherpaOnnxOfflineRecognizerConfig config{};
    Recognizer recognizer{nullptr, SherpaOnnxDestroyOfflineRecognizer};
    Detector detector{nullptr, SherpaOnnxDestroyVoiceActivityDetector};
};
SenseVoiceEngine::SenseVoiceEngine() = default;
SenseVoiceEngine::~SenseVoiceEngine() = default;
void SenseVoiceEngine::Unload() { impl_.reset(); }

void SenseVoiceEngine::Load(const std::string& models)
{
    auto next = std::make_unique<Impl>();
    next->model = models + "/sensevoice-onnx/model.int8.onnx";
    next->tokens = models + "/sensevoice-onnx/tokens.txt";
    auto& config = next->config;
    config.feat_config.sample_rate = 16000;
    config.feat_config.feature_dim = 80;
    config.model_config.sense_voice.model = next->model.c_str();
    config.model_config.sense_voice.language = "auto";
    config.model_config.sense_voice.use_itn = 1;
    config.model_config.tokens = next->tokens.c_str();
    config.model_config.num_threads = 2;
    config.model_config.provider = "cpu";
    config.decoding_method = "greedy_search";
    next->recognizer.reset(SherpaOnnxCreateOfflineRecognizer(&config));
    if (!next->recognizer) throw std::runtime_error("SenseVoice model could not be loaded");
    const auto vad = models + "/silero/silero_vad.onnx";
    SherpaOnnxVadModelConfig vc{};
    vc.silero_vad.model = vad.c_str();
    vc.silero_vad.threshold = .5f;
    vc.silero_vad.min_silence_duration = .5f;
    vc.silero_vad.min_speech_duration = .25f;
    vc.silero_vad.max_speech_duration = 30;
    vc.silero_vad.window_size = 512;
    vc.sample_rate = 16000;
    vc.num_threads = 2;
    vc.provider = "cpu";
    next->detector.reset(SherpaOnnxCreateVoiceActivityDetector(&vc, 31.5f));
    if (!next->detector) throw std::runtime_error("Silero VAD model could not be loaded");
    impl_ = std::move(next);
}

std::string SenseVoiceEngine::Transcribe(const std::vector<float>& samples, const std::string& language,
    const std::atomic_bool& cancelled)
{
    if (!impl_) throw std::runtime_error("SenseVoice model is not loaded");
    if (language != "auto" && language != "zh" && language != "en" && language != "yue" &&
        language != "ja" && language != "ko") throw std::runtime_error("Unsupported SenseVoice language");
    if (samples.empty() || samples.size() > 120 * 16000) throw std::runtime_error("Invalid recording length");
    CheckCancelled(cancelled);
    auto& p = *impl_;
    p.config.model_config.sense_voice.language = language.c_str();
    SherpaOnnxOfflineRecognizerSetConfig(p.recognizer.get(), &p.config);
    p.config.model_config.sense_voice.language = "auto";
    SherpaOnnxVoiceActivityDetectorReset(p.detector.get());
    std::string text;
    bool first = true;
    const auto drain = [&] {
        while (!SherpaOnnxVoiceActivityDetectorEmpty(p.detector.get())) {
            CheckCancelled(cancelled);
            Owned<SherpaOnnxSpeechSegment, SherpaOnnxDestroySpeechSegment> segment(
                SherpaOnnxVoiceActivityDetectorFront(p.detector.get()), SherpaOnnxDestroySpeechSegment);
            if (!segment) throw std::runtime_error("Silero returned no segment");
            std::vector<float> speech;
            if (first && segment->start > 0) {
                const auto start = static_cast<size_t>(segment->start);
                if (start > samples.size()) throw std::runtime_error("Invalid Silero segment");
                const auto from = start > 4800 ? start - 4800 : 0;
                speech.insert(speech.end(), samples.begin() + from, samples.begin() + start);
            }
            first = false;
            speech.insert(speech.end(), segment->samples, segment->samples + segment->n);
            Owned<SherpaOnnxOfflineStream, SherpaOnnxDestroyOfflineStream> stream(
                SherpaOnnxCreateOfflineStream(p.recognizer.get()), SherpaOnnxDestroyOfflineStream);
            if (!stream) throw std::runtime_error("SenseVoice stream could not be created");
            SherpaOnnxAcceptWaveformOffline(stream.get(), 16000, speech.data(), speech.size());
            // shortcut: a decode cannot be interrupted inside ONNX; cancellation joins its current segment.
            SherpaOnnxDecodeOfflineStream(p.recognizer.get(), stream.get());
            CheckCancelled(cancelled);
            Owned<SherpaOnnxOfflineRecognizerResult, SherpaOnnxDestroyOfflineRecognizerResult> result(
                SherpaOnnxGetOfflineStreamResult(stream.get()), SherpaOnnxDestroyOfflineRecognizerResult);
            if (!result || !result->text) throw std::runtime_error("SenseVoice returned no result");
            if (*result->text) { if (!text.empty()) text += ' '; text += result->text; }
            SherpaOnnxVoiceActivityDetectorPop(p.detector.get());
        }
    };
    for (size_t offset = 0; offset < samples.size(); offset += 512) {
        CheckCancelled(cancelled);
        SherpaOnnxVoiceActivityDetectorAcceptWaveform(p.detector.get(), samples.data() + offset,
            std::min<size_t>(512, samples.size() - offset));
        drain();
    }
    SherpaOnnxVoiceActivityDetectorFlush(p.detector.get());
    drain();
    return text;
}
