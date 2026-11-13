#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures Windows OpenSSH Server (port 22) and forwards port 2222 to WSL2 SSH
    so other devices on the local network can SSH into both Windows and WSL.

.PARAMETER WslPort
    Port for WSL2 SSH forwarding (default: 2222). Must match WSL sshd Port.

.PARAMETER WslDistro
    Optional WSL distribution name. If omitted, uses your default WSL distro.

.PARAMETER AllowPublicProfile
    Allow inbound SSH on Windows Firewall Public profile in addition to Private/Domain.
    Use only if your trusted LAN is currently marked as a Public network in Windows.

.EXAMPLE
    .\scripts\setup-windows-ssh.ps1

.EXAMPLE
    .\scripts\setup-windows-ssh.ps1 -WslDistro wsl-fpga-dev

.EXAMPLE
    .\scripts\setup-windows-ssh.ps1 -WslDistro wsl-dev-ubuntu26 -WslPort 2222 -AllowPublicProfile
#>
param(
    [int]$WslPort = 2222,
    [string]$WslDistro = "",
    [switch]$AllowPublicProfile
)

$ErrorActionPreference = "Stop"

Write-Host "[1/6] Checking OpenSSH Server capability..." -ForegroundColor Cyan
$cap = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" } | Select-Object -First 1
if (-not $cap) {
    throw "OpenSSH.Server Windows capability was not found on this system."
}
if ($cap.State -ne "Installed") {
    Write-Host "Installing $($cap.Name)..."
    Add-WindowsCapability -Online -Name $cap.Name | Out-Null
} else {
    Write-Host "OpenSSH.Server is already installed."
}

Write-Host "[2/6] Enabling and starting sshd and ssh-agent services..." -ForegroundColor Cyan
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service ssh-agent

Write-Host "[3/6] Verifying Windows sshd_config and authorized_keys permissions..." -ForegroundColor Cyan
$sshdConfigPath = "$env:ProgramData\ssh\sshd_config"
if (Test-Path $sshdConfigPath) {
    $config = Get-Content $sshdConfigPath -Raw
    $modified = $false

    if ($config -match '(?m)^\s*PasswordAuthentication\s+no\b') {
        $config = $config -replace '(?m)^\s*PasswordAuthentication\s+no\b', 'PasswordAuthentication yes'
        $modified = $true
    }
    if ($config -match '(?m)^\s*PubkeyAuthentication\s+no\b') {
        $config = $config -replace '(?m)^\s*PubkeyAuthentication\s+no\b', 'PubkeyAuthentication yes'
        $modified = $true
    }

    if ($modified) {
        [System.IO.File]::WriteAllText($sshdConfigPath, $config, (New-Object System.Text.UTF8Encoding $false))
        Restart-Service sshd
        Write-Host "Updated sshd_config and restarted sshd."
    }
}

# Windows OpenSSH uses ProgramData\ssh\administrators_authorized_keys for users in Administrators
$adminKeysPath = "$env:ProgramData\ssh\administrators_authorized_keys"
if (-not (Test-Path $adminKeysPath)) {
    New-Item -ItemType File -Path $adminKeysPath -Force | Out-Null
}
# Enforce required strict ACLs (SYSTEM and Administrators only, using locale-independent SIDs)
icacls $adminKeysPath /inheritance:r /grant "*S-1-5-18:F" /grant "*S-1-5-32-544:F" | Out-Null

# Also ensure current user's ~/.ssh/authorized_keys exists (used if not in Administrators group)
$userSshDir = Join-Path $env:USERPROFILE ".ssh"
$userKeysPath = Join-Path $userSshDir "authorized_keys"
if (-not (Test-Path $userSshDir)) {
    New-Item -ItemType Directory -Path $userSshDir -Force | Out-Null
}
if (-not (Test-Path $userKeysPath)) {
    New-Item -ItemType File -Path $userKeysPath -Force | Out-Null
}

Write-Host "[4/6] Configuring Windows Firewall rules..." -ForegroundColor Cyan
$profiles = if ($AllowPublicProfile) { @("Private", "Domain", "Public") } else { @("Private", "Domain") }

$activeProfiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
$publicActive = $activeProfiles | Where-Object { $_.NetworkCategory -eq "Public" }
if ($publicActive -and -not $AllowPublicProfile) {
    Write-Warning ("Active network '$($publicActive.Name -join ', ')' is set to Public. " +
        "Either switch it to Private in Windows Settings, or re-run with -AllowPublicProfile.")
}

# Remove existing custom rules if re-running, then create clean rules
foreach ($ruleName in @("Windows-SSH-LAN-22", "WSL2-SSH-LAN-$WslPort")) {
    Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
}

New-NetFirewallRule `
    -Name "Windows-SSH-LAN-22" `
    -DisplayName "OpenSSH Server LAN (Port 22)" `
    -Enabled True `
    -Direction Inbound `
    -Protocol TCP `
    -Action Allow `
    -LocalPort 22 `
    -Profile $profiles | Out-Null

New-NetFirewallRule `
    -Name "WSL2-SSH-LAN-$WslPort" `
    -DisplayName "WSL2 SSH Server LAN (Port $WslPort)" `
    -Enabled True `
    -Direction Inbound `
    -Protocol TCP `
    -Action Allow `
    -LocalPort $WslPort `
    -Profile $profiles | Out-Null

Write-Host "[5/6] Configuring portproxy from Windows (:$WslPort) to WSL2 (:$WslPort)..." -ForegroundColor Cyan
Set-Service -Name iphlpsvc -StartupType Automatic
Start-Service iphlpsvc

function Get-WslDistroList {
    param([switch]$RunningOnly)

    $wslArgs = if ($RunningOnly) { @("-l", "--running", "-q") } else { @("-l", "-q") }

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $raw = & wsl @wslArgs 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) {
            return @()
        }
    } finally {
        $ErrorActionPreference = $prevEap
    }

    $distros = @()
    foreach ($line in $raw) {
        $clean = ($line -replace "`0", "").Replace([string][char]0xFEFF, "").Trim()
        if ($clean -and $clean -notmatch '^docker-desktop(-data)?$') {
            $distros += $clean
        }
    }
    return $distros
}

function Get-Ipv4FromWslCommand {
    param([string]$Distro)

    $baseArgs = if ($Distro) { @("-d", $Distro) } else { @() }

    $wslRaw = & wsl @baseArgs hostname -I 2>$null
    if ($LASTEXITCODE -eq 0) {
        $ip = ($wslRaw -split '\s+') | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        if ($ip) { return $ip }
    }

    $ipRaw = & wsl @baseArgs ip -4 -o addr show scope global 2>$null
    if ($LASTEXITCODE -eq 0 -and ($ipRaw -join "`n") -match 'inet\s+(\d+\.\d+\.\d+\.\d+)/') {
        return $Matches[1]
    }

    return $null
}

function Get-WslIpv4Address {
    param(
        [string]$DistroName,
        [string]$InferredDistro
    )

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($DistroName) {
        $candidates.Add($DistroName)
    } else {
        if ($InferredDistro) {
            $candidates.Add($InferredDistro)
        }
        foreach ($d in (Get-WslDistroList -RunningOnly)) {
            if (-not $candidates.Contains($d)) { $candidates.Add($d) }
        }
        foreach ($d in (Get-WslDistroList)) {
            if (-not $candidates.Contains($d)) { $candidates.Add($d) }
        }
    }

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        if ($candidates.Count -eq 0) {
            $ip = Get-Ipv4FromWslCommand
            if ($ip) { return @{ Ip = $ip; Distro = "(default)" } }
            return $null
        }

        foreach ($distro in $candidates) {
            $ip = Get-Ipv4FromWslCommand -Distro $distro
            if ($ip) {
                return @{ Ip = $ip; Distro = $distro }
            }
        }
    } finally {
        $ErrorActionPreference = $prevEap
    }

    return $null
}

$inferredDistro = if ($PSCommandPath -match '^\\\\(?:wsl\$|wsl\.localhost)\\([^\\]+)\\') {
    $Matches[1]
} else {
    ""
}

$wslResult = Get-WslIpv4Address -DistroName $WslDistro -InferredDistro $inferredDistro
if (-not $wslResult) {
    if ($WslDistro) {
        throw "Could not determine WSL2 IPv4 address for distro '$WslDistro'. Check 'wsl -l -v' and ensure the distro exists and is healthy."
    }
    throw ("Could not determine WSL2 IPv4 address. If your default WSL distro is docker-desktop/docker-desktop-data, " +
        "re-run with '-WslDistro <DistroName>' (e.g. -WslDistro Ubuntu) or run 'wsl --set-default <DistroName>'.")
}
$wslIp = $wslResult.Ip

$hostIps = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
if ($hostIps -contains $wslIp) {
    Write-Host "WSL appears to share host IP ($wslIp) (mirrored mode); skipping portproxy."
} else {
    & netsh interface portproxy delete v4tov4 listenport=$WslPort listenaddress=0.0.0.0 2>&1 | Out-Null
    & netsh interface portproxy add v4tov4 listenport=$WslPort listenaddress=0.0.0.0 connectport=$WslPort connectaddress=$wslIp
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to configure netsh portproxy (exit code $LASTEXITCODE)."
    }
    Write-Host "Portproxy configured: 0.0.0.0:$WslPort -> ${wslIp}:$WslPort"
}

Write-Host "[6/6] Detecting local LAN IPv4 addresses..." -ForegroundColor Cyan
$lanIps = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -notlike "127.*" -and
        $_.IPAddress -notlike "169.254.*" -and
        $_.InterfaceAlias -notlike "vEthernet (WSL*"
    } |
    Select-Object -ExpandProperty IPAddress

Write-Host ""
Write-Host "=== Windows + WSL2 SSH Setup Complete ===" -ForegroundColor Green
Write-Host "Windows user : $env:USERNAME"
Write-Host "WSL2 distro  : $($wslResult.Distro)"
Write-Host "WSL2 IP      : $wslIp"
Write-Host "LAN IP(s)    : $($lanIps -join ', ')"
Write-Host ""
$exampleIp = if ($lanIps) { $lanIps | Select-Object -First 1 } else { "<YOUR_LAN_IP>" }
Write-Host "Teammates on your local network can connect with:"
Write-Host "  Windows : ssh $env:USERNAME@$exampleIp"
Write-Host "  WSL2    : ssh -p $WslPort <wsl_username>@$exampleIp"
Write-Host ""
Write-Host "Notes:"
Write-Host "  - For Windows key login (Admin account), add public keys to: $adminKeysPath"
Write-Host "  - For Windows key login (Standard account), add public keys to: $userKeysPath"
Write-Host "  - WSL2's internal IP changes after a reboot/wsl --shutdown; re-run this script if port $WslPort stops connecting."
Write-Host "  - Slow/stalling Xpra or large transfers from WSL2? Run .\scripts\optimize-windows-network.ps1 (LSOv2/RSC off)."
