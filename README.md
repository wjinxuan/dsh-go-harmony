# Harness Pocket

面向 HarmonyOS 的非官方 DeepSeek Harness 客户端。使用 ArkTS、ArkUI 和 Stage 模型，可在手机内运行 DeepSeek Harness，也可连接电脑或服务器。当前接入会话、模型和引擎设置、工作区文件、技能、插件盘点、后台任务、自动化及子代理入口，功能按连接主机实际能力提供。

当前是已验证本机首轮对话的基础版本，尚未完成原版全部页面和功能。[全量复刻对照与验收](docs/parity/README.md)记录了原版 v1.0.15 的范围、现有差异及移植路线。

## 致谢与许可证

向原作者 Chimney（ccch1mneyyy）和 dsh-Go 的贡献者致谢。感谢你们开源了把 DeepSeek Harness 带到手机上的实现，为这个鸿蒙移植提供了界面、交互和通信协议的参考。欢迎到原项目为他们点个 Star。[原项目 dsh-Go](https://github.com/ccch1mneyyy/dsh-Go) · [原作者 Chimney](https://github.com/ccch1mneyyy)

本项目基于 dsh-Go v1.0.15，使用 ArkTS 和 ArkUI 重写客户端，并适配鸿蒙的本机运行时、文件访问和凭据存储。首次公开源码于 2026 年 11 月 13 日。项目源码采用 GNU AGPL v3，第三方组件按各自许可证分发。[移植基线](https://github.com/ccch1mneyyy/dsh-Go/tree/v1.0.15) · [AGPL v3](LICENSE) · [第三方声明](THIRD_PARTY_NOTICES.md)

## 构建与安装

首次克隆后，运行 `cp build-profile.example.json5 build-profile.json5` 生成本机的构建配置。然后使用 DevEco Studio 26.0.0.851 和 HarmonyOS API 26 SDK 打开本目录。应用包名为 `com.dshgo.harmony`，编译目标为 API 26，清单最低版本为 API 12。当前本机运行时打包面向 ARM64 手机，设备兼容性以实测为准。

在 macOS 上也可以从本目录运行以下命令。DevEco 安装到其他位置时，请修改第一行。

```sh
deveco='/Applications/DevEco-Studio.app/Contents'
export DEVECO_SDK_HOME="$deveco/sdk"
export NODE_HOME="$deveco/tools/node"
export JAVA_HOME="$deveco/jbr/Contents/Home"
export PATH="$NODE_HOME/bin:$deveco/tools/ohpm/bin:$PATH"
./runtime/prepare-node.sh
sh runtime/pack-dsh.sh
ohpm install --all
"$deveco/tools/hvigor/bin/hvigorw" --mode module -p module=entry@default \
  -p product=default -p buildMode=debug assembleHap --no-daemon
```

默认产物位于 `entry/build/default/outputs/default/entry-default-unsigned.hap`。真机安装前，在 DevEco Studio 的 **Project Structure → Signing Configs** 为本项目生成调试签名，然后运行到已连接设备。DevEco 将签名配置写入本机的 `build-profile.json5`，该文件由 Git 忽略。 [华为自动签名说明](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ide-signing-auto/)

## 手机本机启动

1. 首次打开 Harness Pocket，按引导选「本机」，设置外观和访问范围，再填入 DeepSeek API Key。之后可直接在启动页连接。
2. 首次启动会解包 DSH 运行时，之后复用手机沙箱中的副本。进入对话首页后可以直接输入消息；左上角打开会话列表，右上角加号新建对话。
3. 在会话侧栏进入「设置 → 本机引擎」可停止引擎。勾选「记住 API Key」后，凭据由 HarmonyOS 安全资产存储保护，解锁后重启或覆盖安装可继续使用。未勾选时仅在本次运行中使用。启动页或模型设置可删除已保存的 Key。

手机内的 Node.js 24.22.1 运行 DSH 0.2.2-rc.1。当前默认模型是 `deepseek-flash`，由手机联网调用 DeepSeek API。工作区 read/write/edit、技能与子代理已完成首批真机验证；第二批增加全文搜索、归档恢复、目录选择、队列管理、提问、目标/待办/轨迹/上下文、权限选项和会话 ZIP 导出，宿主验证与真机待验项目分列于 [原生重写进度](docs/parity/native-progress.md)。 [DeepSeek API 文档](https://api-docs.deepseek.com/zh-cn/guides/anthropic_api/)

## 连接电脑或服务器

1. 在已经配置好模型的 DeepSeek Harness 主机启动 Web profile。示例将 DSH 绑定到回环地址，由主机上的 HTTPS 反向代理接入。

   ```sh
   dsh web --no-open --host 127.0.0.1 --port 3080 \
     --public-url https://dsh.example.com/ --trusted-host dsh.example.com
   ```

2. 把示例域名替换为手机可访问的域名。反向代理需将根路径、查询字符串、Cookie 和 `/api/*` 转发至 `http://127.0.0.1:3080`，保留外部 Host，并允许 `/api/remote.mux` 升级为 WebSocket。建议使用标准 HTTPS 端口 443，并保留 WebSocket 的 Origin 校验。使用受系统信任的 TLS 证书。入口有额外 Basic 或 Bearer 认证时，将完整授权值填写到应用的「反向代理授权」。
3. 在应用选择「远程主机 → 连接电脑或服务器」，填写名称，粘贴 `dsh web` 打印的完整 `https://…/?token=…` 启动链接，点「保存并连接」。应用以启动令牌换取 DSH 会话 Cookie；默认只保存主机资料，勾选「安全保存连接凭据」后才将链接和代理授权写入鸿蒙安全资产存储。可以编辑、删除或重新连接保存的主机。
4. 打开已有会话或新建会话，文件、Shell 命令、后台任务在电脑上执行。未选择工作区时采用电脑 DSH 的默认目录；选择工作区后会话归入该工作区。审批会展示实际命令和参数，拒绝后不执行该操作。「更多功能 → 后台任务」可查看输出和状态并取消任务。
5. 抽屉的主机入口与设置中的主机管理共用同一页面。切到电脑不会停止手机本机引擎；切回本机可复用仍有效的内存凭据或已安全保存的 Key。切换不会自动重发命令。

远程模型使用电脑主机的凭据。Mac 原版客户端的账号登录对应「DeepSeek Account」，与「DeepSeek API」的 API Key 分开；选择账号模型时无需再填 API Key。使用独立 `DSH_HOME` 的 Web 主机不会自动继承桌面端登录，需要单独登录或由主机所有者配置授权。启动链接的 `token` 只负责连接主机，不是 DeepSeek 模型凭据。

API 26 支持非默认端口的 WebSocket Origin，较旧系统建议使用标准 HTTPS 443 端口。[Mac 远程执行与 USB 真机验收方法](docs/parity/remote-mac-verification.md)。USB 转发仅用于开发测试，日常远程访问使用上述 HTTPS/WSS 入口。

SSH、DSHarness Remote 配对与加密中继、交互终端、附件、手机操控和动态插件尚未移植。手机本机引擎仍不支持 Shell 子进程；电脑端的命令和任务由原版 DSH 执行。详见 [REA 逆向与架构记录](docs/architecture.md)。

## 协议自检

使用 Node.js 24.9 或更新版本运行协议及本机引擎自检。本机引擎自检以真正的 DSH 执行一轮请求，模型回复由本地测试服务提供。

```sh
sh tests/check-dsh-wire.sh
sh tests/check-markdown.sh
sh tests/check-engine-features.sh
sh tests/check-settings.sh
sh tests/check-onboarding.sh
sh tests/check-remote-hosts.sh
node --disable-warning=ExperimentalWarning --test tests/remote-switch.test.mjs
sh tests/check-session-management.sh
sh tests/check-question-drafts.sh
sh tests/check-session-detail.sh
sh tests/check-session-options.sh
sh tests/check-session-export.sh
sh tests/check-dsh-client-live.sh
smoke_dir=$(mktemp -d)
unzip -q entry/src/main/resources/rawfile/dsh-runtime.zip -d "$smoke_dir"
node tests/local-engine-smoke.mjs "$smoke_dir" --deepseek --deny-session-link --tools
rm -rf "$smoke_dir"
```

运行真实主机的协议探测时，请使用一个临时 DSH 数据目录。先安装 Python 的 `websockets` 依赖，再把该实例的启动日志传给探测脚本。脚本会在临时实例上创建会话。

```sh
python3 tests/dsh-live.py /path/to/disposable-dsh.log
```

Linux 原生发布自检使用 C++20 编译器、libuv 开发包、`timeout` 和 ABI 匹配的 Linux libnode 与头文件。以下命令的默认库名是 `libnode.so.137`。如需指定库文件，可将其绝对路径作为第二个参数，并保证动态加载器可找到它。

```sh
sh tests/check-native-publish.sh /path/to/node-v24.22.1/include/node
```

会话与工作区的原子发布、冲突保护和路径检查已在 Debian sid ARM64 的 libnode 24.22.1 上验证。该自检仅替换鸿蒙日志头，编译实际引擎源文件。同一桥接代码在 Mate 60 Pro+ 已完成真实模型的文件创建、读取和修改；完整越界与符号链接测试仍以 Linux/宿主记录为准。
