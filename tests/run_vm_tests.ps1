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
$BuildPy = Join-Path $RepoRoot "environments\build.py"

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
} elseif ($Machines.Count -gt 0) {
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

    $Env:PYTHONIOENCODING = "utf-8"
    $Env:NO_COLOR = "1"
    
    Write-Host "Ensuring clean state (destroying any existing VM)..."
    if ($ShowLog) {
        & .venv\Scripts\python.exe $BuildPy destroy $machine *>&1 | Tee-Object -FilePath $Log
    } else {
        & .venv\Scripts\python.exe $BuildPy destroy $machine *>&1 > $Log
    }

    # 1. Create VM using native Python
    Write-Host "Creating VM..."
    if ($ShowLog) {
        if ($Gui) {
            & .venv\Scripts\python.exe $BuildPy create $machine --gui *>&1 | Tee-Object -FilePath $Log -Append
        } else {
            & .venv\Scripts\python.exe $BuildPy create $machine *>&1 | Tee-Object -FilePath $Log -Append
        }
    } else {
        if ($Gui) {
            & .venv\Scripts\python.exe $BuildPy create $machine --gui *>&1 >> $Log
        } else {
            & .venv\Scripts\python.exe $BuildPy create $machine *>&1 >> $Log
        }
    }
    $CreateExit = $LASTEXITCODE

    if ($CreateExit -eq 0) {
        # Get dynamic IP of the machine
        $VMIP = (& .venv\Scripts\python.exe $BuildPy ip $machine).Trim()

        # 2. Provision using WSL Ansible (since Windows can't run ansible control node natively)
        Write-Host "Provisioning with Ansible..."
        if ($ShowLog) {
            & wsl -d Ubuntu bash -c "cd /mnt/d/workspace/workstation && ANSIBLE_NOCOLOR=1 ANSIBLE_CONFIG=/mnt/d/workspace/workstation/ansible.cfg ANSIBLE_HOST_KEY_CHECKING=False ANSIBLE_SSH_ARGS='-o ControlMaster=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' ansible-playbook provisioning/site.yml -i provisioning/inventory -i '$VMIP,' --limit '$VMIP' -u vagrant -e ansible_port=22 -e profile=headless 2>&1" | Tee-Object -FilePath $Log -Append
        } else {
            & wsl -d Ubuntu bash -c "cd /mnt/d/workspace/workstation && ANSIBLE_NOCOLOR=1 ANSIBLE_CONFIG=/mnt/d/workspace/workstation/ansible.cfg ANSIBLE_HOST_KEY_CHECKING=False ANSIBLE_SSH_ARGS='-o ControlMaster=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' ansible-playbook provisioning/site.yml -i provisioning/inventory -i '$VMIP,' --limit '$VMIP' -u vagrant -e ansible_port=22 -e profile=headless 2>&1" >> $Log
        }
        $AnsibleExit = $LASTEXITCODE
    } else {
        $AnsibleExit = 1
    }

    # 3. Destroy VM using native Python
    Write-Host "Destroying VM..."
    if ($ShowLog) {
        & .venv\Scripts\python.exe $BuildPy destroy $machine *>&1 | Tee-Object -FilePath $Log -Append
    } else {
        & .venv\Scripts\python.exe $BuildPy destroy $machine *>&1 >> $Log
    }

    if ($CreateExit -eq 0 -and $AnsibleExit -eq 0) {
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
