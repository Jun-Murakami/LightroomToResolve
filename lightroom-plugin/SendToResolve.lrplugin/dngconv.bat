@echo off
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%dngconv.ps1"
set "SOURCE_RAW=%~1"

if "%SOURCE_RAW%"=="" (
    echo Source RAW path is missing.
    exit /b 1
)

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%PS_SCRIPT%" -SourceRaw "%SOURCE_RAW%"
exit /b %ERRORLEVEL%

