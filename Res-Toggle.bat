@echo off
setlocal
rem ---------------------------------------------------------------------------
rem  Flips between two modes. Edit A and B to suit your displays.
rem  Format: WIDTHxHEIGHT@HZ
rem ---------------------------------------------------------------------------

set "A=7680x2160@120"
set "B=3840x2160@120"

set "SCRIPT=%~dp0SetRes.ps1"

if not exist "%SCRIPT%" (
    echo [ERROR] SetRes.ps1 not found next to this batch file.
    echo         Looked in: %~dp0
    echo.
    pause
    exit /b 1
)

echo.
echo Toggling between %A% and %B% ...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Toggle -A %A% -B %B%

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
timeout /t 6
exit /b 0
