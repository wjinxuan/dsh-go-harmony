# 远程 DSH 文件、命令与任务实现计划

> **For agentic workers:** Use subagent-driven-development to implement the independent protocol, host UI and live verification tasks below.

**Goal:** 手机以 ArkTS / ArkUI 连接电脑上的原版 DSH，复用会话、文件、审批和任务界面，验证实际执行发生在电脑。

**Architecture:** 保留 DshClient 的 HTTP 登录和 WebSocket mux。远程主机元数据存 Preferences，用户选择记住的启动令牌及代理凭据存 AssetKit；切换连接不停止后台本机引擎。通过原版 Mac DSH 的隔离工作区验证，而非用手机受限运行时模拟电脑。

**Tech Stack:** ArkTS / ArkUI、RCP、NetworkKit、AssetKit、原版 DSH 0.2.2-rc.1。

## Constraints

- 原版参考固定为 dsh-Go v1.0.15；页面原生实现，不使用 Flutter / WebView。
- 本阶段提供实际 HTTPS/WSS 直连。SSH、Remote 账号配对及交互终端尚未移植，不显示可用的假入口。
- 非回环连接要求受信 HTTPS；保留 token、Cookie、Host 和 Origin 检查，不降低证书验证。
- 测试仅监听 Mac 回环；HDC 反向转发仅为真机验收手段，结束时清理。
- 不读取用户 Key；合成模型仅驱动真实 DSH 文件、命令和后台任务，用单独标记区分验证范围。
- 现有目录不是 Git 仓库，不创建提交或初始化仓库。

## Tasks

- [x] `DshClient.ets`：回环直连禁用代理；API 26 的 WS 保留 Origin 端口；对鉴权拒绝和连接失败做回归测试。
- [x] `remote/RemoteHosts.ets`、`ui/RemoteHostsPanel.ets`：新增、编辑、删除、连接保存主机；安全保存凭据；输入验证、失败可重试、当前主机状态和硬件返回。
- [x] `pages/Index.ets`：引导、抽屉、设置统一主机入口；切换时清空前一主机的会话与草稿；本机引擎生命周期独立，显式停止才终止任务。
- [x] `tests/remote-dsh-live.mjs`：复用现有 Node 网络适配测试真实客户端，断言电脑文件结果、命令输出和后台任务的真实状态；误鉴权必须拒绝。
- [x] 构建并覆盖安装签名 HAP，真机连接隔离 Mac DSH，查看文件、发命令并查看任务。若锁屏需解锁后继续，不以构建代替验收。
- [x] 更新 parity、构建收据、真实验证结果及未完成项，同步知识库。

## Knowledge assessment

知识库中当前 source 对应的活动项目页面已读取；架构自动提取内容不完整，以项目 README、parity 文档和当前源文件为准。当前只有手工启动链接，无保存主机；现有文件/任务已属于 DshClient，应直接复用。必须保持主机切换隔离、防止跨主机草稿和异步返回串入，同时避免断开客户端误停仍在运行的本机任务。

## Result

Signed HAP and phone acceptance completed; see native-build.json and remote-mac-verification.md for exact test scope. Production TLS connectivity, SSH, account pairing and terminal remain outside this delivered direct-connection slice.
