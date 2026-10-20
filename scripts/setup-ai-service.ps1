param(
  [string]$Python = 'python',
  [string]$ModelArchive = '',
  [switch]$SkipModelDownload
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$venvPath = Join-Path $projectRoot 'ai_service\.venv'
if (-not (Test-Path -LiteralPath (Join-Path $venvPath 'Scripts\python.exe'))) {
  & $Python -c "import sys; assert sys.version_info[:2] == (3, 11), 'Install Python 3.11 and pass -Python <python.exe>'"
  if ($LASTEXITCODE) { throw 'Can Python 3.11 de dung dung bo thu vien da kiem thu.' }
  & $Python -m venv $venvPath
  if ($LASTEXITCODE) { throw 'Không tạo được môi trường Python.' }
}
& (Join-Path $venvPath 'Scripts\python.exe') -m pip install -r (Join-Path $projectRoot 'ai_service\requirements.txt')
if ($LASTEXITCODE) { throw 'Không cài được thư viện AI.' }
if (-not $SkipModelDownload) {
  $installerArgs = @('-m', 'ai_service.install_model')
  if ($ModelArchive) { $installerArgs += @('--archive', (Resolve-Path -LiteralPath $ModelArchive).Path) }
  Push-Location $projectRoot
  try {
    & (Join-Path $venvPath 'Scripts\python.exe') @installerArgs
    if ($LASTEXITCODE) { throw 'Khong cai duoc model. Chay lai setup de tiep tuc tai, hoac dung -ModelArchive <ZIP>.' }
  } finally { Pop-Location }
}
