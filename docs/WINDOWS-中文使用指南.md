# Cursor 模型接入 Codex：Windows 快速指南

## 1. 启动代理

双击：

```text
E:\cursor-api-proxy\start-proxy.bat
```

看到下面两行说明启动成功：

```text
cursor-api-proxy listening on http://127.0.0.1:8765
ACP: yes (launcher: node + script)
```

代理窗口需要保持打开。

如果 Cursor Agent 尚未登录，在 PowerShell 中执行：

```powershell
& "$env:LOCALAPPDATA\cursor-agent\agent.cmd" login
```

## 2. 查看 Cursor 可用模型

在 PowerShell 中运行：

```powershell
& "$env:LOCALAPPDATA\cursor-agent\agent.cmd" --list-models
```

假设输出中包含：

```text
gpt-5.6-sol
gpt-5.3-codex-fast
composer-2
```

后面的配置必须使用命令实际列出的模型 ID。这三个名称只是示例。

## 3. 配置 Cursor 提供方

打开：

```text
C:\Users\Admin\.codex\config.toml
```

加入下面这段。多个 Cursor 模型共用这一个提供方配置。

```toml
[model_providers.cursor]
name = "Cursor API Proxy"
base_url = "http://127.0.0.1:8765/v1"
wire_api = "responses"
requires_openai_auth = false
```

在文件顶部指定当前模型：

```toml
model_provider = "cursor"
model = "gpt-5.6-sol"
model_reasoning_effort = "low"
```

最小完整示例：

```toml
model_provider = "cursor"
model = "gpt-5.6-sol"
model_reasoning_effort = "low"

[model_providers.cursor]
name = "Cursor API Proxy"
base_url = "http://127.0.0.1:8765/v1"
wire_api = "responses"
requires_openai_auth = false
```

保存后新建一个 Codex 任务。已经打开的任务不会自动换模型。

## 4. 用批处理切换模型来源

切换前必须从系统托盘彻底退出 Codex。模型提供方在任务创建时确定，不能把已经打开的官方任务热切换成 Cursor。脚本检测到 Codex 仍在运行时会取消操作，不会修改配置。

双击：

```text
E:\cursor-api-proxy\switch-codex-model.bat
```

批处理只选择模型大类：

```text
1. Codex 官方模型
2. Cursor 账号模型
3. 查看当前配置
0. 取消并退出
```

选择 Cursor 后，脚本执行 `agent --list-models`，把当前 Cursor 账号的模型写入：

```text
C:\Users\Admin\.codex\cursor-models.json
```

脚本同时在 `config.toml` 中设置 `model_catalog_json`。切换完成后重新打开 Codex 并新建任务，Codex 自己的模型选择器会显示这批 Cursor 模型。具体模型在这个新任务里选择。

Cursor 返回的多个思考档位会合并成一个基础模型。例如 `gpt-5.6-sol-low`、`gpt-5.6-sol-high` 和 `gpt-5.6-sol-xhigh` 在列表中只显示一次，具体档位使用 Codex 的思考强度选择器设置。`auto` 会显示为 `Auto (Cursor)`。GPT 系模型会写成 `OpenAI GPT-…`（例如 `OpenAI GPT-5.4 Mini`），避免 Codex 界面把开头的 `GPT-` 剥掉后只剩 `5.4 Mini`；`gpt-5.5-extra` 这类重名项会标成 `Extra` 以便区分。

切换窗口会同时显示 Cursor 返回的原始模型 ID 数量和合并后 Codex 显示的模型数量。合并后数量较少通常不是缺失，而是 `low`、`high`、`xhigh`、`max` 等重复条目已归入同一个基础模型。

切回 Codex 官方后，脚本移除 `model_catalog_json`，Codex 的模型选择器恢复官方模型列表。

## 5. 切回 Codex 官方模型

### 用批处理切回

双击 `switch-codex-model.bat`，选择：

```text
1. Codex 官方模型
```

### 手动切回

打开 `config.toml`，删除：

```toml
model_provider = "cursor"
```

或者明确指定官方提供方：

```toml
model_provider = "openai"
model = "gpt-5.6-sol"
model_reasoning_effort = "low"
```

`[model_providers.cursor]` 配置块可以保留。只要当前 `model_provider` 不是 `cursor`，Codex 就不会使用本地代理。

## 6. 检查当前使用的提供方

双击 `switch-codex-model.bat`，选择第 3 项。

也可以查看 `config.toml` 顶部：

```toml
model_provider = "cursor"  # Cursor 本地代理
```

```toml
model_provider = "openai"  # Codex 官方提供方
```

没有 `model_provider` 时，默认使用官方 `openai` 提供方。

## 7. 常见错误

`ACP: no`：关闭旧代理窗口，重新双击 `start-proxy.bat`。正确输出必须是 `ACP: yes`。

`Authentication required`：执行下面的命令登录 Cursor：

```powershell
& "$env:LOCALAPPDATA\cursor-agent\agent.cmd" login
```

登录完成后必须关闭旧代理窗口，并重新双击 `start-proxy.bat`。启动脚本会先验证同一个 Cursor Agent 能否列出模型；验证失败时不会启动代理。

`Port 8765 is already in use`：已有代理正在运行。关闭旧窗口，不要同时运行两个代理。

切换后模型没变化：彻底退出 Codex，重新运行切换批处理，再打开 Codex 并新建任务。提供方不会热切换到当前任务。

`The '<模型名>' model is not supported when using Codex with a ChatGPT account`：说明当前任务仍使用官方 `openai` 提供方。不要在这个旧任务里继续选择 Cursor 模型；退出 Codex，重新切换到 Cursor，然后新建任务。

## 8. 复制到另一台 Windows 电脑

### 当前电脑：复制项目

最省事的方式是复制整个项目目录，但不要带上 `node_modules`、`work` 和 `.git`。如果 `.env` 中保存了密钥，也不要复制它。

例如，把项目复制到 U 盘 `X:`：

```powershell
robocopy E:\cursor-api-proxy X:\cursor-api-proxy /E /XD node_modules work .git /XF .env
```

`robocopy` 返回码 `0` 到 `7` 通常都表示复制已完成，不一定是错误。

不要直接复制以下用户文件或目录：

- `%USERPROFILE%\.codex\config.toml`，其中可能有旧电脑的项目路径、插件和个人设置。
- `%USERPROFILE%\.codex\models_cache.json` 和 `cursor-models.json`。目标电脑会按自己的 Codex 版本和 Cursor 账号重新生成。
- Cursor 的登录信息、令牌或整个 `.cursor`、`.cursor-api-proxy` 用户目录。请在目标电脑单独登录。

批处理使用 `%LOCALAPPDATA%` 和 `%USERPROFILE%` 查找程序及配置，因此目标电脑可以使用不同用户名和盘符。

### 目标电脑：安装和构建

先安装：

- Node.js 18 或更高版本
- Cursor Agent
- Codex

将项目复制到任意目录，例如 `D:\tools\cursor-api-proxy`，然后在 PowerShell 中执行：

```powershell
cd D:\tools\cursor-api-proxy
npm install
npm run build
```

确认 Cursor Agent 已登录，并能列出模型：

```powershell
& "$env:LOCALAPPDATA\cursor-agent\agent.cmd" login
& "$env:LOCALAPPDATA\cursor-agent\agent.cmd" --list-models
```

### 目标电脑：首次启用

1. 双击 `start-proxy.bat`。
2. 确认窗口显示 `cursor-api-proxy listening on http://127.0.0.1:8765` 和 `ACP: yes`。
3. 双击 `switch-codex-model.bat`，选择 `2. Cursor 账号模型`。
4. 脚本会备份并修改目标电脑自己的 `%USERPROFILE%\.codex\config.toml`，同时重新生成 `cursor-models.json`。
5. 重启 Codex 或新建任务，再从 Codex 内部的模型选择器选择具体 Cursor 模型。

启动脚本会先通过 `agent --list-models` 检查 Cursor Agent 的现有登录状态。检查成功后，ACP 会直接复用该状态并跳过 `cursor_login`，实际发送消息时不应再次打开 Cursor 登录页。当前 Cursor Agent 的登录凭据依赖真实 Windows 用户目录，因此启动脚本关闭 chat-only 临时用户目录隔离；不同请求仍会创建独立 ACP 会话，但会共享代理配置的工作区文件状态。

启动脚本默认使用 Cursor 的 `agent` 模式，以便正常执行文件修改和命令。Codex 的模型选择器只负责模型及思考档位，不提供 Cursor `ask`、`plan`、`agent` 模式切换，因此桌面端正常使用时以这个启动默认值为准。

以后需要恢复官方模型时，再运行 `switch-codex-model.bat`，选择 `1. Codex 官方模型`，然后重启 Codex 或新建任务。

建议目标电脑继续使用默认端口 `8765`。如果修改端口，启动代理的端口和 `config.toml` 中 Cursor 提供方的 `base_url` 必须同时修改；切换脚本当前会把地址恢复为 `http://127.0.0.1:8765/v1`。

## 配置依据

`model`、`model_provider`、`model_providers.<id>` 和 `model_catalog_json` 的规则来自 [OpenAI Codex Configuration Reference](https://learn.chatgpt.com/docs/config-file/config-reference)。
