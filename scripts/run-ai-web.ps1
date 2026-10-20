param(
  [string]$ApiBaseUrl = 'http://localhost:3000/api/v1',
  [string]$AiServiceUrl = 'http://localhost:8001',
  [int]$WebPort = 8080,
  [switch]$DebugMode
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $projectRoot
try {
  $runArgs = @('run','-d','chrome','--web-port',"$WebPort", "--dart-define=API_BASE_URL=$ApiBaseUrl", "--dart-define=AI_SERVICE_URL=$AiServiceUrl")
  if (-not $DebugMode) { $runArgs += '--release' }
  & flutter @runArgs
  if ($LASTEXITCODE) { throw 'Không chạy được Flutter. Kiểm tra backend và cổng web đang sử dụng.' }
} finally { Pop-Location }
