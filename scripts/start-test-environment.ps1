param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$backendRoot = Join-Path $workspaceRoot 'backend'
if (-not (Test-Path (Join-Path $backendRoot '.env.test'))) { throw 'Missing backend/.env.test.' }
$runtimeRoot = Join-Path $workspaceRoot '.runtime\testing'
New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
if (Get-NetTCPConnection -State Listen -LocalPort 3003 -ErrorAction SilentlyContinue) { throw 'Port 3003 occupied; existing process left running.' }
if (-not $SkipBuild) {
    Push-Location $workspaceRoot
    try {
        & flutter.bat build web --release --no-wasm-dry-run --no-web-resources-cdn --dart-define=API_BASE_URL=/api/v1 --dart-define=AI_SERVICE_URL=/sign-ai
        if ($LASTEXITCODE) { throw 'Web build failed.' }
    } finally { Pop-Location }
    Push-Location $backendRoot
    try { & npm.cmd run build; if ($LASTEXITCODE) { throw 'Backend build failed.' } }
    finally { Pop-Location }
}
$aiHealth = $null
try { $aiHealth = Invoke-RestMethod 'http://127.0.0.1:8002/health' -TimeoutSec 3 } catch {}
if (-not $aiHealth.ready) {
    if (Get-NetTCPConnection -State Listen -LocalPort 8002 -ErrorAction SilentlyContinue) { throw 'AI port 8002 occupied.' }
    $aiScript = Join-Path $PSScriptRoot 'start-ai-service.ps1'
    $aiProcess = Start-Process powershell.exe -WindowStyle Hidden -PassThru -WorkingDirectory $workspaceRoot `
        -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$aiScript`"",'-Port','8002') `
        -RedirectStandardOutput (Join-Path $runtimeRoot 'ai.log') -RedirectStandardError (Join-Path $runtimeRoot 'ai.error.log')
}
$launcher = Join-Path $backendRoot 'scripts\start-test-server.cjs'
$server = Start-Process (Get-Command node).Source -WindowStyle Hidden -PassThru -WorkingDirectory $backendRoot `
    -ArgumentList @("`"$launcher`"") `
    -RedirectStandardOutput (Join-Path $runtimeRoot 'backend.log') -RedirectStandardError (Join-Path $runtimeRoot 'backend.error.log')
@{ backendPid=$server.Id; backendStartedUtc=$server.StartTime.ToUniversalTime().ToString('o'); port=3003; aiPort=8002; database='signvoice_test' } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runtimeRoot 'state.json')
Write-Host 'Test backend launched: port 3003; AI port 8002; logs .runtime/testing'
foreach ($endpoint in @('http://127.0.0.1:3003/health/ready','http://127.0.0.1:8002/health')) {
    $deadline = (Get-Date).AddSeconds(180)
    $ready = $false
    do {
        try {
            $health = Invoke-RestMethod $endpoint -TimeoutSec 3
            if ($endpoint.Contains(':3003/')) {
                $ready = $health.success -and $health.data.database.connected -and $health.data.database.name -eq 'signvoice_test'
            } else { $ready = $health.ready }
        } catch {}
        if (-not $ready) { Start-Sleep -Milliseconds 750 }
    } while (-not $ready -and (Get-Date) -lt $deadline)
    if (-not $ready) { throw "Testing service not ready: $endpoint. See .runtime/testing logs." }
    Write-Host "Ready: $endpoint"
}
