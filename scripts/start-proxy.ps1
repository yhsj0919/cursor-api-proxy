$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$cliPath = Join-Path $projectRoot 'dist\cli.js'
$agentPath = Join-Path $env:LOCALAPPDATA 'cursor-agent\agent.cmd'

$Host.UI.RawUI.WindowTitle = 'Cursor API 代理'
Set-Location $projectRoot

if (-not (Test-Path -LiteralPath $cliPath)) {
  Write-Host '[错误] 未找到 dist\cli.js。' -ForegroundColor Red
  Write-Host '请先构建项目，再启动代理。'
  Read-Host '按回车键退出'
  exit 1
}

if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
  Write-Host '[错误] PATH 环境变量中找不到 node.exe。' -ForegroundColor Red
  Read-Host '按回车键退出'
  exit 1
}

if (-not $env:CURSOR_AGENT_BIN -and (Test-Path -LiteralPath $agentPath)) {
  $env:CURSOR_AGENT_BIN = $agentPath
}
$env:CURSOR_BRIDGE_USE_ACP = 'true'
$env:CURSOR_BRIDGE_DEFAULT_MODEL = 'auto'
$env:CURSOR_BRIDGE_MODE = 'agent'
# Cursor ACP 的已登录凭据来自当前 Windows 用户目录，现有隔离模式会隐藏该凭据。
$env:CURSOR_BRIDGE_CHAT_ONLY_WORKSPACE = 'false'

if (-not $env:CURSOR_AGENT_BIN -or -not (Test-Path -LiteralPath $env:CURSOR_AGENT_BIN)) {
  Write-Host "[错误] 找不到 Cursor Agent：$($env:CURSOR_AGENT_BIN)" -ForegroundColor Red
  Read-Host '按回车键退出'
  exit 1
}

Write-Host '正在检查 Cursor Agent 登录状态和模型列表...'
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  $modelOutput = @(& $env:CURSOR_AGENT_BIN --list-models 2>&1)
  $modelExitCode = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $previousErrorAction
}
$modelCount = @($modelOutput | Where-Object {
  (([string]$_) -replace '\x1b\[[0-9;]*m', '') -match '^\s*[^\s]+\s+-\s+.+$'
}).Count
if ($modelExitCode -ne 0 -or $modelCount -eq 0) {
  Write-Host '[错误] Cursor Agent 尚未登录，或无法获取模型列表。代理未启动。' -ForegroundColor Red
  $message = (($modelOutput | ForEach-Object { [string]$_ }) -join "`n")
  if ($message) { Write-Host $message }
  Write-Host ''
  Write-Host '请先在 PowerShell 中执行：'
  Write-Host "& `"$($env:CURSOR_AGENT_BIN)`" login" -ForegroundColor Yellow
  Write-Host '登录完成后，重新双击 start-proxy.bat。'
  Read-Host '按回车键退出'
  exit 1
}
Write-Host "Cursor Agent 登录正常，可用原始模型 ID：$modelCount 个。" -ForegroundColor Green

# --list-models 已经用当前 Cursor Agent 凭据完成了认证检查。
# ACP 的 authenticate(cursor_login) 会强制再次打开 Cursor 登录页，因此这里明确跳过。
$env:CURSOR_BRIDGE_ACP_SKIP_AUTHENTICATE = 'true'

$port = if ($env:CURSOR_BRIDGE_PORT) { $env:CURSOR_BRIDGE_PORT } else { '8765' }
Write-Host '正在启动 Cursor API 代理...'
Write-Host "管理面板：http://127.0.0.1:$port"
Write-Host '按 Ctrl+C 可停止服务。'
Write-Host ''

& node.exe $cliPath @args
$exitCode = $LASTEXITCODE

Write-Host ''
Write-Host "Cursor API 代理已停止，退出代码：$exitCode。"
if ($exitCode -ne 0) { Read-Host '按回车键退出' }
exit $exitCode
