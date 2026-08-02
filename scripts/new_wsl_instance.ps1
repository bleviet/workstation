# scripts/new_wsl_instance.ps1
# Creates a new named WSL2 instance from a wsl.yml spec file, then provisions
# it by running the Ansible playbook inside the instance via community.general.wsl.
#
# Prerequisites:
#   - WSL2 enabled (wsl --install)
#   - A base distro installed (e.g. Ubuntu 24.04 from the Microsoft Store)
#   - ansible-core >= 2.17 installed on the host or in an existing WSL instance
#
# Usage:
#   .\scripts\new_wsl_instance.ps1 -SpecFile local-vms\wsl-dev-ubuntu26\wsl.yml
#   .\scripts\new_wsl_instance.ps1 -SpecFile local-vms\wsl-fpga-dev\wsl.yml -Provision
#
# After creation, enable the host in ansible/inventory/hosts.yml:
#   wsl_instances:
#     hosts:
#       wsl-dev-ubuntu26:

param(
    [Parameter(Mandatory = $true)]
    [string]$SpecFile,

    [switch]$Provision,   # also run the Ansible playbook after creation
    [switch]$Force        # re-create the instance if it already exists
)

$ErrorActionPreference = "Stop"

# ── Load spec ────────────────────────────────────────────────────────────────
if (-not (Test-Path $SpecFile)) {
    Write-Error "Spec file not found: $SpecFile"
    exit 1
}

# Parse the minimal YAML by hand (no external dependency required).
$spec = @{}
Get-Content $SpecFile | Where-Object { $_ -match '^\s*\w' -and $_ -notmatch '^\s*#' } | ForEach-Object {
    if ($_ -match '^\s*(\w[\w_-]*)\s*:\s*"?([^"#]*)"?\s*$') {
        $spec[$Matches[1].Trim()] = $Matches[2].Trim()
    }
}

$InstanceName    = $spec["name"]
$OS              = $spec["os"]
$InstallLocation = $spec["install_location"] -replace '/', '\'

if (-not $InstanceName) { Write-Error "spec missing 'name'"; exit 1 }
if (-not $OS)           { Write-Error "spec missing 'os'"; exit 1 }

# ── Map OS name → base distro ─────────────────────────────────────────────────
# The base distro must already be installed (wsl --list shows it).
# The instance is stamped from an export of the base distro, keeping the base
# distro clean for future stamps.
$osBaseMap = @{
    "ubuntu2404" = "Ubuntu-24.04"
    "ubuntu2604" = "Ubuntu-26.04"
    "debian13"   = "Debian"
}

$BaseDistro = $osBaseMap[$OS]
if (-not $BaseDistro) {
    Write-Error "Unknown OS '$OS'. Available: $($osBaseMap.Keys -join ', ')"
    exit 1
}

Write-Host "=== new_wsl_instance.ps1 ===" -ForegroundColor Cyan
Write-Host "Instance : $InstanceName"
Write-Host "OS       : $OS (base: $BaseDistro)"
Write-Host "Location : $InstallLocation"

# ── Check if instance already exists ─────────────────────────────────────────
$existing = wsl --list --quiet 2>$null | Where-Object { $_.Trim() -eq $InstanceName }
if ($existing) {
    if ($Force) {
        Write-Host "Instance '$InstanceName' exists — removing (--Force)..." -ForegroundColor Yellow
        wsl --terminate $InstanceName 2>$null
        wsl --unregister $InstanceName
    } else {
        Write-Host "Instance '$InstanceName' already exists. Use -Force to recreate." -ForegroundColor Yellow
        exit 0
    }
}

# ── Export the base distro to a temporary tarball ─────────────────────────────
$TmpDir    = Join-Path $env:TEMP "wsl-stamp"
$TarPath   = Join-Path $TmpDir "$BaseDistro.tar.gz"

if (-not (Test-Path $TarPath)) {
    New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null
    Write-Host "Exporting base distro '$BaseDistro' to tarball (first time only)..." -ForegroundColor Yellow
    wsl --export $BaseDistro $TarPath
    if ($LASTEXITCODE -ne 0) {
        Write-Error "wsl --export failed. Is '$BaseDistro' installed? (wsl --list)"
        exit 1
    }
}

# ── Import the new instance ───────────────────────────────────────────────────
if ($InstallLocation) {
    New-Item -ItemType Directory -Force -Path $InstallLocation | Out-Null
} else {
    $InstallLocation = Join-Path $env:USERPROFILE "AppData\Local\WSL\$InstanceName"
    New-Item -ItemType Directory -Force -Path $InstallLocation | Out-Null
}

Write-Host "Importing '$InstanceName'..." -ForegroundColor Yellow
wsl --import $InstanceName $InstallLocation $TarPath --version 2
if ($LASTEXITCODE -ne 0) {
    Write-Error "wsl --import failed."
    exit 1
}

Write-Host "Instance '$InstanceName' created successfully." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Enable it in ansible/inventory/hosts.yml under wsl_instances:"
Write-Host "       $InstanceName`:"
Write-Host "  2. Add host_vars/inventory/host_vars/$InstanceName.yml"
Write-Host "  3. Provision it:"

if ($Provision) {
    Write-Host ""
    Write-Host "Running Ansible provisioning..." -ForegroundColor Yellow
    $RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

    # Run bootstrap inside the new instance first (installs ansible-core)
    wsl -d $InstanceName -- bash -c "cd /mnt/$(($RepoRoot -replace '\\', '/' -replace ':', '').ToLower()) && ./bootstrap.sh"
} else {
    Write-Host "     ansible-playbook ansible/site.yml -l $InstanceName"
    Write-Host ""
    Write-Host "Or provision from inside the instance:"
    Write-Host "     wsl -d $InstanceName"
    Write-Host "     ./bootstrap.sh"
}
