$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$keytool = if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin/keytool.exe'))) { Join-Path $env:JAVA_HOME 'bin/keytool.exe' } else { 'E:/WorkSpace/Android Studio/jbr/bin/keytool.exe' }
$keystore = Join-Path $env:USERPROFILE '.android/debug.keystore'
if (-not (Test-Path $keytool) -or -not (Test-Path $keystore)) { throw 'Android debug keystore or Java keytool not found.' }
$lines = & $keytool '-J-Duser.language=en' '-J-Duser.country=US' -list -v -keystore $keystore -alias androiddebugkey -storepass android -keypass android
if ($LASTEXITCODE) { throw 'Cannot inspect debug signing certificate.' }
$fingerprint = [regex]::Match(($lines -join "`n"), 'SHA256:\s*((?:[A-F0-9]{2}:){31}[A-F0-9]{2})').Groups[1].Value
if (-not $fingerprint) { throw 'Missing SHA-256 signing fingerprint.' }
$folder = Join-Path $root '.runtime/testing'
New-Item -ItemType Directory -Force -Path $folder | Out-Null
@{ package='com.example.sign_voice'; sha256=$fingerprint; host='localhost' } | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $folder 'android-app-links.json') -Encoding UTF8
Write-Host 'Saved public debug signing association for the local test backend. No private key was exported.'
