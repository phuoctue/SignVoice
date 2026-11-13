$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('signvoice-launcher-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $scratch 'scripts') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $scratch 'backend') -Force | Out-Null
$passed = 0
try {
    foreach ($name in @('start-public-server.ps1','public-server-production.ps1','public-server-config.cjs')) {
        $source = Join-Path $PSScriptRoot $name
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination (Join-Path $scratch "scripts/$name") }
    }
    $launcher = Join-Path $scratch 'scripts/start-public-server.ps1'
    $sha = 'a' * 40
    function Check([string]$Name, [hashtable]$Options, [string]$Failure = '') {
        & {
            param($Name, $Options, $Failure)
            $global:launcherTestEvents = @(); $global:launcherTestStops = @(); $global:launcherTestOptions = $Options
            $runtime = Join-Path $scratch '.runtime'
            New-Item -ItemType Directory -Path $runtime -Force | Out-Null
            $stateFile = Join-Path $runtime 'public-server.json'
            Microsoft.PowerShell.Management\Remove-Item -LiteralPath $stateFile -ErrorAction SilentlyContinue
            $settingsFile = Join-Path $runtime 'public-settings.json'
            Microsoft.PowerShell.Management\Remove-Item -LiteralPath $settingsFile -ErrorAction SilentlyContinue
            $started = [datetime]'2026-11-13T01:00:00Z'
            $state = @{processId=4242; startedUtc=$started.ToString('o'); mode='production-local'; port=3001;
                aiPort=8001; skipAi=$true; publicOrigin='https://signvoice.example'; trustProxy='loopback';
                sha=$sha; envFile=(Join-Path $scratch 'backend/.env.production.local'); configStamp='test-stamp'}
            if ($Options.StateChange) { $state[$Options.StateChange] = $Options.StateValue }
            if ($Options.Legacy) { $state.mode = $Options.Legacy }
            if ($Options.Attach -or $Options.Legacy) { $state | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8 }
            function Test-Path {
                param($LiteralPath, $Path, $PathType)
                $target = if ($LiteralPath) { $LiteralPath } else { $Path }
                if ($target -like '*.env*') { return -not $global:launcherTestOptions.MissingEnv }
                if ($target -like '*python.exe' -or $target -like '*conveyorcli.exe') { return $true }
                Microsoft.PowerShell.Management\Test-Path -LiteralPath $target
            }
            function Get-Content {
                param($LiteralPath, [switch]$Raw)
                if ($LiteralPath -like '*.env*') { throw 'ENV READ FORBIDDEN' }
                Microsoft.PowerShell.Management\Get-Content -LiteralPath $LiteralPath -Raw:$Raw
            }
            function git {
                $global:LASTEXITCODE = 0
                if ($args -contains 'rev-parse') { if ($global:launcherTestOptions.WrongHead) { return ('b' * 40) }; return $sha }
                if ($global:launcherTestOptions.DirtyCheckout) { return ' M dummy-source' }
                if ($global:launcherTestOptions.UntrackedSource) { return '?? dummy-source' }
            }
            function Mock-Node {
                $global:launcherTestEvents += 'validate'
                if ($global:launcherTestOptions.Attach) { throw 'ATTACH INVOKED NODE' }
                if ($env:NODE_ENV -ne 'production' -or $env:SIGNVOICE_ENV_FILE -ne (Join-Path $scratch 'backend/.env.production.local')) {
                    throw 'WRONG PRODUCTION SELECTION'
                }
                $global:LASTEXITCODE = if ($global:launcherTestOptions.InvalidConfig) { 1 } else { 0 }
            }
            function node {
                if ($global:launcherTestOptions.SelectedNode) { throw 'SESSION NODE USED INSTEAD OF SELECTED APPLICATION' }
                Mock-Node
            }
            function mock-selected-node { Mock-Node }
            function Get-Command {
                param($Name, $CommandType)
                if ($global:launcherTestOptions.Attach) { throw 'ATTACH RESOLVED NODE' }
                [pscustomobject]@{Source=$(if ($global:launcherTestOptions.SelectedNode) { 'mock-selected-node' } else { 'node' })}
                if ($global:launcherTestOptions.TwoNodes) { [pscustomobject]@{Source='node-secondary'} }
            }
            # Stub hashes and code inventory, never read a real or virtual env file.
            function Get-FileHash { param($LiteralPath, $Algorithm) return @{Hash='dummy-file-hash'} }
            function Get-ChildItem { param($LiteralPath, $Filter, [switch]$Recurse, [switch]$File) return }
            function Get-CimInstance {
                param($ClassName, $Filter, $ErrorAction)
                if ($Filter -like '*conveyorcli*') {
                    if ($global:launcherTestOptions.ExistingTunnel) { [pscustomobject]@{ProcessId=5656; CommandLine='conveyorcli.exe -p 3001i'} }
                    return
                }
                if ((-not $global:launcherTestOptions.Attach -and -not $global:launcherTestOptions.Legacy) -or $global:launcherTestOptions.NoApi) { return }
                $api = [pscustomobject]@{ProcessId=4242; Name='node.exe'; CommandLine=('node "' + (Join-Path $scratch 'backend/dist/server.js') + '"')}
                $api
                if ($global:launcherTestOptions.TwoApis) { [pscustomobject]@{ProcessId=4243; Name='node.exe'; CommandLine='node dist/server.js'} }
            }
            function Get-Process {
                param($Id, $ErrorAction)
                [pscustomobject]@{Id=$Id; StartTime=$(if ($global:launcherTestOptions.WrongStart) { $started.AddSeconds(1) } else { $started })}
            }
            function Get-NetTCPConnection {
                param($State, $LocalPort, $ErrorAction)
                if (($global:launcherTestOptions.Attach -or $global:launcherTestOptions.Legacy) -and -not $global:launcherTestOptions.NoApi) {
                    [pscustomobject]@{OwningProcess=4242; LocalAddress=$(if ($global:launcherTestOptions.PublicBind) { '0.0.0.0' } else { '127.0.0.1' })}
                }
            }
            function Start-Process {
                param($FilePath, $ArgumentList, $WorkingDirectory, $WindowStyle, [switch]$PassThru, $RedirectStandardOutput, $RedirectStandardError)
                if ($FilePath -is [array]) { throw 'NODE PATH WAS AN ARRAY' }
                if ($global:launcherTestOptions.TwoNodes -and $FilePath -ne 'node') { throw 'WRONG NODE PATH SELECTED' }
                if ($global:launcherTestOptions.SelectedNode -and $FilePath -ne 'mock-selected-node') { throw 'PREFLIGHT AND SERVER NODE DIFFER' }
                if ($FilePath -like '*node*') {
                    $global:launcherTestEvents += 'api'
                    if ($global:launcherTestOptions.Attach) { throw 'ATTACH SPAWNED NODE' }
                    return [pscustomobject]@{Id=4242; HasExited=$false}
                }
                $global:launcherTestEvents += 'tunnel'
                if ($global:launcherTestOptions.Sentinel) { throw 'TUNNEL SENTINEL' }
                $stateIndex = [array]::IndexOf($ArgumentList, '--state') + 1
                $sessionIndex = [array]::IndexOf($ArgumentList, '--session-id') + 1
                $origin = if ($global:launcherTestOptions.WrongOrigin) { 'https://unexpected.example' } else { 'https://signvoice.example' }
                @{session_id=$ArgumentList[$sessionIndex]; phase='ready'; origin=$origin; process_id=5656} |
                    ConvertTo-Json | Set-Content -LiteralPath $ArgumentList[$stateIndex].Trim('"') -Encoding UTF8
                $wrapper = [pscustomobject]@{Id=6060; HasExited=$false}
                $wrapper | Add-Member -MemberType ScriptMethod -Name Refresh -Value { }
                return $wrapper
            }
            function Stop-Process { param($Id, $ErrorAction) $global:launcherTestEvents += 'stop'; $global:launcherTestStops += $Id }
            function Invoke-RestMethod { param($Uri, $TimeoutSec) return @{success=$true; ready=$true} }
            function Mock-Python {
                if ($args -contains 'pip') { throw 'PIP INSTALL FORBIDDEN' }
                $global:LASTEXITCODE = if ($global:launcherTestOptions.MissingWinpty) { 1 } else { 0 }
            }
            Set-Alias -Name (Join-Path $scratch 'ai_service\.venv\Scripts\python.exe') -Value Mock-Python
            if ($Options.Attach) {
                $backendRoot = Join-Path $scratch 'backend'; $envFile = Join-Path $backendRoot '.env.production.local'
                . (Join-Path $scratch 'scripts/public-server-production.ps1')
                $launchEnvironment = @{PORT='3001'; NODE_ENV='production'; SIGNVOICE_ENV_FILE=$envFile; TRUST_PROXY='loopback';
                    SERVE_WEB='true'; PUBLIC_ORIGIN='https://signvoice.example'; LOG_LEVEL='info';
                    WEB_ORIGIN='https://signvoice.example'; CORS_ALLOWED_ORIGINS='https://signvoice.example';
                    OAUTH_BACKEND_ORIGIN='https://signvoice.example'; OAUTH_FRONTEND_ORIGIN='https://signvoice.example';
                    GOOGLE_CALLBACK_URL='https://signvoice.example/api/v1/auth/oauth/google/callback';
                    FACEBOOK_CALLBACK_URL='https://signvoice.example/api/v1/auth/oauth/facebook/callback';
                    PASSWORD_RESET_ORIGIN='https://signvoice.example'; AI_PUBLIC_PROXY='false'; AI_PROXY_TARGET='http://127.0.0.1:8001'}
                foreach ($key in $launchEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key,$launchEnvironment[$key],'Process') }
                if ($Options.StateChange -ne 'configStamp') { $state.configStamp = Production-Stamp }
                $state | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
            }
            $parameters = @{TrustProxy='loopback'; PublicOrigin='https://signvoice.example'; ExpectedSha=$sha; SkipBuild=$true; SkipAi=$true}
            if ($Options.Attach) { $parameters.AttachTunnel = $true } else { $parameters.LocalOnly = $true }
            if ($Options.Legacy) { $parameters.Remove('LocalOnly') }
            if ($Options.NoOrigin) { $parameters.Remove('PublicOrigin') }
            if ($Options.NoSha) { $parameters.Remove('ExpectedSha') }
            $caught = ''
            try { $messages = & $launcher @parameters 6>&1 } catch { $caught = $_.Exception.Message }
            if ($Failure) {
                if ($caught -notmatch $Failure) { throw "$Name : expected $Failure, got $caught" }
            } elseif ($caught) { throw "$Name : $caught" }
            if ($global:launcherTestEvents -contains 'tunnel' -and -not $Options.AllowTunnel) { throw "$Name : tunnel called" }
            if ($Options.Attach -and $global:launcherTestEvents -contains 'api') { throw "$Name : API spawned" }
            if ($Options.Attach -and $global:launcherTestStops -contains 4242) { throw "$Name : original API stopped" }
            if ($Options.Legacy -and $global:launcherTestEvents.Count) { throw "$Name : legacy run acted on staged API" }
            if (-not $Failure -and -not $Options.Attach -and ($global:launcherTestEvents -join ',') -ne 'validate,api') {
                throw "$Name : wrong startup ordering: $($global:launcherTestEvents -join ',')"
            }
            if ($Options.InvalidConfig -and $global:launcherTestEvents -contains 'api') { throw "$Name : invalid config spawned API" }
            if (-not $Failure -and -not $Options.Attach -and -not $Options.Legacy) {
                if (Microsoft.PowerShell.Management\Test-Path -LiteralPath $settingsFile) { throw "$Name : local-only saved a public setting" }
                if (($messages -join '\n') -notmatch 'loopback only') { throw "$Name : local-only output claims a public API" }
            }
            if ($Options.Attach -and -not $Failure) {
                $saved = Microsoft.PowerShell.Management\Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
                if ($saved.mode -ne 'production-attached' -or $saved.processId -ne 4242 -or $saved.managedTunnel.processId -ne 5656) {
                    throw "$Name : attached process state was not preserved"
                }
            }
            if ($Options.WrongOrigin -and ($global:launcherTestStops -join ',') -ne '5656,6060') { throw "$Name : tunnel cleanup missing" }
            Write-Host "PASS $Name"
        } $Name $Options $Failure
        $script:passed++
    }
    Check 'legacy refuses local-only production state without stopping it' @{Legacy='production-local'} 'staged production'
    Check 'legacy refuses attached production state without stopping it' @{Legacy='production-attached'} 'staged production'
    Check 'multiple Node installs resolve one path for startup' @{TwoNodes=$true}
    Check 'preflight and API use the same selected Node application' @{SelectedNode=$true}
    Check 'missing production file refuses without fallback' @{MissingEnv=$true} 'Missing.*production'
    Check 'explicit future origin required' @{NoOrigin=$true} 'PublicOrigin'
    Check 'explicit approved SHA required' @{NoSha=$true} 'ExpectedSha'
    Check 'wrong checkout SHA refuses' @{WrongHead=$true} 'ExpectedSha'
    Check 'dirty tracked checkout refuses' @{DirtyCheckout=$true} 'clean working tree'
    Check 'untracked source checkout refuses' @{UntrackedSource=$true} 'untracked source'
    Check 'invalid production config refuses before API/tunnel' @{InvalidConfig=$true} 'configuration validation failed'
    Check 'local-only starts one API and no tunnel' @{}
    Check 'local-only refuses existing public tunnel' @{ExistingTunnel=$true} 'tunnel already'
    Check 'attach refuses absent API' @{Attach=$true; NoApi=$true} 'exactly one|matching API'
    Check 'attach refuses two APIs' @{Attach=$true; TwoApis=$true} 'exactly one'
    Check 'attach refuses wrong PID' @{Attach=$true; StateChange='processId'; StateValue=9999} 'identity|PID|matching API'
    Check 'attach refuses reused PID' @{Attach=$true; WrongStart=$true} 'identity|start time|matching API'
    Check 'attach refuses public API listener' @{Attach=$true; PublicBind=$true} 'loopback port'
    Check 'attach refuses changed env file' @{Attach=$true; StateChange='envFile'; StateValue='wrong-file'} 'configuration|env file'
    Check 'attach refuses changed config' @{Attach=$true; StateChange='configStamp'; StateValue='changed'} 'configuration'
    Check 'attach refuses wrong SHA' @{Attach=$true; StateChange='sha'; StateValue=('b' * 40)} 'SHA'
    Check 'attach refuses existing untracked tunnel' @{Attach=$true; ExistingTunnel=$true} 'existing tunnel'
    Check 'attach refuses missing winpty without pip install' @{Attach=$true; MissingWinpty=$true} 'winpty is missing'
    Check 'matching attach reaches only tunnel launch' @{Attach=$true; AllowTunnel=$true; Sentinel=$true} 'TUNNEL SENTINEL'
    Check 'matching attach saves same API plus tunnel identity' @{Attach=$true; AllowTunnel=$true}
    Check 'wrong issued origin stops only new tunnel' @{Attach=$true; AllowTunnel=$true; WrongOrigin=$true} 'Issued tunnel origin differs'
    & {
        . (Join-Path $scratch 'scripts/public-server-production.ps1')
        $backendRoot = Join-Path $scratch 'backend'
        $envFile = Join-Path $scratch 'dummy-config'
        $codeDir = Join-Path $backendRoot 'dist'
        New-Item -ItemType Directory -Path $codeDir -Force | Out-Null
        $codeFile = Join-Path $codeDir 'server.js'
        Set-Content -LiteralPath $envFile -Value 'dummy-private-value-a'
        Set-Content -LiteralPath $codeFile -Value '// dummy code'
        $first = Production-Stamp
        Set-Content -LiteralPath $envFile -Value 'dummy-private-value-b'
        $second = Production-Stamp
        Set-Content -LiteralPath $codeFile -Value '// changed code'
        $third = Production-Stamp
        $prior = $env:SIGNVOICE_LAUNCHER_TEST_INPUT
        try {
            $env:SIGNVOICE_LAUNCHER_TEST_INPUT = 'dummy-inherited-override'
            $fourth = Production-Stamp
        } finally { $env:SIGNVOICE_LAUNCHER_TEST_INPUT = $prior }
        if ($first -cnotmatch '^[a-f0-9]{64}$' -or @($first,$second,$third,$fourth | Select-Object -Unique).Count -ne 4) {
            throw 'Fingerprint did not bind file contents, compiled code and inherited overrides.'
        }
        Write-Host 'PASS fingerprint binds config file, compiled code and inherited overrides'
    }
    $passed++
    Write-Host "$passed launcher checks passed; no real env, API, AI or tunnel opened."
} finally {
    $resolved = [IO.Path]::GetFullPath($scratch)
    if (-not $resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe scratch cleanup path' }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $resolved -Recurse -Force
}
