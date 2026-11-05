$ErrorActionPreference = 'Continue'

$repoRoot = Split-Path -Parent $PSScriptRoot
$results = @()

function Invoke-Check {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )

    Write-Host "`n=== $Name ==="
    $exitCode = 0

    try {
        & $Command 2>&1 | ForEach-Object { Write-Host ([string]$_) }
        if ($LASTEXITCODE -ne $null) {
            $exitCode = $LASTEXITCODE
        }
    }
    catch {
        Write-Host "Command error: $($_.Exception.Message)"
        $exitCode = 1
    }

    $status = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
    Write-Host "[$status] $Name (exit $exitCode)"
    $script:results += [pscustomobject]@{
        Name = $Name
        Status = $status
        ExitCode = $exitCode
    }
}

function Invoke-BackendCheck {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )

    Push-Location (Join-Path $repoRoot 'backend')
    try {
        & $Command
    }
    finally {
        Pop-Location
    }
}

Set-Location $repoRoot

Invoke-Check 'flutter analyze' { flutter analyze }
Invoke-Check 'flutter test' { flutter test }
Invoke-Check 'backend npm run typecheck' { Invoke-BackendCheck { npm run typecheck } }
Invoke-Check 'backend npm run lint' { Invoke-BackendCheck { npm run lint } }
Invoke-Check 'backend npm test' { Invoke-BackendCheck { npm test } }

Write-Host "`n=== Summary ==="
$results | ForEach-Object {
    Write-Host ("[{0}] {1} (exit {2})" -f $_.Status, $_.Name, $_.ExitCode)
}

if (@($results | Where-Object { $_.ExitCode -ne 0 }).Count -gt 0) {
    exit 1
}

exit 0
