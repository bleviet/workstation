# workstation

Personal workstation provisioning for Linux. Ansible handles system setup; chezmoi manages dotfiles.

## How it works

**Ansible** owns all variation — packages, OS-specific shell snippets, git config, tools.
**chezmoi** owns common dotfiles — no templates, no conditionals, just `apply`.

OS-specific aliases land in `~/.config/shell/os.sh` via an Ansible template. The shell configs source `~/.config/shell/*.sh` by glob, so chezmoi never needs to know which OS it's on.

## Supported platforms

| OS | Package manager |
|---|---|
| Debian 13 | apt |
| Ubuntu 26.04 | apt |
| AlmaLinux 10 | dnf |

## Quick start

```bash
git clone <repo> ~/workspace/workstation
cd ~/workspace/workstation
./bootstrap.sh
```

`bootstrap.sh` installs Ansible (`ansible-core` on AlmaLinux 10 via AppStream; `ansible` on Debian/Ubuntu via apt), pulls the `community.general` collection, and runs `playbooks/site.yml`.

## Daily use

```bash
# Re-apply dotfiles after editing dotfiles/
ansible-playbook playbooks/dotfiles.yml

# Full re-provision (idempotent)
ansible-playbook playbooks/site.yml -K
```

## Structure

```
bootstrap.sh              # entry point — installs Ansible, runs site.yml
inventory/
  hosts.yml               # localhost (local connection)
  group_vars/all.yml      # packages, brew formulae, git config, feature flags
playbooks/
  site.yml                # full provisioning
  dotfiles.yml            # chezmoi apply only
roles/
  packages/               # apt / dnf system packages
  homebrew/               # Homebrew install + formulae
  git/                    # global gitconfig
  shell/                  # oh-my-zsh + os.sh template
  chezmoi/                # install chezmoi, configure source, apply
  fonts/                  # Nerd Fonts (features.gui)
  fpga/                   # FPGA tools (features.fpga)
dotfiles/                 # chezmoi source — flat, no conditionals
tests/
  container/
    Dockerfile.{debian,ubuntu,almalinux}
  vagrant/
    Vagrantfile             # multi-machine (debian/ubuntu/almalinux), multi-provider
  run_container_tests.sh  # parallel syntax-check via Podman
  run_vm_tests.sh         # full provisioning via Vagrant VMs
```

## Configuration

All tunables live in `inventory/group_vars/all.yml`:

- `packages` — system packages per package manager
- `brew_formulae` — Homebrew formulae list
- `git_name` / `git_email` — global git identity
- `features.gui` — enables Nerd Fonts install
- `features.fpga` — enables FPGA toolchain

## Testing

### Container tests (fast, syntax-check only)

```bash
./tests/run_container_tests.sh
```

Builds a container per OS in parallel (Podman, rootless) and runs `ansible-playbook --syntax-check` against both playbooks.

### VM tests (full provisioning)

Three providers are supported:

| Provider | Host | Requirement |
|---|---|---|
| `virtualbox` | Windows / Linux desktop | VirtualBox installed |
| `vmware_desktop` | Windows / Linux | VMware + [vagrant-vmware-desktop](https://developer.hashicorp.com/vagrant/docs/providers/vmware) |
| `libvirt` | WSL2 / native Linux | KVM + vagrant-libvirt (see below) |

```bash
# VirtualBox (default)
./tests/run_vm_tests.sh

# VMware
VAGRANT_PROVIDER=vmware_desktop ./tests/run_vm_tests.sh

# KVM/libvirt (WSL2 or native Linux)
VAGRANT_PROVIDER=libvirt ./tests/run_vm_tests.sh

# Single machine
./tests/run_vm_tests.sh ubuntu
```

Or drive Vagrant directly from the `tests/vagrant/` directory:

```bash
cd tests/vagrant
vagrant up debian --provider=virtualbox
vagrant up ubuntu --provider=vmware_desktop
vagrant up almalinux --provider=libvirt
vagrant destroy debian -f
```

#### Windows (PowerShell) setup

Vagrant on Windows cannot reach the repo when it lives on the WSL filesystem. Clone the repo to a Windows path first:

```powershell
git clone <repo> C:\workspace\workstation
cd C:\workspace\workstation\tests\vagrant
```

Then bring up a VM with whichever provider is installed:

```powershell
# VMware (vagrant-vmware-desktop plugin + VMware Utility required)
vagrant up debian --provider=vmware_desktop

# VirtualBox
vagrant up debian --provider=virtualbox
```

To run all machines in sequence (PowerShell equivalent of `run_vm_tests.sh`):

```powershell
$provider = "vmware_desktop"   # or virtualbox
foreach ($os in @("debian", "ubuntu", "almalinux")) {
    vagrant up $os --provider=$provider
    vagrant destroy $os -f
}
```

#### libvirt / KVM setup (WSL2 or Linux)

```bash
# Install KVM and libvirt
sudo apt install qemu-kvm libvirt-daemon-system virtinst

# Add your user to the libvirt group (re-login after)
sudo usermod -aG libvirt "$USER"

# Install the Vagrant plugin
vagrant plugin install vagrant-libvirt
```

On WSL2, nested virtualisation must be enabled. Create `%USERPROFILE%\.wslconfig`:
```ini
[wsl2]
nestedVirtualization=true
```
Then `wsl --shutdown` and restart.

`bento/*` boxes are used because they ship pre-built for VirtualBox, VMware, and libvirt. Each VM installs Ansible inside the guest via a shell provisioner and runs the full `playbooks/site.yml`, so the setup works identically across all three providers.

`features.gui` and `features.fpga` are forced to `false` in VMs to skip font downloads and FPGA toolchain installs. Override via `--extra-vars` if needed.
