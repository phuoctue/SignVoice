param(
  [string]$ListenHost = '127.0.0.1',
  [int]$Port = 8001,
  [string]$ModelDirectory = '',
  [string]$SslCert = '',
  [string]$SslKey = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$aiPython = Join-Path $projectRoot 'ai_service\.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $aiPython)) {
  Write-Error 'Chay scripts\setup-ai-service.ps1 truoc.'
}
$selectionArgs = @('-m','ai_service.model_selection','resolve')
if ($ModelDirectory) { $selectionArgs += @('--model-dir',$ModelDirectory) }
Push-Location $projectRoot
try {
  $selectedJson = & $aiPython @selectionArgs
  if ($LASTEXITCODE) { throw 'Bo model chua day du hoac khong khop feature camera. Khong khoi dong AI.' }
  $selected = $selectedJson | ConvertFrom-Json
} finally { Pop-Location }
if ($ListenHost -eq '127.0.0.1') {
  $running = $null
  try { $running = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2 } catch { }
  if ($running -and $running.ready) {
    if ($running.model_manifest_sha256 -eq $selected.manifest_sha256) {
      if ($running.camera_runtime -ne 'camera_ensemble_v8') {
        throw "Service AI dang giu adapter camera cu trong RAM. Dung service cu roi chay lai de nap camera v8."
      }
      $adapterHash = (Get-FileHash -LiteralPath (Join-Path $projectRoot 'ai_service\engine.py') -Algorithm SHA256).Hash.ToLowerInvariant()
      if ($running.camera_adapter_sha256 -ne $adapterHash) {
        throw "Service AI dang giu adapter cu trong RAM. Dung service cu roi chay lai de nap thay doi camera."
      }
      $runtimeHash = (Get-FileHash -LiteralPath (Join-Path $projectRoot 'ai_service\model_runtime.py') -Algorithm SHA256).Hash.ToLowerInvariant()
      if ($running.runtime_sha256 -ne $runtimeHash) {
        throw "Service AI tren cong $Port van giu code cu trong RAM. Dung cua so service cu roi chay lai de nap ban sua camera."
      }
      $ensemblePath = Join-Path $projectRoot '.runtime\word-ensemble.json'
      if (Test-Path -LiteralPath $ensemblePath) {
        $ensemblePolicy = Get-Content -LiteralPath $ensemblePath -Raw | ConvertFrom-Json
        if ($ensemblePolicy.manifest_sha256 -eq $selected.manifest_sha256 -and $running.word_engine -ne 'probability_ensemble') {
          throw "Service AI van chay TCN cu. Dung service cu roi chay lai de nap ca TCN va embedding."
        }
      }
      Write-Host "Service AI da san sang: http://127.0.0.1:$Port ($($running.word_classes) tu)."
      return
    }
    throw "Cong $Port dang chay model khac ($($running.word_classes) tu). Dung rieng service AI cu roi chay lai; model da chon chua duoc nap."
  }
}
$env:SIGNVOICE_MODEL_DIR = $selected.model_dir
Write-Host "Model da chon: $($selected.word_classes) tu | $($selected.manifest_sha256.Substring(0,12))"
$arguments = @('-m','uvicorn','ai_service.server:app','--host',$ListenHost,'--port',"$Port",'--ws-max-size','4194304','--ws-max-queue','1','--no-access-log')
if ($SslCert -and $SslKey) { $arguments += @('--ssl-certfile',$SslCert,'--ssl-keyfile',$SslKey) }
Push-Location $projectRoot
try { & $aiPython @arguments; if ($LASTEXITCODE) { throw "Service AI thoat voi ma $LASTEXITCODE" } }
finally { Pop-Location }
