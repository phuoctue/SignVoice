param(
  [string]$AvdName = 'Medium_Phone',
  [string]$SdkPath = '',
  [string]$FlutterPath = '',
  [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $SdkPath) { $SdkPath = $env:ANDROID_HOME }
if (-not $SdkPath) { $SdkPath = $env:ANDROID_SDK_ROOT }
if (-not $SdkPath -and $env:LOCALAPPDATA) {
  $candidate = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
  if (Test-Path -LiteralPath $candidate) { $SdkPath = $candidate }
}
if (-not $SdkPath) { throw 'Dat ANDROID_HOME hoac truyen -SdkPath <thu muc Android SDK>.' }
if (-not $FlutterPath) {
  $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
  if ($flutterCommand) { $FlutterPath = $flutterCommand.Source }
}
if (-not $FlutterPath) { throw 'Them Flutter vao PATH hoac truyen -FlutterPath <flutter.bat>.' }
$runtime = Join-Path $projectRoot '.runtime'
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$reportPath = Join-Path $runtime 'emulator-launch-diagnostics.json'
$diagnostics = [ordered]@{
  checked_at = (Get-Date).ToString('o')
  shell_version = $PSVersionTable.PSVersion.ToString()
  default_flutter = @(Get-Command flutter -All -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
  android_home_before = $env:ANDROID_HOME
  android_sdk_root_before = $env:ANDROID_SDK_ROOT
  adb_server_socket = $env:ADB_SERVER_SOCKET
  sdk_path = $SdkPath
  flutter_path = $FlutterPath
  avd_name = $AvdName
}
$savedEnvironment = @{}
foreach ($key in @('ANDROID_HOME','ANDROID_SDK_ROOT','JAVA_TOOL_OPTIONS')) {
  $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
Push-Location $projectRoot
try {
  $adb = Join-Path $SdkPath 'platform-tools\adb.exe'
  foreach ($required in @($adb,$FlutterPath)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Khong tim thay: $required" }
  }
  $env:ANDROID_HOME = $SdkPath
  $env:ANDROID_SDK_ROOT = $SdkPath
  $socketDirectory = Join-Path $runtime 'java-sockets'
  New-Item -ItemType Directory -Path $socketDirectory -Force | Out-Null
  $env:JAVA_TOOL_OPTIONS = "$($savedEnvironment['JAVA_TOOL_OPTIONS']) -Djdk.net.unixdomain.tmpdir=`"$socketDirectory`""
  & $FlutterPath config --android-sdk $SdkPath --enable-android
  if ($LASTEXITCODE) { throw 'Khong khai bao duoc Android SDK cho Flutter.' }
  & $adb start-server
  if ($LASTEXITCODE) { throw 'Khong khoi dong duoc ADB.' }
  $adbListing = @(& $adb devices -l)
  if ($LASTEXITCODE) { throw 'Khong doc duoc thiet bi ADB.' }
  $diagnostics['adb_devices'] = $adbListing
  $adbListing | ForEach-Object { Write-Host $_ }
  $deviceOutput = @(& $FlutterPath devices --machine --device-timeout 30)
  $diagnostics['flutter_devices_output'] = $deviceOutput
  if ($LASTEXITCODE) { throw 'Flutter khong doc duoc danh sach thiet bi.' }
  $devices = ($deviceOutput -join "`n") | ConvertFrom-Json
  $candidates = @($devices | Where-Object { $_.emulator -and $_.targetPlatform -like 'android-*' })
  $selected = $null
  foreach ($candidate in $candidates) {
    $avdOutput = @(& $adb -s $candidate.id emu avd name)
    if ($LASTEXITCODE -eq 0 -and $avdOutput -contains $AvdName) {
      $selected = $candidate
      break
    }
  }
  if (-not $selected) {
    throw "Flutter chua nhan AVD $AvdName. Giu may ao mo. Chan doan da luu: $reportPath"
  }
  $diagnostics['selected_device'] = $selected
  $diagnostics['status'] = 'device_ready'
  $diagnostics | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
  Write-Host "Da nhan $AvdName : $($selected.id) | $($selected.sdk)"
  if (-not $CheckOnly) {
    & $FlutterPath run -d $selected.id --device-timeout 60 '--dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1' '--dart-define=AI_SERVICE_URL=http://10.0.2.2:8001'
    if ($LASTEXITCODE) { throw "Flutter run that bai, exit code $LASTEXITCODE." }
  }
} catch {
  $diagnostics['error'] = $_.Exception.Message
  $diagnostics | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
  throw
} finally {
  foreach ($key in $savedEnvironment.Keys) {
    [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], 'Process')
  }
  Pop-Location
}
