<#
.SYNOPSIS
    Change the Windows display mode (resolution + refresh rate) from the
    command line, via the Win32 ChangeDisplaySettingsEx API.

.DESCRIPTION
    No dependencies beyond Windows PowerShell 5.1. Enumerates the modes the
    display driver actually exposes, validates the requested mode with a
    CDS_TEST pass, then commits it with CDS_UPDATEREGISTRY so it survives a
    reboot.

.EXAMPLE
    .\SetRes.ps1 -List
.EXAMPLE
    .\SetRes.ps1 -Width 3840 -Height 2160 -Refresh 120
.EXAMPLE
    .\SetRes.ps1 -Toggle -A 7680x2160@120 -B 3840x2160@120
.EXAMPLE
    .\SetRes.ps1 -List -Device '\\.\DISPLAY2'
#>

[CmdletBinding(DefaultParameterSetName = 'Toggle')]
param(
    # --- Explicit mode ---
    [Parameter(ParameterSetName = 'Explicit', Mandatory = $true)]
    [int]$Width,

    [Parameter(ParameterSetName = 'Explicit', Mandatory = $true)]
    [int]$Height,

    [Parameter(ParameterSetName = 'Explicit')]
    [int]$Refresh = 0,

    # --- Toggle mode ---
    [Parameter(ParameterSetName = 'Toggle')]
    [switch]$Toggle,

    # Toggle endpoints, format WIDTHxHEIGHT@HZ. Override these to make the
    # toggle fit your own displays.
    [Parameter(ParameterSetName = 'Toggle')]
    [string]$A = '7680x2160@120',

    [Parameter(ParameterSetName = 'Toggle')]
    [string]$B = '3840x2160@120',

    # --- Diagnostics ---
    [Parameter(ParameterSetName = 'List')]
    [switch]$List,

    # --- Common ---
    # Target device, e.g. '\\.\DISPLAY2'. Defaults to the primary display.
    [string]$Device = '',

    [int]$Bpp = 32
)

$ErrorActionPreference = 'Stop'

Add-Type -Namespace Win32 -Name Disp -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion;
    public short dmDriverVersion;
    public short dmSize;
    public short dmDriverExtra;
    public int   dmFields;
    public int   dmPositionX;
    public int   dmPositionY;
    public int   dmDisplayOrientation;
    public int   dmDisplayFixedOutput;
    public short dmColor;
    public short dmDuplex;
    public short dmYResolution;
    public short dmTTOption;
    public short dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels;
    public int   dmBitsPerPel;
    public int   dmPelsWidth;
    public int   dmPelsHeight;
    public int   dmDisplayFlags;
    public int   dmDisplayFrequency;
    public int   dmICMMethod;
    public int   dmICMIntent;
    public int   dmMediaType;
    public int   dmDitherType;
    public int   dmReserved1;
    public int   dmReserved2;
    public int   dmPanningWidth;
    public int   dmPanningHeight;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
public struct DISPLAY_DEVICE {
    public int cb;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]  public string DeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
    public int StateFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
}

[DllImport("user32.dll", CharSet = CharSet.Ansi)]
public static extern bool EnumDisplaySettings(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);

[DllImport("user32.dll", CharSet = CharSet.Ansi)]
public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, int dwFlags, IntPtr lParam);

// IntPtr overload: PowerShell coerces $null to "" when binding to a string
// parameter, so a genuine NULL for lpDevice must be passed as IntPtr.Zero.
[DllImport("user32.dll", CharSet = CharSet.Ansi, EntryPoint = "EnumDisplayDevicesA")]
public static extern bool EnumDisplayDevicesNull(IntPtr lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
'@

$ENUM_CURRENT_SETTINGS  = -1
$DM_BITSPERPEL          = 0x00040000
$DM_PELSWIDTH           = 0x00080000
$DM_PELSHEIGHT          = 0x00100000
$DM_DISPLAYFREQUENCY    = 0x00400000
$CDS_UPDATEREGISTRY     = 0x00000001
$CDS_TEST               = 0x00000002
$DD_ATTACHED_TO_DESKTOP = 0x00000001
$DD_PRIMARY_DEVICE      = 0x00000004

function Fail([string]$msg) {
    Write-Host $msg -ForegroundColor Red
    # Launchers may run without a visible console, so mirror failures to a dialog.
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show($msg, 'SetRes', 'OK', 'Error')
    } catch { }
    exit 1
}

trap {
    Fail ("Unhandled error at line " + $_.InvocationInfo.ScriptLineNumber + ":`n" + $_.Exception.Message)
}

function ConvertFrom-ModeString([string]$s) {
    # Accepts 3840x2160@120 or 3840x2160
    if ($s -notmatch '^\s*(\d+)\s*[xX]\s*(\d+)\s*(?:@\s*(\d+))?\s*$') {
        Fail "Invalid mode string '$s'. Expected WIDTHxHEIGHT@HZ, e.g. 3840x2160@120."
    }
    return [pscustomobject]@{
        W = [int]$Matches[1]
        H = [int]$Matches[2]
        R = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
    }
}

function Get-Adapters {
    $out  = @()
    $size = [System.Runtime.InteropServices.Marshal]::SizeOf([type][Win32.Disp+DISPLAY_DEVICE])
    $i = 0
    while ($true) {
        $dd = New-Object Win32.Disp+DISPLAY_DEVICE
        $dd.cb = $size
        if (-not [Win32.Disp]::EnumDisplayDevicesNull([IntPtr]::Zero, $i, [ref]$dd, 0)) { break }
        $out += [pscustomobject]@{
            Name     = $dd.DeviceName
            Adapter  = $dd.DeviceString
            Attached = [bool]($dd.StateFlags -band $DD_ATTACHED_TO_DESKTOP)
            Primary  = [bool]($dd.StateFlags -band $DD_PRIMARY_DEVICE)
        }
        $i++
        if ($i -gt 64) { break }
    }
    return $out
}

function Get-CurrentModeOrNull([string]$dev) {
    $dm = New-Object Win32.Disp+DEVMODE
    # [int16], not [short] - the latter is not a Windows PowerShell 5.1 accelerator.
    $dm.dmSize = [int16][System.Runtime.InteropServices.Marshal]::SizeOf([type][Win32.Disp+DEVMODE])
    if ([Win32.Disp]::EnumDisplaySettings($dev, $ENUM_CURRENT_SETTINGS, [ref]$dm)) {
        if ($dm.dmPelsWidth -gt 0) { return $dm }
    }
    return $null
}

function Get-PrimaryDeviceName {
    # Path 1: adapter enumeration.
    $primary = Get-Adapters | Where-Object { $_.Attached -and $_.Primary } | Select-Object -First 1
    if ($primary) { return $primary.Name }

    # Path 2 (fallback): probe \\.\DISPLAYn and take whichever is at desktop origin.
    $atOrigin = $null
    $anyLive  = $null
    for ($n = 1; $n -le 16; $n++) {
        $dev = "\\.\DISPLAY$n"
        $dm = Get-CurrentModeOrNull $dev
        if ($dm) {
            if (-not $anyLive) { $anyLive = $dev }
            if ($dm.dmPositionX -eq 0 -and $dm.dmPositionY -eq 0) { $atOrigin = $dev; break }
        }
    }
    if ($atOrigin) { return $atOrigin }
    if ($anyLive)  { return $anyLive }
    return $null
}

function Get-CurrentMode([string]$dev) {
    $dm = Get-CurrentModeOrNull $dev
    if (-not $dm) { Fail "EnumDisplaySettings returned no current mode for '$dev'." }
    return $dm
}

function Get-AllModes([string]$dev) {
    $modes = @()
    $size  = [System.Runtime.InteropServices.Marshal]::SizeOf([type][Win32.Disp+DEVMODE])
    $i = 0
    while ($true) {
        $dm = New-Object Win32.Disp+DEVMODE
        $dm.dmSize = [int16]$size
        if (-not [Win32.Disp]::EnumDisplaySettings($dev, $i, [ref]$dm)) { break }
        $modes += [pscustomobject]@{
            Width   = $dm.dmPelsWidth
            Height  = $dm.dmPelsHeight
            Bpp     = $dm.dmBitsPerPel
            Refresh = $dm.dmDisplayFrequency
        }
        $i++
    }
    return $modes
}

function Set-Mode([string]$dev, [int]$w, [int]$h, [int]$r, [int]$bpp) {
    $modes = Get-AllModes $dev
    $match = $modes | Where-Object {
        $_.Width -eq $w -and $_.Height -eq $h -and $_.Bpp -eq $bpp -and ($r -eq 0 -or $_.Refresh -eq $r)
    }

    if (-not $match) {
        $near = ($modes | Where-Object { $_.Width -eq $w -and $_.Height -eq $h } |
                 Select-Object -ExpandProperty Refresh -Unique | Sort-Object) -join ', '
        if ($near) {
            Fail "$w x $h @ ${r}Hz is not enumerated for $dev. Available refresh rates at $w x ${h}: $near Hz."
        } else {
            Fail "$w x $h is not enumerated for $dev. Run with -List to see all modes."
        }
    }

    $dm = Get-CurrentMode $dev
    $dm.dmPelsWidth  = $w
    $dm.dmPelsHeight = $h
    $dm.dmBitsPerPel = $bpp
    $dm.dmFields     = $DM_PELSWIDTH -bor $DM_PELSHEIGHT -bor $DM_BITSPERPEL
    if ($r -gt 0) {
        $dm.dmDisplayFrequency = $r
        $dm.dmFields = $dm.dmFields -bor $DM_DISPLAYFREQUENCY
    }

    $test = [Win32.Disp]::ChangeDisplaySettingsEx($dev, [ref]$dm, [IntPtr]::Zero, $CDS_TEST, [IntPtr]::Zero)
    if ($test -ne 0) { Fail "Mode rejected in test pass (DISP_CHANGE code $test)." }

    $res = [Win32.Disp]::ChangeDisplaySettingsEx($dev, [ref]$dm, [IntPtr]::Zero, $CDS_UPDATEREGISTRY, [IntPtr]::Zero)
    switch ($res) {
        0       { Write-Host "$dev -> $w x $h @ ${r}Hz" -ForegroundColor Green; return }
        1       { Write-Host "$dev -> $w x $h @ ${r}Hz (restart required)" -ForegroundColor Yellow; return }
        default { Fail "ChangeDisplaySettingsEx failed (DISP_CHANGE code $res)." }
    }
}

# --- main -------------------------------------------------------------------

if (-not $Device) {
    $Device = Get-PrimaryDeviceName
    if (-not $Device) {
        Fail 'Could not resolve the primary display device. Run with -List for diagnostics.'
    }
}

if ($List) {
    Write-Host '--- Adapters (EnumDisplayDevices) ---'
    $adapters = Get-Adapters
    if ($adapters) { $adapters | Format-Table Name, Adapter, Attached, Primary -AutoSize }
    else { Write-Host '  (none returned)' -ForegroundColor Yellow }

    Write-Host '--- Live \\.\DISPLAYn probe ---'
    for ($n = 1; $n -le 16; $n++) {
        $d = "\\.\DISPLAY$n"
        $m = Get-CurrentModeOrNull $d
        if ($m) {
            Write-Host ('  {0}  {1}x{2} @ {3}Hz  pos=({4},{5})' -f $d, $m.dmPelsWidth, $m.dmPelsHeight, $m.dmDisplayFrequency, $m.dmPositionX, $m.dmPositionY)
        }
    }

    $cur = Get-CurrentMode $Device
    Write-Host "`nSelected: $Device  ($($cur.dmPelsWidth) x $($cur.dmPelsHeight) @ $($cur.dmDisplayFrequency)Hz, $($cur.dmBitsPerPel)bpp)`n"
    Get-AllModes $Device |
        Where-Object { $_.Bpp -eq 32 } |
        Sort-Object -Property Width, Height, Refresh -Descending |
        Format-Table Width, Height, Refresh, Bpp -AutoSize
    exit 0
}

if ($PSCmdlet.ParameterSetName -eq 'Explicit') {
    Set-Mode $Device $Width $Height $Refresh $Bpp
    exit 0
}

# Toggle (default parameter set)
$mA  = ConvertFrom-ModeString $A
$mB  = ConvertFrom-ModeString $B
$cur = Get-CurrentMode $Device

if ($cur.dmPelsWidth -eq $mA.W -and $cur.dmPelsHeight -eq $mA.H) {
    Set-Mode $Device $mB.W $mB.H $mB.R $Bpp
} else {
    Set-Mode $Device $mA.W $mA.H $mA.R $Bpp
}
