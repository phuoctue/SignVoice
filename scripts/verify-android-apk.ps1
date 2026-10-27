param(
  [Parameter(Mandatory=$true)][string]$ApkPath,
  [ValidateSet('android-arm64','android-arm,android-arm64,android-x64')]
  [string]$TargetPlatform = 'android-arm64'
)
$ErrorActionPreference = 'Stop'
$abiNames = @{'android-arm'='armeabi-v7a'; 'android-arm64'='arm64-v8a'; 'android-x64'='x86_64'}
$expected = @($TargetPlatform.Split(',') | ForEach-Object { $abiNames[$_] } | Sort-Object)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ApkPath).Path)
try {
  $packaged = @($archive.Entries | Where-Object { $_.FullName -match '^lib/[^/]+/[^/]+\.so$' } |
    ForEach-Object { $_.FullName.Split('/')[1] } | Sort-Object -Unique)
  if ($packaged.Count -ne $expected.Count -or @(Compare-Object $expected $packaged).Count) {
    throw "APK ABI mismatch. Requested: $($expected -join ', '); packaged: $($packaged -join ', ')."
  }
  foreach ($abi in $expected) {
    foreach ($library in @('libapp.so','libflutter.so')) {
      if (-not $archive.GetEntry("lib/$abi/$library")) {
        throw "Incomplete APK: lib/$abi/$library is missing."
      }
    }
  }
  Write-Output "Verified complete Flutter libraries for: $($expected -join ', ')"
} finally { $archive.Dispose() }
