# DSH Go 鸿蒙移植架构

以社区项目 `ccch1mneyyy/dsh-Go` 的 Android v1.0.15 为对照。上游用 Flutter/Riverpod 做界面、纯 Dart 做客户端，Kotlin 管理 Android 本机引擎。应用包名为 `io.github.ccch1mneyyy.dsh_app`。 [发布页](https://github.com/ccch1mneyyy/dsh-Go/releases/tag/v1.0.15) · [上游架构](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/docs/architecture.md) · [Android 构建配置](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/app/android/app/build.gradle.kts)

## 当前集成状态（2026-11-16）

八组功能的实现及回归见[逐项清单](parity/full-implementation-checklist.md)，交付产物摘要见[第八批构建记录](parity/native-build-phase8.json)。安全删除与伙伴自动回忆使用固定上游补丁；删除墓碑通过受限目录句柄及不可覆盖的原子重命名兼容手机硬链接限制。原生插件资源、信号分享、媒体保存和主机切换均有真实协议或生命周期回归。下文首版与第二批手机记录是历史证据，本批新增能力仍按[真机清单](parity/phone-acceptance.md)验收。

## REA 发布包观察

分析对象是官方 arm64 APK，大小 210,847,089 字节。SHA-256 为 `231ac2a5155e5460466529b99790f111484378c3b1f579dc00cef0fe418928cb`，与发布元数据一致。Android `apksigner` 另外通过了 v2、v3 签名完整性验证。

| REA 操作 | 观察 | Evidence ID |
| --- | --- | --- |
| `inspect_android_package` | APK 包名 `io.github.ccch1mneyyy.dsh_app`，versionName 1.0.15，versionCode 11101246，minSdk 26，targetSdk 28。清单包含前台服务和无障碍声明。 | `ev_3634ed2f1951fdbb82641f364c60ecf30116020f4d7d9eff99e0aca7332c0229` |
| `identify_flutter_build` | 确认 ARM64 Flutter。APK 含 `libapp.so` 和 `libflutter.so`，观察到 Dart 快照哈希 `0451907c2eaa8467e848c0067bfe8ed4`。 | `ev_285ad52581f31029d6c5647555af4010833b027a55fe0a9e0f8057ce65c610c4` |
| `inspect_artifact` | ZIP 中央目录记录了 640 个成员。进一步检查其中的运行时 manifest，确认随包分发 Ubuntu 24.04.5、Node 24.22.1、DSH 0.2.2-rc.1，以及 `rootfs-arm64-v8a.tar.xz`、`libproot.so` 和 `libproot-loader.so`。 | `ev_64bf59732713e38ac1930ac382ae74a83f12544934f1dc54b8d9e3a93a619102` |
| `inspect_android_method` | `DshService.onStartCommand` 有安装、安装完成和停止等分支，调用 Android 前台服务及通知 API。 | `ev_dde615af3a864c086080fd7aea3a7c7dd0d0eddf3f2d46759078964094a1c357` |

REA 的 `inspect_dart_aot` 无法从这个构建的动态符号表找到所需的快照符号。Dart 层的协议和逻辑由同版本开源代码补证。这些结果来自静态检查，未运行 Android APK。

## 原生客户端

ArkTS/ArkUI 原生页面与本机和远程 `dsh web` 共用会话协议。客户端以启动令牌换取 Cookie，通过 HTTPS 发起请求，通过 WSS `/api/remote.mux` 订阅会话和审批事件。反向代理可以额外使用 `Authorization`。远程模式支持会话列表、读取、新建、发送、中止和处理工具审批。

| 模式 | Android 上游 v1.0.15 | 鸿蒙版 |
| --- | --- | --- |
| 直接连接 `dsh web` | 本机和 SSH 启动的引擎使用 DSH Web 客户端协议 | 首版使用用户配置的 WSS 反向代理 |
| SSH | 通过密码或私钥认证、校验主机指纹、启动远端 DSH，再通过隧道连接 | 使用打包的 SSH 客户端建立连接，认证和指纹校验完成后启动或复用远端 DSH，经本机回环代理提供原生客户端接口 |
| DSHarness Remote | 身份校验与端到端加密，按条件尝试 LAN、WebRTC/TURN 或中继。只支持图片附件，插件管理限开关 | 支持登录和二维码配对。依次尝试 LAN/WebRTC、TURN 和服务中继，各通道统一验证主机身份并使用 Noise IK |
| 本机引擎 | App 自带 Ubuntu、Node.js 和 DSH。支持启动、停止、重启、日志与不加载插件的安全模式 | HAP 内嵌 ARM64 Node，支持手机本机引擎启动与首轮文本流程 |
| 插件、网页与手机操控 | 本机有插件桥和 DSH WebView。正常模式的本机引擎可经授权操控 Android 设备 | 待移植 |

[上游主机使用指南](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/docs/guide/zh/03-engine-hosts.md) · [手机操控指南](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/docs/guide/zh/04-phone-control.md) · [Dart 客户端](https://github.com/ccch1mneyyy/dsh-Go/tree/v1.0.15/packages/dsh_client) · [登录与传输协议](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/packages/dsh_client/lib/src/connection.dart) · [WebSocket 多路复用](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/packages/dsh_client/lib/src/mux.dart) · [远程传输](https://github.com/ccch1mneyyy/dsh-Go/tree/v1.0.15/packages/dsh_remote)

SSH 和中继由内嵌 Node 运行时管理，控制接口只监听手机回环地址，并校验引擎每次启动生成的随机凭据。建立连接后，数据端口分别通过 SSH 隧道或 Noise IK 通道复用原有 DSH 客户端。远程会话的 PTY 由主机维护，ArkUI 将输入与尺寸送入现有多路复用连接，并通过只加载本地资源的 ArkWeb 渲染终端。

直连使用打包的 werift 建立 DataChannel，根据选中的 ICE 候选报告 LAN、WebRTC 或 TURN。直连协商失败后使用新连接尝试下一个通道，主机身份或 Noise 握手校验失败会终止连接。图片缩略图沿用会话附件接口，进入可见区域才请求和解码，滑出或切换会话会取消旧请求并释放图像。

## 上游本机引擎与插件

- `runtime/build-runtime.sh` 在该标签默认打包 Ubuntu Base 24.04.5、Linux Node 24.22.1、`@deepseek-ai/dsh` 0.2.2-rc.1 和 pnpm 11.28.5。产物包括按 ABI 打包的 rootfs、manifest 和 Termux PRoot 原生文件。DSH 的版本与补丁绑定在 `runtime/patches/pins.json`。 [运行时构建](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/runtime/build-runtime.sh#L1-L75) · [补丁清单](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/runtime/patches/pins.json)
- `RuntimeInstaller.kt` 将 rootfs 安装到 Android 应用私有的 `filesDir/runtime/rootfs`。常规更新只替换受管理的引擎路径，保留 Linux 用户环境和工作区。Kotlin 的 `DshProcess.kt` 使用 `ProcessBuilder`，默认经 PRoot 启动。实验性的直接模式仍启动 Linux glibc 程序，由 `runtime/direct/processes.mjs` 调整 Node 子进程和 PTY 的调用。 [安装器](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/runtime/RuntimeInstaller.kt#L16-L44) · [启动器](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/runtime/DshProcess.kt#L113-L176) · [直接模式适配](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/runtime/direct/processes.mjs)
- App 通过 `dsh/runtime` 和 `dsh/runtime/events` 接收状态、日志和进度。引擎启动 `dsh web` 并监听回环地址，客户端用启动 token 换取 Cookie。模型调用仍由用户配置的提供方处理。 [上游平台通道和本地连接](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/docs/architecture.md)
- DSH 插件逻辑在引擎的 Node 环境执行。会话记录自带的 `dsh-go/view` 可以渲染为原生工具卡。面板、状态条及菜单依赖 `dshGo` 清单、`ctx.dshGo` 与 `/dsh-go/v1/*` 桥接。上游随本机运行时安装桥接到 `/opt/dsh-go/dsh-go-bridge`。本机开发插件建议放在 Linux 客体的 `/root/.dsh/dsh-go/plugins/`，加入 `web` profile。 [桥接源码](https://github.com/ccch1mneyyy/dsh-Go/tree/v1.0.15/runtime/bridge/dsh-go-bridge) · [插件协议](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/docs/design/native-plugins-protocol.md) · [插件路径及主机覆盖](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/docs/plugins/hosts.md)

## 鸿蒙手机本机运行的验证条件

华为的 `startNativeChildProcess` 公开接口支持平板和 PC/2in1，手机返回 801。NDK 的对应接口也有同类限制。HAP 集成并独立运行 ELF 的公开能力从 API 24 起支持 PC/2in1，PTRACE 调试权限同样面向 PC/2in1。鸿蒙 Node-API 是 ArkTS/JS 与 C/C++ 的桥接机制。 [ArkTS 子进程 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-ability-childprocessmanager/) · [NDK 子进程 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/capi-native-child-process-h/) · [HAP 可执行文件](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/hap-bin/) · [PTRACE 权限](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/permissions-for-all/) · [Node-API](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/napi-introduction/)

ARM64 SDK 能链接 `posix_spawn` 和 `openpty`。OpenHarmony 的公开 SELinux 策略把 `/system/bin/sh` 标为 `sh_exec`，并对执行转换设限，普通 HAP 不在例外域内。手机出厂系统的实际结果仍需设备验证。当前本机引擎未启用系统 Shell。 [文件标签](https://github.com/openharmony/security_selinux_adapter/blob/master/sepolicy/base/system/file_contexts#L327) · [Shell 执行规则](https://github.com/openharmony/security_selinux_adapter/blob/master/sepolicy/base/public/domain.te#L291-L294)

## 本机引擎

- `runtime/prepare-node.sh` 校验并准备 OpenHarmony ARM64 的 Node.js 24.22.1 与匹配的 libc++。`runtime/pack-dsh.sh` 使用 Android 版 v1.0.15 的固定依赖锁准备 DSH 0.2.2-rc.1，打包 JavaScript 和许可文件。HAP 携带完整运行时。
- ArkTS 首次启动把资源解包到应用私有目录，使用原生模块在后台线程创建 Node 环境。V8 使用 jitless，Node 的信号和标准流设置与宿主隔离。会话写入使用 C++ 提供的非阻塞文件锁。 [Node.js 嵌入 API](https://nodejs.org/docs/latest-v24.x/api/embedding.html)
- DSH 监听随机端口的 `127.0.0.1`。ArkTS 用沙箱内就绪标记提供的启动链接交换会话 Cookie。会话和工作区存放于 `filesDir/dsh-local-data`。DeepSeek 密钥通过本机 DSH API 注入内存凭据提供者，停止引擎后清除。
- 最初首轮仅开放文本对话。其后原生重写批次增加了受约束的工作区文件、技能和子代理工具，见 [当前进度](parity/native-progress.md)。任意子进程、外部原生 Node 扩展与任意安装脚本仍受普通手机 HAP 限制；随包插件桥、媒体、DS Bot 与原生动态面板已启用。SenseVoice 使用经过打包校验的 C++ 桥。jitless 模式用 Node HTTP/TLS 的实现提供流式 Fetch 接口，避免 Undici 加载 WebAssembly。

## 本机验证

- HarmonyOS SDK 交叉编译并打包 ARM64 HAP，核对了原生运行时、DSH ZIP 和版本摘要。REA 产物 Evidence ID 为 `ev_232a08bdf0db36530a01b0bce6b4800f0fb4bb1c54d80daa81ffd4e1900fcccb`。
- 使用同一份 C++ 引擎、Node.js 24.22.1 和解包后的 DSH，在 Linux ARM64 通过启动、真实文件锁、停止重启，以及默认 DeepSeek 和 OpenAI 兼容协议的首轮流式对话。测试模型在本机返回固定内容。
- Mate 60 Pro+ 的首次启动触发了沙箱对 `io_uring_setup`（系统调用 425）的限制。运行时准备脚本校验原始 ARM64 指令，并让 libuv 使用已有的 epoll 回退。修复后的签名 HAP 已覆盖安装。 [Node 24.22.1 中的 libuv 回退实现](https://github.com/nodejs/node/blob/v24.22.1/deps/uv/src/unix/linux.c)
- Mate 60 Pro+ 启动本机引擎后，首次发送消息时返回 `EACCES/link`。运行包只在首次会话日志发布遇到该权限错误或 `EPERM` 时使用 `renameat2(RENAME_NOREPLACE)`。临时文件同步、目录同步和已存在日志保护继续执行。 [OpenHarmony 应用域硬链接规则](https://github.com/openharmony/security_selinux_adapter/blob/master/sepolicy/base/public/normal_hap.te#L43)
- Mate 60 Pro+（HarmonyOS 7.0.0.111，API 26）安装调试签名包后，本机引擎启动成功。用户在手机输入 API Key，发送测试消息后界面显示 DeepSeek 回复 `HARMONY_DSH_OK`。返回会话列表再打开，消息仍可读，应用沙箱内也生成了正式会话日志。
- 2026-11-13 的 ArkUI 扩展版在同一手机再次完成真实首轮；模型使用 write/read/edit/read 在沙箱内创建并修改文件。覆盖安装保留会话和文件，历史工具结果恢复正常。新增文件发布回调使用基于目录文件描述符的 `renameat2(RENAME_NOREPLACE)`，不依赖鸿蒙 HAP 禁止的硬链接。更细范围和未验收项见 [原生实现进度](parity/native-progress.md)。

## 首版远程客户端验证

- DevEco Studio 26.0.0.851 使用 API 26 构建了兼容 API 12 的 HAP。REA 识别最终产物为 HAP，包内含 `ets/modules.abc` 和 Stage 模块清单。SHA-256 为 `9e04015e9d6a2f3c481cfb66fe5a6c25b06de3a3c6c01d11e6520dd28deba40d`，REA Evidence ID 为 `ev_250f60ac2fcc45448e3cfc0d831e8e6b1746575382a483df093c340e5b047bf2`。
- 用隔离的真实 DSH 0.2.2-rc.2 主机验证令牌登录、工作区、会话创建与读取、中止请求。使用本地确定性 SSE 模型验证发消息、流式回复及最终记录，并用一条只打印固定文字的工具调用验证拒绝和允许一次。用捕获的真实事件测试 ArkTS 消息及审批解析。
- DevEco Previewer 渲染了 ArkUI 连接页。HAP 未签名，鸿蒙设备上的安装、TLS、软键盘和实机连接还需要验证。
