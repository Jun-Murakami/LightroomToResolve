@echo off
setlocal EnableDelayedExpansion

echo ==========================================
echo Lightroom to Resolve Installer (Windows)
echo ==========================================

REM 1. Check Required Applications
echo.
echo [1/2] Checking Required Applications...

set "ALL_FOUND=1"

REM Check Adobe Lightroom Classic
set "LR_FOUND=0"
if exist "C:\Program Files\Adobe\Adobe Lightroom Classic\Adobe Lightroom Classic.exe" (
    echo [OK] Adobe Lightroom Classic found.
    set "LR_FOUND=1"
) else if exist "C:\Program Files\Adobe\Adobe Lightroom Classic" (
    echo [OK] Adobe Lightroom Classic found.
    set "LR_FOUND=1"
)
if !LR_FOUND!==0 (
    echo [ERROR] Adobe Lightroom Classic not found.
    set "ALL_FOUND=0"
)

REM Check DaVinci Resolve
set "RESOLVE_FOUND=0"
if exist "C:\Program Files\Blackmagic Design\DaVinci Resolve\Resolve.exe" (
    echo [OK] DaVinci Resolve found.
    set "RESOLVE_FOUND=1"
)
if !RESOLVE_FOUND!==0 (
    echo [ERROR] DaVinci Resolve not found.
    set "ALL_FOUND=0"
)

REM Check Adobe DNG Converter
set "DNG_FOUND=0"
if exist "C:\Program Files\Adobe\Adobe DNG Converter\Adobe DNG Converter.exe" (
    echo [OK] Adobe DNG Converter found.
    set "DNG_FOUND=1"
) else if exist "C:\Program Files (x86)\Adobe\Adobe DNG Converter\Adobe DNG Converter.exe" (
    echo [OK] Adobe DNG Converter found.
    set "DNG_FOUND=1"
)
if !DNG_FOUND!==0 (
    echo [ERROR] Adobe DNG Converter not found.
    set "ALL_FOUND=0"
)

REM Exit if any required application is missing
if !ALL_FOUND!==0 (
    echo.
    echo ==========================================
    echo Installation Aborted
    echo ==========================================
    echo The following required applications are not installed:
    if !LR_FOUND!==0 echo   - Adobe Lightroom Classic
    if !RESOLVE_FOUND!==0 echo   - DaVinci Resolve
    if !DNG_FOUND!==0 echo   - Adobe DNG Converter
    echo.
    echo Please install these applications before continuing.
    echo ==========================================
    pause
    exit /b 1
)

REM 2. Copy Files
echo.
echo [2/2] Installing Scripts and Plugins...

set "LR_PLUGIN_SRC=%~dp0lightroom-plugin\SendToResolve.lrplugin"
set "RESOLVE_SCRIPT_SRC=%~dp0resolve-script\LightroomToResolve.lua"

set "LR_PLUGIN_DEST=%APPDATA%\Adobe\Lightroom\Modules\SendToResolve.lrplugin"
set "RESOLVE_SCRIPT_DEST=%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Edit"

REM Copy Lightroom Plugin
if not exist "%LR_PLUGIN_SRC%" (
    echo [ERROR] Plugin source not found: %LR_PLUGIN_SRC%
    goto :End
)

echo Installing Lightroom Plugin...
if not exist "%APPDATA%\Adobe\Lightroom\Modules" mkdir "%APPDATA%\Adobe\Lightroom\Modules"
xcopy /E /I /Y "%LR_PLUGIN_SRC%" "%LR_PLUGIN_DEST%" >nul
echo [OK] Copied to %LR_PLUGIN_DEST%

REM Copy Resolve Script
if not exist "%RESOLVE_SCRIPT_SRC%" (
    echo [ERROR] Script source not found: %RESOLVE_SCRIPT_SRC%
    goto :End
)

echo Installing Resolve Script...
if not exist "%RESOLVE_SCRIPT_DEST%" mkdir "%RESOLVE_SCRIPT_DEST%"
copy /Y "%RESOLVE_SCRIPT_SRC%" "%RESOLVE_SCRIPT_DEST%\" >nul
echo [OK] Copied to %RESOLVE_SCRIPT_DEST%\LightroomToResolve.lua

echo.
echo ==========================================
echo Installation Complete!
echo.
echo Please restart Lightroom Classic and DaVinci Resolve.
echo ==========================================
pause

:End
endlocal

