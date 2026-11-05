param([string]$DeviceId = 'emulator-5554', [switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$adb = if ($env:ANDROID_HOME) { Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe' } else { 'E:/Android/Sdk/platform-tools/adb.exe' }
if (-not (Test-Path $adb)) { throw 'Set ANDROID_HOME to the Android SDK directory.' }
$health = Invoke-RestMethod 'http://localhost:3003/health/ready' -TimeoutSec 5
if ($health.data.database.name -ne 'signvoice_test') { throw 'Test backend is not ready.' }
Push-Location $root
try {
    $abi = (& $adb -s $DeviceId shell getprop ro.product.cpu.abi).Trim()
    $target = switch ($abi) { 'x86_64' { 'android-x64' } 'arm64-v8a' { 'android-arm64' } 'armeabi-v7a' { 'android-arm' } default { throw "Unsupported device ABI: $abi" } }
    if (-not $SkipBuild) {
        & flutter.bat build apk --debug --target-platform $target --no-pub --dart-define=API_BASE_URL=http://127.0.0.1:3003/api/v1 --dart-define=AI_SERVICE_URL=http://127.0.0.1:3003/sign-ai
        if ($LASTEXITCODE) { throw 'APK build failed.' }
    }
    & $adb -s $DeviceId reverse tcp:3003 tcp:3003
    if ($LASTEXITCODE) { throw 'ADB reverse failed.' }
    & $adb -s $DeviceId install -r 'build/app/outputs/flutter-apk/app-debug.apk'
    if ($LASTEXITCODE) { throw 'APK install failed. Existing app data was not removed.' }
    & $adb -s $DeviceId shell am start -n com.example.sign_voice/.MainActivity
} finally { Pop-Location }
