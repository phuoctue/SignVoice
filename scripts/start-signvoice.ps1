param(
    [Parameter(Position=0)][ValidateSet('Local','Public')][string]$Mode = 'Local',
    [switch]$SkipBuild,
    [string]$PublicOrigin = ''
)
$ErrorActionPreference = 'Stop'
if ($Mode -eq 'Local') {
    if ($PublicOrigin) { throw 'PublicOrigin is only used in Public mode.' }
    & (Join-Path $PSScriptRoot 'start-public-server.ps1') -NoTunnel -Port 3002 -SkipBuild:$SkipBuild
} else {
    & (Join-Path $PSScriptRoot 'start-public-server.ps1') -SkipBuild:$SkipBuild -PublicOrigin $PublicOrigin
}
