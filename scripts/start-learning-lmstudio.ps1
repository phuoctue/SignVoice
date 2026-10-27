param([string]$LmsPath = '')
$ErrorActionPreference = 'Stop'
if (-not $LmsPath) {
  $taskUserHome=[Environment]::GetFolderPath('UserProfile')
  $pointer=Join-Path $taskUserHome '.lmstudio-home-pointer'
  $taskLmHome=if(Test-Path -LiteralPath $pointer){(Get-Content -LiteralPath $pointer -Raw).Trim()}else{Join-Path $taskUserHome '.lmstudio'}
  $LmsPath=Join-Path $taskLmHome 'bin\lms.exe'
}
if (-not (Test-Path -LiteralPath $LmsPath)) { throw 'LM Studio CLI not found. Install the official llmster service or supply -LmsPath.' }
& $LmsPath daemon up
if ($LASTEXITCODE) { throw 'Could not start LM Studio background service.' }
$model='qwen3-4b-instruct-2507'
$loaded=& $LmsPath ps --json | ConvertFrom-Json
if ($LASTEXITCODE) { throw 'Could not inspect loaded models.' }
if (-not (@($loaded) | Where-Object { $_.identifier -eq $model })) {
  # Load only SignVoice's model; leave other loaded models and runtime choices intact.
  & $LmsPath load $model --identifier $model --context-length 4096 --gpu off -y
  if ($LASTEXITCODE) { throw 'Could not load SignVoice Qwen3 4B. Confirm the Q4_K_M model has been downloaded.' }
}
try {
  $models=Invoke-RestMethod -Uri 'http://127.0.0.1:1235/v1/models' -TimeoutSec 5
} catch {
  & $LmsPath server start --port 1235 --bind 127.0.0.1
  if ($LASTEXITCODE) { throw 'Could not start the local server on port 1235.' }
  $models=Invoke-RestMethod -Uri 'http://127.0.0.1:1235/v1/models' -TimeoutSec 10
}
if (-not (@($models.data) | Where-Object { $_.id -eq $model })) { throw 'The server on port 1235 does not expose the SignVoice model.' }
Write-Host 'SignVoice learning AI ready: http://127.0.0.1:1235/v1'
Write-Host 'Keep this computer running while using AI analysis from the APK. No Bionic window is required.'
