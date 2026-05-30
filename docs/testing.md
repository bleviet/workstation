# Testing

## Container tests (fast — syntax-check only)

Builds a container per OS in parallel (Podman, rootless) and runs
`ansible-playbook --syntax-check` against both playbooks.

```bash
./tests/run_container_tests.sh
```

## VM tests (full provisioning)

Three providers are supported:

| Provider | Host | Requirement |
|---|---|---|
| `virtualbox` | Windows / Linux desktop | VirtualBox installed |
| `vmware_desktop` | Windows / Linux | VMware + [vagrant-vmware-desktop](https://developer.hashicorp.com/vagrant/docs/providers/vmware) |
| `libvirt` | WSL2 / native Linux | KVM + vagrant-libvirt (see below) |

```bash
# VirtualBox (default) — headless machines only
./tests/run_vm_tests.sh

# Desktop i3wm machines
./tests/run_vm_tests.sh --desktop

# All machines (headless + desktop)
./tests/run_vm_tests.sh --all

# VMware
VAGRANT_PROVIDER=vmware_desktop ./tests/run_vm_tests.sh --desktop

# KVM/libvirt (WSL2 or native Linux)
VAGRANT_PROVIDER=libvirt ./tests/run_vm_tests.sh

# Specific machine(s) by name
./tests/run_vm_tests.sh debian-i3wm
```

Or drive Vagrant directly from `tests/vm/`:

```bash
cd tests/vm

vagrant up debian --provider=virtualbox
vagrant up debian-i3wm --provider=vmware_desktop
vagrant up ubuntu-i3wm --provider=virtualbox
vagrant up ubuntu --provider=vmware_desktop
vagrant up almalinux --provider=libvirt
vagrant destroy debian -f
```

## Windows (PowerShell) setup

Vagrant on Windows cannot reach the repo when it lives on the WSL filesystem.
Clone the repo to a Windows path first:

```powershell
git clone <repo> C:\workspace\workstation
cd C:\workspace\workstation\tests\vm
```

Bring up a VM with the installed provider:

```powershell
# VMware (vagrant-vmware-desktop plugin + VMware Utility required)
vagrant up debian --provider=vmware_desktop

# VirtualBox
vagrant up debian --provider=virtualbox
```

Run all machines in sequence:

```powershell
$provider = "vmware_desktop"   # or virtualbox
foreach ($os in @("debian", "ubuntu", "almalinux")) {
    vagrant up $os --provider=$provider
    vagrant destroy $os -f
}
```

## libvirt / KVM setup (WSL2 or Linux)

```bash
sudo apt install qemu-kvm libvirt-daemon-system virtinst
sudo usermod -aG libvirt "$USER"   # re-login after
vagrant plugin install vagrant-libvirt
```

On WSL2, enable nested virtualisation. Create `%USERPROFILE%\.wslconfig`:

```ini
[wsl2]
nestedVirtualization=true
```

Then run `wsl --shutdown` and restart.

`bento/*` boxes are used because they ship pre-built for VirtualBox, VMware,
and libvirt. Each VM installs Ansible inside the guest via a shell provisioner
and runs the full `provisioning/site.yml`.

`features.xrdp` and `features.fpga` are forced to `false` in VMs. Override via
`--extra-vars` if needed.
