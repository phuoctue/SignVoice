$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$python = Join-Path $projectRoot 'ai_service/.venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $python)) { $python = (Get-Command python).Source }
& $python -m pip install --target (Join-Path $projectRoot '.tools/video-tools') imageio-ffmpeg==0.8.1 --disable-pip-version-check
if ($LASTEXITCODE) { throw 'Không cài được công cụ chuyển video.' }
Write-Host 'Đã sẵn sàng nhận và chuyển video để phát trong ứng dụng.'
