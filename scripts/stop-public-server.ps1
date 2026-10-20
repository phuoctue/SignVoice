param([switch]$KeepServices)
$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$stateFile = Join-Path $workspaceRoot '.runtime/public-server.json'
if (-not (Test-Path -LiteralPath $stateFile)) { Write-Host 'No public server state found.'; return }
$serverState = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
$serverProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($serverState.processId)" -ErrorAction SilentlyContinue
if ($serverProcess) {
    $listener = Get-NetTCPConnection -State Listen -LocalPort $serverState.port -ErrorAction SilentlyContinue
    if ($serverProcess.Name -ne 'node.exe' -or $serverProcess.CommandLine -notmatch 'dist/server\.js' -or
        ($serverState.startedUtc -and (Get-Process -Id $serverState.processId).StartTime.ToUniversalTime().Ticks -ne ([datetime]$serverState.startedUtc).ToUniversalTime().Ticks) -or
        -not ($listener | Where-Object { $_.OwningProcess -eq $serverState.processId })) {
        throw 'Saved process does not match the SignVoice public server; it was not stopped.'
    }
    Stop-Process -Id $serverState.processId
}
function Stop-Managed($Record, [string]$ExpectedName, [string]$Pattern) {
    if (-not $Record) { return }
    $managed = Get-CimInstance Win32_Process -Filter "ProcessId = $($Record.processId)" -ErrorAction SilentlyContinue
    if (-not $managed) { return }
    if ($managed.Name -ne $ExpectedName -or $managed.CommandLine -notmatch $Pattern -or
        (Get-Process -Id $Record.processId).StartTime.ToUniversalTime().Ticks -ne ([datetime]$Record.startedUtc).ToUniversalTime().Ticks) {
        Write-Warning "Process $($Record.processId) no longer matches its saved identity; not stopped."
        return
    }
    Stop-Process -Id $managed.ProcessId
}
if (-not $KeepServices) {
    Stop-Managed $serverState.managedTunnel 'conveyorcli.exe' ('(?:-p|--ports)\s+' + [regex]::Escape("$($serverState.port)i") + '(?:\s|$)')
    Stop-Managed $serverState.managedTunnelWrapper 'python.exe' 'conveyor-tunnel.py'
    Stop-Managed $serverState.managedAi 'python.exe' 'uvicorn.*ai_service.server'
    Stop-Managed $serverState.managedAiWrapper 'powershell.exe' 'start-ai-service.ps1'
}
Remove-Item -LiteralPath $stateFile
Write-Host 'SignVoice public server stopped.'
