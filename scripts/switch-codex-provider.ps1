param(
  [ValidateSet('codex', 'cursor', 'status')]
  [string]$Provider = 'status',
  [string]$Model = '',
  [string]$ConfigPath = (Join-Path $env:USERPROFILE '.codex\config.toml'),
  [string]$AgentPath = ''
)

$ErrorActionPreference = 'Stop'
$codexDir = Split-Path -Parent $ConfigPath
$cursorCatalogPath = Join-Path $codexDir 'cursor-models.json'
$agentPath = if ($AgentPath) { $AgentPath } else { Join-Path $env:LOCALAPPDATA 'cursor-agent\agent.cmd' }

function Write-Utf8WithoutBom {
  param([string]$Path, [string]$Content)
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Assert-CodexIsClosed {
  $running = @(Get-Process -Name 'ChatGPT', 'codex' -ErrorAction SilentlyContinue)
  if ($running.Count -gt 0) {
    throw '检测到 Codex 桌面端仍在运行。当前任务的模型提供方不能热切换。请先从系统托盘彻底退出 Codex，再运行本批处理；切换完成后重新打开 Codex，并新建任务。'
  }
}

function Get-TopLevelValue {
  param([string]$Text, [string]$Key)
  $header = ($Text -split '(?m)^\s*\[')[0]
  $match = [regex]::Match($header, "(?m)^\s*$([regex]::Escape($Key))\s*=\s*[`"']([^`"']*)[`"']\s*$")
  if ($match.Success) { return $match.Groups[1].Value }
  return $null
}

function Set-TopLevelValue {
  param([string]$Text, [string]$Key, [string]$Value)
  $section = [regex]::Match($Text, '(?m)^\s*\[')
  $cut = if ($section.Success) { $section.Index } else { $Text.Length }
  $header = $Text.Substring(0, $cut)
  $tail = $Text.Substring($cut)
  $pattern = "(?m)^\s*$([regex]::Escape($Key))\s*=.*(?:\r?\n|$)"
  $line = "$Key = `"$Value`"`r`n"
  if ([regex]::IsMatch($header, $pattern)) {
    $header = [regex]::Replace($header, $pattern, $line, 1)
  } else {
    $header = $line + $header.TrimStart("`r", "`n")
  }
  return $header + $tail
}

function Remove-TopLevelValue {
  param([string]$Text, [string]$Key)
  $section = [regex]::Match($Text, '(?m)^\s*\[')
  $cut = if ($section.Success) { $section.Index } else { $Text.Length }
  $header = $Text.Substring(0, $cut)
  $tail = $Text.Substring($cut)
  $pattern = "(?m)^\s*$([regex]::Escape($Key))\s*=.*(?:\r?\n|$)"
  return ([regex]::Replace($header, $pattern, '', 1) + $tail)
}

function Ensure-CursorProvider {
  param([string]$Text)
  $block = @"

[model_providers.cursor]
name = "Cursor API Proxy"
base_url = "http://127.0.0.1:8765/v1"
wire_api = "responses"
requires_openai_auth = false
"@
  $pattern = '(?ms)^\[model_providers\.cursor\]\s*.*?(?=^\[|\z)'
  if ([regex]::IsMatch($Text, $pattern)) {
    return [regex]::Replace($Text, $pattern, $block.TrimStart() + "`r`n", 1)
  }
  return $Text.TrimEnd() + "`r`n" + $block + "`r`n"
}

function Get-CursorModels {
  if (-not (Test-Path -LiteralPath $agentPath)) {
    throw "找不到 Cursor Agent：$agentPath"
  }
  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $raw = @(& $agentPath --list-models 2>&1)
    $agentExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorAction
  }
  if ($agentExitCode -ne 0) {
    $message = (($raw | ForEach-Object { [string]$_ }) -join "`n")
    if ($message -match 'Authentication required') {
      throw "Cursor Agent 尚未登录。请先在 PowerShell 中执行：`n& `"`$env:LOCALAPPDATA\cursor-agent\agent.cmd`" login"
    }
    throw $message
  }

  $models = @()
  foreach ($line in $raw) {
    $clean = ([string]$line) -replace '\x1b\[[0-9;]*m', ''
    if ($clean -match '^\s*([^\s]+)\s+-\s+(.+?)\s*$') {
      $models += [pscustomobject]@{ Id = $Matches[1]; Name = $Matches[2] }
    }
  }
  $models = @($models | Sort-Object Id -Unique)
  if ($models.Count -eq 0) {
    throw '未获取到任何可供 Codex 使用的 Cursor 模型。为避免切换到空列表，Codex 配置保持不变。请先手动执行 agent --list-models 检查输出。'
  }
  return $models
}

function ConvertTo-CursorModelVariant {
  param($CursorModel)

  $id = [string]$CursorModel.Id
  $core = $id
  $fast = $false
  if ($core -match '^(.*)-fast$') {
    $core = $Matches[1]
    $fast = $true
  }

  $effort = $null
  $baseCore = $core
  $effortPattern = '(none|minimal|low|medium|high|xhigh|max|ultra|extra-high)'
  if ($core -match "^(.*)-$effortPattern-thinking$") {
    $baseCore = "$($Matches[1])-thinking"
    $effort = $Matches[2]
  } elseif ($core -match "^(.*)-$effortPattern$") {
    $baseCore = $Matches[1]
    $effort = $Matches[2]
  }
  if ($effort -eq 'extra-high') { $effort = 'xhigh' }

  [pscustomobject]@{
    BaseId = $baseCore + $(if ($fast) { '-fast' } else { '' })
    Effort = $effort
    Id = $id
    Name = [string]$CursorModel.Name
  }
}

function Format-CursorDisplayName {
  param(
    [string]$Slug,
    [string]$RawName
  )

  if ($Slug -eq 'auto') { return 'Auto (Cursor)' }

  $name = [string]$RawName
  $name = $name -replace '(?i)\s+(extra high|none|minimal|low|medium|high|xhigh|max|ultra)(?=(\s+thinking)?(\s+fast)?$)', ''
  $name = $name.Trim()
  if (-not $name) { $name = $Slug }

  # Cursor sometimes reuses the same marketing name for -extra variants.
  if ($Slug -match '(?i)(^|-)extra(-|$)') {
    if ($name -notmatch '(?i)\bextra\b') {
      if ($name -match '(?i)^(.*?)(\s+Fast)$') {
        $name = "$($Matches[1].Trim()) Extra$($Matches[2])"
      } else {
        $name = "$name Extra"
      }
    }
  }

  # Codex UI strips a leading "GPT-"/"GPT " from labels. Keep a vendor word
  # in front (like Claude / Gemini) so the family stays visible in the picker.
  if ($Slug -match '^(?i)(gpt-|o[0-9])') {
    if ($name -match '(?i)^GPT[- ]') {
      $name = "OpenAI $name"
    } elseif ($name -match '(?i)^Codex\b') {
      $name = "OpenAI $name"
    } elseif ($name -notmatch '(?i)^OpenAI\b') {
      $name = "OpenAI $name"
    }
  }

  return $name
}

function Write-CursorModelCatalog {
  param([array]$CursorModels)

  if ($null -eq $CursorModels -or $CursorModels.Count -eq 0) {
    throw 'Cursor 模型列表为空，已取消生成模型目录，Codex 配置保持不变。'
  }

  $cachePath = Join-Path $codexDir 'models_cache.json'
  if (-not (Test-Path -LiteralPath $cachePath)) {
    throw "找不到 Codex 模型目录模板：$cachePath"
  }
  $cache = Get-Content -Raw -Encoding UTF8 -LiteralPath $cachePath | ConvertFrom-Json
  $template = $cache.models | Where-Object { $_.slug -eq 'gpt-5.6-sol' } | Select-Object -First 1
  if (-not $template) { $template = $cache.models | Select-Object -First 1 }
  if (-not $template) { throw 'Codex 模型目录模板为空。' }

  $variants = @($CursorModels | ForEach-Object { ConvertTo-CursorModelVariant -CursorModel $_ })
  $groups = @($variants | Group-Object BaseId | Sort-Object Name)
  Write-Host "Cursor 返回 $($CursorModels.Count) 个原始模型 ID；按思考档位合并后，Codex 将显示 $($groups.Count) 个模型项。"
  $effortOrder = @('none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra')
  $effortDescriptions = @{
    none = 'No additional reasoning'
    minimal = 'Minimal reasoning'
    low = 'Fast responses with lighter reasoning'
    medium = 'Balances speed and reasoning depth'
    high = 'Greater reasoning depth for complex problems'
    xhigh = 'Extra high reasoning depth for complex problems'
    max = 'Maximum reasoning depth'
    ultra = 'Maximum reasoning with automatic task delegation'
  }

  $catalogModels = @()
  $priority = 1
  foreach ($group in $groups) {
    $representative = $group.Group | Select-Object -First 1
    $displayName = Format-CursorDisplayName -Slug $group.Name -RawName $representative.Name

    $availableEfforts = @($group.Group | Where-Object { $_.Effort } | ForEach-Object { $_.Effort } | Sort-Object -Unique)
    $supportedEfforts = @()
    foreach ($effort in $effortOrder) {
      if ($availableEfforts -contains $effort) {
        $supportedEfforts += [pscustomobject]@{
          effort = $effort
          description = $effortDescriptions[$effort]
        }
      }
    }

    $entry = ($template | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
    $entry.slug = $group.Name
    $entry.display_name = $displayName
    $entry.description = 'Cursor 模型，通过本地 cursor-api-proxy 使用。'
    $entry.priority = $priority++
    $entry.visibility = 'list'
    $entry.supported_reasoning_levels = $supportedEfforts
    if ($supportedEfforts.Count -gt 0) {
      $preferredDefault = @('medium', 'high', 'low', 'xhigh', 'max', 'none', 'minimal', 'ultra') |
        Where-Object { $availableEfforts -contains $_ } |
        Select-Object -First 1
      $entry.default_reasoning_level = $preferredDefault
    } else {
      $entry.default_reasoning_level = 'low'
    }
    $entry.additional_speed_tiers = @()
    $entry.service_tiers = @()
    $entry.availability_nux = $null
    $entry.upgrade = $null
    $catalogModels += $entry
  }

  if ($catalogModels.Count -eq 0) {
    throw '生成后的 Cursor 模型目录为空，已取消切换，Codex 配置保持不变。'
  }

  $cache.models = $catalogModels
  $cache.fetched_at = (Get-Date).ToUniversalTime().ToString('o')
  $json = $cache | ConvertTo-Json -Depth 100
  $validated = $json | ConvertFrom-Json
  if ($null -eq $validated.models -or @($validated.models).Count -eq 0) {
    throw 'Cursor 模型目录校验失败，已取消切换，Codex 配置保持不变。'
  }

  $temporaryCatalogPath = "$cursorCatalogPath.tmp"
  try {
    Write-Utf8WithoutBom -Path $temporaryCatalogPath -Content $json
    Move-Item -LiteralPath $temporaryCatalogPath -Destination $cursorCatalogPath -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryCatalogPath) {
      Remove-Item -LiteralPath $temporaryCatalogPath -Force
    }
  }
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
  throw "Codex config not found: $ConfigPath"
}

$text = Get-Content -Raw -Encoding UTF8 -LiteralPath $ConfigPath
$currentProvider = Get-TopLevelValue -Text $text -Key 'model_provider'
$currentModel = Get-TopLevelValue -Text $text -Key 'model'
$currentCatalog = Get-TopLevelValue -Text $text -Key 'model_catalog_json'

if ($Provider -eq 'status') {
  $label = if ($currentProvider -eq 'cursor') { 'Cursor local proxy' } else { 'Codex official' }
  Write-Host "当前提供方：$label"
  Write-Host "当前模型：  $currentModel"
  if ($currentCatalog) { Write-Host "模型目录：  $currentCatalog" }
  Write-Host "配置文件：  $ConfigPath"
  return
}

Assert-CodexIsClosed

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = "$ConfigPath.$stamp.bak"

if ($Provider -eq 'cursor') {
  if (-not $Model) { $Model = 'auto' }
  Write-Host '正在读取 Cursor 模型并生成 Codex 内部模型目录...'
  $cursorModels = @(Get-CursorModels)
  Write-CursorModelCatalog -CursorModels $cursorModels
  Copy-Item -LiteralPath $ConfigPath -Destination $backupPath
  $catalogModelIds = @($cursorModels | ForEach-Object { (ConvertTo-CursorModelVariant -CursorModel $_).BaseId } | Sort-Object -Unique)
  if (-not ($catalogModelIds -contains $Model)) {
    $preferredModels = @('auto', 'gpt-5.6-sol', 'gpt-5.3-codex', 'composer-2.5')
    $selectedModel = $preferredModels | Where-Object { $catalogModelIds -contains $_ } | Select-Object -First 1
    $Model = if ($selectedModel) { $selectedModel } else { $catalogModelIds[0] }
  }
  $text = Set-TopLevelValue -Text $text -Key 'model_provider' -Value 'cursor'
  $text = Set-TopLevelValue -Text $text -Key 'model' -Value $Model
  $catalogForToml = $cursorCatalogPath -replace '\\', '/'
  $text = Set-TopLevelValue -Text $text -Key 'model_catalog_json' -Value $catalogForToml
  $text = Remove-TopLevelValue -Text $text -Key 'model_reasoning_effort'
  $text = Ensure-CursorProvider -Text $text
  $label = 'Cursor local proxy'
} else {
  if (-not $Model) { $Model = 'gpt-5.6-sol' }
  Copy-Item -LiteralPath $ConfigPath -Destination $backupPath
  $text = Remove-TopLevelValue -Text $text -Key 'model_provider'
  $text = Remove-TopLevelValue -Text $text -Key 'model_catalog_json'
  $text = Set-TopLevelValue -Text $text -Key 'model' -Value $Model
  $label = 'Codex official'
}

Write-Utf8WithoutBom -Path $ConfigPath -Content $text
Write-Host "已切换到：$label"
Write-Host "模型：    $Model"
Write-Host "备份文件：$backupPath"
Write-Host '请重启 Codex 或新建任务，使提供方配置生效。'
