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

Test VMs are defined in `tests/vm/machines.yml` and managed via
`environments/build.py` (VBoxManage). No Vagrant or VMware required.

### Prerequisites

| Tool | Where to get it |
|---|---|
| VirtualBox ≥ 7.0 | https://www.virtualbox.org/wiki/Downloads |
| Python ≥ 3.10 | system or `pyenv` |
| Python packages | `pip install -r environments/requirements.txt` |
| `qemu-img` | `apt install qemu-utils` / `dnf install qemu-img` |

### Available test machines

| Name | OS | Profile |
|---|---|---|
| `workstation-test-debian` | Debian 13 | headless |
| `workstation-test-ubuntu` | Ubuntu 24.04 | headless |
| `workstation-test-almalinux` | AlmaLinux 9 | headless |
| `workstation-test-debian-i3wm` | Debian 13 | desktop-i3wm |
| `workstation-test-ubuntu-i3wm` | Ubuntu 24.04 | desktop-i3wm |
| `workstation-test-almalinux-i3wm` | AlmaLinux 9 | desktop-i3wm |
| `workstation-test-debian-xfce` | Debian 13 | desktop-xfce |
| `workstation-test-ubuntu-xfce` | Ubuntu 24.04 | desktop-xfce |
| `workstation-test-almalinux-xfce` | AlmaLinux 9 | desktop-xfce |
| `workstation-test-debian-gnome` | Debian 13 | desktop-gnome |
| `workstation-test-ubuntu-gnome` | Ubuntu 24.04 | desktop-gnome |
| `workstation-test-almalinux-gnome` | AlmaLinux 9 | desktop-gnome |

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

#### Windows (with WSL)

On Windows, the VM lifecycle is managed natively on Windows via Python (`VBoxManage.exe`), while the Ansible control node runs inside **WSL** (since Ansible cannot run natively on Windows).

**Prerequisites:**
1. **VirtualBox:** Installed on Windows, with `VBoxManage` available in your Windows PATH (usually `C:\Program Files\Oracle\VirtualBox`).
2. **Python:** Installed on Windows (venv/uv).
3. **WSL (Ubuntu):** Installed on the host with Ansible installed inside the WSL distribution.
4. **SSH Keys:** The WSL user must have an SSH key pair (e.g., `~/.ssh/id_ed25519` with no passphrase for automation). The Windows host-side public key (e.g. `C:\Users\<user>\.ssh\id_ed25519.pub`) is injected into the VM during creation to facilitate SSH logins.

To run the VM tests on Windows, run the PowerShell script:

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


Or drive `build.py` directly:

```bash
# Create a single test VM
python environments/build.py create workstation-test-debian

# Connect via SSH (NAT port-forward set up by build.py)
ssh vagrant@127.0.0.1 -p 2222

# Run the full playbook against it
ansible-playbook provisioning/site.yml \
  -i '127.0.0.1,' \
  -u vagrant -e ansible_port=2222 \
  -e profile=headless

# Destroy when done
python environments/build.py destroy workstation-test-debian
```

All `features.fpga.*` and `features.xrdp` flags default to `false` in test
VMs. `features.editor.neovim` defaults to `true`. Override via `--extra-vars`
if needed.
