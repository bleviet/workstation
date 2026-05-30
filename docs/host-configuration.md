# Host configuration

## Environment profiles

Each host has a `profile` variable that controls which desktop environment (if
any) is installed. Set it in `provisioning/inventory/host_vars/<hostname>.yml`:

| Profile | Description |
|---|---|
| `headless` | No GUI — SSH + X11 forwarding only |
| `desktop-gnome` | GNOME Shell + GDM |
| `desktop-xfce` | XFCE 4 + LightDM |
| `desktop-i3wm` | i3wm + LightDM + polybar/rofi/dunst/picom |

SSH and X11 forwarding (`X11Forwarding yes`, `AllowAgentForwarding yes`) are
**always configured** on every host regardless of profile.

## Optional features

Override per host in `provisioning/inventory/host_vars/<hostname>.yml`:

| Variable | Default | Effect |
|---|---|---|
| `features.xrdp` | `false` | Install xrdp (Windows Remote Desktop access, port 3389) |
| `features.fpga` | `false` | Install FPGA toolchain |

## Example host\_vars

```yaml
# provisioning/inventory/host_vars/my_laptop.yml
profile: desktop-xfce
features:
  fpga: false
  xrdp: false
```

```yaml
# provisioning/inventory/host_vars/dev_server.yml
profile: headless
features:
  fpga: false
  xrdp: true
```

## Shared tunables

Defaults live in `provisioning/inventory/group_vars/all.yml` and can be overridden per
group or host:

| Variable | Description |
|---|---|
| `packages` | System packages per package manager |
| `github_binaries` | Dev tool versions (eza, fd, rg, bat, fzf, …) |
| `nvm_version` / `node_version` | nvm version and Node.js version to install |
| `profile` | Default environment profile |
| `dev_user` | Developer account to create and provision (default: SSH user) |
| `features.xrdp` | Enables xrdp install |
| `features.fpga` | Enables FPGA toolchain |

See [custom-user.md](custom-user.md) for details on provisioning a machine for
a user other than the Ansible SSH user.

> **Git identity** (`name`, `email`, `editor`) is a personal dotfile — edit
> `dotfiles/dot_gitconfig` (owner mode) or your own dotfiles repo (shared mode).
> It no longer lives in Ansible inventory.

## Repository structure

```
bootstrap.sh              # entry point — installs Ansible, runs site.yml
controller/
  Containerfile           # Ansible controller image (Podman/Docker)
  run.sh                  # wrapper: build image + run ansible-playbook
provisioning/
  site.yml                # full provisioning playbook (profile-aware)
  inventory/
    hosts.yml             # workstations + servers groups
    group_vars/
      all.yml             # shared packages, git config
      workstations.yml    # workstation defaults (profile, features)
      servers.yml         # server defaults (headless, xrdp)
    host_vars/
      localhost.yml       # local machine overrides
  roles/
    user/                 # create dev_user account + passwordless sudo
    packages/             # apt / dnf system packages
    dev-tools/            # GitHub release binaries + rustup + nvm + uv
    shell/                # oh-my-zsh + os.sh template
    chezmoi/              # configure chezmoi source, apply dotfiles
    fonts/                # Nerd Fonts
    fpga/                 # FPGA tools (features.fpga)
    ssh/                  # openssh-server + X11 forwarding (always on)
    desktop/              # Xorg base (when profile contains 'desktop')
    gnome/                # GNOME Shell + GDM (desktop-gnome)
    xfce/                 # XFCE 4 + LightDM (desktop-xfce)
    i3wm/                 # i3wm stack + LightDM (desktop-i3wm)
    xrdp/                 # xrdp RDP server (features.xrdp)
dotfiles/                 # chezmoi source — flat, no conditionals
environments/
  fpga-ubuntu/            # FPGA dev VM (Ubuntu 24.04, VMware)
  fpga-alma/              # FPGA dev VM (AlmaLinux 9, VMware)
tests/
  container/
    Dockerfile.{debian,ubuntu,almalinux}
  vm/
    Vagrantfile           # multi-machine (debian/ubuntu/almalinux), multi-provider
  run_container_tests.sh  # parallel syntax-check via Podman
  run_vm_tests.sh         # full provisioning via Vagrant VMs
```
