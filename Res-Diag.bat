@echo off
setlocal
rem ---------------------------------------------------------------------------
rem  Diagnostic launcher. Visible window, stays open, writes SetRes-diag.log.
rem  The work lives in Diag.ps1 to avoid cmd quoting problems.
rem ---------------------------------------------------------------------------

if not exist "%~dp0Diag.ps1" (
    echo [ERROR] Diag.ps1 not found next to this batch file.
    echo         Looked in: %~dp0
    echo.
    pause
    exit /b 1
)

echo Repo folder : %~dp0
echo.

powershell.exe -NoProfile -NoExit -ExecutionPolicy Bypass -File "%~dp0Diag.ps1"

endlocal
