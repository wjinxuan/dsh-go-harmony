# DeepSeek Harness 接续交接 · 2026-11-18

交接断点为手机步骤 **1108 后点击「添加记忆」**。用户要求 Codex 停在这里，把剩余开发和验收交给 DeepSeek Harness。八组功能和 17 条真机验收仍是部分完成。用户确认麦克风正常并要求不再测，状态保留为 `USER_CONFIRMED_NORMAL_NOT_RETESTED`。Live2D 暂缓，用户当前没有可用的授权角色包。以下状态以停测前已取得的记录为准，换会话后先确认设备和服务现状。

在 DeepSeek Harness 中打开工作区 `/Users/wangzhaojin/work/dsh/dsh-go-harmony`，提交以下启动消息即可接续：

> 请读取 `docs/parity/deepseek-harness-handoff-20261118.md` 和其中链接的真机验收清单，按交接的优先级接手。先确认 Huawei ALN-AL10 的连接、phase25 安装版本和步骤 1108 后的群聊记忆状态。按原版 dsh-Go v1.0.15 对照完成仍可验收的项目，发现可复现的问题就修复并验证，更新清单和清理记录。麦克风已由用户确认，无需复测。Live2D 等授权素材。仅在本轮隔离测试对象上执行写入或删除，保留工作区现有改动。

## 对照和已验证结果

- 固定对照为 dsh-Go v1.0.15，提交 `a9877420ab9aee121134faf01b6a92a39ce0b05b`。当前源树里有多批未提交的开发及验收记录，基于当前源树继续。真机当前安装 **phase25**，版本 1.0.1（1000001），包名 `com.dshgo.harmony`，HAP SHA-256 `ef47c8aa3b45ebb822656ab292927137f7e97674948123edcb3c1a0e870a573b`，197451531 B。构建、签名、CRC 均通过，运行时 SHA-256 `48ae9d052ca3e90416d36fcf28adc930ffc158323b3a550c38c9e08e12a29754`。见 [phase25 构建记录](native-build-phase25.json) 和 [17 条真机清单及当前映射](phone-acceptance.md#截至-phase24-的当前覆盖映射)。
- **附件队列**：修复本机沙箱外祖先目录 `fsync` 导致的 `EACCES`。5 项附件存储回归、实际原生发布桥回归和 129 条打包客户端断言通过。手机 1059–1064 的同一场景完成上传、进入队列、撤回、重新入队、立即发送并中止原回复；持久历史中只提交一次，211 B 原件、存储对象和别名字节一致。见 [phase24 记录](native-build-phase24.json)。
- **DS Bot 启用入口**：旧包连接过程中重入 `busy` 检查，入口未显示。phase25 复用本次本机引擎返回的控制句柄并校验连接版本。新增 9 项行为在源码和实际编译输出均通过，`tests/check-dsbot.sh` 共 25 项通过。手机 1075–1079 确认入口显示、确认保存、提示重启以及重启后团队可用。见 [phase25 构建记录](native-build-phase25.json)。
- **DS Bot 已完成的后续动作**：1080–1088 创建 A、展示合成问候、改名及改色；1089–1096 复制为独立 Bot B、改名，两个 Bot 的会话 ID 不同，均读回显式测试模型。1097–1102 创建群聊，精确两名自有成员、A 为管理员、创建问候关闭，空群历史和 provider 请求数 36 不变。团队基线中的 Chief ID 和默认模型选择保持一致。1103–1106 将群接力上限填为 `1` 并点击保存，返回群聊，仍需重开表单或只读接口确认持久值。1108 打开群记忆，输入 `DSH-ROOM-MEM-1118-A` 后点击添加，**没有事后快照或读回**。群记忆、手动聊天 / @ 路由、Bot/群调度、删除、停用恢复均未结案。
- **此前有效结果**：合成媒体、会话回放、独立重答、工作区和搜索、配置导入读回、合成网页席位、通知正负例、壁纸、2×2/2×4 卡片及 Recall、删除保护、普通定时授权均已有各自限定证据。开发环境 coturn UDP/TCP 强制中继已通过。手机 TURN 走 USB TCP 转发，强制中继并双向各核对 50,000 B；真实手机 UDP、蜂窝、公网 NAT 未验。普通签名 API 26 本机 PTY 探测返回 13，远程 SSH/PTY 有独立验证。见 [11 月 17 日真机记录](device-acceptance-20261117.md)、[11 月 18 日真机记录](device-acceptance-20261118.md) 和 [开发验收清单](full-implementation-checklist.md)。

## 接续第 1 步：确认断点并完成 DS Bot

1. 用 DevEco 的 HDC `list targets` 检查 ALN-AL10/API 26（测试序列号 `23F0224326021832`），解锁后确认 Harness Pocket 前台。从 `1109` 开始追加快照。先查看群记忆是否已有 `DSH-ROOM-MEM-1118-A`，确认存在时直接核对并继续编辑或删除。先前点击可能已生效，确认缺失后再重试。复验接力上限 `1`。手动记忆只用本轮群的 `group` 范围。
2. 只在下表精确对象内测试单聊消息、群 @ 提及和接力。先确认两个 Bot 都用测试模型，且测试服务可达。创建/复制自动问候会发模型请求，空初始任务也会触发。群聊自动派发、头像生成、记忆摘要等可能走默认模型，先核对请求归属再触发。保留自动生成的 Chief，测试时不选其模型。
3. 清单第 17 条尚待 Bot/群原生或 Web 调度。先在隔离环境核对实际工具名和调度归属，再用明确授权和一个未来、可立即清除的自有任务验证单聊及群聊。核对所属目标、任务 ID 和执行历史为零，删除前核对归属。普通聊天拒绝、取消、超时、允许、完全访问仍授权、编辑与删除已经覆盖；并发/迁移/暂停历史有宿主证据，手机路径另记。
4. 结束 DS Bot 后从 UI 按 **群 → B → A** 删除精确对象并只读复核，正常删除可能归档专用会话。团队只保留其基线对象，Chief 及初始化目录可能仍存在。停用内置 DS Bot，再正常重启手机引擎，读取 `/botBundle/state` 确认 `enabled=false`、`activeAtStart=false`、`restartRequired=false`。确认默认模型仍是 `deepseek-official/deepseek-flash/off`。原状态证据为 `/tmp/dsh-device-20261118/1067-dsbot-control-state.json`。

| 本轮自有对象 | 显示名称 | 精确 ID |
|---|---|---|
| Bot A | `DSH-BOT-UI-1118-A-EDIT` | `session-fb3fe888-bcf6-4b2c-98b8-a941b3d4ee1f` |
| Bot B | `DSH-BOT-UI-1118-B` | `session-2c5e0913-fca4-49a0-9037-48df0bab9d76` |
| 群聊 | `DSH-ROOM-UI-1118` | `session-b0949e4d-5f4f-497e-a5fe-50f90757afd3` |

合成模型为 `device_fixture_976c9a5c40054f1cb81bee3a4744bbc4/device-fixture`。Mac 合成服务通过 HDC reverse `64114` 提供；停测时本地记录显示运行中、累计 36 个请求，**预定 2026-11-18 14:30:53 CST 自动到期**。接手时先检查实际是否仍在线。过期就重新准备自有隔离服务并验证连接，再恢复模型请求。切勿用默认付费模型代替夹具。此前隔离 Mac 插件主机 `60863`、其目录和转发已清理，手机可能仍列出该主机注册。需要远程插件或 PTY 时新建隔离主机。

## 接续第 2 步：补测剩余可执行路径

| 优先级 | 清单项 | 下一次最小验证 |
|---|---|---|
| 高 | 1、2、6 新建首发、引用、导航 | 新对话选显式合成模型、`standard` 及「仅可查看」，发送唯一纯文本 `DSH-FIRSTSEND-1118-ONLYONCE`。精确会话只读核对权限、模型、预设在首轮前应用，消息一次、无工具调用、终态 idle。模型选择可能保存全局默认，先记录、后恢复。用自有 `DSH-DEVICE-LOCAL-1117-0dcc8309064f/`、其 `proof.txt`、以及 `DSH-DEVICE-BUSY-1118` 会话各插一枚 @ 引用，系统复制清空后粘贴，核对顺序、原子签和提交载荷。再验一个固定深链及桌面新对话静态入口。 |
| 高 | 5 翻译与速记 | 验原生设置、合成思考块「翻译 → 原文 → 译文」及失败重试。先核对翻译 API 是否兼容现有夹具。速记使用对应合规服务验证配置保存、取消和重开，可以先完成配置流。 |
| 中 | 4、10 媒体和分享 | 用自有参考图核服务收到的图像字节与选定参数；配置分享导出实际保存文件，再从选择器读回核对载荷。商业服务、加密链接托管、真实插件安装分别需要服务条件。 |
| 中 | 7、9 远程终端和插件 | 新隔离主机补原生粘贴，核 PTY 实际收到的输入。核维护日志、取消重置。补插件专用配置保存/重开、请求取消及换主机后旧回包隔离。Cordis 和真实包管理需要可写隔离主机。 |
| 中 | 8、11 设置/论坛 | 补设置的用量、隐私、性能、子代理允许列表读回并恢复。论坛先做匿名阅读/搜索，账号、OAuth、订阅、余额等待真实账号；宽屏视觉需对应视口。 |
| 中 | 12、13、14 手机工具、桌宠、伙伴 | 补截图拒绝/再授权、权限状态刷新、模型工具闭环。桌宠用有权使用的 pack 试导入并核输入/滚动/后台暂停；卡片周期刷新及进程恢复单列。补伙伴未保存取消、轻量/完整会话隔离。Live2D 舞台等授权包，Signals 预览/分享等实际生产器。API 26 的普通 HAP 无障碍节点/手势当前未证实。 |

第 15、16 条限定的 Recall 和删除保护已有设备证据，可直接引用。每次修复先在同条件复现，再跑针对回归、构建签名、覆盖安装及同路径复验。结果区分宿主、真机 UI 与真机协议。视觉验收用同语言、主题、字体和视口，比对正常、空、加载、错误、键盘和返回状态。把剩余的材料、账号、平台及网络条件留在清单里。

## 取证和收尾

- DevEco `/Applications/DevEco-Studio.app/Contents`，HDC `sdk/default/openharmony/toolchains/hdc`，Node 24 `tools/node/bin/node`；标准编译 `tools/hvigor/bin/hvigorw --mode module -p module=entry@default -p product=default -p buildMode=debug assembleHap --no-daemon`。构建环境变量及签名入口见 [项目 README](../../README.md)。签名 HAP 在 `entry/build/default/outputs/default/entry-default-signed.hap`。变动只在 ArkTS 时沿用相同打包运行时。
- 本机证据根目录 `/tmp/dsh-device-20261118`；UI JSON、图片及 `phone.py` 在 `/tmp/dsh-device-20261117`。phase25 用 `phase25/1079-process.json`、`dsbot-observer/{team-baseline1,a-created1,a-edited1,ab-ready1,room-created1}.json` 与 1075–1108 UI 树。`a-edited1` 读取时复制已出现，第三个 Bot 当时尚未登记；`ab-ready1` 排除精确 A/B 后基线一致。先用新 ready 核端口，停测前最后已知 DSH 端口为 `34371`。观察工具 `dsbot-observer/read-only.mjs` 只在团队 UI ready 后读取 `hello/state` 及精确自有聊天，`synthetic-openai-24gorhxs/read-owned-firstsend.mjs` 可验首发。私有 ready、票据、配置文件仅本地读取，日志、文档及模型消息只记录脱敏字段、摘要和哈希。
- 完成后还原临时亮屏和熄屏超时。最后的文档记录显示测试 `SCREEN` 运行锁及曾设 `7200000 ms` 的覆盖值无恢复凭证。通过 `hidumper -s PowerManagerService -a -f`、`power-shell timeout -r` 解除测试设置，再以 `hidumper -s PowerManagerService -a -r` 和 `-a -s` 读回。系统通知 OFF / 应用五项 ON 已恢复，测试壁纸已关闭但自有 PNG 保留，2×2 和 2×4 测试卡片已移除。
- 完成模型相关测试并确认空闲后，再精确清理本轮独有合成渠道、凭据引用、测试会话/文件及 HDC 转发，按实际需要保留证据备份。先 `fport ls`，仅移除本轮可确认所属的规则。旧规则记录含 `36351`、`39595`、`40833`、`34061`、`33175`，最后一批有 `34371` 和 provider reverse `64114`，以实时列表为准。删除正向规则要分别传两个参数，例如 `fport rm tcp:36351 tcp:36351`，并检查工具文本和实际列表。用户会话、正常凭据、其他主机和工作区不在清理范围。
- 形成最终结论时更新 [真机验收清单](phone-acceptance.md) 和 [设备记录](device-acceptance-20261118.md)，记录使用的 HAP SHA、实际结果、未覆盖场景及恢复状态。旧失败证据保留。为下一次接续优先保存脱敏摘要，`/tmp` 证据随后可能过期或被系统清理。
