# Isolated local test only; does not pin a model or rebuild/deploy public.
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testRoot = Join-Path $projectRoot '.runtime\tcn180-camera-test'
$bundle = Join-Path $testRoot 'bundle'
$python = Join-Path $projectRoot 'ai_service\.venv\Scripts\python.exe'
$flutter = Join-Path (Split-Path (Split-Path $projectRoot -Parent) -Parent) 'flutter\bin\flutter.bat'
$checkpoint = Join-Path $bundle 'word_temporal.keras'
if (-not (Test-Path -LiteralPath $checkpoint)) { throw 'The isolated TCN180 test bundle has not been prepared.' }
if ((Get-FileHash -LiteralPath $checkpoint -Algorithm SHA256).Hash.ToLowerInvariant() -ne '98f721276b117832a3d3dd417a9a68ee79e5ab9c320691f4eaed18e3aad2c669') {
  throw 'Test checkpoint differs from the notebook TCN180 reference.'
}
if (-not (Test-Path -LiteralPath $flutter)) { throw 'Flutter SDK was not found.' }
Push-Location $projectRoot
try {
  $selectionText = & $python -m ai_service.model_selection inspect --model-dir $bundle --expected-words 180
  if ($LASTEXITCODE) { throw 'Test bundle validation failed.' }
  $selection = $selectionText | ConvertFrom-Json
} finally { Pop-Location }

$serviceListener = Get-NetTCPConnection -State Listen -LocalPort 8002 -ErrorAction SilentlyContinue
if ($serviceListener) {
  $health = Invoke-RestMethod 'http://127.0.0.1:8002/health' -TimeoutSec 5
  if ($health.model_manifest_sha256 -ne $selection.manifest_sha256 -or $health.word_engine -ne 'tcn') {
    throw 'Port 8002 belongs to another service. No process was stopped.'
  }
} else {
  $previousOrigins = $env:AI_ALLOWED_ORIGINS
  try {
    $env:AI_ALLOWED_ORIGINS = 'http://127.0.0.1:8081,http://localhost:8081'
    $service = Start-Process -FilePath powershell.exe -WindowStyle Hidden -PassThru -WorkingDirectory $projectRoot -ArgumentList @(
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
      ('"' + (Join-Path $PSScriptRoot 'start-ai-service.ps1') + '"'),
      '-Port', '8002', '-ModelDirectory', ('"' + $bundle + '"')
    ) -RedirectStandardOutput (Join-Path $testRoot 'ai.stdout.log') -RedirectStandardError (Join-Path $testRoot 'ai.stderr.log')
    $service.Id | Set-Content -LiteralPath (Join-Path $testRoot 'ai-launcher.pid')
  } finally { $env:AI_ALLOWED_ORIGINS = $previousOrigins }
}

if (-not (Get-NetTCPConnection -State Listen -LocalPort 8081 -ErrorAction SilentlyContinue)) {
  $webCommand = "& '" + $flutter.Replace("'", "''") + "' run -t test_browser/tcn180_camera_main.dart -d web-server --web-hostname 127.0.0.1 --web-port 8081 --dart-define=AI_SERVICE_URL=http://127.0.0.1:8002 --dart-define=CAMERA_DIAGNOSTICS=true --dart-define=CAMERA_PHASE_PACING=true --dart-define=CAMERA_VERIFY_SMALL_TRACKS=true"
  $web = Start-Process -FilePath powershell.exe -WindowStyle Hidden -PassThru -WorkingDirectory $projectRoot -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $webCommand
  ) -RedirectStandardOutput (Join-Path $testRoot 'web.stdout.log') -RedirectStandardError (Join-Path $testRoot 'web.stderr.log')
  $web.Id | Set-Content -LiteralPath (Join-Path $testRoot 'web-launcher.pid')
}
Write-Host 'TCN180 test is starting: http://127.0.0.1:8081/#S10'
Write-Host ('Logs: ' + $testRoot)
