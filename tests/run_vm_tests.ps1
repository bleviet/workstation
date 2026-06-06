param (
    [switch]$All,
    [switch]$Desktop,
    [string[]]$Machines,
    [switch]$ShowLog,
    [switch]$Gui
)

$ErrorActionPreference = "Continue"

# Configure UTF-8 encoding for console output and file redirection to prevent "weird characters"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")


$HeadlessMachines = @(
    "workstation-test-debian"
    "workstation-test-ubuntu24"
    "workstation-test-ubuntu26"
    "workstation-test-alma9"
    "workstation-test-alma10"
)
$DesktopMachines = @(
    "workstation-test-debian-i3wm"
    "workstation-test-ubuntu24-i3wm"
    "workstation-test-ubuntu26-i3wm"
    "workstation-test-alma9-i3wm"
    "workstation-test-alma10-i3wm"
)

if ($All) {
    $TargetMachines = $HeadlessMachines + $DesktopMachines
} elseif ($Desktop) {
    $TargetMachines = $DesktopMachines
} elseif ($Machines -and $Machines.Count -gt 0) {
    $TargetMachines = $Machines
} else {
    $TargetMachines = $HeadlessMachines
}

$Pass = 0
$Fail = 0

foreach ($machine in $TargetMachines) {
    $Log = "$env:TEMP\workstation-vm-$machine.log"
    Write-Host ""
    Write-Host "=== [$machine] ==="

    $Env:VAGRANT_NO_COLOR = "1"
    
    Write-Host "Ensuring clean state (destroying any existing VM)..."
    if ($ShowLog) {
        & vagrant destroy -f $machine *>&1 | Tee-Object -FilePath $Log
    } else {
        & vagrant destroy -f $machine *>&1 > $Log
    }

    # 1. Create and provision VM using Vagrant
    Write-Host "Creating and provisioning VM via Vagrant..."
    if ($ShowLog) {
        & vagrant up $machine *>&1 | Tee-Object -FilePath $Log -Append
    } else {
        & vagrant up $machine *>&1 >> $Log
    }
    $CreateExit = $LASTEXITCODE

    # 2. Destroy VM using Vagrant
    Write-Host "Destroying VM..."
    if ($ShowLog) {
        & vagrant destroy -f $machine *>&1 | Tee-Object -FilePath $Log -Append
    } else {
        & vagrant destroy -f $machine *>&1 >> $Log
    }

    if ($CreateExit -eq 0) {
        Write-Host "[$machine] PASS"
        $Pass++
    } else {
        Write-Host "[$machine] FAIL - see $Log"
        $Fail++
    }
}

Write-Host ""
Write-Host "Results: $Pass passed, $Fail failed"

if ($Fail -gt 0) {
    exit 1
}
