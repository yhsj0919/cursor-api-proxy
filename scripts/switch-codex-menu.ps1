$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = '切换 Codex 模型来源'
$switchScript = Join-Path $PSScriptRoot 'switch-codex-provider.ps1'

Write-Host '========================================'
Write-Host '  Codex 模型来源切换工具'
Write-Host '========================================'
Write-Host '  1. Codex 官方模型'
Write-Host '  2. Cursor 账号模型'
Write-Host '  3. 查看当前配置'
Write-Host '  0. 取消并退出'
Write-Host ''

$exitCode = 0
try {
  $choice = (Read-Host '请选择 [0-3]').Trim()
  switch ($choice) {
    '1' { & $switchScript -Provider codex }
    '2' { & $switchScript -Provider cursor }
    '3' { & $switchScript -Provider status }
    '0' { exit 0 }
    default { throw '输入无效，请输入 0 到 3。' }
  }
} catch {
  $exitCode = 1
  Write-Host ''
  Write-Host "切换失败：$($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ''
Read-Host '按回车键退出'
exit $exitCode
