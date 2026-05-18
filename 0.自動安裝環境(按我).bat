@echo off
setlocal
chcp 65001 >nul

title work-log setup

cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
set "code=%errorlevel%"

echo.
if not "%code%"=="0" (
    echo Setup finished with errors. Exit code: %code%
) else (
    echo Setup completed successfully.
)
pause
exit /b %code%
