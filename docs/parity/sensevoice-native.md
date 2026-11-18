# 本机 SenseVoice 模型与推理

上游基线：`ccch1mneyyy/dsh-Go@a9877420ab9aee121134faf01b6a92a39ce0b05b`，引擎锁 `0.2.2-rc.1`。逐项核对原版 `voice_model_assets.dart`、`voice_model_state.dart`、模型下载器，以及锁内 `dsh-experimental-speech-to-text-sensevoice/lib/worker.js`。模型是 3 个原始文件，没有压缩包解包步骤。

## 原生实现与边界

- 复用上游 `speechToText` 注册表、`speech/catalog|prepare|cancelPreparation|configure|transcribe` 协议；Harmony provider 替换需要 `spawn` 的 Linux 识别进程。
- `sensevoice_bridge.cpp` 在嵌入 Node 的 V8 上安装私有异步桥，`uv_queue_work` 执行实际 C API，异步 environment cleanup 等待 native 工作结束。
- `sensevoice_engine.cpp` 实际加载 SenseVoiceSmall INT8 和 Silero VAD v4；16 kHz、80 维特征、CPU 2 线程、30 秒 VAD 分段、首段 300 ms 前补、ITN、多语言 `auto/zh/en/yue/ja/ko` 与上游一致。未加载成功不能报告 ready；没有桥会明确失败。
- 当前 ONNX C API 不能中断段内 decode。取消会阻止后续分段、丢弃结果并等待当前 decode 完成；删除、关闭和 isolate 销毁同样等待，不能提前删除使用中的文件或 native 内存。
- 所用库是官方 **OHOS ARM64** 产物，不是 Android `.so`。构建需要先执行 `./runtime/prepare-sensevoice.sh`。CMake 缺依赖直接失败。

[官方 v1.13.8 发布资产](https://github.com/k2-fsa/sherpa-onnx/releases/expanded_assets/v1.13.8)：`sherpa-onnx-v1.13.8-ohos-arm64-v8a.tar.bz2`，SHA-256 `7473e1f6138c2d33a26adda01dd94f4d618089370957ed374f8cc0d50b8cdfa7`。`llvm-readelf -d` 验证依赖 `libhilog_ndk.z.so`、`librawfile.z.so`、`libonnxruntime.so`、`libc++_shared.so`、`libc.so`；归档内 ORT 版本为 1.16.3。许可随 HAP 的 `rawfile/sensevoice-NOTICES.txt` 携带。

## 模型管理

模型目录：`filesDir/dsh-local-data/speech-to-text/sensevoice/models`。不放在可由代理写入的工作区内。三个文件来自锁中的固定 revision，首先尝试原版 ModelScope 镜像，然后 Hugging Face 原始地址。

| 文件 | 字节 | SHA-256 |
| --- | ---: | --- |
| `sensevoice-onnx/model.int8.onnx` | 239233841 | `c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51` |
| `sensevoice-onnx/tokens.txt` | 315894 | `f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc` |
| `silero/silero_vad.onnx` | 1807522 | `a35ebf52fd3ce5f1469b2a36158dba761bc47b973ea3382b3186ca15b1f5af28` |

总计 241357257 字节。HTTPS 下载验证 redirect 协议、准确 Range/Content-Range、Content-Length、流式字节上限、文件类型和 SHA-256。60 秒无数据超时，保留 `.dsh-go.part` 供续传。下载前检查剩余空间并保留 100 MiB。重新下载先到 staging，完整校验后逐文件 rename，同固定内容的旧模型在失败时继续可用。取消等待 writer 和 native 结束，删除清理模型、partial 和 staging。wanted 标记原子写入，重新启动恢复已请求但未完成的下载。

管理操作只通过已有 authenticated loopback transportControl：`GET /sensevoice/state`、`POST /sensevoice/download|redownload|cancel|delete`。不接受 body，不允许外部控制地址。ArkUI `SenseVoiceModelPanel` 显示大小、进度、错误，包含流量提示、重下载和删除确认。

## 宿主验证（2026-11-16）

- `tests/check-sensevoice.sh`：15 个确定性测试通过，覆盖 pinned 清单、缓存复用、断点、忽略 Range、错误 Range、错误摘要、过大响应、取消 writer、symlink、HTTPS、native 缺失/加载失败不 ready、取消准备、失败重下载保留旧模型、删除等待推理。
- Harmony SDK arm64 对 `sensevoice_engine.cpp`、`sensevoice_bridge.cpp` 的 C++20 syntax 检查通过。
- 同源 C++ 连接官方 v1.13.8 macOS arm64 库，实际加载上述校验模型，识别官方固定 revision `test_wavs/zh.wav` 为“开饭时间早上9点至下午5点。”；验证静音为空、取消预检、卸载后拒绝。
- `tests/check-sensevoice-native.sh <models> <zh.wav> <host-lib-directory>` 编译同份 bridge/engine 为宿主临时 addon，验证真实 Promise 推理、busy 互斥、NaN 拒绝、取消、卸载，以及 Worker terminate 时 async cleanup 等待原生工作，全部通过。该 addon 仅供宿主验证；产品继续使用嵌入 V8 私有桥。
- 更新后的 runtime profile/module 覆盖临时解包运行时后，`speech-live.mjs` 通过：真正本地目录显示 sensevoice-local/unprepared；合成 RPC 服务仅验证现有客户端协议，不作为模型推理证据。

宿主依赖：官方 `sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts-lib.tar.bz2` SHA-256 `f3e0cbd86cc3f38dad30c97921b40e9a8bcc6f2c943777eb76ad77176993e417`。模型与音频从上述上游固定 revision 获取并在测试前校验。模型没有写入 Git，也没有打进 HAP。

真机加载、CPU/内存/耗时、录音到真实结果和移动网络中断恢复尚待用户最终设备验证；宿主通过不等于真机通过。
