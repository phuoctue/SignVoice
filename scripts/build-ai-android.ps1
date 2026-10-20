param(
  [string]$ApiBaseUrl = 'http://10.0.2.2:3000/api/v1',
  [string]$AiServiceUrl = 'http://10.0.2.2:8001',
  [string]$SdkPath = '',
  [ValidateSet('android-arm64','android-arm,android-arm64,android-x64')]
  [string]$TargetPlatform = 'android-arm64'
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$socketTemp = Join-Path $projectRoot '.runtime\java-sockets'
New-Item -ItemType Directory -Force -Path $socketTemp | Out-Null
$previousOptions = $env:JAVA_TOOL_OPTIONS
$previousSdk = $env:ANDROID_HOME
try {
  # Java NIO socket paths under the user's Windows temp caused connect errors.
  # Scope this workaround to the build and leave global Java settings untouched.
  $env:JAVA_TOOL_OPTIONS = "$previousOptions -Djdk.net.unixdomain.tmpdir=`"$socketTemp`""
  if (-not $SdkPath -and $env:ANDROID_HOME) { $SdkPath = $env:ANDROID_HOME }
  if (-not $SdkPath) { $SdkPath = $env:ANDROID_SDK_ROOT }
  if (-not $SdkPath -and $env:LOCALAPPDATA) {
    $candidate = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    if (Test-Path -LiteralPath $candidate) { $SdkPath = $candidate }
  }
  if ($SdkPath) { $env:ANDROID_HOME = (Resolve-Path -LiteralPath $SdkPath).Path }
  Push-Location $projectRoot
  try {
    & flutter build apk --release --target-platform $TargetPlatform "--dart-define=API_BASE_URL=$ApiBaseUrl" "--dart-define=AI_SERVICE_URL=$AiServiceUrl"
    if ($LASTEXITCODE) { throw 'Android build failed. Read the error above before installing an older APK.' }
  } finally { Pop-Location }
} finally {
  $env:JAVA_TOOL_OPTIONS = $previousOptions
  $env:ANDROID_HOME = $previousSdk
}
