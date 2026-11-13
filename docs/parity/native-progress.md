# DSH Go 鸿蒙原生实现进度

## 优先项：远程电脑 DSH（2026-11-13）

已接入 ArkTS / ArkUI 原生远程主机管理：引导、会话抽屉、设置共用入口，支持新增、编辑、删除、保存和重连 HTTPS/WSS 主机。主机资料不含令牌；用户勾选后，连接凭据由 AssetKit 保护。存储写入失败不删除原凭据，切换连接不停止手机本机引擎，不重发此前的命令，前一主机的会话与草稿会清除。

复用现有会话、文件、任务界面和 DshClient 协议，执行地点随主机切换。已修复 API 26 非默认端口 WebSocket Origin 与回环代理问题。审批要求会话、调用 ID、工具名称和完整参数匹配，Shell / `run_code` 展示实际命令 / 代码，无法完整展示时禁止允许。

真机已连接 Mac 原版 DSH，实际完成文件写入和读取、Shell 命令及后台任务；Mac 文件逐字节验证通过，手机原生任务详情显示真实 `mac-job-fixture` 输出及已完成状态。最终签名 HAP 覆盖安装后，无需重新输入远程凭据即可重连；手机审批拒绝后 Mac 没有产生目标文件。临时主机及凭据已从手机删除，手机切回本机引擎且无需再输入 Key。

文件、命令和后台任务验收使用 USB 反向转发和隔离的合成模型，执行工具的是 Mac 原版 DSH。另在 Mac 使用实际 ArkTS 客户端的 Node 适配器验证了公网 HTTPS/WSS，模型回复成功且 `turn/end` 为 `completed`。手机经公网接收模型回复仍待验证。日常使用需提供已配置模型及受信 HTTPS/WSS 的 DSH 主机。SSH、DSHarness Remote 登录配对 / 加密中继及交互终端仍未完成。[复现步骤](remote-mac-verification.md) · [签名构建收据](native-build.json)

这是 DSH Go v1.0.15 的 ArkTS / ArkUI 原生实现记录。原版全部页面、交互和视觉一比一复刻仍待完成。原版范围和验收依据见 [页面与交互清单](ui-audit.md) 与 [页面类清单](ui-pages.json)。

## 第二批原生实现与验证

| 入口 | 已接入的原生能力 |
| --- | --- |
| 首次引导与凭据 | 欢迎、运行位置、外观、访问范围、API Key、完成六步引导。本机环境准备与外观、访问步骤并行，远程选择交给实际主机连接页。用户可选择通过 HarmonyOS Asset Store 保存本机 Key。已解锁时读取，按应用身份隔离，关闭同步，支持替换和删除。引导完成标记与已有外观数据独立存放。 [引导](../../entry/src/main/ets/ui/OnboardingPanel.ets) · [安全存储](../../entry/src/main/ets/local/LocalKeyStore.ets) · [验证](../../tests/check-onboarding.sh) |
| 聊天互动 | 队列和结构化问题接入真实主机操作。队列面板包含编辑、撤回、插入引导、立即发送以及失败后的草稿恢复。问题支持单选、多选、自填、拒答和继续提问。能力取决于当前主机。 [队列](../../entry/src/main/ets/ui/ChatActivityPanel.ets) · [提问](../../entry/src/main/ets/ui/QuestionCard.ets) |
| 会话详情 | 轨迹和历史分页，依据实际工具结果汇总文件改动，目标建立/编辑/暂停/恢复/完成/清除，实时待办、计划状态和上下文用量。文件和子代理转到真实页面。插件标签在提供会话插件标签数据时显示。 [详情](../../entry/src/main/ets/ui/SessionDetailPanel.ets) · [验证](../../tests/check-session-detail.sh) |
| 会话和工作区管理 | 工作区目录选择与创建，会话搜索、归档列表、会话预设及权限选项接入主机。 [目录选择](../../entry/src/main/ets/ui/DirectoryPickerPanel.ets) · [会话搜索](../../entry/src/main/ets/ui/SessionSearchPanel.ets) · [会话选项](../../entry/src/main/ets/ui/SessionOptionsPanel.ets) |
| 会话导出 | 当前会话及后代的真实 ZIP 下载、取消导出、鸿蒙文件选择器保存和系统分享。校验 HTTP、MIME 与 ZIP 头，不覆盖已存在的缓存目标；只有系统分享完成事件才显示完成。宿主导出和临时文件测试已过；真机 ZIP 校验、Download 保存、系统分享面板打开和取消已验证，没有实际对外发送。 [导出页](../../entry/src/main/ets/ui/SessionExportPanel.ets) |
| 系统返回 | 设置、引擎功能、文件、模型页面优先退回子页，正在确认的主机写入结束后才允许退出。渠道和自动化任务编辑器提示放弃未保存更改。 [设置](../../entry/src/main/ets/ui/SettingsPanel.ets) · [引擎](../../entry/src/main/ets/ui/EngineFeaturesPanel.ets) · [文件](../../entry/src/main/ets/ui/FilesPanel.ets) · [模型](../../entry/src/main/ets/ui/ModelPanel.ets) |

第二批签名 HAP 已构建并覆盖安装，安装包内运行时摘要已核对。宿主对打包运行时执行了 67 条客户端断言，覆盖真实全文命中、权限、目标、待办和提问。引导、安全存储适配层及会话详情解析也通过宿主合成数据测试。

设置正文默认颜色回调的旧版闪退已修复；新增编译产物回归在旧版本失败、在新版本通过。最终 HAP 已真机打开并加载「引擎参数」页，随后返回本机对话首页；16:00 后没有新增故障记录。

## 第一批已接入的入口

| 入口 | 本轮实现 |
| --- | --- |
| 启动和主界面 | 本机启动进度、直接 HTTPS/WSS 主机连接、聊天壳、窄屏会话抽屉和宽屏侧栏、全部功能页和基础系统返回。 [主界面](../../entry/src/main/ets/pages/Index.ets#L526) |
| 会话和工作区 | 会话新建、打开、标题筛选、重命名、置顶、归档、分支。工作区选择、按可访问的目录路径添加、重命名、移除。工作区文件目录和前 500 行文本/Markdown 预览。 [会话](../../entry/src/main/ets/ui/SessionsPanel.ets) · [工作区](../../entry/src/main/ets/ui/WorkspacesPanel.ets) · [文件](../../entry/src/main/ets/ui/FilesPanel.ets) |
| 聊天和会话详情 | 文本发送、排队、中止、历史加载、流式回复、复制/引用、基础单项工具审批、折叠思考内容和工具结果、用量摘要、原生 Markdown。详情可转到文件、模型和分支。 [聊天](../../entry/src/main/ets/pages/Index.ets#L590) · [Markdown](../../entry/src/main/ets/ui/MessageBody.ets) |
| 外观 | 六套配色、浅色/深色/跟随系统、阅读字号、主题图标和等宽字体。外观选择通过应用偏好持久化。 [主题](../../entry/src/main/ets/ui/DshTheme.ets) · [偏好](../../entry/src/main/ets/ui/AppPreferences.ets) |
| 应用和引擎设置 | 设置总览、局部搜索、模型和服务商、可写主机的 API Key 管理和默认模型、按主机 schema 查看和修改引擎参数/权限/联网搜索、基础诊断和关于。本机引擎有状态、启动、停止和重启入口，重启后重新录入凭据。 [设置](../../entry/src/main/ets/ui/SettingsPanel.ets#L558) · [会话模型](../../entry/src/main/ets/ui/ModelPanel.ets) |
| 插件 | 主机库存、预设组成、官方市场和详情。支持管理的主机可启停插件与包、检查安装源、安装、取消和卸载。本机嵌入配置未启用插件管理，仍可读库存和预设组成。 [插件面板](../../entry/src/main/ets/ui/EngineFeaturesPanel.ets#L501) · [市场读取](../../entry/src/main/ets/ui/EnginePluginMarket.ets) |
| 技能和后台任务 | 读取会话技能、说明、适用范围和来源，预填 `/技能名`。订阅后台任务和输出，支持复制与确认后请求停止。 [技能与任务](../../entry/src/main/ets/ui/EngineFeaturesPanel.ets#L926) |
| 自动化任务 | 按标题、指令和规则搜索，按状态过滤，查看运行历史，创建、编辑、确认运行、暂停/恢复和确认删除。写入以主机的实际结果为准。 [任务详情](../../entry/src/main/ets/ui/EngineFeaturesPanel.ets#L971) · [编辑器](../../entry/src/main/ets/ui/EngineScheduleEditor.ets) |
| 子代理和团队 | 读取父会话的子代理和团队投影，按父会话地址读取子会话，可继续的子代理可发送消息及中止。团队页有成员、任务、消息和部分读取失败提示。 [子代理与团队](../../entry/src/main/ets/ui/EngineFeaturesPanel.ets#L379) |

## 第一批验证记录

| 环境 | 已验证 |
| --- | --- |
| macOS / DevEco Studio | ArkTS 编译与 HAP 打包通过。Markdown 与引擎功能解析测试覆盖多种 Markdown 块、调度日期/时间/周期边界、插件来源与版本选择、主机操作失败以及团队消息解析。 [Markdown 测试](../../tests/check-markdown.sh) · [引擎功能测试](../../tests/check-engine-features.sh) |
| 宿主本地 DSH 0.2.2-rc.1 | 使用回环模型服务与合成凭据验证启动、模型流、停止、工作区文件的读写和边界拒绝、技能加载、子代理 spawn/fork。客户端线协议验证覆盖会话和工作区管理、模型、设置、预设、技能、插件库存和后台任务订阅。另用实际本地 DSH 验证调度创建、编辑、立即运行、送达目标会话、历史和删除。 [运行时测试](../../tests/local-engine-smoke.mjs) · [客户端测试](../../tests/check-dsh-client-live.sh) |
| Linux ARM64 / Node 24.22.1 | 运行原生 C++ 嵌入路径，验证工作区文件原子创建、`EEXIST` 拒绝覆盖、路径和符号链接限制，以及既有会话日志的原子发布。 [原生工作区验证](../../tests/native-workspace-publish.cjs) · [本机桥接代码](../../entry/src/main/cpp/node_engine.cpp) |
| Huawei Mate 60 Pro+ | 本轮已验证原生首页、本机启动、真实 DeepSeek 首轮、模型选择、会话侧栏、浅深色切换、文件目录/预览，以及插件、技能、子代理、后台任务和自动化页的读取/空态。模型实际执行 write → read → edit → read，文件内容由独立读取确认。覆盖安装后测试会话、工具结果和文件仍可读。 [真机历史记录](../architecture.md) |

本轮真机发现并修复了三类差异：嵌入式 Node 的插件解析基准、ArkUI 对同标识旧行的复用，以及 Markdown 对标识符下划线的误处理。预设插件改为从打包目录解析，宿主回归带上与手机一致的 `--expose-internals`；消息及工具的可见内容改变时更新行标识，展开状态仍保留。

手机工作区测试文件为 `harmony-native-1418.md`，最终内容是 `HARMONY_EDIT_OK`。正常范围读取成功，父目录越界请求被拒绝。原有用户会话未删除，测试会话命名为「鸿蒙本机验证 2026-11-13」。第一批的 Key 由用户输入，只在引擎内存中存放。一次重新输入的 Key 未通过 DSH 的字符格式检查，未发出 HTTP。客户端现已增加相同规则的前置校验和固定中文提示，提示中省略密钥内容。

重新输入有效 Key 后，同一手机完成了 read 和子代理实际调用：子会话持久回复为 `NATIVE_SUBAGENT_OK`，有独立模型用量和完成事件；父会话收到 settled 通知并回复 `HARMONY_LIVE_OK`，原生子代理详情也显示了实际回复。父会话中的两条相同确认文本是不同消息 ID 的持久记录，并非重复渲染。

第一批签名包摘要见 [构建记录](native-build-phase1.json)。临时 HDC 端口转发已经清除，测试时的 10 分钟息屏覆盖已恢复。

完整设置写入及重启后偏好、插件管理的远端写操作、实际后台任务取消、团队真实消息和子代理继续对话尚待手机验收。

## 第二批真机验证记录

| 路径 | Huawei Mate 60 Pro+ 实测结果 |
| --- | --- |
| 引导按钮 | 旧包在 IME 提交后仍禁用下一步。定位到 ArkUI `@Builder` 捕获初始值后，修复包已覆盖安装。生成代码在组件更新时读取当前按钮状态。 |
| 本机启动与 Key 保留 | 勾选通过 HarmonyOS Asset Store 保存后，覆盖安装修复包，点击启动即可进入本机引擎。未重新输入 Key，真实模型回复 `HARMONY_NATIVE_PHASE2_OK`。 |
| 本机全文索引 | 手机的嵌入式 `node:sqlite` 返回 `HARMONY_EDIT_OK` 一条全文命中。 |
| 权限与历史兼容 | 本机权限目录返回 3 项。既有测试会话的分页接口正常返回 30 条记录。 |
| 目标表单 | 会话详情 → 进度 → 新建目标。空白时保存按钮禁用，输入测试文案后变为可用。目标写入仍待真机验证。 |

会话 ZIP 导出已通过宿主与真机验证：测试会话的归档为 5,795 字节、1 个条目，CRC、JSONL 和完整回合标记校验通过。原生文件选择器实际保存至手机 Download，应用完成字节数校验及 fsync 后报告成功；系统分享面板显示正确 ZIP，返回后报告面板关闭，没有向外发送。未保存的测试目标通过放弃确认清除，手机回到测试对话。完整页面与原版视觉待逐页比对。第二批安装包及运行时摘要见 [构建记录](native-build.json)。

## 仍待复刻

- 引导的账号和系统权限分支、折叠屏/多栏详情、全量中英语料、玻璃/壁纸/自定义主题，以及尺寸、状态和视觉截图逐页比对。
- 完整聊天行模型、富输入和附件、媒体和语音、队列与提问交互细节、Math/Mermaid/ANSI、完整改动查看器、制品及跨来源搜索。
- SSH、DSHarness Remote 的身份配对和加密中继、网页模式、终端、安全模式、引擎更新和恢复、完整账户与订阅，以及插件动态贡献、专用表单、更新和安装脚本授权。
- 聊天内的完整目标和待办呈现、转写与思路翻译，会话内容分享/导入/回放，论坛、DS Bot、系统手机操控和桌宠/伙伴小屋。

