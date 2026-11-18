# 第三方声明

原版 dsh-Go 的名称、标识和吉祥物适用单独的授权条款。[上游素材说明](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/ASSETS.md)

- 图标字体 `DshIcons.ttf` 来自 dsh-Go v1.0.15，基于 Phosphor Icons 2.1.1 的 MIT 图标子集，并包含 dsh-Go 的改绘图标。[Phosphor MIT 许可证](entry/src/main/resources/rawfile/fonts/Phosphor-MIT.txt) · [上游声明](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/THIRD_PARTY_NOTICES.md#phosphor-iconsmit)
- JetBrains Mono 采用 SIL Open Font License 1.1。[字体许可证](entry/src/main/resources/rawfile/fonts/JetBrainsMono-OFL.txt)
- 终端使用 xterm.js 6.0.0 及 Fit 0.11.0，采用 MIT 许可证。[源码](https://github.com/xtermjs/xterm.js/tree/6.0.0) · [xterm.js 许可证](entry/src/main/resources/rawfile/terminal/XTERM-LICENSE.txt) · [Fit 许可证](entry/src/main/resources/rawfile/terminal/XTERM-FIT-LICENSE.txt)
- 加密中继按 DSHarness Remote v1 实现，协议参考及测试向量随 MIT 许可证分发。[DSHarness Remote](https://github.com/liguobao/ds-harness-remote) · [许可证](tests/fixtures/dsh-remote/LICENSE)
- WebRTC 使用 werift 0.26.0，采用 MIT 许可证。其依赖 Mediabunny 1.65.2 采用 MPL-2.0，对应源码和依赖许可证随 npm 包提供。[werift 许可证](runtime/webrtc-deps/LICENSE) · [Mediabunny 1.65.2 源码](https://registry.npmjs.org/mediabunny/-/mediabunny-1.65.2.tgz)
- 本机 SSH 和 PNG 编解码使用固定版本的 ssh2 1.17.0 和 pngjs 7.0.0。完整许可证随打包依赖提供。[ssh2](https://github.com/mscdex/ssh2/tree/v1.17.0) · [pngjs](https://github.com/pngjs/pngjs)
- 构建脚本安装 DeepSeek Harness 及其 npm 依赖，并对少量模块应用 HarmonyOS 兼容性补丁。依赖的许可证随各自 npm 包提供。[DeepSeek Harness 许可证](https://github.com/deepseek-ai/deepseek-harness/blob/master/LICENSE) · [打包脚本](runtime/pack-dsh.sh)
- 本机引擎使用 OpenHarmony 版 Node.js 和 LLVM C++ 运行库。[运行时来源与修改](entry/src/main/resources/rawfile/node-licenses/provenance.txt) · [运行时许可证](entry/src/main/resources/rawfile/node-licenses)

- 数学公式采用 KaTeX 0.19.1，图表采用 Mermaid 11.4.1，均随包离线分发并采用 MIT 许可证。[KaTeX 许可证](entry/src/main/resources/rawfile/render/KATEX-LICENSE.txt) · [Mermaid 许可证](entry/src/main/resources/rawfile/render/MERMAID-LICENSE.txt)。版本及完整依赖摘要见 `runtime/render-deps/package-lock.json`。
- ANSI 解析按原版移植，原版注明源自 PiPilot，Copyright (c) 2026 CikeSeven，采用 MIT 许可证。[许可证](entry/src/main/resources/rawfile/render/PIPILOT-LICENSE.txt)。

- 插件 Web 席位与页面定位脚本原样取自 dsh-Go v1.0.15（`a9877420ab9aee121134faf01b6a92a39ce0b05b`），遵循 AGPL-3.0。[素材来源](entry/src/main/resources/rawfile/islands/SOURCE.txt) · [许可证](entry/src/main/resources/rawfile/islands/LICENSE.txt)。
- 会话离线回放使用同一固定版本的原版播放器模板，遵循 AGPL-3.0，打包模板保留原版 CSP 与隔离规则。[原版播放器](runtime/vendor/replay/viewer.html) · [许可证](runtime/vendor/replay/LICENSE)。

- DS Bot 使用固定 dsh-Go 基线引用的官方 0.2.3 源码与移动端协议增量，遵循 Apache-2.0；具体提交、保留的修复与 Harmony 调度适配见[来源记录](runtime/vendor/ds-bot/SOURCE.md)及[许可证](runtime/vendor/ds-bot/LICENSE)。
- 伙伴 Recall、执行结果 Signals、安全删除及定时任务独立授权采用固定 dsh-Go v1.0.15 的原版补丁，遵循 AGPL-3.0；随包保留原补丁、来源、完整性摘要与许可证。见[Recall](runtime/vendor/companion-recall-patches/SOURCE.md)、[Signals](runtime/vendor/companion-signals-patches/SOURCE.md)、[删除](runtime/vendor/session-deletion/SOURCE.md)与[任务授权](runtime/vendor/schedule-authorization/SOURCE.md)。
- 本机 SenseVoice 使用 sherpa-onnx 1.13.8 与其固定 ONNX Runtime，来源、模型摘要与许可证见[原生语音记录](docs/parity/sensevoice-native.md)及[随包声明](entry/src/main/resources/rawfile/sensevoice-NOTICES.txt)。
