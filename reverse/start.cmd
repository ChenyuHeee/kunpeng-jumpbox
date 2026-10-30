@echo off
setlocal
cd /d "%~dp0"
echo Starting Kunpeng jumpbox reverse tunnel. Keep this window open; Ctrl+C stops it.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start.ps1"
echo.
pause
