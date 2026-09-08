# SetRes

One-click display resolution and refresh-rate switching for Windows 11.

Windows has no built-in way to jump straight to a saved display mode. You go
Settings → System → Display, change resolution, change refresh rate, confirm.
This repo reduces that to double-clicking a `.bat` file, or pressing a hotkey.

It is a thin PowerShell wrapper around the same Win32 API the Settings app
itself calls — `ChangeDisplaySettingsEx`. No drivers, no services, no
third-party binaries, no installer.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (ships with Windows — nothing to install)
- No administrator rights needed

## Quick start

```
git clone https://github.com/maximedgoulet/Win11ResolutionChanger.git
cd Win11ResolutionChanger
```

Everything resolves paths relative to its own location, so the folder can live
anywhere — Desktop, `C:\Tools`, a USB stick, a synced drive.

See what your display actually supports:

```
Res-Diag.bat
```

Then double-click whichever mode you want:

| File | Applies |
| --- | --- |
| `Res-7680x2160-120.bat` | 7680x2160 @ 120 Hz |
| `Res-5120x1440-120.bat` | 5120x1440 @ 120 Hz |
| `Res-3840x2160-120.bat` | 3840x2160 @ 120 Hz |
| `Res-Toggle.bat` | Flips between two configured modes |
| `Res-Diag.bat` | Environment + supported-mode report |

## Making it yours

The shipped resolutions are examples. To change one, open the `.bat` in any
text editor and edit the three variables at the top:

```bat
set "x=2560"
set "y=1440"
set "r=144"
```

For the toggle, edit the two endpoints (format `WIDTHxHEIGHT@HZ`):

```bat
set "A=3440x1440@175"
set "B=1920x1080@60"
```

Copy a `.bat` and rename it to add more modes. Only the variables at the top
need to change.

## Hotkeys

Right-click a `.bat` → **Send to** → **Desktop (create shortcut)**, then open
the shortcut's **Properties** and set a **Shortcut key**, e.g. `Ctrl+Alt+4`.
Windows only honours hotkeys on shortcuts, not on the `.bat` itself.

To suppress the console window entirely, point the shortcut target directly at
PowerShell instead of at the `.bat`:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\path\to\SetRes.ps1" -Width 3840 -Height 2160 -Refresh 120
```

Note that you lose the on-screen confirmation and error text this way. Errors
still surface as a message box.

## Direct PowerShell use

```powershell
# List adapters, live displays, and every mode the driver exposes
.\SetRes.ps1 -List

# Apply a specific mode to the primary display
.\SetRes.ps1 -Width 3840 -Height 2160 -Refresh 120

# Flip between two modes
.\SetRes.ps1 -Toggle -A 7680x2160@120 -B 3840x2160@120

# Target a secondary display
.\SetRes.ps1 -List -Device '\\.\DISPLAY2'
.\SetRes.ps1 -Width 2560 -Height 1440 -Refresh 144 -Device '\\.\DISPLAY2'
```

| Parameter | Purpose |
| --- | --- |
| `-Width` / `-Height` | Target resolution (required together) |
| `-Refresh` | Target refresh rate in Hz. Omit to accept any |
| `-Toggle` | Flip between `-A` and `-B` |
| `-A` / `-B` | Toggle endpoints, `WIDTHxHEIGHT@HZ` |
| `-List` | Diagnostics and full supported-mode table |
| `-Device` | Target display, e.g. `\\.\DISPLAY2`. Defaults to primary |
| `-Bpp` | Colour depth, default 32 |

Exit code is `0` on success, `1` on failure, so the scripts compose with other
automation.

## How it works

1. `EnumDisplayDevices` finds the primary adapter. If that returns nothing, it
   falls back to probing `\\.\DISPLAY1` through `\\.\DISPLAY16` and selecting
   whichever display reports desktop position `(0,0)`.
2. `EnumDisplaySettings` walks every mode the driver exposes. The requested
   mode is matched against that list, so you get a useful error listing the
   available refresh rates rather than a silent failure.
3. `ChangeDisplaySettingsEx` is called with `CDS_TEST` first. Only if the
   driver accepts the mode is it re-applied with `CDS_UPDATEREGISTRY`, which
   persists it across reboots.

Custom resolutions are out of scope. This selects among modes the driver
already publishes; creating new ones is a driver-level operation (NVIDIA
Control Panel, AMD Adrenalin, CRU).

## Troubleshooting

Run `Res-Diag.bat` first. It writes `SetRes-diag.log` alongside the scripts and
reports PowerShell version, execution policy per scope, file block status, and
the full mode table.

**Nothing happens at all.** Something failed before the error handler could
run. Use `Res-Diag.bat`, which runs in a visible window that stays open.

**"...cannot be loaded because running scripts is disabled".** The launchers
pass `-ExecutionPolicy Bypass`, which covers the normal case. If Group Policy
sets the policy at `MachinePolicy` or `UserPolicy` scope, that flag is ignored
and no command-line workaround applies. `Res-Diag.bat` shows the policy for
every scope.

**Downloaded as a ZIP.** Files carry a `Zone.Identifier` stream (mark of the
web) that can block execution. Clear it once:

```powershell
Unblock-File .\*
```

Cloning with git avoids this entirely.

**"X x Y @ ZHz is not enumerated".** The driver does not publish that mode.
`-List` shows what it does publish. Common causes are cable bandwidth limits,
a display running through a KVM or a passive adapter, or a mode that needs DSC
which the current link configuration cannot negotiate.

**Windows get rearranged after switching.** Resolution changes on displays
using DSC can cause the display to re-train, which Windows sees as a brief
disconnect. Windows are then reflowed onto whatever display remained active.
This is driver behaviour, not something the script can prevent. Tools that
save and restore window layouts, such as NirSoft's MultiMonitorTool, help.

**Picture is stretched after switching to a different aspect ratio.** Scaling
is handled by the monitor and the GPU driver, not by this script. Check the
monitor's on-screen menu for an aspect-ratio or screen-fit setting, and the
scaling mode in your GPU control panel.

## Files

```
SetRes.ps1               Core script. All logic lives here.
Diag.ps1                 Diagnostic report.
Res-*.bat                One-click launchers. Thin wrappers over SetRes.ps1.
Res-Diag.bat             Launcher for Diag.ps1, visible window.
```

## Notes

Multi-monitor setups are supported through `-Device`, but each invocation
changes one display. To reconfigure several at once, chain calls.

The script changes mode only. It does not move windows, change DPI scaling,
alter HDR state, or reposition displays in the desktop layout.
