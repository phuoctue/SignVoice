param(
  [string]$DeviceId = '',
  [string]$AdbPath = ''
)
$ErrorActionPreference = 'Stop'

if (-not $AdbPath) {
  $candidates = @()
  if ($env:ANDROID_HOME) { $candidates += Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe' }
  if ($env:ANDROID_SDK_ROOT) { $candidates += Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe' }
  if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe') }
  $AdbPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $AdbPath) {
    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) { $AdbPath = $command.Source }
  }
}
if (-not $AdbPath -or -not (Test-Path -LiteralPath $AdbPath)) {
  throw 'Khong tim thay adb. Truyen -AdbPath <Android SDK>\platform-tools\adb.exe.'
}

$listing = & $AdbPath devices -l
if ($LASTEXITCODE) { throw 'Khong doc duoc danh sach ADB.' }
$devices = @(foreach ($line in $listing) {
  if ($line -match '^(\S+)\s+(device|unauthorized|offline)\b') {
    [pscustomobject]@{ Id = $Matches[1]; State = $Matches[2] }
  }
})
if ($DeviceId) { $devices = @($devices | Where-Object Id -eq $DeviceId) }
if ($devices.Count -eq 0) {
  throw 'Chua thay dien thoai. Cam cap USB truyen du lieu, bat USB debugging va bam Allow tren dien thoai; sau do chay lai.'
}
if ($devices.Count -gt 1) {
  $devices | Format-Table | Out-Host
  throw 'Co nhieu thiet bi. Chay lai voi -DeviceId <ID dien thoai>.'
}
$device = $devices[0]
if ($device.State -ne 'device') {
  throw "Thiet bi $($device.Id): $($device.State). Mo khoa dien thoai, chap nhan USB debugging hoac cam lai cap."
}

foreach ($port in @(3000, 8001)) {
  & $AdbPath -s $device.Id reverse "tcp:$port" "tcp:$port"
  if ($LASTEXITCODE) { throw "Khong tao duoc USB reverse cong $port." }
}
Write-Host "USB da noi: $($device.Id) | API 3000 | AI 8001"
& $AdbPath -s $device.Id reverse --list
if ($LASTEXITCODE) { throw 'Khong kiem tra duoc USB reverse.' }

foreach ($endpoint in @('http://127.0.0.1:3000/health/live', 'http://127.0.0.1:8001/health')) {
  try {
    $response = Invoke-WebRequest -Uri $endpoint -UseBasicParsing -TimeoutSec 5
    Write-Host "OK $endpoint ($($response.StatusCode))"
  } catch {
    Write-Warning "Chua ket noi duoc $endpoint. Bat dung backend/AI service tren may tinh."
  }
}
Write-Host 'Chon dien thoai trong Android Studio, chay SignVoice USB - Profile.'
Write-Host 'API_BASE_URL=http://127.0.0.1:3000/api/v1'
Write-Host 'AI_SERVICE_URL=http://127.0.0.1:8001'
