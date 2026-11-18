# 八组一比一复刻验收清单

固定来源：dsh-Go v1.0.15，`a9877420ab9aee121134faf01b6a92a39ce0b05b`。本文状态范围：phase9 / 2026-11-17 开发环境复验历史快照。
用户要求：八组开发与开发环境检查完成后，再安排真机测试。phase9 当时未开展新增真机测试；后续已经逐项真机验收并修复至 phase25，当前仍是部分覆盖。最新产物与17项映射见 [真机清单](phone-acceptance.md#截至-phase24-的当前覆盖映射)、[11月18日设备记录](device-acceptance-20261118.md) 和 [phase25证据](native-build-phase25.json)。下列开发勾选不等于手机全项通过。

下文 `[x]` 表示对应原版功能已实现并有行为证据，不表示 Android 与 HarmonyOS 的系统权限相同，也不表示真机视觉验收通过。跨平台不等价处逐项列出；最终签名包、统一回归和嵌入摘要见 [phase9 验证记录](native-build-phase9.json)，不借用历史成绩代替。

## 1. 聊天输入

- [x] 文件/目录/会话 `@` 引用、原子引用签、剪贴板文字和原文语法；真实文件和引用对话进入模型上下文。
- [x] 完成回复重新回答、原图恢复、分叉、恢复队列、新草稿保护；排队附件立即发送和失败恢复。
- [x] 系统/主机语音输入、录音桥、权限与取消；本机 SenseVoice 下载、断点、摘要、加载、真实 native 推理、取消、重下载与删除。
- [x] 媒体配置、模型/参数/引用图、真实 prompt 头、生成进度与取消、结果预览/保存/分享、再生成。
- [x] 语音速记插件专用 `get-settings` / `set-settings` REST 配置，与短录音输入区分；插件缺失时进入实际插件管理。
- [x] 思路翻译 provider 配置、流尾与分段、缓存/失败重试、译文与原文切换。

证据：`check-mentions.sh`、`mentions-live.mjs`、`message-regeneration.test.mjs`、`queue-now.test.mjs`、`check-voice.sh`、`check-speech.sh`、`speech-live.mjs`、`check-sensevoice.sh`、`check-sensevoice-native.sh`、`check-media.sh`、`check-media-generation-live.sh`、`check-media-live.sh`、`check-cot-scribe.sh`、`check-voice-scribe-transport.sh`。

SenseVoice 宿主使用同份 C++、官方固定模型和真实音频推理；phase9 当时系统 ASR、麦克风、移动网络及设备 native 性能仍待手机；后续已有系统 ASR、SenseVoice 实际网络/SHA/加载及手机 WAV 推理证据，麦克风现由用户确认正常且不再复测（USER_CONFIRMED_NORMAL_NOT_RETESTED），不增加本轮代理通过数。第三方媒体/翻译/转写协议的成功响应使用隔离服务，不声称已向商业服务付费调用。

## 2. 聊天展示与会话

- [x] Math/Mermaid 隔离离线渲染、ANSI、连续工具分组、媒体/插件独立卡、完整 Diff 的行号/文件切换/复制/换行。
- [x] 实际回合制品文件读取、预览、保存与分享；同主机标题/文件夹/全文跨来源搜索。
- [x] 目标、计划、待办、上下文用量、折叠已完成轮次及会话详情的真实写入/订阅。
- [x] 永久删除完整原版引擎补丁：忙会话、活跃目标、未完成任务与子代理/调度引用拒绝；持久墓碑、日志清理、重试和重启后的禁止重建。

证据：`check-markdown.sh`、`render-browser.test.mjs`、`ansi.test.mjs`、`turn-fold.test.mjs`、`chat-artifacts.test.mjs`、`workspace-file-viewer.test.mjs`、`check-session-detail.sh`、`check-dsh-client-live.sh`、`check-session-deletion.sh`、`session-deletion-live.mjs`、`check-deletion-marker.sh`。删除验证只使用隔离临时会话；未删除用户会话。当前删除专项 14 项 core/源码守卫及 7 项真实存储/inbox 测试全通过。实际客户端另外验证删除、忙/目标/任务/关联拒绝、永久墓碑、原生发布回退和重启隔离。

## 3. 工作区与导航

- [x] 按主机保存工作区分组、置顶、最近选择；原版 before-ID 主机排序及回读确认。
- [x] 公共目录入口依据主机实际目录能力展示；不构造不可访问的系统目录。
- [x] 新对话创建前再次校验，preset→projection 确认→permission→projection 确认；未确认选项按主机和真实会话 ID 立即持久化，失败保留草稿并阻止默认权限发送。损坏存储不静默清空，不淘汰第 21 个未完成配置。
- [x] 右侧快捷面板及顺序/显示配置、会话信息、插件面板；窄屏与宽屏入口。
- [x] 原版固定 allowlist 页面深链、分享导入、论坛授权、DS Bot 单聊/群聊、应用生命周期暂存与恢复。深链不自动切换远程主机或发送草稿。
- [x] Harmony 静态桌面新对话/语音入口与伙伴桌面卡；近期会话保持应用内导航。Android 动态 pinned shortcut 能力不冒充已在普通 Harmony 手机验证。

证据：`check-workspace-shell.sh` 11 项、`launch-routing.test.mjs`、`check-notifications.sh`、`companion-widget.test.mjs`。实际 caller 已接入 Index/EntryAbility；本轮复核了新对话持久化发生在打开会话之前的顺序。

## 4. 本机引擎与远程

- [x] 实际 Shell/PTY 探测、进程 old-space 内存预算、安全模式、自动启动策略、连续失败恢复、已知正常配置快照。
- [x] 有界脱敏日志、包内运行时版本/摘要、重启更新、双确认重置及可恢复迁移。
- [x] 当前主机网页模式、一次性 loopback 入口、凭据隔离、退出回收；网络诊断、恢复上次主机。
- [x] 远程 HTTPS/WSS、SSH、加密 Relay/WebRTC、远端 PTY。

证据及精确边界见 [运行维护记录](runtime-maintenance.md)。`check-engine-maintenance.sh`、`check-node-budget.sh`、`engine-recovery-live.mjs`、`web-proxy.mjs`、`ssh-bridge-live.mjs`、`check-dsh-remote.sh`、`check-dsh-remote-rtc.sh`、`remote-dsh-live.mjs`、`terminal-browser.test.mjs`。普通 HAP 不因宿主 Shell 成功而获得手机进程权限；生产本机 preset 保持禁止 subprocess，远端实际执行。收尾另外使用原版 lock 安装、未叠加 Harmony 补丁的官方 DSH 0.2.2-rc.1，真实 Mac 远程客户端、隔离 OpenSSH 和终端 4 项全部通过（`/tmp/dsh-remote-reference-{remote,ssh,terminal}.log`）。

## 5. 账号、设置与外观

- [x] DeepSeek 账号/余额与授权；ChatGPT/Claude 订阅完整 begin/poll/answer/cancel/signOut，独立 0600 OAuth 凭据持久化。
- [x] 模型目录、渠道、默认/当前模型、推理档位、完整模型管理；子代理允许列表与 enabled 原子写入、revision 和回读确认。
- [x] 通知偏好、权限拒绝/设置返回、前台提示和后台 Want 路由；隐私、使用统计、引导权限/账号分支。
- [x] 宽屏双侧栏、轮次折叠、壁纸裁切/缩放/明暗/模糊、自定义主题、玻璃、字体与中英语言；原生性能与热状态监测。
- [x] 静态界面与状态文案接入共享中英字典；动态用户内容保持原文。最终新增页面的字典完整性由 `check-locale.sh` 统一检查。

证据：`check-account.sh`、`check-subscriptions.sh`、`subscription-live.mjs`、`subscription-credentials.mjs`、`check-model-panel.sh`、`check-settings.sh`、`check-onboarding.sh`、`check-appearance-notifications.sh`、`check-notifications.sh`、`check-usage-stats.sh`、`settings-native.test.mjs`、`check-locale.sh`。其中 settings-native 当前 12 项通过；账号/订阅外部 OAuth 使用隔离 runner，没有生产账号登录。

匿名统计确实按日记账、限流、关闭删除与轮换随机 ID，系统语言解析成实际 zh/en。原版收集端仅接受 Android sdk 26..60；Harmony 的真实 sdk 不符合时不发送，不伪造 Android 设备。5 项专项覆盖该边界，不能将此路径记作生产统计上报成功。系统权限成功只取实际 SDK 返回；phase9 当时通知、壁纸选择与玻璃效果待手机，后续已有通知正负例/恢复、壁纸绘制/关闭恢复及玻璃偏好专项证据；宽屏视觉仍需对应窗口条件。

## 6. 插件

- [x] 动态工具卡、菜单、面板、原生 schema 配置与模型 UI 回复；原版 dsh-ui 控件和隔离内容边界。
- [x] 包检查、安装/更新/取消/卸载、明确的安装脚本授权；实际安装结果与订阅状态回读。
- [x] 插件席位、预设组成、Cordis 和 `ns:<id>` 原生配置路由。

证据：`native-plugin.test.mjs`、`plugin-chart.test.mjs`、`model-ui-owner.test.mjs`、`plugin-seats.test.mjs`、`plugin-clipboard.test.mjs`、`check-native-plugins-live.sh`、`island-browser.test.mjs`。远程可写主机使用真实包管理协议；本机无 npm/spawn 的平台限制会明确拒绝安装脚本与外部包变更，库存/已有合法配置可读写，内置可选 DS Bot 有专用启用入口。

## 7. 分享与回放

- [x] 消息/回合选择、脱敏、加密托管链接、分享码、三类 conversation/profile/plugin 载荷导入和会话回放。
- [x] 配置/插件分享固定版本与 integrity；排除密钥、凭据、私人路径，预览差异、显式选择与最终导入确认。新安装 namespace 出现真实 schema 后重新规划，新增敏感项不得绕过审阅。
- [x] 本机 AGENTS/技能实际写入、确认前只读、摘要并发检查、独立备份；取消停止后续步骤，失败行不报成功。导入后的 AGENTS 真实进入模型请求，技能真实可发现。
- [x] 真实会话 ZIP 导出、文件保存、系统分享；剪贴板读取使用系统 PasteButton，不申请受限读取权限。

证据：`share.test.mjs`、`share-browser.test.mjs`、`share-cache.test.mjs`、`check-profile-share.sh` 当前 12 项、`profile-share-live.mjs`、会话导出既有专项。实际打包 runtime 完成 source→prepare→decode→plan→确认→apply、revision 设置 RPC、私有备份、技能与 AGENTS 模型注入。后续手机系统保存/选择、分享面板与取消、会话回放、配置和技能导入/备份已完成所列场景；商业托管发布、实际外部分享接收和插件安装仍未由这些结果覆盖。

## 8. 社区与系统

- [x] 原生论坛主题、分类、搜索、通知、发帖/回复、上传、喜欢/书签、用户页、分页、草稿；RSA 授权回调与加密私有凭据。
- [x] DS Bot 实际 hello/state/配置/模型/会话/群聊/记忆/用量/通知 feed/解绑删除，以及原版 Web/API 定时任务；使用固定官方 0.2.3 底包加移动端补丁（双 SHA 与逐文件审计记录），默认不启用，本机明确选择启用后重启。调度迁移保留任务 ID、暂停状态与历史，经过原版授权并保护并发新增任务。
- [x] 原版 13 项手机工具协议及权限/确认/取消；公开 SDK 可用部分连接真实节点、手势、系统意图、截屏与图片附件、剪贴板、通知和 handoff。
- [x] 桌宠素材/角色状态与应用内展示、伙伴小屋 light/full、语音、角色适配与动作、记忆、Recall、Initiative、同意与 Signals。
- [x] Recall 完整原版引擎补丁与真实 full preset；明确同意、干净会话绑定、确认记忆真实进入模型、其他会话隔离、撤销永久封存、开启状态重启后的旧绑定退役与新会话重新同意。
- [x] Initiative 原版 C212 状态机与先持久化再呈现；Signals 实际订阅、one-shot 预览/确认分享、连接/房间/授权/文本重验及共享配额。

证据：`check-forum.sh`、`check-dsbot.sh`、`dsbot-live.mjs`、`dsbot-schedules.test.mjs`、`dsbot-schedules-live.mjs`、`check-phone.sh`、`phone-service.test.mjs`、`phone-live.mjs`、`pets.test.mjs`、`companion.test.mjs`、`companion-session.test.mjs`、`companion-voice.test.mjs`、`companion-voice-http.test.mjs`、`companion-widget.test.mjs`、`check-companion-contracts.sh`、`companion-recall-live.mjs`、`companion-signals.test.mjs`、`companion-signals-http.mjs`、`companion-signals-live.mjs`。Recall/Initiative/Adapt/Consent 和补丁源码守卫当前 27 项全通过（启用实际 runtime hash 检查，0 skip）。Signals 最终 fresh runtime 的 10 项纯测试、HTTP 和实际 producer 链路均 exit 0，日志 `/tmp/dsh-release-signals-{pure,http,live}.log`；宿主真实 SenseVoice 识别复跑 exit 0，`/tmp/dsh-release-sensevoice-native.log`。

角色舞台支持导入原版资源包；专有 Live2D 运行时及角色素材不随本开源仓库擅自分发。phase9 当时系统 TTS/AV、ArkWeb/WebGL 与 Form 卡均待手机；后续已验证合成媒体播放、完整网页/席位交互及两尺寸 Form 卡添加/点击/更新/移除。授权角色舞台、WebGL/角色声音、卡片周期刷新等未验分支仍保留，不以部分成功替代。

精确差异见 [手机操控](phone-native.md)、[论坛](forum-native.md)、[伙伴信号](companion-signals-native.md)、[SenseVoice](sensevoice-native.md)：普通手机 HAP 无 Android root/Shizuku、全局 app 列表、后台虚拟屏及任意悬浮窗权限；不伪装已授权。没有公开等价路由的键盘提交/部分系统意图明确返回不支持。DS Bot 调度兼容缺口已修复：原版 Web/API 调度真实可用，不新增原移动端没有的设置页；精确目标归属、并发 revision、同 ID 迁移保留暂停/时间/历史，自动换段经过原版授权问答。迁移失败或新增任务阻止旧段归档，不用 stopActivity 删除后来的任务。生产本机无 bash Signals producer，真实返回 unavailable；宿主隔离测试启用原执行器验证完整 producer→SSE，不能据此宣称手机 Shell 可用。

### DS Bot 固定版本与调度收尾

原版 fixture `dsbot_v023_mobile.json` 的 `base` 为 `4a7b55069ad300eae8be42a74f31bc170b40ead7`，`mobilePr` 为 `6f3e1b3e8603abd84820b334a7f99985236dbbdf`；原生测试明确期望 0.2.3 加移动接口。最终 vendor 按该组合保留官方 0.2.3 的持久记忆、请求/交接及等待迁移后归档修复，移植移动增量，未把旧 0.2.1 单独分支改名。

当前宿主调度采用 host-wide API。兼容适配只以 `target.kind/sessionId` 判断归属，不使用历史 involvedSessionIds 授权；删除先 view 并带 expectedUpdatedAt，任务换段同 ID 修改 target，仅移动 active/paused，历史 ended/inactive 留原段。显式 Web 人工操作保留 human 语义，自动迁移使用真实 originating Session actor 并接受原版 userQuestions gate。拒绝、冲突和归档失败保留 restart marker；普通归档不强删竞态中新建任务。

证据：原生 DS Bot 10 项及兼容适配 6 项通过。最终 vendor 的官方 mobile/remote/part-switch/switch-keeps-input/schedules 回归 26 项通过、0 skip（`/tmp/dsh-bot-v023-final-upstream.log`）。`dsbot-schedules-live.mjs` 用实际原版调度、授权和持久化，测试 authenticated Web 新建/列出/删除、Bot/群归属、跨 Bot/普通会话拒绝、paused 重启、真实拒绝/授权迁移，以及最终枚举后新增任务仍存活。只有 native file-lock 和让测试调用内部迁移函数的临时 route 是替身；生产包未增加该 route。最终 freshpack 日志为 `/tmp/dsh-release4-dsbot-schedules.log`。

原版定时授权补丁完整移植，源码守卫 4 项通过、0 skip。`schedule-authorization-live.mjs` 在最终打包引擎上验证 danger-full-access/approval=never 仍显示专门授权问题；拒绝、取消、自定义答复和完整 120000 ms 超时均不新建任务；明确授权仅创建一个持久任务，编辑再次确认，等待期间的并发修改返回冲突。模型响应为合成服务，调度、问答、持久化和超时使用真实引擎，未执行付费模型或定时任务。日志 `/tmp/dsh-release4-schedule-authorization.log`。

## 最终验收与证据口径

- [x] 上述功能专项和实际 caller 收尾审计；发现的新插件 schema 复核、Recall ON 重启、分享预览可变文本及新对话保存顺序问题已补回归。
- [x] 76 条单元/UI/浏览器命令（612 项报告测试）及 38 条真实 runtime/原生/远程专项全部通过；包含独立官方 Mac DSH/OpenSSH/PTY、离线浏览器及真实 Linux 文件锁/原子发布/完整嵌入器。最终有效记录零失败、零跳过，命令与边界见 phase9 JSON。
- [x] 最终 ArkTS/C++ 编译与签名 HAP；独立签名/权限摘要、ZIP CRC、5 个 ARM64 native 库和嵌入 runtime 摘要一致。
- [x] 实际生成 ArkUI 观察器 10 项、RTC/TURN 5 项全部通过。中英、聊天/伙伴、扩展 UI/插件/分享已纳入本轮 612 项矩阵。
- [x] 最终构建摘要与真机步骤已更新；项目知识同步 1 项、0 错误。这是 phase9 当时的下一步；后续真机验收进行中，当前结果见上方链接，尚未全部完成。
- [ ] 同视口逐页视觉比对及手机权限/前后台/系统面板/真实录音与操控验证。

最新 WebRTC/强制 TURN 共 5 项、零跳过。`tests/check-turn-local.sh` 用独立 UDP-only、TCP-only 临时 coturn 服务强制中继，双方各 50,000 字节比对通过，候选均为 relay；默认入口经独立复跑通过并清理临时服务。phase8 中未配置服务导致的跳过保留为历史记录，本轮已补齐。此结果不代替公网 NAT、运营商网络和手机实际连接验收。

独立收尾再次执行 `profile-share-live.mjs`、`companion-recall-live.mjs`、`session-deletion-live.mjs /tmp/dsh-release-runtime` 均 exit 0，完整日志分别为 `/tmp/dsh-release-profile-share-final.log`、`/tmp/dsh-release-recall-final.log`、`/tmp/dsh-release-deletion-final.log`。

运行时行为测试以隔离临时 dataDir 和真实打包 DSH 为主体。模型、OAuth、Discourse 和部分原生平台接口在对应脚本中明确为替身；服务返回不等于真实外部账户或手机权限验证。历史真机成绩只适用于对应历史包，不替代此次新增功能。
