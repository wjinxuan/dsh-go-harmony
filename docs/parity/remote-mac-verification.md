# Mac DSH 远程操作验证

测试使用原版 Mac DSH 0.2.2-rc.1 的 `web` profile，以及应用中实际使用的 `DshClient.ets`。Node 测试适配鸿蒙网络和文件 API，在 Mac 上完成真实 HTTP、WebSocket 和 DSH 鉴权。模型响应由回环地址上的测试服务提供，执行文件工具和 shell 的进程是原版 Mac DSH。

## 准备

使用 Node.js 24.22.1，以及按项目锁文件安装的 Mac 版 DSH 0.2.2-rc.1。安装需包含 macOS 对应的可选原生依赖。现成的完整 Mac 安装可直接使用。若只有项目的鸿蒙运行时 ZIP，可以从中提取依赖清单，在临时目录中安装锁定的 Mac 依赖：

```sh
mac_dsh=$(mktemp -d)
runtime_zip=entry/src/main/resources/rawfile/dsh-runtime.zip
unzip -j "$runtime_zip" package.json package-lock.json -d "$mac_dsh"
npm --prefix "$mac_dsh" ci --include=optional --ignore-scripts --no-audit --no-fund
```

Node、DSH 和 HDC 路径应按实际安装位置替换。

```sh
node tests/remote-dsh-live.mjs /path/to/node_modules/@deepseek-ai/dsh/lib/bin.js
```

测试用独立临时 HOME、DSH_HOME 和默认工作区启动 DSH。只监听 `127.0.0.1`，测试完成后清理。覆盖：

- 错误启动令牌被拒绝，正确启动令牌换取会话 Cookie。Mac DSH 拒绝缺端口的 WebSocket Origin，API 26 适配携带同源端口后握手成功。
- 手机端客户端 API 创建会话，在 Mac 测试工作区写入并读取文件，读不存在的文件时返回工具错误。
- Mac 执行 Bash 命令并同时返回标准输出和文件结果。
- 通过会话后台任务接口接收命令的标准输出和结束状态。
- 手机端客户端 API 收到包含命令详情的审批请求，拒绝后文件未创建。

## USB 真机验证

连接一台已授权 USB 调试的鸿蒙手机。运行同一测试脚本的真机模式：

```sh
node tests/remote-dsh-live.mjs /path/to/node_modules/@deepseek-ai/dsh/lib/bin.js \
  --phone /path/to/hdc
```

脚本建立手机到 Mac 回环地址的 USB 反向转发，并显示临时启动 URL 文件的位置。文件权限为 `0600`。将其中的 URL 输入应用的「远程主机」，使用 `deepseek-flash`，选择已登记的临时工作区或用默认目录新建会话。测试脚本会在按 Ctrl-C 或 30 分钟后清理 DSH 和转发。

按需发送以下精确提示：

| 提示 | 预期结果 |
| --- | --- |
| `fixture-write` | 在 Mac 工作区创建 `fixture.txt` |
| `fixture-read` | 工具结果显示测试文件内容 |
| `fixture-missing` | 工具报告文件不存在 |
| `fixture-bash` | Bash 工具输出 `mac-shell-fixture` 并创建 `shell-proof.txt` |
| `fixture-job` | 后台任务输出 `mac-job-fixture` 并创建 `job-proof.txt` |
| `fixture-approval` | 显示提权审批。点击拒绝后，`approval-proof.txt` 仍不存在 |

USB 转发用于开发验收。日常使用从应用连接可信 HTTPS/WSS 的 DSH 主机。 [连接说明](../../README.md) · [HDC 转发文档](https://github.com/openharmony/docs/blob/master/en/application-dev/dfx/hdc.md#creating-a-remote-port-forwarding)

## 2026 年 11 月 13 日真机验收

在 Mate 60 Pro+（HarmonyOS API 26）通过 USB 开发转发连接 Mac。手机发起会话后，Mac 工作区里的 `fixture.txt`、`shell-proof.txt` 和 `job-proof.txt` 均逐字节匹配测试值。手机读回工作区文件，并在原生后台任务页显示实际标准输出 `mac-job-fixture`。审批卡显示完整命令，拒绝后 Mac 上没有生成 `approval-proof.txt`。

覆盖安装后，手机使用已保存的测试连接凭据重新连接。验收结束后，在手机上删除测试主机并返回本机引擎。Mac 临时 DSH 数据、回环监听和 USB 转发均已清理。

这次使用本地模拟模型响应。鉴权、会话、文件工具、Bash 以及后台任务由 Mac 上原版 DSH 执行。USB 链路只用于开发验收。
