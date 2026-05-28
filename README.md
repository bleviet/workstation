# workstation

Personal workstation provisioning for Linux. Ansible handles system setup; chezmoi manages dotfiles.

## How it works

**Ansible** owns all variation — packages, OS-specific shell snippets, git config, tools.
**chezmoi** owns common dotfiles — no templates, no conditionals, just `apply`.

OS-specific aliases land in `~/.config/shell/os.sh` via an Ansible template. The shell configs source `~/.config/shell/*.sh` by glob, so chezmoi never needs to know which OS it's on.

## Supported platforms

| OS | Package manager |
|---|---|
| Debian 12 | apt |
| Ubuntu 24.04 | apt |
| AlmaLinux 9 | dnf |

## Quick start

```bash
git clone <repo> ~/workspace/workstation
cd ~/workspace/workstation
./bootstrap.sh
```

`bootstrap.sh` installs Ansible, pulls the `community.general` collection, and runs `playbooks/site.yml`.

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
  Dockerfile.{debian,ubuntu,almalinux}
  run_tests.sh            # parallel syntax-check via Podman
```

## Configuration

All tunables live in `inventory/group_vars/all.yml`:

- `packages` — system packages per package manager
- `brew_formulae` — Homebrew formulae list
- `git_name` / `git_email` — global git identity
- `features.gui` — enables Nerd Fonts install
- `features.fpga` — enables FPGA toolchain

## Testing

```bash
./tests/run_tests.sh
```

Builds a container per OS in parallel (Podman, rootless) and runs `ansible-playbook --syntax-check` against both playbooks.
