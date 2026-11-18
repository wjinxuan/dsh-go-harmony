# 伙伴信号原生实现与验证

固定来源：`ccch1mneyyy/dsh-Go@a9877420ab9aee121134faf01b6a92a39ce0b05b`，对应 `packages/dsh_client/lib/src/companion_signals.dart`、`companion_signals_api.dart`、`app/lib/companion/companion_signals.dart`、`companion_late_use.dart`。本次移植遵循上游 AGPL-3.0，固定运行结果语料放于 `tests/fixtures/companion/companion_signal_results.json`。引擎原补丁及许可证由 `runtime/vendor/companion-signals-patches/` 保留；构建先应用 Recall，再应用 Signals 的整文件 SHA256 守卫补丁。

- `dsh/CompanionSignalProtocol.ets` 是纯严格协议解析。能力最大 4096 bytes，明确 `replay:false`、`counts:false`、电量/通知不可用；`run.result` 最大 1024 UTF-8 bytes，固定键集、UUID generation、安全整数、source tuple 的 SHA256/base64url event ID。测试数始终未知，不能由输出文字推测成功。
- `DshClient.companionSignalCapabilities/companionSignalEvents` 使用当前认证 HTTP 连接，保留路径前缀、不跳转；能力绑定实际客户端对象和连接 generation。SSE 必须先收到匹配的 ready，严格逐字节 UTF-8、2048 byte 行与 4096 byte 帧边界，拒绝重复字段、额外事件、错误 id/generation。45 秒无数据关闭，不自动重连或回放。取消、连接关闭、主机切换、isAllowed 撤销或重入更换连接立即让旧 receipt 失效。
- `CompanionSignals` 是真实接收所有者。未读取同意设置不订阅；能力 unavailable 不冒充 ready。task approval/cancel 来自当前客户端实际 mux listener；terminal 仅由实际 running→idle 边沿触发精确会话读取，异步返回前重验 session revision 与连接。过滤伙伴自身会话。后台、页面/模式/主机所有者退出清空 gate 并取消订阅。
- `CompanionSignalsData` gate 保留实际 source/client/connection/capability 身份，hostKey 只用来显示与去重。每个 host 最多 10 个 seq 事件/分钟，8 个展示槽、512 个去重项；更新事实先撤回旧结果再限流。终端/运行元数据 10 分钟过期，台词 2 分钟，approval 只在仍 pending 时有效；先收到 clear 也阻止迟到 waiting 复活。单调时钟退回时关闭 gate。
- 四项同意分别为状态、可选台词、语音、深夜关怀。既有安装无记录才使用上游 state/optionalSpeech 默认 true，voice/nightCare 默认 false；损坏或不可读不恢复授权。授权在持久化成功后生效，撤销立即生效。可选台词送入 `CompanionInitiativeOwner/Panel` 的共享持久配额与安静/时段 gate，不能直接由事件回调播放；语音还受原生语音设置双重限制。
- 深夜关怀仅统计真实交互后的两分钟以内前台活动；深夜窗口 23:00–07:00，累计 15 分钟。后台和长时间无交互不补计；时区/壁钟漂移清空进度，倒退故障关闭，不采集输入内容。
- 预览为本机元数据模板；用户点选才读取该 client/session/seq 的详情（4096 字符上限）。分享再次显示确切文本并确认；许可只能使用一次，绑定具体 recipient、room epoch、light keeper/model 配置身份，或 full client/connection/完整 recall binding。full 分享在发送前实际重新读取绑定，异步边界和最终写入前重验；不自动发送信号或终端输出给模型。

## 本机生产能力边界

Harmony 配置仍禁止 Node 子进程；未安装实际 bash 工具生产器时，原版 bridge 正确返回 `available:false, reason:producer-unavailable`。这不阻断 mux task 状态/审批与本机深夜观察。不能用系统日志、shell 探测、任意 tool metadata 或伪造 SSE 充当执行结果生产器。远端拥有真实原版执行器时可直接使用上述协议。

## 宿主验证

Node 24：

```sh
node --test tests/companion-signals.test.mjs
node tests/companion-signals-http.mjs /path/to/unpacked-runtime
node tests/companion-signals-live.mjs /path/to/unpacked-runtime
```

纯协议/gate/owner 10 项覆盖固定上游 corpus、UTF-8/SHA256、授权和对象归属、重入、去重/乱序/限流/TTL、clear 抢先到达、异步 idle 失效、一次性分享、目标/文本篡改、夜间实际活动累计。HTTP 测试使用真实 loopback HTTP 与生产 DshClient，只有 RCP 映射 Node fetch，覆盖 auth/前缀/no redirect、恶意 SSE 和取消/断线。

实际引擎链路首先验证**未改变的生产包**返回 producer-unavailable；随后仅在隔离测试子进程的 import hook 中临时启用原版 `dsh-subprocess-local`、`dsh-bash-local`、`tool-bash` 并恢复宿主 spawn。真正运行 `node --test fixture-test.mjs`，经原版 producer wrapper→提交 pipeline→bridge SSE→原生客户端，验证 succeeded/exit 0、测试数 null、stdout 不在信号中、取消/连接更换失效、重新订阅无回放。测试没有改生产脚本或 HAP；模型 HTTP 与宿主 native file-lock 是测试替身，执行器和进程输出是真实的。普通 HAP shell 能力不能由此宣称已验证。
