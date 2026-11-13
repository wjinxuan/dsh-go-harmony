# DSH Go v1.0.15 鸿蒙复刻验收底稿

上游基线为 `ccch1mneyyy/dsh-Go` v1.0.15，提交 `a9877420ab9aee121134faf01b6a92a39ce0b05b`。以下上游路径相对于该提交，鸿蒙路径相对于本项目。当前为第二批 ArkTS / ArkUI 原生实现。全量一比一复刻与逐页视觉对照仍待完成。原版的本机、SSH 和 DSHarness Remote 会按主机能力隐藏、禁用或改变功能入口，验收需覆盖这些差异。 [原生实现进度](native-progress.md) · [上游发布](https://github.com/ccch1mneyyy/dsh-Go/releases/tag/v1.0.15) · [主机使用指南](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/docs/guide/zh/03-engine-hosts.md)

## 清点口径

- 原版 `app/lib` 有 836 个 Dart 文件，其中 `app/lib/ui` 有 543 个文件、169,888 行。聊天 119 个文件、插件 50 个、公共 UI 44 个、应用设置 34 个、引擎设置 17 个、主壳 28 个、主题 22 个。
- [原版页面类清单](ui-pages.json) 共 120 个公开的 `*Page` / `*Screen` Flutter Widget 类，分布在 113 个文件。其中包括共享容器、嵌套页和适配用页面，独立路由需要另按实际入口验收。另有 32 个以 `_sheet.dart` 命名的文件、3 个 `_dialog.dart`、7 个 `_panel.dart`，许多弹层在页面文件内定义。以常用 Flutter/Riverpod Widget 基类为口径，UI 有 1,268 个公开或私有 Widget 类声明。
- 设置索引有 34 个页面 ID 和 71 个静态设置锚点。全部功能目录有 6 组、27 个静态功能入口，运行时还可以添加原生插件面板。两个聚合 ARB 各有 6,122 个中英文翻译键，分别由 61 个分片维护。 [设置索引](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/app/lib/ui/settings/index/spots.dart#L59) · [功能目录](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/app/lib/ui/features/feature_catalog.dart#L189) · [本地化资源](https://github.com/ccch1mneyyy/dsh-Go/tree/v1.0.15/app/lib/l10n)
- 当前鸿蒙版的入口包括连接、会话抽屉、聊天、会话详情、工作区、工作区文件、模型选择、全部功能和设置。全部功能已接入插件、技能、后台任务、自动化任务及子代理与团队。页面与交互仍按下表逐项核对。 [主界面](../../entry/src/main/ets/pages/Index.ets#L819) · [引擎功能](../../entry/src/main/ets/ui/EngineFeaturesPanel.ets#L14) · [设置](../../entry/src/main/ets/ui/SettingsPanel.ets#L558)

在项目根目录用固定版本的上游 Git 工作副本核对清单。加上 `--output docs/parity/ui-pages.json` 可明确重生成。 [清单工具](../../tools/parity-inventory.py)

```sh
python3 tools/parity-inventory.py --self-test
python3 tools/parity-inventory.py --source /path/to/dsh-Go
```

## 页面与交互验收

| 功能组 | 原版行为和入口 | 鸿蒙现状 |
| --- | --- | --- |
| 首次启动与导航 | 欢迎、本机或远程、外观、权限、DeepSeek 登录/API Key/自定义渠道/稍后、安装完成。安装有等待、安装中、完成、失败状态。主页是对话壳，包含左侧会话抽屉、右侧快捷面板、顶部状态、底部主机选择和七个抽屉入口。支持系统返回、双向拖动、冷启动链接、桌面快捷入口和文件分享导入。 | 已有六步原生引导、本机与远程连接、本机准备进度、会话抽屉、宽屏侧栏、全部功能入口和系统返回。鸿蒙 Asset Store 保存本机 Key 后，真机覆盖安装可用已有凭据启动。原版账号和系统权限引导分支、右侧快捷面板、深链、桌面快捷入口、分享导入与双向拖动待实现。 [引导](../../entry/src/main/ets/ui/OnboardingPanel.ets) |
| 响应式与主题 | 手机详情页、折叠屏和中尺寸两段式详情抽屉、大屏会话侧栏/导航轨和右侧详情，宽度阈值 600/840，高度低于 480 回到紧凑布局。深浅与跟随系统，六套主题色、自定义 OKLCH、壁纸取色、玻璃层级、代码字体、图标样式、启动图标/启动页、壁纸编辑、阅读字号、表格颜色、动画/模糊/帧率。中英和系统语言切换。 | 已有浅色、深色、跟随系统，六套配色、可保存的字号、主题资源与代码字体。宽度达到 840 vp 时显示会话侧栏。折叠屏与中尺寸详情布局、自定义配色、壁纸取色、玻璃动效、启动样式、性能控制及全量中英切换待实现。 |
| 会话和工作区 | 新建对话可选工作区、模型、预设、思考程度。会话列表支持工作区切换、管理/目录选择、过滤、标题/内容搜索、重命名、归档、置顶、删除和多选。当前主机身份和状态影响列表、菜单、空白页与故障提示。 | 已有工作区切换、目录浏览/面包屑/隐藏目录/新建目录、工作区添加/重命名/移除、可取消的会话搜索、命中高亮、已归档页，以及单项与批量置顶、归档和恢复。最近目录按主机保存在应用私有偏好中。支持安全删除桥接的主机可永久删除，普通 DSH 主机不会开放删除。真机 `node:sqlite` 全文索引已返回测试命中，既有测试会话可分页读取。原版工作区分组、拖动排序、手机公共存储快捷位置与完整新建选项待实现。 [会话搜索](../../entry/src/main/ets/ui/SessionSearchPanel.ets) · [目录选择](../../entry/src/main/ets/ui/DirectoryPickerPanel.ets) |
| 聊天输入与执行 | 顶部模型与状态、输入框和 Plus 面板，包含相册/相机/文件、生成媒体、原生插件工具、语音、斜杠指令、`@` 引用、复制/选择/引用、重新回答、快捷键、IME。生成时可排队、插话、立即发送或中止。审批、系统提问、定时任务的授权各自有状态。 | 已有文本发送和排队、实时更新、中止、复制/引用、单项批准或拒绝，技能页可预填斜杠命令。支持相应主机时可编辑、撤回、插话、立即发送队列项，并处理结构化提问。第二批真机已收到实际模型回复。附件、相机、媒体、语音、斜杠菜单、`@` 选择、重新回答和完整输入交互待补齐。 [队列](../../entry/src/main/ets/ui/ChatActivityPanel.ets) · [提问](../../entry/src/main/ets/ui/QuestionCard.ets) |
| 聊天渲染与会话详情 | 13 类会话行，含用户、排队、助手、单工具、工具组、通知、审批、提问、文件变更、制品、过程、回合脚注、指令通知。支持 Markdown、表格、代码、数学、Mermaid、图片、ANSI、Diff、流中修复。详情标签含轨迹、变更、文件、进度、上下文、子代理、插件，另有用量、任务、文件预览、制品与导出。 | 已有消息、可展开的思考过程与单工具调用/结果、基本用量，以及原生 Markdown 文本、链接、标题、列表、引用、代码复制和表格。详情接入轨迹、文件改动汇总、目标、待办/计划状态、上下文、工作区文本/Markdown 文件、子代理和会话插件标签。原版完整行型、图像、数学、Mermaid、ANSI、完整 Diff、富文件和制品待实现。 [会话详情](../../entry/src/main/ets/ui/SessionDetailPanel.ets) |
| 账户、模型与渠道 | 账户、DeepSeek 登录及 Key、余额/用量、内置及自定义渠道、订阅、测试连通、添加/编辑模型、上下文设置、默认选择、思考深度和模型弹层。 | 已有真实主机模型目录、会话模型及思考深度选择、可用时保存默认模型，以及本机凭据输入和可写主机的 Key 管理。支持相应 API 的主机可添加、编辑和移除自定义渠道，以及从渠道读取模型。原版完整账户登录、余额/用量、订阅、专用表单和模型管理流程待实现。 [渠道设置](../../entry/src/main/ets/ui/settings/ProviderSettings.ets) |
| 本机引擎和设置 | 引擎安装、启动、停止、重启、安全模式、自动启动和启动恢复、日志、重置/卸载、备份相关提示、一般引擎参数、代理循环/子代理/Shell/Web 搜索，以及启动引导、安全诊断和开发者设置。Android 运行 Ubuntu/PRoot，兼容模式与直接启动有各自状态。 | 已有本机嵌入 Node/DSH、启动/停止、重启入口、状态和可复制的基础诊断。选择系统安全存储后可在启动时读取凭据，已在真机覆盖安装后完成真实模型调用。原版安全模式、自动启动、运行日志、升级、重置、卸载及 Shell 待实现。 |
| SSH、DSHarness Remote 和网页 | SSH 密码或私钥、信任主机指纹、启动远端 DSH、隧道、连接管理。DSHarness Remote 登录、扫码或验证码、身份核验、LAN/WebRTC/TURN/中继、网络诊断、恢复上次主机及精简历史。网页模式同会话切换，包含移动布局及 Web 专有入口。 | 已有手工输入启动链接和可选反向代理授权的直接 HTTPS/WSS，界面可返回连接页切换本机与手工远程。SSH、DSHarness Remote、配对、已保存主机管理、WebView 及网页切换待实现。 |
| 插件和动态界面 | 已装/市场、详情、安装/更新/删除/启停、设置表单、库存/席位和原生贡献的工具卡、输入胶囊、菜单、状态条、面板、选择文件和媒体。另有插件问题列表、语音转写配置、Cordis 视图。各主机上桥接能力不同。 | 已有库存、预设组成、官方市场和详情。主机开放管理时，可真实启停、检查安装源、安装/取消/卸载。动态贡献、插件专用配置、更新及脚本审批流程、席位、Cordis、语音和媒体面板待实现。 |
| 工具和自动化 | 全部功能包含终端、后台任务及输出、定时任务及 Cron/时区/授权、计划与目标、待办、技能、子代理和团队、权限预设、工作区文件、制品、转写/思路翻译。包含原生入口、动作和 Web 专有入口。 | 已有后台任务列表/输出/停止、自动化任务创建/编辑/运行/暂停/删除与历史、技能详情与调用入口、子代理与团队、工作区文件，以及主机提供的权限设置。会话详情可读取计划与待办并操作目标。本机权限目录已在真机返回 3 项。终端、完整的聊天内计划/目标/待办、制品、转写和思路翻译待实现。 |
| 应用设置 | 设置总览、搜索及命中项聚焦、账户/主机卡，设置分组为 AI、能力、外观、通用、主机、帮助与关于。含个人化、回复偏好、引擎参数、插件表单、权限、媒体、界面、语言、性能、通知、语音、后台说明、隐私/分享链接、诊断、升级、开源许可。 | 已有设置总览、局部搜索、主题/字号持久化、模型与服务商、主机权限/搜索/引擎参数、诊断和关于。原版 34 个索引页与 71 个锚点、通知/语音/媒体/隐私/升级等仍待补齐。 |
| 分享、导出和回放 | 按消息/回合/对话分享，图片/文件/文字/端到端加密链接、脱敏、链接管理、回放和继续对话。配置/插件二维码、导入、恢复点和原生分享菜单。 | 已接入会话和后代的 ZIP 导出、系统文件选择器保存和分享面板。宿主和真机已通过真实 ZIP 下载；手机文件选择器保存、系统分享面板打开和取消已验，未实际向外发送。聊天消息与代码可本地复制。原版消息/回合分享、加密链接、回放和分享码导入待实现。 [导出页](../../entry/src/main/ets/ui/SessionExportPanel.ets) |
| 社区与 DS Bot | 社区入口、论坛账户/首页/主题/搜索/通知/发帖，DS Bot 列表、创建、单聊、群聊、群详情、执行记录与工具审批。 | 社区、论坛和 DS Bot 待实现。 |
| 手机操控和宠物 | 手机操控引导、屏幕/点按/输入、悬浮条、停止、三档确认、应用名单、授权恢复、不打扰、限制解除、日志及诊断。桌宠选择、状态动作、大小、静音、跨应用显示、截图/语音提问、确认半轮盘。伙伴小屋和独立的记忆/人设/语音页面，Live2D 包单独提供。 | 手机操控、宠物和伙伴小屋待实现。鸿蒙权限、跨应用能力与桌面展示须单独真机验证。 |

## 上游源码定位

| 审计范围 | 原版路径与行号 |
| --- | --- |
| 根 App、引导、抽屉、搜索和适配 | `app/lib/app.dart:147`，`app/lib/ui/onboarding/onboarding_flow.dart:19` 和 `:84`，`runtime_setup_page.dart:23`，`ui/shell/home_shell.dart:228`、`:247`、`:261`，`sessions_drawer.dart:80`、`:424`、`:580`、`:919`，`session_search_page.dart:104`，`adaptive/adaptive_layout.dart:20` 和 `:79` |
| 主题与资源 | `app/lib/ui/theme/accent.dart:259`，`theme/surfaces.dart:20`，`theme/glass.dart:40`，`theme/typography.dart:76` 和 `:158`，`theme/app_theme.dart:149`，`ui/settings/appearance/appearance_page.dart:68`、`:139`、`:412`，`app/pubspec.yaml:116`，`app/lib/state/locale_state.dart:14` |
| 会话、输入和渲染 | `app/lib/ui/chat/chat_screen.dart:110`、`:989`、`:1347`、`:2365`，`chat_header.dart:49`，`composer.dart:36`、`:416`、`:746`，`widgets/plus_panel.dart:121` 和 `:324`，`slash_palette.dart:75`，`mention/mention_picker.dart:30`，`widgets/message_menu.dart:169`，`chat_rows.dart:11` 和 `:199`，`chat_list.dart:1131`，`render/markdown_body.dart:53`，`render/code_block.dart:345`，`render/diff_view.dart:107`，`render/mermaid_preview.dart:74`，`render/markdown_math.dart:22` |
| 详情和工作区 | `app/lib/ui/session/session_tab.dart:7`，`session_detail_page.dart:80` 和 `:304`，`session_artifacts.dart:100`，`workspace_files.dart:67`，`ui/workspace/workspaces_page.dart:21`，`directory_picker.dart:251` |
| 设置、搜索和全部功能 | `app/lib/ui/settings/settings_screen.dart:129`、`:141`、`:166`、`:205`、`:227`、`:265`、`:291`、`:365`，`index/spots.dart:59`、`:299`、`:1058`，`index/settings_pages.dart:47` 和 `:84`，`search/settings_search_page.dart:82`，`ui/features/feature_catalog.dart:189`、`:273`、`:283`、`:323`、`:354`、`:385`、`:467` |
| 模型、本机和远程 | `app/lib/ui/providers/providers_page.dart:37`，`provider_form_page.dart:35`，`provider_detail_page.dart:31`，`provider_model_page.dart:45`，`model_context_page.dart:27`，`subscription_page.dart:29`，`ui/engine/engine_screen.dart:70`、`:197`、`:355`，`ui/engine_settings/engine_settings_hub.dart:28`，`ui/remote/remote_screen.dart:39` 和 `:378`，`ssh_host_form.dart:27`，`pairing_page.dart:46`、`:223`、`:277`、`:358`，`ui/web/local_web_screen.dart:29`，`web_view_page.dart:33` |
| 插件与工具 | `app/lib/ui/plugins/plugins_screen.dart:18`，`plugin_inventory_page.dart:85`，`config/plugin_config_page.dart:158`，`native/native_panel.dart:155`，`native/native_plugin_section.dart:167`，`seats/plugin_seat_page.dart:14`，`ui/terminal/terminal_page.dart:35`，`ui/cordis/cordis_page.dart:33`，`ui/features/jobs_page.dart:34`、`:116`，`schedules_page.dart:38`、`:217`，`schedule_editor/schedule_editor_page.dart:47`，`skills_page.dart:23`，`permission_page.dart:65`，`ui/agents/team_page.dart:38` |
| 分享、社区及系统入口 | `app/lib/ui/share/share_panel.dart:151`，`share_panel_pages.dart:319`、`:533`，`share_image_page.dart:80`，`ui/share_hosted/hosted_links_page.dart:43`，`ui/share_code/share_code_panel.dart:429`，`ui/replay/replay_page.dart:51`，`ui/forum/forum_home_page.dart:30`，`ui/bots/bots_page.dart:27`，`bot_chat_page.dart:34`，`room_chat_page.dart:34`，`app/lib/links/app_links.dart:154` 和 `:334`，`links/page_links.dart:30` 和 `:69`，`links/launcher_entries.dart:20` 和 `:91` |
| 手机操控与宠物 | `app/lib/ui/phone/phone_control_screen.dart:68`，`app_rules_page.dart:56`，`dnd_mode_page.dart:64`，`phone_unlock_page.dart:104` 和 `:238`，`action_log_page.dart:97`，`ui/pets/pet_settings_page.dart:47`，`ui/companion/companion_page.dart:79`，`companion_memory_page.dart:40`，`companion_persona_page.dart:17`，`companion_voice_page.dart:22` |

## 实施与验收拆分

1. **导航和设计基线。** 固定原版截图与已核实状态，覆盖同尺寸紧凑、折叠、中宽和宽屏，浅色/深色与中英。先实现路由树、主题、公共卡片/弹层和返回行为。复用 Flutter 源码需要实测原版 `Dart ^3.13.5`、Flutter 3.47.7 与可获得的 OHOS SDK 及插件。当前 ArkUI 工程可独立沿同一清单推进。 [上游依赖](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/app/pubspec.yaml#L25) · [Flutter OH 维护者](https://gitcode.com/CPF-Flutter)
2. **会话与工作区。** 复用现有鸿蒙客户端连接和真机已验证的本机引擎，补齐会话状态机、原版输入和渲染、工作区、会话搜索及详情。以真实本机与远端引擎复测历史加载、流式生成、插话、中止和审批。
3. **设置、模型与运行时。** 实现 34 个索引页、71 个设置锚点、模型/账户、引擎日志和管理、诊断、权限与通知。按本机和远程能力核对每个入口，以及设置保存后实际行为。
4. **主机、插件与工具。** 做 SSH、DSHarness Remote、Web、动态插件、终端、计划、任务、技能、子代理等。按真实主机验收每个功能，并复核全部功能目录的原生、动态和 Web 入口。
5. **系统能力、分享与社区。** 移植文件、权限、通知、分享回放、Bot/论坛、媒体、手机操控和桌宠。每项以真机和可用的外部服务完成正向和故障路径验证。

同一验收项需核对页面入口、文案、视觉状态、操作产生的结果及错误回退。品牌、Deepy、鲸娘等专有资产与代码许可证分开，原版允许用于构建、测试和运行仓库，衍生版发布时需换成自己的名称与素材或取得授权。伙伴小屋 Live2D 另有授权和素材包。手机操控含经作者许可使用的 Phase 代码，鸿蒙实现需核对平台能力及对应授权。 [资产说明](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/ASSETS.md#L1) · [第三方通知](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.0.15/THIRD_PARTY_NOTICES.md#L12)
