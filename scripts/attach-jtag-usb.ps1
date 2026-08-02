# scripts/attach-jtag-usb.ps1
# Attaches USB JTAG programming boards to a WSL2 instance via usbipd-win.
#
# Prerequisites:
#   winget install usbipd                      # install usbipd-win
#
# Usage (run from an elevated PowerShell):
#   .\scripts\attach-jtag-usb.ps1                          # attach to default instance
#   .\scripts\attach-jtag-usb.ps1 -Distro wsl-fpga-dev    # attach to named instance
#   .\scripts\attach-jtag-usb.ps1 -List                    # show all USB devices

param(
    [string]$Distro = "wsl-fpga-dev",
    [switch]$List
)

$ErrorActionPreference = "Stop"

# ── Check usbipd is installed ─────────────────────────────────────────────────
if (-not (Get-Command usbipd -ErrorAction SilentlyContinue)) {
    Write-Host "usbipd not found. Install it with:" -ForegroundColor Red
    Write-Host "  winget install usbipd"
    exit 1
}

# ── List mode ─────────────────────────────────────────────────────────────────
if ($List) {
    Write-Host "=== USB devices visible to Windows ===" -ForegroundColor Cyan
    usbipd list
    Write-Host ""
    Write-Host "To attach a device:  .\scripts\attach-jtag-usb.ps1 -Distro $Distro"
    exit 0
}

# ── Known JTAG device VID:PID patterns ───────────────────────────────────────
# Used to auto-detect boards when no BUSID is specified.
$knownBoards = @(
    @{ Name = "Intel USB-Blaster (original)";    VidPid = "09fb:6001" },
    @{ Name = "Intel USB-Blaster II";            VidPid = "09fb:6010" },
    @{ Name = "Intel USB-Blaster+ / Arrow";      VidPid = "09fb:6810" },
    @{ Name = "Digilent JTAG-HS2 / HS3";        VidPid = "0403:6014" },
    @{ Name = "Digilent general (FTDI)";         VidPid = "0403:6010" },
    @{ Name = "Xilinx Platform Cable USB II";    VidPid = "03fd:0013" }
)

Write-Host "=== attach-jtag-usb.ps1 (target: $Distro) ===" -ForegroundColor Cyan

# Get raw usbipd device list
$usbOutput = usbipd list 2>&1 | Out-String

$attached = 0
foreach ($board in $knownBoards) {
    if ($usbOutput -match $board.VidPid) {
        # Extract the BUSID from the line containing this VID:PID
        $line = ($usbOutput -split "`n") | Where-Object { $_ -match $board.VidPid } | Select-Object -First 1
        if ($line -match '^\s*(\d+-\d+)') {
            $busid = $Matches[1]
            Write-Host "Found: $($board.Name) at BUSID $busid" -ForegroundColor Green
            Write-Host "  Attaching to WSL2 instance '$Distro'..." -ForegroundColor Yellow
            usbipd attach --wsl $Distro --busid $busid
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Attached." -ForegroundColor Green
                $attached++
            } else {
                Write-Host "  Attach failed (is the instance running? Is this an elevated shell?)" -ForegroundColor Red
            }
        }
    }
}

if ($attached -eq 0) {
    Write-Host ""
    Write-Host "No known JTAG boards found. All devices:" -ForegroundColor Yellow
    usbipd list
    Write-Host ""
    Write-Host "To attach manually:"
    Write-Host "  usbipd attach --wsl $Distro --busid <BUSID>"
} else {
    Write-Host ""
    Write-Host "$attached board(s) attached. Verify inside WSL2:" -ForegroundColor Green
    Write-Host "  wsl -d $Distro -- lsusb"
    Write-Host "  wsl -d $Distro -- ls /dev/bus/usb/"
}

Write-Host ""
Write-Host "Note: This attachment is session-scoped. Re-run after each" -ForegroundColor DarkGray
Write-Host "      board reconnect or WSL2 restart." -ForegroundColor DarkGray
