# 本机运行、恢复和网页模式

基线：ccch1mneyyy/dsh-Go `a9877420ab9aee121134faf01b6a92a39ce0b05b`（v1.0.15）。对照 `app/lib/state/settings_state.dart`、`hosts_state.dart`、Android 本机引擎服务的 safe-mode/reset 行为。本文记录宿主验证，不代表手机通过。

## 启动和恢复

`StartupPreferences` 独立保存 `auto_start_local`、`remote_auto_connect_on_startup` 和最后主机种类/稳定 ID，不保存启动 token。未显式保存时，物理内存不足 5 GiB 的设备默认不自动启动本机，其他设备及无法读取内存时默认 true；已有用户 true/false 始终优先。已完成引导、尚未手动选择时才执行启动策略。恢复已保存远程主机优先；关闭恢复时按本机自动启动选项处理；主机不存在或凭据失效由入口显示连接错误，不能悄悄连接别的远程主机。启动是打开应用时启动，并非后台系统开机自启。

嵌入式 Node 第一次启动时从 `uv_get_total_memory()` 获取物理内存，按固定原版规则将四分之一内存向下取整到 128 MiB，再限制到 512–2048 MiB，通过实际 `--max-old-space-size` argv 交给 V8。它限制的是 old space，不是整个进程 RSS。libuv 线程池仍采用默认 4；同进程已初始化的全局线程池不能用偏好设置即时切到原版 light 的 2，界面不会假装已调整。

正常模式两次启动或 120 秒内错误会自动尝试安全模式。手动退出安全模式为试运行，一次早期失败返回安全模式。ENOSPC 和上次进程被杀不累计崩溃次数。安全模式使用干净 `safe-profile`，保留 `profile/cordis.patch.yml`，会话、工作区、账号、模型仍是同一 dataDir。连续正常运行 120 秒后保存 `profile/cordis.good.patch.yml`。恢复先停止引擎，保存现有配置的 `.before-restore-<UUID>`，再替换并重启。

`runtime-state.json`、命令文件、日志均应用私有 0600。日志捕获 stdout/stderr 的完整行再脱敏，跨 write 分段 token 仍一起过滤。单行超过 16 KiB 省略，日志约 512 KiB 轮换；UI 读最后 300 行。版本来自应用包内 runtime SHA256，安装前真实摘要验证；运行版本与包内版本不同时提供重启更新入口。没有通过 npm 或未签名远程包替换应用原生运行时。

## 重置的数据边界

UI 两项保留选项与原版 `uiAndSkills` / `pluginsAndSettings` 对应。第二次明确确认后才停止引擎并写 `${dataDir}.reset-request`。默认仅选中保留界面/技能，未确认不执行。引擎下次启动先将根目录原子改名为 `.retired`，按持久计划迁移选中路径，全部完成后才删除其余文件；崩溃可续迁，冲突停止并保留 `.retired`。

- 界面/技能：`dsh-go`、`skills`、`workspace/.dsh/skills`、`workspace/.agents/skills`。
- 插件/设置：`profile`、`cordis.patch.yml`、`.env`、`.harmony-bundled-bot.json`（包内 Bot 启用选择）。
- 其余本机数据会删除，含会话、工作区源文件、`.harmony-account-credentials.json`、`.harmony-subscription-credentials.json`、`speech-to-text/sensevoice/models`。后续新增账号数据只要在 dataDir 下同样受此边界管理。
- 应用原生 preferences 和 AssetStore 在引擎目录之外，不会被误清空。原版 `uiAndSkills` 的 UI 路径是 DSH_HOME/dsh-go，也不等价于 Android 系统 preferences。

所有重置测试仅使用 `mkdtemp` fixture，从未对用户当前 dataDir 调用。

## Shell 和 PTY

`shell_probe.cpp` 使用真实 `openpty` + `posix_spawn`，仅执行固定 `/system/bin/sh -c 'test -t 0 && printf dsh-shell-ok'`，最长 3 秒并强制回收，返回实际 errno、退出值和握手结果。NAPI 异步执行，不阻塞 UI。宿主 `/bin/sh` 正常握手和不存在 executable 的 ENOENT 已测试；SDK arm64 真实链接 `--no-undefined` 通过。普通 HAP 的 `/system/bin/sh` 执行、SELinux 与 PTY 权限仍必须由手机上的此检查确认，宿主成功不能证明设备许可。当前 profile 继续禁用 subprocess/本机交互终端；没有用模拟 shell 代替系统能力。现有远程 PTY 使用远程服务。

## 网页与诊断

`WebModePanel` 由 native 页面打开当前连接的真实 DSH 网页。`DshClient.webSession()` 只读已认证 cookie/代理 Authorization，经已有认证 loopback control 创建独立 loopback 网页代理。初始随机 token 仅用一次，换成 HttpOnly/SameSite cookie；页面拿不到远程凭据。所有 HTTP/POST/WS 只到该连接的固定 origin/base path，代理不跟随跨源重定向；远端 Set-Cookie 不透传。反向代理 Authorization 同时用于资源和 WebSocket。退出页面/切换连接关闭代理；旧页面只能按自身 origin 关闭自身代理。ArkWeb 禁止文件访问、混合内容和外站主框架导航。15 分钟无请求回收。

网络诊断只读系统当前网络类型并请求当前主机的真实 engine capabilities，显示实测耗时和连接 generation 状态；没有将凭据送到第三方探针。

## 宿主证据

- `tests/check-engine-maintenance.sh`：启动策略 3 项，恢复/日志/重置 12 项通过。
- `tests/check-node-budget.sh`：C++ 原版内存边界静态断言，真实 Node 启动后的 V8 heap limit 验收。
- `tests/engine-recovery-live.mjs`：隔离真实 runtime 的损坏配置两次失败后进入安全模式，原配置、账号和工作区保留。
- `tests/web-proxy.mjs <runtime>`：真实 HTTP POST、重定向、文本/二进制 WS、认证隔离、禁止跨源、一次性启动、限定关闭通过。
- SenseVoice/订阅凭据和实际推理另见 `sensevoice-native.md` 及对应测试。
