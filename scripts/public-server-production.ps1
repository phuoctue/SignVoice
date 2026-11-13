# Configuration checks import only config/env, never the server or database connector.
function Validate-ProductionConfig {
    & $nodeExecutable (Join-Path $PSScriptRoot 'public-server-config.cjs') $backendRoot $envFile
    if ($LASTEXITCODE) { throw 'Backend configuration validation failed; server/tunnel was not started.' }
}
function Production-Stamp {
    # Hash inputs only: attach must not even launch a config-only Node process.
    $parts = @((Get-FileHash -LiteralPath $envFile -Algorithm SHA256).Hash)
    $parts += @(Get-ChildItem -LiteralPath (Join-Path $backendRoot 'dist') -Filter '*.js' -Recurse -File |
        Sort-Object FullName | ForEach-Object { $_.FullName; (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash })
    $parts += @([Environment]::GetEnvironmentVariables('Process').GetEnumerator() | Sort-Object Key |
        ForEach-Object { "$($_.Key)=$($_.Value)" })
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $parts -Compress)))).Replace('-','').ToLowerInvariant() }
    finally { $hash.Dispose() }
}
function Assert-LaunchSha {
    if ($ExpectedSha -cnotmatch '^[a-f0-9]{40}$') { throw 'Production staged modes require -ExpectedSha with the approved full commit SHA.' }
    $currentSha = & git -C $workspaceRoot rev-parse HEAD
    if ($LASTEXITCODE -or $currentSha -cne $ExpectedSha) { throw 'Checkout does not match ExpectedSha.' }
    # The selected private config is expected to be untracked; never print status entries.
    $changes = & git -C $workspaceRoot status --porcelain --untracked-files=all -- . ':!backend/.env.production.local'
    if ($LASTEXITCODE -or $changes) { throw 'Production staged modes require a clean working tree at ExpectedSha (including untracked source).' }
}
function Assert-AttachIdentity {
    Assert-LaunchSha
    if (-not $oldState -or $oldState.mode -ne 'production-local' -or $oldState.sha -cne $ExpectedSha) {
        throw 'No production local-only state matching the expected SHA.'
    }
    if ($oldState.envFile -ne $envFile -or $oldState.configStamp -cne $configStamp -or
        $oldState.publicOrigin -cne $PublicOrigin -or $oldState.trustProxy -cne $TrustProxy -or $oldState.port -ne $Port) {
        throw 'Saved production configuration/env file does not match; restart local-only and repeat smoke tests.'
    }
    $apis = @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" |
        Where-Object { $_.CommandLine -match 'dist[\\/]server\.js(?:"|\s|$)' })
    if ($apis.Count -ne 1) { throw 'Attach requires exactly one running API; no API was started.' }
    $expectedEntry = Join-Path $backendRoot 'dist/server.js'
    $expectedCommand = '(?:^|\s)"' + [regex]::Escape($expectedEntry) + '"(?:\s|$)'
    if ($apis[0].ProcessId -ne $oldState.processId -or $apis[0].CommandLine -notmatch $expectedCommand -or
        -not (Record-Alive $oldState)) { throw 'Running API PID/start time/command identity does not match local-only state.' }
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
    if (-not $listeners.Count -or @($listeners | Where-Object { $_.OwningProcess -ne $oldState.processId -or $_.LocalAddress -ne '127.0.0.1' }).Count) {
        throw 'Matching API must be the only listener on the expected loopback port.'
    }
}
