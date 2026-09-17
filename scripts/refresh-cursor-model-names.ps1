param(
  [string]$CatalogPath = (Join-Path $env:USERPROFILE '.codex\cursor-models.json')
)

$ErrorActionPreference = 'Stop'

function Write-Utf8WithoutBom {
  param([string]$Path, [string]$Content)
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
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

if (-not (Test-Path -LiteralPath $CatalogPath)) {
  throw "找不到 Cursor 模型目录：$CatalogPath"
}

$cache = Get-Content -Raw -Encoding UTF8 -LiteralPath $CatalogPath | ConvertFrom-Json
if ($null -eq $cache.models -or @($cache.models).Count -eq 0) {
  throw "模型目录为空：$CatalogPath"
}

$changed = 0
foreach ($model in @($cache.models)) {
  $before = [string]$model.display_name
  $seed = $before -replace '^(?i)OpenAI\s+', ''
  $after = Format-CursorDisplayName -Slug ([string]$model.slug) -RawName $seed
  if ($after -ne $before) {
    $model.display_name = $after
    $changed++
    Write-Host ("{0}: {1} -> {2}" -f $model.slug, $before, $after)
  }
}

$json = $cache | ConvertTo-Json -Depth 100
$temporaryCatalogPath = "$CatalogPath.tmp"
try {
  Write-Utf8WithoutBom -Path $temporaryCatalogPath -Content $json
  Move-Item -LiteralPath $temporaryCatalogPath -Destination $CatalogPath -Force
} finally {
  if (Test-Path -LiteralPath $temporaryCatalogPath) {
    Remove-Item -LiteralPath $temporaryCatalogPath -Force
  }
}

Write-Host "已更新 $changed 个展示名：$CatalogPath"
Write-Host '请重启 Codex 或新建任务，使模型列表生效。'
