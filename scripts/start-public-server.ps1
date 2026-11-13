param(
    [ValidateRange(1,65535)][int]$Port = 3001,
    [ValidateRange(1,65535)][int]$AiPort = 8001,
    [string]$PublicOrigin = '',
    [string]$TrustProxy = '',
    [switch]$SkipBuild,
    [switch]$NoTunnel,
    [switch]$LocalOnly,
    [switch]$AttachTunnel,
    [string]$ExpectedSha = '',
    [switch]$SkipAi
)
$ErrorActionPreference = 'Stop'
if (($NoTunnel -and ($LocalOnly -or $AttachTunnel)) -or ($LocalOnly -and $AttachTunnel)) {
    throw 'NoTunnel (development), LocalOnly (production), and AttachTunnel are mutually exclusive.'
}
$stagedProduction = $LocalOnly -or $AttachTunnel
if ($stagedProduction -and [string]::IsNullOrWhiteSpace($PublicOrigin)) {
    throw 'Production staged modes require explicit -PublicOrigin for the later HTTPS tunnel, before local smoke.'
}
if (-not $NoTunnel -and [string]::IsNullOrWhiteSpace($TrustProxy)) {
    throw 'Public mode requires -TrustProxy for a verified proxy chain. Verify Conveyor X-Forwarded-For behavior first; never use true.'
}
if (-not $NoTunnel) {
    $TrustProxy = $TrustProxy.Trim()
    $validProxy = $TrustProxy -cmatch '^[1-9]\d*$' -and $TrustProxy.Length -le 2 -and [int]$TrustProxy -le 16
    if (-not $validProxy) {
        $validProxy = $true
        foreach ($entry in $TrustProxy.Split(',')) {
            $part = $entry.Trim()
            if (@('loopback','linklocal','uniquelocal') -ccontains $part) { continue }
            $segments = $part.Split('/')
            $proxyAddress = $null
            # .NET accepts shorthand numeric addresses (e.g. 99 = 0.0.0.99);
            # reject those so numeric hop counts cannot become proxy IPs.
            $explicitIp = $segments[0].Contains(':') -or $segments[0] -cmatch '^\d{1,3}(\.\d{1,3}){3}$'
            if (-not $explicitIp -or $segments.Length -gt 2 -or -not [Net.IPAddress]::TryParse($segments[0], [ref]$proxyAddress)) {
                $validProxy = $false; break
            }
            if ($segments.Length -eq 2) {
                $maxBits = if ($proxyAddress.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) { 32 } else { 128 }
                if ($segments[1] -notmatch '^\d{1,3}$' -or [int]$segments[1] -lt 1 -or [int]$segments[1] -gt $maxBits) {
                    $validProxy = $false; break
                }
            }
        }
    }
    if (-not $validProxy) { throw 'Public mode requires a valid trusted proxy chain (1..16 or proxy IP/subnets); false/true are unsafe for this tunnel.' }
}
if ($Port -eq $AiPort) { throw 'Public and AI service ports must be different.' }
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$backendRoot = Join-Path $workspaceRoot 'backend'
$envFile = Join-Path $backendRoot $(if ($NoTunnel) { '.env' } else { '.env.production.local' })
$aiPython = Join-Path $workspaceRoot 'ai_service\.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
    if ($NoTunnel) { throw 'Missing backend/.env. Copy backend/.env.example to backend/.env and configure it first.' }
    throw 'Missing backend/.env.production.local; production startup refused without fallback.'
}
if ($stagedProduction) { . (Join-Path $PSScriptRoot 'public-server-production.ps1') }
if (-not (Test-Path -LiteralPath $aiPython)) {
    throw 'AI Python environment is missing. Install Python 3.11, then run: .\scripts\setup-ai-service.ps1 -Python (py -3.11 -c "import sys; print(sys.executable)")'
}
$runtimeRoot = Join-Path $workspaceRoot '.runtime'
$stateFile = Join-Path $runtimeRoot $(if ($NoTunnel) { 'local-server.json' } else { 'public-server.json' })
$settingsFile = Join-Path $runtimeRoot 'public-settings.json'
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
$oldState = if (Test-Path -LiteralPath $stateFile) { Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } else { $null }
if (-not $NoTunnel -and -not $stagedProduction -and -not $PublicOrigin -and (Test-Path -LiteralPath $settingsFile)) {
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
if ($NoTunnel -and $PublicOrigin) { throw 'Local mode does not use PublicOrigin. Omit it when using -NoTunnel.' }
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
function Set-LaunchEnvironment {
    $env:PORT = "$Port"
    $env:NODE_ENV = if ($NoTunnel) { 'development' } else { 'production' }
    $env:SIGNVOICE_ENV_FILE = $envFile
    $env:TRUST_PROXY = if ($NoTunnel) { 'false' } else { $TrustProxy }
    $env:SERVE_WEB = 'true'
    $env:PUBLIC_ORIGIN = $PublicOrigin; $env:LOG_LEVEL = 'info'
    # OAuth and refresh cookies must use this launch's origin, not a stale localhost/tunnel in .env.
    $env:WEB_ORIGIN = $PublicOrigin; $env:CORS_ALLOWED_ORIGINS = $PublicOrigin
    $env:OAUTH_BACKEND_ORIGIN = $PublicOrigin; $env:OAUTH_FRONTEND_ORIGIN = $PublicOrigin
    $env:GOOGLE_CALLBACK_URL = "$PublicOrigin/api/v1/auth/oauth/google/callback"
    $env:FACEBOOK_CALLBACK_URL = "$PublicOrigin/api/v1/auth/oauth/facebook/callback"
    $env:PASSWORD_RESET_ORIGIN = $PublicOrigin
    $env:AI_PUBLIC_PROXY = if ($SkipAi) { 'false' } else { 'true' }
    $env:AI_PROXY_TARGET = "http://127.0.0.1:$AiPort"
}
$serverProcess = $null; $newAiWrapper = $null; $newTunnel = $null; $newTunnelWrapper = $null
$managedAi = $null; $managedAiWrapper = $null; $managedTunnel = $null; $managedTunnelWrapper = $null
$savedEnvironment = @{}
foreach ($key in @('PORT','NODE_ENV','SIGNVOICE_ENV_FILE','SERVE_WEB','PUBLIC_ORIGIN','AI_PUBLIC_PROXY','AI_PROXY_TARGET','LOG_LEVEL',
    'WEB_ORIGIN','CORS_ALLOWED_ORIGINS','OAUTH_BACKEND_ORIGIN','OAUTH_FRONTEND_ORIGIN',
    'GOOGLE_CALLBACK_URL','FACEBOOK_CALLBACK_URL','PASSWORD_RESET_ORIGIN','TRUST_PROXY')) {
    $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key,'Process')
}
Push-Location $workspaceRoot
try {
    if (-not $stagedProduction -and $oldState.mode -in @('production-local','production-attached')) {
        throw 'Legacy launcher refuses staged production state; use AttachTunnel or stop it explicitly first.'
    }
    if ($stagedProduction) { Assert-LaunchSha }
    if ($AttachTunnel) {
        if (-not $oldState -or $oldState.mode -ne 'production-local') { throw 'No matching API from a production local-only launch.' }
        $AiPort = $oldState.aiPort; $SkipAi = [bool]$oldState.skipAi
        Set-LaunchEnvironment
        $configStamp = Production-Stamp
        Assert-AttachIdentity
        $managedAi = $oldState.managedAi; $managedAiWrapper = $oldState.managedAiWrapper
    }
    if (-not $AttachTunnel) {
    $nodeExecutable = (Get-Command node -CommandType Application | Select-Object -First 1).Source
    if (-not $nodeExecutable) { throw 'Node executable could not be resolved.' }
    $listener = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
    if ($listener) {
        if ($LocalOnly) { throw 'Local-only launch requires a free API port; stop the existing API explicitly.' }
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
        Push-Location $backendRoot
        try {
            if (-not (Test-Path -LiteralPath 'node_modules/.bin/tsc.cmd')) {
                Write-Host 'Installing backend dependencies (including TypeScript)...'
                & npm.cmd ci --include=dev
                if ($LASTEXITCODE) { throw 'Backend dependency installation failed.' }
            }
        } finally { Pop-Location }
        Write-Host 'Building Flutter web (release) with same-origin AI...'
        & flutter build web --release --dart-define=API_BASE_URL=/api/v1 --dart-define=AI_SERVICE_URL=/sign-ai --no-web-resources-cdn
        if ($LASTEXITCODE) { throw 'Flutter web build failed.' }
        Push-Location $backendRoot
        try { & npm.cmd run build; if ($LASTEXITCODE) { throw 'Backend build failed.' } } finally { Pop-Location }
    }
    if ($LocalOnly) {
        $tunnelPattern = '(?:-p|--ports)\s+' + [regex]::Escape("${Port}i") + '(?:\s|$)'
        if (Get-CimInstance Win32_Process -Filter "Name = 'conveyorcli.exe'" | Where-Object { $_.CommandLine -match $tunnelPattern }) {
            throw 'A Conveyor tunnel already targets this port; stop it before the local-only smoke.'
        }
        Set-LaunchEnvironment
        Validate-ProductionConfig
        $configStamp = Production-Stamp
    }
    if (-not $SkipAi) {
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
        # Track the process we launched: Windows CIM may omit a healthy listening socket.
        # A venv Python launcher can start the actual interpreter as a second child.
        $aiLauncher = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($newAiWrapper.Id)" |
            Where-Object { $_.Name -eq 'python.exe' -and $_.CommandLine -match 'uvicorn.*ai_service.server' } |
            Select-Object -First 1
        if (-not $aiLauncher) { throw 'AI launcher exited after startup. Check .runtime/public-ai logs.' }
        $aiWorker = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($aiLauncher.ProcessId)" |
            Where-Object { $_.Name -eq 'python.exe' -and $_.CommandLine -match 'uvicorn.*ai_service.server' } |
            Select-Object -First 1
        $managedAi = Process-Record $(if ($aiWorker) { $aiWorker.ProcessId } else { $aiLauncher.ProcessId })
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
    } else {
        Write-Host 'Starting UI/API preview without starting the AI service.'
    }
    }
    if (-not ($NoTunnel -or $LocalOnly)) {
        $conveyor = Join-Path $workspaceRoot '.tools\conveyor\conveyorcli.exe'
        if (-not (Test-Path -LiteralPath $conveyor)) { throw 'Conveyor CLI is missing.' }
        $tunnelPattern = '(?:-p|--ports)\s+' + [regex]::Escape("${Port}i") + '(?:\s|$)'
        $existingTunnel = Get-CimInstance Win32_Process -Filter "Name = 'conveyorcli.exe'" |
            Where-Object { $_.CommandLine -match $tunnelPattern } | Select-Object -First 1
        if ($existingTunnel) {
            if ($AttachTunnel) { throw 'An existing tunnel cannot be verified for attach; stop it explicitly first.' }
            if (-not $PublicOrigin) { throw 'An external Conveyor tunnel is running. Supply -PublicOrigin once so it can be reused.' }
            if (Record-Alive $oldState.managedTunnel) {
                $managedTunnel = $oldState.managedTunnel; $managedTunnelWrapper = $oldState.managedTunnelWrapper
            }
            Write-Host 'Reusing existing Conveyor tunnel.'
        } else {
            Write-Host 'Starting Conveyor tunnel...'
            & $aiPython -c "import importlib.util; raise SystemExit(0 if importlib.util.find_spec('winpty') else 1)"
            if ($LASTEXITCODE) {
                if ($AttachTunnel) { throw 'winpty is missing; provision dependencies separately before production attach. No pip install was run.' }
                Write-Host 'Installing Windows PTY helper for Conveyor...'
                & $aiPython -m pip install -r (Join-Path $PSScriptRoot 'requirements-public.txt') --disable-pip-version-check
                if ($LASTEXITCODE) { throw 'Could not install Conveyor PTY helper.' }
            }
            $tunnelLog = Join-Path $runtimeRoot 'conveyor.log'
            $tunnelState = Join-Path $runtimeRoot 'conveyor-state.json'
            $tunnelSession = [guid]::NewGuid().ToString('N')
            @{ phase='starting'; session_id=$tunnelSession } | ConvertTo-Json | Set-Content -LiteralPath $tunnelState -Encoding UTF8
            $tunnelScript = Join-Path $PSScriptRoot 'conveyor-tunnel.py'
            $newTunnelWrapper = Start-Process -FilePath $aiPython -WindowStyle Hidden -PassThru -WorkingDirectory $workspaceRoot `
                -ArgumentList @("`"$tunnelScript`"",'--executable',"`"$conveyor`"",'--port',"$Port",'--state',"`"$tunnelState`"",'--log',"`"$tunnelLog`"",'--session-id',$tunnelSession) `
                -RedirectStandardOutput (Join-Path $runtimeRoot 'conveyor-wrapper.log') `
                -RedirectStandardError (Join-Path $runtimeRoot 'conveyor.error.log')
            $tunnelDeadline = (Get-Date).AddSeconds(60); $issuedOrigin = $null
            do {
                $newTunnelWrapper.Refresh()
                if ($newTunnelWrapper.HasExited) { throw 'Conveyor exited. Check .runtime/conveyor.log and conveyor.error.log.' }
                $status = Get-Content -LiteralPath $tunnelState -Raw | ConvertFrom-Json
                if ($status.session_id -eq $tunnelSession -and $status.phase -in @('error','exited','expired')) { throw 'Conveyor stopped or its session expired. Check .runtime/conveyor.log; use config -s once if sign-in is required.' }
                if ($status.session_id -eq $tunnelSession -and $status.phase -eq 'ready') {
                    $issuedOrigin = $status.origin
                    $newTunnel = Get-Process -Id $status.process_id
                    break
                }
                Start-Sleep -Milliseconds 700
            } while ((Get-Date) -lt $tunnelDeadline)
            if (-not $issuedOrigin) { throw 'No Conveyor URL received. Check .runtime/conveyor logs and Conveyor sign-in.' }
            if ($AttachTunnel -and $issuedOrigin -cne $PublicOrigin) {
                throw 'Issued tunnel origin differs from the explicit production origin; tunnel stopped. Restart local-only with the confirmed origin and repeat smoke.'
            }
            $PublicOrigin = $issuedOrigin
            $managedTunnel = Process-Record $newTunnel.Id
            $managedTunnelWrapper = Process-Record $newTunnelWrapper.Id
        }
    }
    if ($AttachTunnel) {
        # Check again after tunnel startup; never replace/restart the already-smoked API.
        if ((Production-Stamp) -cne $configStamp) { throw 'Production configuration changed during attach.' }
        Assert-AttachIdentity
        $oldState | Add-Member -NotePropertyName managedTunnel -NotePropertyValue $managedTunnel -Force
        $oldState | Add-Member -NotePropertyName managedTunnelWrapper -NotePropertyValue $managedTunnelWrapper -Force
        $oldState | Add-Member -NotePropertyName mode -NotePropertyValue 'production-attached' -Force
        $oldState | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile -Encoding UTF8
        Write-Host "Tunnel attached to the existing production API: $PublicOrigin"
        return
    }
    if (-not $PublicOrigin) { $PublicOrigin = "http://localhost:$Port" }
    Set-LaunchEnvironment
    Push-Location $backendRoot
    try {
        if ($LocalOnly) {
            if ((Production-Stamp) -cne $configStamp) { throw 'Production configuration changed during local-only startup.' }
        } else {
            & $nodeExecutable -e "require('./dist/config/env.js').validateEnv()"
            if ($LASTEXITCODE) { throw 'Backend configuration validation failed; server was not started.' }
        }
    } finally { Pop-Location }
    $serverArgument = if ($LocalOnly) { '"' + (Join-Path $backendRoot 'dist/server.js') + '"' } else { 'dist/server.js' }
    $serverProcess = Start-Process -FilePath $nodeExecutable -ArgumentList $serverArgument `
        -WorkingDirectory $backendRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $runtimeRoot 'public-server.log') `
        -RedirectStandardError (Join-Path $runtimeRoot 'public-server.error.log')
    # Allow a cold start on a busy machine; readiness still returns immediately when available.
    Write-Host 'Waiting up to 120 seconds for backend/database readiness...'
    $health = Wait-Health "http://127.0.0.1:$Port/health/ready" 120 $serverProcess.Id
    if (-not $health.success) { throw 'Backend/database is not ready.' }
    if (-not $SkipAi) {
        $proxyHealth = Wait-Health "http://127.0.0.1:$Port/sign-ai/health" 10 $serverProcess.Id
        if (-not $proxyHealth.ready) { throw 'Public AI proxy is not ready.' }
    }
    $nodeRecord = Process-Record $serverProcess.Id
    $newState = @{ processId=$serverProcess.Id; startedUtc=$nodeRecord.startedUtc; port=$Port; publicOrigin=$PublicOrigin;
        aiPort=$AiPort; managedAi=$managedAi; managedAiWrapper=$managedAiWrapper; managedTunnel=$managedTunnel; managedTunnelWrapper=$managedTunnelWrapper }
    if ($LocalOnly) {
        $newState.mode = 'production-local'; $newState.sha = $ExpectedSha; $newState.envFile = $envFile
        $newState.configStamp = $configStamp; $newState.trustProxy = $TrustProxy; $newState.skipAi = [bool]$SkipAi
    }
    $newState | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile -Encoding UTF8
    if (-not $LocalOnly -and $PublicOrigin.StartsWith('https://')) {
        @{publicOrigin=$PublicOrigin} | ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding UTF8
    }
    $displayOrigin = if ($LocalOnly) { "http://127.0.0.1:$Port" } else { $PublicOrigin }
    if ($LocalOnly) { Write-Host "SignVoice production UI + API (loopback only): $displayOrigin" }
    else { Write-Host "SignVoice UI + API: $displayOrigin" }
    if (-not $SkipAi) { Write-Host "AI health: $displayOrigin/sign-ai/health" }
    if ($NoTunnel) { Write-Host 'Stop with: .\scripts\stop-public-server.ps1 -Local' }
    else { Write-Host 'Stop with: .\scripts\stop-public-server.ps1' }
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
