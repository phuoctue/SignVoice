param(
    [ValidateRange(1,65535)][int]$Port = 3001,
    [ValidateRange(1,65535)][int]$AiPort = 8001,
    [string]$PublicOrigin = '',
    [switch]$SkipBuild,
    [switch]$NoTunnel
)
$ErrorActionPreference = 'Stop'
if ($Port -eq $AiPort) { throw 'Public and AI service ports must be different.' }
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$backendRoot = Join-Path $workspaceRoot 'backend'
$runtimeRoot = Join-Path $workspaceRoot '.runtime'
$stateFile = Join-Path $runtimeRoot 'public-server.json'
$settingsFile = Join-Path $runtimeRoot 'public-settings.json'
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
$oldState = if (Test-Path -LiteralPath $stateFile) { Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } else { $null }
if (-not $PublicOrigin -and (Test-Path -LiteralPath $settingsFile)) {
    $PublicOrigin = (Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json).publicOrigin
}
if ($PublicOrigin) {
    $publicUri = [Uri]$PublicOrigin
    if (-not $publicUri.IsAbsoluteUri -or $publicUri.Scheme -ne 'https' -or
        $publicUri.AbsolutePath -ne '/' -or $publicUri.Query -or $publicUri.Fragment -or $publicUri.UserInfo) {
        throw 'PublicOrigin must be an HTTPS origin without a path.'
    }
    $PublicOrigin = $publicUri.GetLeftPart([UriPartial]::Authority)
}
function Process-Record([int]$ProcessId) {
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($process) { return @{ processId=$ProcessId; startedUtc=$process.StartTime.ToUniversalTime().ToString('o') } }
    return $null
}
function Record-Alive($Record) {
    if (-not $Record) { return $false }
    $process = Get-Process -Id $Record.processId -ErrorAction SilentlyContinue
    return $process -and ($process.StartTime.ToUniversalTime().Ticks -eq ([datetime]$Record.startedUtc).ToUniversalTime().Ticks)
}
function Wait-Health([string]$Uri, [int]$Seconds, [int]$WatchProcessId=0) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        if ($WatchProcessId -and -not (Get-Process -Id $WatchProcessId -ErrorAction SilentlyContinue)) {
            throw "Process $WatchProcessId exited. Check logs in .runtime."
        }
        try { return Invoke-RestMethod -Uri $Uri -TimeoutSec 3 } catch { Start-Sleep -Milliseconds 700 }
    } while ((Get-Date) -lt $deadline)
    throw "Not ready: $Uri. Check .runtime logs."
}
$serverProcess = $null; $newAiWrapper = $null; $newTunnel = $null; $newTunnelWrapper = $null
$managedAi = $null; $managedAiWrapper = $null; $managedTunnel = $null; $managedTunnelWrapper = $null
$savedEnvironment = @{}
foreach ($key in @('PORT','NODE_ENV','SERVE_WEB','PUBLIC_ORIGIN','AI_PUBLIC_PROXY','AI_PROXY_TARGET','LOG_LEVEL')) {
    $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key,'Process')
}
Push-Location $workspaceRoot
try {
    $listener = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
    if ($listener) {
        $current = if ($oldState) { Get-CimInstance Win32_Process -Filter "ProcessId = $($oldState.processId)" -ErrorAction SilentlyContinue } else { $null }
        if (-not $current -or $current.Name -ne 'node.exe' -or $current.CommandLine -notmatch 'dist/server\.js' -or
            -not ($listener | Where-Object OwningProcess -eq $oldState.processId)) {
            throw "Port $Port is used by another process; it was not stopped."
        }
        Write-Host 'Restarting managed public server; existing AI/tunnel will be reused.'
        Stop-Process -Id $oldState.processId
        Start-Sleep -Milliseconds 500
    }
    if (-not $SkipBuild) {
        Write-Host 'Building Flutter web (release) with same-origin AI...'
        & flutter build web --release --dart-define=API_BASE_URL=/api/v1 --dart-define=AI_SERVICE_URL=/sign-ai --no-web-resources-cdn
        if ($LASTEXITCODE) { throw 'Flutter web build failed.' }
        Push-Location $backendRoot
        try { & npm.cmd run build; if ($LASTEXITCODE) { throw 'Backend build failed.' } } finally { Pop-Location }
    }
    $aiPython = Join-Path $workspaceRoot 'ai_service\.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $aiPython)) { throw 'Run scripts/setup-ai-service.ps1 first.' }
    $selectedOutput = & $aiPython -m ai_service.model_selection resolve
    if ($LASTEXITCODE) { throw 'Selected AI model is not valid.' }
    $selected = $selectedOutput | ConvertFrom-Json
    $aiHealth = $null
    try { $aiHealth = Invoke-RestMethod -Uri "http://127.0.0.1:$AiPort/health" -TimeoutSec 5 } catch { }
    if (-not $aiHealth) {
        if (Get-NetTCPConnection -State Listen -LocalPort $AiPort -ErrorAction SilentlyContinue) {
            throw "Port $AiPort is occupied but AI is not ready; it was not stopped."
        }
        Write-Host 'Starting separate AI service; waiting for model initialization...'
        $aiScript = Join-Path $PSScriptRoot 'start-ai-service.ps1'
        $newAiWrapper = Start-Process powershell.exe -WindowStyle Hidden -PassThru -WorkingDirectory $workspaceRoot `
            -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$aiScript`"",'-Port',"$AiPort") `
            -RedirectStandardOutput (Join-Path $runtimeRoot 'public-ai.log') `
            -RedirectStandardError (Join-Path $runtimeRoot 'public-ai.error.log')
        $aiHealth = Wait-Health "http://127.0.0.1:$AiPort/health" 150 $newAiWrapper.Id
        $aiListener = Get-NetTCPConnection -State Listen -LocalPort $AiPort | Select-Object -First 1
        $managedAi = Process-Record $aiListener.OwningProcess
        $managedAiWrapper = Process-Record $newAiWrapper.Id
    } elseif (Record-Alive $oldState.managedAi) {
        $managedAi = $oldState.managedAi; $managedAiWrapper = $oldState.managedAiWrapper
    }
    if (-not $aiHealth.ready -or $aiHealth.model_manifest_sha256 -ne $selected.manifest_sha256 -or
        $aiHealth.runtime_sha256 -ne (Get-FileHash -LiteralPath 'ai_service/model_runtime.py' -Algorithm SHA256).Hash.ToLowerInvariant() -or
        $aiHealth.camera_adapter_sha256 -ne (Get-FileHash -LiteralPath 'ai_service/engine.py' -Algorithm SHA256).Hash.ToLowerInvariant()) {
        throw 'AI is running a different model/code. Stop that AI service explicitly, then run this command again.'
    }
    Write-Host "AI ready: $($aiHealth.word_classes) words; keeping the selected model."
    if (-not $NoTunnel) {
        $conveyor = Join-Path $workspaceRoot '.tools\conveyor\conveyorcli.exe'
        if (-not (Test-Path -LiteralPath $conveyor)) { throw 'Conveyor CLI is missing.' }
        $tunnelPattern = '(?:-p|--ports)\s+' + [regex]::Escape("${Port}i") + '(?:\s|$)'
        $existingTunnel = Get-CimInstance Win32_Process -Filter "Name = 'conveyorcli.exe'" |
            Where-Object { $_.CommandLine -match $tunnelPattern } | Select-Object -First 1
        if ($existingTunnel) {
            if (-not $PublicOrigin) { throw 'An external Conveyor tunnel is running. Supply -PublicOrigin once so it can be reused.' }
            if (Record-Alive $oldState.managedTunnel) {
                $managedTunnel = $oldState.managedTunnel; $managedTunnelWrapper = $oldState.managedTunnelWrapper
            }
            Write-Host 'Reusing existing Conveyor tunnel.'
        } else {
            Write-Host 'Starting Conveyor tunnel...'
            & $aiPython -c 'import winpty' 2>$null
            if ($LASTEXITCODE) {
                Write-Host 'Installing Windows PTY helper for Conveyor...'
                & $aiPython -m pip install -r (Join-Path $PSScriptRoot 'requirements-public.txt') --disable-pip-version-check
                if ($LASTEXITCODE) { throw 'Could not install Conveyor PTY helper.' }
            }
            $tunnelLog = Join-Path $runtimeRoot 'conveyor.log'
            $tunnelState = Join-Path $runtimeRoot 'conveyor-state.json'
            @{ phase='starting' } | ConvertTo-Json | Set-Content -LiteralPath $tunnelState -Encoding UTF8
            $tunnelScript = Join-Path $PSScriptRoot 'conveyor-tunnel.py'
            $newTunnelWrapper = Start-Process -FilePath $aiPython -WindowStyle Hidden -PassThru -WorkingDirectory $workspaceRoot `
                -ArgumentList @("`"$tunnelScript`"",'--executable',"`"$conveyor`"",'--port',"$Port",'--state',"`"$tunnelState`"",'--log',"`"$tunnelLog`"") `
                -RedirectStandardOutput (Join-Path $runtimeRoot 'conveyor-wrapper.log') `
                -RedirectStandardError (Join-Path $runtimeRoot 'conveyor.error.log')
            $tunnelDeadline = (Get-Date).AddSeconds(60); $issuedOrigin = $null
            do {
                $newTunnelWrapper.Refresh()
                if ($newTunnelWrapper.HasExited) { throw 'Conveyor exited. Check .runtime/conveyor.log and conveyor.error.log.' }
                $status = Get-Content -LiteralPath $tunnelState -Raw | ConvertFrom-Json
                if ($status.phase -in @('error','exited')) { throw 'Conveyor stopped. Check .runtime/conveyor.log; use config -s once if sign-in is required.' }
                if ($status.phase -eq 'ready') {
                    $issuedOrigin = $status.origin
                    $newTunnel = Get-Process -Id $status.process_id
                    break
                }
                Start-Sleep -Milliseconds 700
            } while ((Get-Date) -lt $tunnelDeadline)
            if (-not $issuedOrigin) { throw 'No Conveyor URL received. Check .runtime/conveyor logs and Conveyor sign-in.' }
            $PublicOrigin = $issuedOrigin
            $managedTunnel = Process-Record $newTunnel.Id
            $managedTunnelWrapper = Process-Record $newTunnelWrapper.Id
        }
    }
    if (-not $PublicOrigin) { $PublicOrigin = "http://localhost:$Port" }
    $env:PORT = "$Port"; $env:NODE_ENV = 'production'; $env:SERVE_WEB = 'true'
    $env:PUBLIC_ORIGIN = $PublicOrigin; $env:LOG_LEVEL = 'info'
    $env:AI_PUBLIC_PROXY = 'true'; $env:AI_PROXY_TARGET = "http://127.0.0.1:$AiPort"
    $serverProcess = Start-Process -FilePath (Get-Command node).Source -ArgumentList 'dist/server.js' `
        -WorkingDirectory $backendRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $runtimeRoot 'public-server.log') `
        -RedirectStandardError (Join-Path $runtimeRoot 'public-server.error.log')
    $health = Wait-Health "http://127.0.0.1:$Port/health/ready" 45 $serverProcess.Id
    if (-not $health.success) { throw 'Backend/database is not ready.' }
    $proxyHealth = Wait-Health "http://127.0.0.1:$Port/sign-ai/health" 10 $serverProcess.Id
    if (-not $proxyHealth.ready) { throw 'Public AI proxy is not ready.' }
    $nodeRecord = Process-Record $serverProcess.Id
    @{ processId=$serverProcess.Id; startedUtc=$nodeRecord.startedUtc; port=$Port; publicOrigin=$PublicOrigin;
       aiPort=$AiPort; managedAi=$managedAi; managedAiWrapper=$managedAiWrapper; managedTunnel=$managedTunnel; managedTunnelWrapper=$managedTunnelWrapper } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile -Encoding UTF8
    if ($PublicOrigin.StartsWith('https://')) {
        @{publicOrigin=$PublicOrigin} | ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding UTF8
    }
    Write-Host "SignVoice UI + API + AI: $PublicOrigin"
    Write-Host "AI health: $PublicOrigin/sign-ai/health"
    Write-Host 'Stop with: .\scripts\stop-public-server.ps1'
} catch {
    if ($serverProcess -and -not $serverProcess.HasExited) { Stop-Process -Id $serverProcess.Id -ErrorAction SilentlyContinue }
    if ($newTunnel -and -not $newTunnel.HasExited) { Stop-Process -Id $newTunnel.Id -ErrorAction SilentlyContinue }
    if ($newTunnelWrapper) { Stop-Process -Id $newTunnelWrapper.Id -ErrorAction SilentlyContinue }
    if ($newAiWrapper) {
        Get-CimInstance Win32_Process -Filter "ParentProcessId = $($newAiWrapper.Id)" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'python.exe' -and $_.CommandLine -match 'uvicorn.*ai_service.server' } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
        Stop-Process -Id $newAiWrapper.Id -ErrorAction SilentlyContinue
    }
    throw
} finally {
    foreach ($key in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key,$savedEnvironment[$key],'Process') }
    Pop-Location
}
