# Harness Pocket

面向 HarmonyOS 的非官方 DeepSeek Harness 客户端。使用 ArkTS、ArkUI 和 Stage 模型，可在手机内运行 DeepSeek Harness，也可连接电脑或服务器。当前接入会话、模型和引擎设置、工作区文件、技能、插件盘点、后台任务、自动化及子代理入口，功能按连接主机实际能力提供。

当前八组功能已完成开发集成，正在按 [17 项清单](docs/parity/phone-acceptance.md) 做真机验收和修复，尚未全部通过。

17 项真机验收仍未全部通过。此前 506 覆盖安装、507/508 启动的 [phase17](docs/parity/native-build-phase17.json)（HAP `e4c074…`，197416715 B，运行时 `93bd20…`）。509–540 已复验快捷面板保存/排序、同页语言切换、插件表单刷新、唯一选中样式和图片全屏安全区五项修复，具体动作见 [11 月 18 日设备记录](docs/parity/device-acceptance-20261118.md) 及 [脱敏证据](docs/parity/device-acceptance-20261118.json)。旧包失败和 501–505 未安装阶段仍保留，不改写当时结果。

558–562 已确认手机原生 Recall 启用、取消关闭、明确 OFF 与退出重开；同一绑定由 `ready` 变为 `retired / user-off`，后端 active 为空。568 已读取 192 B 持久标记，591 安装新包和 593 实际重启后，594 确认该标记逐字节不变；重启后旧会话历史可读、activeBindingId=null 也已只读核实；596 原生界面仍显示“启用自动回忆”，已确认重启后 OFF。初次 549 UI/后端不一致保留为 `UNRESOLVED_CAUSE`。565–579 的置顶/取消置顶、归档恢复、永久删除取消已取得限定结果；580/581 的空树与连接失败保留为历史 UNKNOWN；588 重连只读确认尚未删除，589 再次真实确认后精确目标已不存在，三个控制会话和 47 B 文件不变，590 取得 140 B 墓碑。594 已确认删除墓碑在实际重启后不变；重启后目标仍不存在、三个控制会话和控制文件不变已只读核实；忙状态拒绝已由 615–622 后续验证，654 的未来 active 任务也真实阻止会话删除（session-active）；658–671 已完成编辑授权和本次任务/会话清理。

[phase18](docs/parity/native-build-phase18.json) 已于 591 覆盖安装、593 新进程启动，该阶段 HAP `bff63f…`，197426727 B；583 构建退出 0，584 专项 19 项（12 项源码、7 项实际生成代码）及语言 4 项通过且零跳过，585 独立签名、CRC、5 个原生库和运行时一致性通过。595–606 已复验无角色时四项信号设置可操作、关闭/重开/恢复及完整会话入口；实际舞台、信号预览/分享仍未验。586 离线为历史，588 已重连，593 已确认进程更换；594 两份持久标记均不变，后续只读核查已确认目标删除持久和 Recall 无 active；596 原生 OFF 及上述设置入口 UI 已有后续复验。

612/613 新增实际缺陷：自定义模型渠道密钥在引擎重启后丢失，首次 BUSY 样本报“这个模型渠道还没有密钥”，未真正进入 hold。只读结果 running=false，未出现本轮手机 provider 请求。仅将自有合成密钥临时回注内存以恢复测试条件，**不计持久化修复通过**；共享凭据/加密存储与模型发现修复已纳入 phase19；679–689 后续完成自有渠道真实重启及原生模型发现复验，原失败与临时恢复仍保留。

615–622 在临时恢复测试条件后，第二次 BUSY 已真正进入合成 hold（请求 12）：永久删除被明确拒绝为 session-active，目标与运行状态保留；随后原生停止使会话 idle、队列为空，provider 记录 hold-cancelled，早于 180 秒自然结束。此项通过不覆盖关联任务拒绝，也不证明密钥持久化已修复；定时授权后续结果见下文，编辑/关联删除/清理已由 654–671 后续限定验证。

[phase19](docs/parity/native-build-phase19.json) 已构建校验，并于 675 安装、676/677 启动：HAP `9e3f19…`，197437176 B；运行时 `5f1fbe…` 仅 main/credentials/engine-reset 三个内容变化，18394 项 CRC/内容核验通过。644 构建退出 0，649 实打包 18 项合同、完整三次启动的真实凭据/发现模型闭环及语言 4 项通过，650 签名与 5 个 native 库一致性通过。641 为打包校验器共享 ZipInfo 的偏移误用，旧包未改，642 已校正并保留失败记录。678 确认新 PID 3495、ready 已变化，实际运行 `5f1fbe…`。679 前仅保存一次自有合成凭据，source=file；680 正常停止、681 重启应用后，682 PID 由 3495 变为 4706、ready 更新，683 回到聊天。随后 describe-only 仍 configured=true/source=file，没有读取秘密、回注、写入或调用解锁接口。687 编辑原渠道时 API Key 输入为空、尚无添加按钮；688/689 原生“从端点读取模型”得到“添加 device-fixture”。fixture 先精确验证 Bearer 再返回模型，未保存渠道或改默认模型。本轮自有渠道的重启持久化和发现模型已通过，整体仍为部分验收。

632–648 已分别确认定时任务快速拒绝、聊天停止取消、无输入等过原授权时限均不创建任务；明确授权后仅一项未来任务、执行历史为 0，且完全访问模式仍需独立授权。631 近截止操作只记“未授权、无任务”。关联删除、模型编辑授权及任务清理已由 654–671 后续限定证据补齐；Bot/群任务 UI 仍单独待验。

654–671 已补自有任务关联删除保护（实际 reason=session-active）、模型编辑拒绝不改原任务、再次明确授权后更新、任务删除及自有会话清理；任务未执行。673 在普通签名 ALN-AL10/API 26 上实际点击“检查本机 Shell”，得到 PTY 错误 13，探测在 spawn 前返回。这是该设备 PTY 路径的实际限制，不是 posix_spawn 失败或完整本机终端通过。

694–699 已实际打开合成网页席位，等待后显示正文与计数 0，点击加一为 1、重置为 0，再返回席位目录。695 的初始加载空白不记失败；原控件树含临时网页票据，仓库仅归档脱敏摘要与哈希。此结果限于该合成网页的实际加载和交互，不扩大为全部第三方网页插件通过。

700–726 曾发现两项实际失败，保留历史，phase20 后续复验见下文：配置分享 707 取消确认后自有渠道仍不存在、其它设置和默认模型未变；709 明确导入后自有渠道实际写入，UI 却报“主机未确认配置已导入”，不能计导入通过。工作区 a/b 添加及最近目录已有结果，但 720 下移后的显示顺序未更新，723 改名后仍显示旧 b，直到 725 新分组出现才显示新名。721 文件名虽写 a-rename，实际表单针对 b；不误记为 a 改名。727 离页重开后置顶和新标题保留，仅证明持久化/重建结果，不能覆盖即时刷新失败；728–732 自定义色后续结果见下文。

728–732 自定义色已有限定通过：非法输入正确报错；应用 `#336699` 后两个按钮采样为 RGB(51,102,153)，重开保持，随后恢复输入 `#5F7A55` 和 mist，采样回到原 RGB(75,103,180)。734 壁纸页未显示路径输入，尚无完整选择/应用结果，不记壁纸通过。

[phase20](docs/parity/native-build-phase20.json) 已构建、校验并安装启动，此处保留安装阶段记录；753/777/780/781 后续专项复验结果见下文。733 构建退出 0、10.098 秒；HAP `76616e…`，197434652 B；735 工作区 12 项（源码 6 + 实际生成代码 6）、配置分享 15 项通过。735 语言检查误用不存在脚本退出 127，原失败保留；738 正确脚本 4 项通过。736 签名、CRC、5 个原生库与运行时一致性通过，仅 ABC/sourceMaps 改变；740 安装退出 0、11.417 秒，741 新 PID 14169（此前 4706）。仅安装启动时未计通过，后续专项动作另行确认。

phase20 两项修复已有后续限定手机通过：748 仅加载中，不声称本轮观察到默认 OFF；749 勾选、750 取消后新渠道仍不存在，752 重确认、753 显示 done，真实只读 user 与载荷严格一致，旧 709 渠道/其它设置/默认模型未变。此配置写入目标是隔离 Mac 主机，不是手机本机。773 取消置顶、776 取消分组后，777 下移立即变为 b,a，780 改名立即显示 DSH-UI-B-VERIFIED-1118，781 重开保持顺序和标题；注册项移除及文件保留已由 784–788 后续限定验证。755/756/763 是外部前台中断，图片已删除只留哈希，不计产品成败。

[phase21](docs/parity/native-build-phase21.json) 已构建校验并于 791 安装：HAP `fa0657…`，197434651 B；775 构建退出 0、12.465 秒。769 运行时 `e87517…` 只替换 engine-lifecycle 一项，ZIP 共 18394 项、其它内容不变，CRC 已核；779 维护 18 项及实际 HAP 提取运行时的故障恢复通过，783 签名、CRC、5 个原生库通过，HAP 仅运行时 ZIP/version 改变。746 的 phase=stopped、strikes=0，failure.at 早于本次 startedAt，是旧失败未清而非新的停止失败；修复仅在 ready 清当前旧 failure，历史日志/安全模式/strikes 保留。791 实际安装退出 0、10.654 秒；795 新 PID 23397（此前 14169）、本机运行时 e87517… ready，脱敏状态 phase=running、strikes=0、failurePresent=false；796 引擎页旧错误提示已消失。已确认本轮旧 failure 清除修复，原 746 历史记录保留，不扩大为所有故障恢复路径真机通过。

工作区 773–788 的独立聚合包含 10 项限定 UI/协议断言及 54 份哈希证据：784 取消移除保留条目，786/788 仅移除自有 b/a 注册项；只读主机 own=[]、其它原条目保留，两份 51 B 证明文件仍匹配初始 SHA，未清理目录。804 正文 nonce 搜索实际命中自有会话，标题/路径搜索在该阶段尚未验，后续 854/875 结果另列。807 已允许系统通知并出现前台“对话已完成/查看/关闭”横幅，仅计前台出现，808“查看”路由已由后续验证；后台通知的独立尝试仍未通过。

后续独立聚合确认 808“查看”回到精确 nonce 会话，前台搜索/完成/查看路由共 8 项限定断言；请求 26 实际使用重启后持久凭据，seq31→35 completed。它按合成服务的历史匹配进入原 180 秒 hold，不是普通模型语义，也不证明后台通知。

821–844 自有技能导入已完成 10 项限定验证：A/B 分别审阅和确认，取消不落盘，当前文件各 244 B 与预期 SHA 一致，同一 B 重导无差异。workspace 读取私有备份被边界拒绝的历史保留；844 仅经合法调试包读取精确备份 SKILL.md，244 B/SHA 确认仍是 A，未读其它备份配置。849 核对 B 后删除精确文件，rm -d 不支持；850 改用 rmdir 完成空目录移除，后续 exact workspace-file/not-found 已只读确认，私有备份保留。

phase21 的后台尝试未通过，原失败保留：请求 27 完成时是否持续后台不明确，815 已前台；请求 28 的独立 20 秒合成服务发完，但 841/842 在 Home、843 通知中心没有自有通知，读取手机连接超时。846 同 PID 23397 为 Frozen/background 且转发仍在；847 经官方前台打开后同 PID 变为 Thawed/top-app，随后仅确认 seq48→51 completed/idle，总观测 201670 ms。850 系统通知 ON、五项应用开关均 true，前台完成横幅出现，不替代后台发布证据。当时合法短时后台任务方案仍在研究；后续 phase22 的实现及正向结果另列；不据此断言产品崩溃或确定 publish 失败根因。

技能最终清理已有只读 exact workspace-file/not-found，连接关闭、无写入，私有备份保留，原 rm -d 不支持记录不覆盖。854 标题搜索和 875 目录专用 nonce 搜索分别命中自有目标，876 打开真实空控制会话；新对话草稿权限只读重开、完全访问确认取消、workspace-write 恢复，以及临时模型重开和 DeepSeek/Off 恢复均有 12 项限定验证。未从新草稿发送 prompt，只有 standard 预设，不声称多预设切换或新会话首发应用已测；临时控制会话已删，17 个其它会话、默认值及 28 个请求计数未变。

[phase22](docs/parity/native-build-phase22.json) 已于 883 安装、885/886 新 PID 38437、本机 ready；HAP `a0ee4a…`，197452348 B，运行时仍 e87517…。877 构建退出 0、9.056 秒；同 14 项通知回归分别执行源码和实际生成代码，均零失败/跳过，不重复算 28 项；语言 4 项通过。879 签名/CRC/5 个原生库通过，仅 .pages.info、ABC、sourceMaps 改变。881/882 正常停止且 failureAbsent；887–889 外部前台中断只留删除截图哈希，不记 crash。

891–895 的真实 20 秒后台正向已通过：请求 29、seq57→61 completed，20366 ms，在通知中心和点击之前完成；894 脱敏树有系统“DSH Go / 对话已完成”，895 点击返回精确本机 BUSY 与该结果。同 PID 从后台 Thawed 到完成释放后的 Frozen，再因点击回前台 Thawed；这次完成后的 API 超时不推翻已发生的系统通知。仅系统实际授予的短时窗口和额度有效，不承诺永久后台；到期不自动续租。896–902 当时负例进行中；后续 903–910 已完成负例与系统 OFF/五项 ON 基线恢复，见下文。

896–910 已完成关闭完成通知的真实负例：系统通知仍 ON、仅 done OFF，先清空旧自有通知；请求 30 在 20.054 秒正常完成，早于 903 通知中心观察，中心无自有通知，905 回前台仍 done OFF 且无完成提醒。906 恢复应用五项 ON，910 重开读回系统通知 OFF、五项仍 ON，已恢复原始基线。904 缺少 contextlib 的取证包装错误保留，不记产品失败；私有通知树和 907/908 设置截图未读取或复制。仅证明完成事件的关闭过滤，不扩大为其它事件均已发出或永久后台。

壁纸在 phase22 已导入成功：921 的 320×180 自有 PNG 为 1734 B、SHA `71d610…`，状态 ON，但原生绘制空白。原因是 Image 收到裸沙箱路径，phase23 改用 fileUri.getUriFromPath，存储原路径不变。旧源码/旧生成各有 1 项有效红测；新源码/实际生成同 3 行为全绿，默认外观入口共 11 项去重通过，不能据宿主适配器判手机绘制已过。922 文件名含 disabled 并不准确，只观察到 blur=0.3，busy 时关闭点击未生效；该阶段壁纸仍 ON，关闭尚未生效；后续 955–986 已安装修复、实际绘制并通过 UI 关闭，见下文，选择的测试图片保留。

桌面卡片分尺寸记录：2×2 已添加、点击进入小屋、原生活动更新，并在重新进入小屋后刷新过期状态；932/934 仍为 snack，不能声称后台自动到期刷新。937–939 只移除了自有 2×2，应用图标保留。943 新增 2×4 当时只确认显示；944 点击过程中 USB 断开，没有点击/移除结果，不能把先前空注册表当作全部卡片清理完成。重连后 949 点击实际进入小屋，950/951 移除确认，952 仅自有宽卡消失、应用图标保留，精确 ID 771658338→空表；两张自有卡片现已清理。此续验仍属于 phase22；30 分钟后台刷新和进程退出恢复未验。

[phase23](docs/parity/native-build-phase23.json) 已构建校验并在重连后安装：940 构建退出 0、54.202 秒，HAP `9d8211…`，197452297 B。947 签名退出 0、CRC 通过、5 个原生库与运行时 e87517… 不变，HAP 仅 ABC/sourceMaps 改变；946 是输出证书误用 .pem 导致工具拒绝、未验证 HAP，修正扩展名后通过，原记录保留。944 的 HDC Empty、Mac USB 无设备为安装前的历史中断，未据此判产品崩溃。重连后 955 安装退出 0、10.836 秒，981 手动启动本机引擎、983 聊天 ready；986 确认 PID 22804、运行时 e87517…。系统通知 OFF/五项 ON 已恢复，SCREEN/timeout 仍待测试结束时恢复。

957 已实际看到壁纸预览，959–978 的缩放、横纵位置、模糊、提亮和压暗均有可见变化；重开保持的已核范围为横纵位置、模糊和提亮，966 滚动误触缩放到 3.07 后已于 967 改回 2，不将其误记为持久化失败。983 聊天页真实显示四色背景，985 通过 UI 关闭后 986 恢复默认背景。脱敏状态确认 System/mist/16、其它外观与 921 一致，最终 OFF、zoom=1、x/y=0、blur≈0.3、lighten/dim≈0.2；数值比较使用 1e-6 容差，先前精确浮点断言失败保留。自有 PNG 与选择路径仍保留，符合原版关闭后保留图片的行为，不声称恢复原空路径或完全无痕。整体验收仍继续，尚非 17 项全部通过。

995–1008 已完成隔离 Mac 主机上的限定配置导出：仅选 llm-pi-ai，生成自有 DSH-EXPORT-1118；实际复制后由系统粘贴按钮读入 416 字符，解码后的完整载荷（含 created）与生成结果一致。敏感预览默认未勾选、确认按钮禁用，未执行导入、保存文件或外传。同主机预览仍显示两个 models 数组差异，不记“无更改”：导出采用 user 层，预览比较补默认值后的 value 层，差异仅为两个空 compat 字段；固定原版也按整体数组比较。

1011–1019 已验证当前隔离主机的完整网页模式：预览说明点继续后实际显示空聊天、workspace 和标准模式；网页侧栏显示合成网页席位及新会话。重新连接经历 Loading plugins 后恢复空聊天，loopback 代理端口由 38713 换为 42031；返回原生后仍为空聊天与“合成插入”，抽屉保留 DSH-PLUGIN-TEST-1118。仅记录 URL origin/query 参数名和文件哈希，不记录临时票据。此结果限加载、侧栏、重连及返回保留主机，不声称精确 sessionID 绑定或发送已验证。

1022–1025 官方插件分享只验证了本机预览：172 字符输入与官方名称/来源/详情匹配，完整性显示不可验证，选项未勾选且禁用、确认按钮禁用，返回后状态保留；未确认安装或启用，也未验证外部 registry 获取与 npm 固定版本。1026 返回本机后，经授权清理隔离 Mac 60863：先保留两份 51 B 自有证明文件（0600、原 SHA），再精确 CAS 移除自有席位/原生插件节点，其它配置和会话元数据在关机前不变。随后自有 supervisor 退出并删除临时主机根目录和启动文件；手机保存的主机注册未改，旧 60863 工作区不能再当可用资源。原整块 CAS 因 YAML 规范化及块内出现其它设置而正确拒绝，失败记录保留。

1029–1032 已完成本机重新回答的限定验证：1029 生成中，1030 虽名 completion 仍是中间态；1031 新分支完成，1032 返回原会话。只读指纹确认原 71 条记录逐条不变，新分支 session-b3a707bc-cd04-4917-a6bc-b5eedfb27f9f 与原会话不同，继承前 62 条一致，测试 nonce 各恰好一次，重答的消息 ID 新建；新分支 73 条、idle、queue=0，合成请求 31 完成。未据相同回复文字判断身份，未声称新分支已清理。

1040/1041 本机附件入队实际失败：界面显示 gateway/internal，原文草稿与 DSH-UI-1117-artifact.html 附件签均保留；只读后态仍是原 hold 运行、queue=0、cursor=76、测试消息未进入历史，观察间 provider 日志不变。观察脚本的 PASS 仅指取证成功，不能算入队通过；1040 文件名 queued 也不代表已排队。该阶段仍在诊断，后续 1043 定位及 phase24 修复另列；旧失败保留。DS Bot 仍仅完成源码预检，尚未做手机 UI 流程。

1043 唯一诊断上传已定位附件失败：211 B 文件上传返回 HTTP 200 但 ok=false，实际错误为 EACCES，尝试打开 `/data/storage/el2`；调用链在持久化目录同步时越过应用自有边界。没有提交消息或修改队列，两次更早的测试准备失败也未上传。1044 仅清除自有失败草稿和附件，1045 只读确认 idle、queue=0、80 条记录，1046 通过 UI 正常停止引擎。

[phase24](docs/parity/native-build-phase24.json) 已构建、校验，并于 1048 安装退出 0（11.067 秒）：HAP `4ae616…`，197452298 B；运行时 `48ae9d…` 在 18394 项中只改附件模块一项，其余 18393 项内容不变且 CRC 通过。真实 Linux C++ 发布与实打包模块在祖先目录拒绝 fixture 下，旧版退出 1、新版退出 0，验证 211 B 对象/别名、精确读回、去重、不覆盖、目录同步和临时文件清理；实打包附件 5 项与 129 项客户端断言通过，附件用例零跳过。HAP 构建退出 0、7.140 秒，签名/CRC 通过，五个原生库及 ABC 不变，仅 runtime ZIP/version 改变。该安装阶段尚未确认启动和本机附件复验，未把宿主绿测计为手机通过；1051–1064 后续真机结果另列。

隔离 Mac 60863 的反向转发已精确移除；首次把两参数合成单字符串时，工具虽退出 0 却返回失败且规则仍在，原记录保留，改为分开参数后成功。64114 反向转发及当时 36351 正向转发保留。合成 provider 仅延长同配置、同 key 的测试服务寿命，没有发起手机请求；SCREEN/timeout 恢复仍待验收结束。

1051 已确认 phase24 真正运行：PID 35344、运行时 `48ae9d…`、failurePresent=false。1059 将自有 211 B HTML 附件排入队列；1061 撤回后原文字和文件签恢复、queue=0、消息尚未提交；1062 再入队为新队列项，1063“立即发送”，1064 回到 idle/queue=0。最终测试消息恰好一次，提交 requestId 对应重新入队项，撤回的旧 requestId 未提交；原 hold 在 171552 ms 被主动中止，随后附件回合 701 ms completed。ROOT 通过标准调试包读取精确对象和别名，两份均为 211 B、SHA `8ec6ff…`，与原文件一致。此附件上传/撤回/重排/立即发送闭环已通过，五次只读观察是一个完整场景，不算五个独立案例，也不代表任意文件或跨重启队列已测。

1050 观察器误读 engine-state.json、1056 文件选择器转场未结束时输入，以及首次 final 观察器把 records 包装当 event 解码的失败都保留；它们不记产品失败，也不靠删除断言获得通过。旧 1041/1043 的实际 EACCES 失败仍保留。1066/1067 又发现 DS Bot 原生页缺少内置启用操作，控制接口实际 HTTP 200/enabled=false；ROOT 已定位初始化 busy 顺序，该阶段 phase25 尚在修复、未实装，未运行 Bot 创建/群组；后续有限复验见下文。整体验收仍为部分完成。

[phase25](docs/parity/native-build-phase25.json) 已构建、签名校验并安装：HAP `ef47c8…`，197451531 B；构建退出 0、7.454 秒，运行时仍为 `48ae9d…`，五个原生库不变，仅 ABC/sourceMaps 改变。相同 9 项生命周期行为分别执行源码与实际 CompileArkTS 生成代码，18 次执行全过、零跳过，不算 18 个独立行为。修复复用当前本机 control，避免 busy 初始化重入，并保护切主机、离页后的旧回包；原红测与 peer 发现的两处竞态记录保留。

1075 已显示内置 DS Bot“启用”，1076 确认提示重启且保留团队数据；1077 后端 enabled=true、activeAtStart=false、restartRequired=true，尚不能叫团队已运行。1078 重启后，1079 本机 ready、failurePresent=false，原生列表出现 Chief/Chief of Staff。至此只确认启用入口、保存与重启后团队可用；自有 Bot 创建/编辑/复制/群组/消息和清理仍等完整闭环汇总，不能提前记整行通过。

17 项当前覆盖与真正剩余动作见 [截至 phase24 的映射](docs/parity/phone-acceptance.md#截至-phase24-的当前覆盖映射)；第 15/16 项限定场景已有组合证据，第 3 项按用户确认不再复测，其余仍按实际缺口记录。

用户已确认麦克风正常且不需再测，记录为 `USER_CONFIRMED_NORMAL_NOT_RETESTED`，不计本轮代理测试通过。Live2D 仍待有权使用的角色/运行库包。系统通知原 OFF 基线已于 910 恢复；临时 SCREEN 亮屏运行锁与 7200000 ms 熄屏超时覆盖也尚未恢复，须在验收结束后由 ROOT 释放、恢复并读回确认。

此前的键盘、分享/回放、队列、211 B 制品再上传、合成媒体、SenseVoice 网络/WAV、TURN USB TCP、SSH/PTY 和 Recall 协议证据，保留各自包版本及覆盖范围，见 [11 月 17 日历史记录](docs/parity/device-acceptance-20261117.md)。[八组实现与平台差异](docs/parity/full-implementation-checklist.md)。

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
./runtime/prepare-sensevoice.sh
sh runtime/pack-dsh.sh
ohpm install --all
"$deveco/tools/hvigor/bin/hvigorw" --mode module -p module=entry@default \
  -p product=default -p buildMode=debug assembleHap --no-daemon
```

默认产物位于 `entry/build/default/outputs/default/entry-default-unsigned.hap`。真机安装前，在 DevEco Studio 的 **Project Structure → Signing Configs** 为本项目生成调试签名，然后运行到已连接设备。DevEco 将签名配置写入本机的 `build-profile.json5`，该文件由 Git 忽略。 [华为自动签名说明](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ide-signing-auto/)

## 手机本机启动

1. 首次打开 Harness Pocket，按引导选「本机」，设置外观和访问范围，再选择「使用 DeepSeek 账号」或「使用 API Key」。账号登录在系统浏览器完成，返回应用即可查看授权状态。账号授权保存在应用私有目录，重启后可从启动页的「使用 DeepSeek 账号」继续。
2. 首次启动会解包 DSH 运行时，之后复用手机沙箱中的副本。进入对话首页后可以直接输入消息；左上角打开会话列表，右上角加号新建对话。
3. 在会话侧栏进入「设置 → 本机引擎」可停止引擎。勾选「记住 API Key」后，凭据由 HarmonyOS 安全资产存储保护，解锁后重启或覆盖安装可继续使用。未勾选时仅在本次运行中使用。启动页或模型设置可删除已保存的 Key。
4. 在输入框输入 `/` 查看命令。打开对话后，列表会加入该会话的主机命令和技能。支持 `/compact` 的对话可以压缩上下文，并在会话内查看执行结果。

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

在「远程主机」可选择 SSH 或 DSHarness Remote。SSH 支持密码或 OpenSSH 私钥，首次连接时核对主机指纹。远端需要有可运行的 `dsh web`，并允许 SSH TCP 转发。DSHarness Remote 支持浏览器登录、自建服务的邮箱密码登录及扫码配对。连接时先尝试 LAN 或 WebRTC 直连，再尝试 TURN，最后回退到服务中继。所有通道都验证主机身份并使用 Noise IK 端到端加密，对话页显示当前连接方式。

打开有终端能力的远程对话后，在「更多功能 → 终端」可启动或重新接入主机 PTY。对话输入框的「＋」可选文件、相册图片或拍照。DSHarness Remote 按原版只提供图片附件。草稿和历史消息中的图片会显示缩略图，点开后可滑动浏览同组图片、缩放、保存到相册或分享。本机模型可读取同一会话中的 UTF-8 文档。

本机系统 Shell 受鸿蒙手机子进程限制，当前仍由远程主机提供 Shell 和 PTY。手机操控使用公开无障碍、单次截图和允许的系统意图；动态插件桥及原生界面已经接入。Android 特权接口、本机任意安装脚本与应用外悬浮窗的差异见[真机验收](docs/parity/phone-acceptance.md)。[REA 逆向与架构记录](docs/architecture.md)

## 协议自检

使用 Node.js 24.9 或更新版本运行协议及本机引擎自检。本机引擎自检以真正的 DSH 执行一轮请求，模型回复由本地测试服务提供。

```sh
sh tests/check-dsh-wire.sh
sh tests/check-markdown.sh
sh tests/check-engine-features.sh
sh tests/check-settings.sh
sh tests/check-account.sh
sh tests/check-model-panel.sh
node --disable-warning=ExperimentalWarning --test tests/chat-interactions.test.mjs
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

远程功能的隔离验证可使用原版 Mac DSH CLI 和固定版本的 DSHarness Remote 源码。SSH 脚本还需要本机 `ssh-keygen`、`sshd` 及已安装的打包依赖。

```sh
npm ci --prefix runtime/ssh-deps --ignore-scripts --omit=optional
node runtime/ssh-deps/prepare.cjs runtime/ssh-deps
node --disable-warning=ExperimentalWarning tests/ssh-bridge-live.mjs /path/to/official/dsh/lib/bin.js
sh tests/check-dsh-remote.sh /path/to/pinned/ds-harness-remote
DSH_TERMINAL_TEST_BIN=/path/to/official/dsh/lib/bin.js node --test tests/terminal.test.mjs
```

完整 TURN 自检会启动独立的 UDP-only 和 TCP-only 回环服务，强制 relay，并校验双向各 50,000 字节；缺少服务不能静默跳过。需要 Node.js 24.9+、C 编译器、make、pkg-config、libevent 和 OpenSSL 3。已有 coturn 时可设置 `DSH_TURN_SERVER=/path/to/turnserver`；否则脚本临时构建 SHA-256 固定的 coturn 4.19.0，退出时清理进程和临时目录，不安装系统服务。

```sh
PATH=/Applications/DevEco-Studio.app/Contents/tools/node/bin:$PATH \
  sh tests/check-turn-local.sh entry/src/main/resources/rawfile/dsh-runtime.zip
```

Linux 原生发布自检使用 C++20 编译器、libuv 开发包、`timeout` 和 ABI 匹配的 Linux libnode 与头文件。以下命令的默认库名是 `libnode.so.137`。如需指定库文件，可将其绝对路径作为第二个参数，并保证动态加载器可找到它。

```sh
DSH_NATIVE_TEST_RUNTIME=/path/to/unpacked-runtime \
  sh tests/check-native-publish.sh /path/to/node-v24.22.2/include/node /path/to/libnode.so.137
```

会话、工作区、附件的原子发布，真实 POSIX 文件锁争用/释放，以及完整引擎工具、沙箱和压缩流程已在 Debian sid ARM64 的 Node/libnode/头文件 24.22.2 上复验。该自检仅替换鸿蒙日志头，编译实际引擎源文件；设置 `DSH_NATIVE_TEST_RUNTIME` 后还会运行完整原生嵌入器自检。手机包内运行时未升级。历史手机文件操作结果不替代此次新增功能的真机验收。
