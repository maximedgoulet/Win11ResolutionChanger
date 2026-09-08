@echo off
setlocal
rem ---------------------------------------------------------------------------
rem  Standard 16:9 4K mode.
rem  Edit x / y / r below to change what this script applies.
rem  Paths are resolved relative to this file, so the repo can live anywhere.
rem ---------------------------------------------------------------------------

set "x=3840"
set "y=2160"
set "r=120"

set "SCRIPT=%~dp0SetRes.ps1"

if not exist "%SCRIPT%" (
    echo [ERROR] SetRes.ps1 not found next to this batch file.
    echo         Looked in: %~dp0
    echo.
    pause
    exit /b 1
)

echo.
echo Changing Resolution to %x% x %y% (%r%hz)...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Width %x% -Height %y% -Refresh %r%

if errorlevel 1 (
    echo.
    echo [FAILED] The display mode was not applied.
    echo Run Res-Diag.bat to see what the driver actually supports.
    echo.
    pause
    exit /b 1
)

echo.
echo Done!!!
echo.
echo If you want another resolution edit the script!
echo   ^(the x / y / r values at the top^)
echo.
timeout /t 6
exit /b 0
