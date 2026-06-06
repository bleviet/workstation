# Testing

## Container tests (Automated pipeline)

Builds a container per OS in parallel (Podman/Docker, rootless) and executes a robust four-stage testing pipeline:
1. **Syntax Check:** Runs `ansible-playbook --syntax-check` against the playbooks.
2. **Provisioning:** Runs the full Ansible playbook inside the container to verify clean deployment.
3. **Idempotency:** Runs the playbook a second time to ensure zero unhandled changes (`changed=0`).
4. **BATS Unit Tests:** Executes the BATS shell testing framework (`tests/bats/`) against dotfiles functions.

```bash
./tests/run_container_tests.sh
```

## VM tests (full provisioning)

Test VMs are defined in `tests/vm/machines.yml` and managed via **Vagrant**.
Vagrant natively supports multiple providers including VirtualBox, VMware Desktop, and Libvirt.

### Prerequisites

| Tool | Where to get it |
|---|---|
| Vagrant | https://developer.hashicorp.com/vagrant/downloads |
| A hypervisor | VirtualBox (default), VMware Desktop, or Libvirt/KVM |

### Available test machines

| Name | OS | Profile |
|---|---|---|
| `workstation-test-debian` | Debian 13 | headless |
| `workstation-test-ubuntu24` | Ubuntu 24.04 | headless |
| `workstation-test-ubuntu26` | Ubuntu 26.04 | headless |
| `workstation-test-alma9` | AlmaLinux 9 | headless |
| `workstation-test-alma10` | AlmaLinux 10 | headless |
| `workstation-test-*-i3wm` | *OS matched* | desktop-i3wm |
| `workstation-test-*-xfce` | *OS matched* | desktop-xfce |
| `workstation-test-*-gnome` | *OS matched* | desktop-gnome |

### Running tests

#### Linux/macOS

On Linux/macOS, use the shell runner:

```bash
# Headless machines only (default)
./tests/run_vm_tests.sh

# Desktop machines
./tests/run_vm_tests.sh --desktop

# All machines (headless + desktop)
./tests/run_vm_tests.sh --all

# Specific machine(s) by name
./tests/run_vm_tests.sh workstation-test-debian workstation-test-ubuntu
```

#### Windows (Native via Vagrant)

On Windows, the VM lifecycle and Ansible provisioning are fully automated natively via **HashiCorp Vagrant**. You do NOT need WSL or Python.

**Prerequisites:**
1. **VirtualBox:** Installed on Windows.
2. **Vagrant:** Installed on Windows (e.g. `winget install HashiCorp.Vagrant`).

Vagrant automatically handles creating the VM, configuring USB passthrough, injecting SSH keys, and running the Ansible playbook *locally* inside the guest VM (`ansible_local` provisioner).

To manually bring up a specific machine without running tests:
```powershell
vagrant up workstation-test-ubuntu24
```

To run the automated VM tests on Windows, run the PowerShell script:

```powershell
# Run the tests for a specific VM (e.g. Debian 13)
.\tests\run_vm_tests.ps1 -Machines "workstation-test-debian"

# Run headless VMs (default)
.\tests\run_vm_tests.ps1

# Run desktop VMs
.\tests\run_vm_tests.ps1 -Desktop

# Run all test VMs
.\tests\run_vm_tests.ps1 -All
```

*Note: You may need to bypass the PowerShell Execution Policy if running local scripts is restricted:*
```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run_vm_tests.ps1 -Machines "workstation-test-debian"
```


Or drive Vagrant directly:

```bash
# Bring up and automatically provision a single test VM
vagrant up workstation-test-debian

# Connect via SSH
vagrant ssh workstation-test-debian

# Destroy when done
vagrant destroy workstation-test-debian
```

All `features.fpga.*` and `features.xrdp` flags default to `false` in test
VMs. `features.editor.neovim` defaults to `true`. Override via `--extra-vars`
if needed.
