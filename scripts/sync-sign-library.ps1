param(
  [Parameter(Mandatory=$true)][string]$ZipPath,
  [switch]$Apply,
  [switch]$SyncRemoved
)
$ErrorActionPreference='Stop'
$project=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$archivePath=(Resolve-Path -LiteralPath $ZipPath).Path
$packageHash=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
$staging=[IO.Path]::GetFullPath((Join-Path $project ".runtime\media-updates\$packageHash"))
$expectedRoot=[IO.Path]::GetFullPath((Join-Path $project '.runtime\media-updates'))+[IO.Path]::DirectorySeparatorChar
if(-not $staging.StartsWith($expectedRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid staging directory.'}
function Assert-UnlinkedPath([string]$Candidate) {
  $walk=[IO.Path]::GetFullPath($Candidate)
  while($walk -and $walk.StartsWith($project+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
    if(Test-Path -LiteralPath $walk) {
      if((Get-Item -LiteralPath $walk -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Refusing linked staging path.'}
    }
    $walk=Split-Path -Parent $walk
  }
}
Assert-UnlinkedPath $staging
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($archivePath)
try {
  $manifests=@($archive.Entries | Where-Object { $_.FullName -match '(^|/)manifest\.json$' })
  if($manifests.Count -ne 1){throw 'Use a processed SignVoice media ZIP containing one manifest.json, not the raw training dataset.'}
  $prefix=$manifests[0].FullName.Substring(0,$manifests[0].FullName.Length-'manifest.json'.Length)
  $files=@($archive.Entries | Where-Object {$_.Name})
  if($files.Count -gt 30001 -or ($files | Measure-Object Length -Sum).Sum -gt 15GB){throw 'Media package exceeds the supported size.'}
  $plan=[Collections.Generic.List[object]]::new()
  foreach($entry in $files) {
    if(-not $entry.FullName.StartsWith($prefix,[StringComparison]::Ordinal)){throw 'Archive contains files outside its package root.'}
    $relative=$entry.FullName.Substring($prefix.Length)
    if($relative -notmatch '^(manifest\.json|README_VI\.md|install-media\.cjs|media/([a-f0-9]{64}(-[1-5])?\.(mp4|jpg)|LICENSE-(apache-2\.0|cc-by-4\.0)\.txt)|metadata/(library|categories|taxonomy|source_cards|package-info)\.json)$'){throw "Unsupported archive entry: $relative"}
    $destination=[IO.Path]::GetFullPath((Join-Path $staging $relative))
    if(-not $destination.StartsWith($staging+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Archive entry leaves staging.'}
    $plan.Add(@{Entry=$entry;Destination=$destination})
  }
  New-Item -ItemType Directory -Path $staging -Force | Out-Null
  $checkedParents=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach($item in $plan) {
    $parent=Split-Path -Parent $item.Destination
    if($checkedParents.Add($parent)) {
    Assert-UnlinkedPath $parent
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    # Reject linked staging paths; never follow a pre-existing junction/symlink.
    $walk=Get-Item -LiteralPath $parent
    while($walk -and $walk.FullName.StartsWith($staging,[StringComparison]::OrdinalIgnoreCase)) {
      if($walk.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Refusing linked staging directory.'}
      $walk=$walk.Parent
    }
    }
    if(Test-Path -LiteralPath $item.Destination){if((Get-Item -LiteralPath $item.Destination).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Refusing linked staging file.'}}
    $source=$item.Entry.Open();$target=[IO.File]::Open($item.Destination,[IO.FileMode]::Create,[IO.FileAccess]::Write)
    try{$source.CopyTo($target)}finally{$target.Dispose();$source.Dispose()}
  }
} finally {$archive.Dispose()}
$installer=Join-Path $project 'scripts\install-sign-library-media.cjs'
& node $installer --bundle $staging --verify-only
if($LASTEXITCODE){throw 'Package verification failed; dictionary was not changed.'}
if(-not $Apply){Write-Host 'Verified. Run again with -Apply to install and synchronize this complete package.';exit 0}
& node $installer --bundle $staging --project $project --update
if($LASTEXITCODE){throw 'Media installation failed; dictionary was not changed.'}
$pendingPath=Join-Path $project '.runtime\library-package-pending.json'
$pending=Get-Content -LiteralPath $pendingPath -Raw | ConvertFrom-Json
$catalog=[IO.Path]::GetFullPath((Join-Path $project $pending.catalog))
if(-not $catalog.StartsWith((Join-Path $project '.runtime\speech-sign-library\bundles')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid installed catalog path.'}
Push-Location (Join-Path $project 'backend')
try {
  $importArguments=@((Join-Path $project 'backend\node_modules\tsx\dist\cli.mjs'),(Join-Path $project 'backend\scripts\import-sign-library.ts'),'--catalog',$catalog,'--apply')
  if($SyncRemoved){$importArguments+='--sync-removed'}
  & node @importArguments
  if($LASTEXITCODE){throw 'Catalog synchronization failed; previous database transaction was preserved.'}
} finally {Pop-Location}
$pending | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $project '.runtime\library-package-active.json') -Encoding UTF8
Write-Host 'Dictionary synchronized. Existing references retain their IDs; active apps refresh on the next version check. No APK rebuild is required.'
