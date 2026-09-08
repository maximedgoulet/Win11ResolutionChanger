<#
    Diag.ps1 - environment + display-mode diagnostics for SetRes.ps1
    Writes SetRes-diag.log next to this file and echoes to the console.
#>

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$log  = Join-Path $here 'SetRes-diag.log'
$ps1  = Join-Path $here 'SetRes.ps1'

# *>&1 merges all six streams into the pipeline so errors are captured too.
& {
    $ErrorActionPreference = 'Continue'

    "PSVersion  : $($PSVersionTable.PSVersion)"
    "Is64Bit    : $([Environment]::Is64BitProcess)"
    "Tools path : $here"
    "Timestamp  : $(Get-Date -Format s)"
    ''
    '---- Execution policy by scope ----'
    Get-ExecutionPolicy -List | Format-Table -AutoSize | Out-String

    '---- Alternate data streams on SetRes.ps1 ----'
    if (Test-Path $ps1) {
        Get-Item -Path $ps1 -Stream * -ErrorAction SilentlyContinue |
            Select-Object Stream, Length | Format-Table -AutoSize | Out-String
    } else {
        "  MISSING: $ps1"
    }

    '---- Running SetRes.ps1 -List ----'
    if (Test-Path $ps1) {
        & $ps1 -List
    } else {
        "  Skipped, SetRes.ps1 not found."
    }
} *>&1 | Tee-Object -FilePath $log

Write-Host ''
Write-Host "Log written to: $log" -ForegroundColor Cyan
