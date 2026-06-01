# Testing

## Container tests (fast — syntax-check only)

Builds a container per OS in parallel (Podman, rootless) and runs
`ansible-playbook --syntax-check` against both playbooks.

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
