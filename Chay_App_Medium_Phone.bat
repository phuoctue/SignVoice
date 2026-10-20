@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run-ai-emulator.ps1" %*
if errorlevel 1 (
  echo.
  echo Khong chay duoc. Chan doan: %~dp0.runtime\emulator-launch-diagnostics.json
  pause
  exit /b 1
)
endlocal
