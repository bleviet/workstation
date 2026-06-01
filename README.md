# workstation

Personal workstation provisioning for Linux. Ansible handles system setup; chezmoi manages dotfiles.

**Ansible** owns all variation — packages, OS-specific shell snippets, git config, tools, and desktop
environment. **chezmoi** owns common dotfiles — no templates, no conditionals, just `apply`.

## Supported platforms

| OS | Package manager |
|---|---|
| Debian 13 | apt |
| Ubuntu 26.04 | apt |
| AlmaLinux 9 | dnf |

## Quick start

```bash
git clone <repo> ~/workspace/workstation
cd ~/workspace/workstation
./bootstrap.sh
```

## Documentation

📊 **[Interactive guide](docs/index.html)** — visual scenario explorer (open in a browser).

**Provisioning**

| Doc | Scenario |
|---|---|
| [Quick start](docs/provisioning/quick-start.md) | Clone repo on this machine and run `bootstrap.sh` (owner flow) |
| [Host configuration](docs/provisioning/host-configuration.md) | Profiles, feature flags, host\_vars, shared tunables, repo structure |
| [Remote deployment](docs/provisioning/remote-deployment.md) | Deploy to remote hosts from an admin PC or container |
| [Custom developer user](docs/provisioning/custom-user.md) | Provision a machine for a user other than the SSH login |
| [FPGA development VMs](docs/provisioning/fpga-vms.md) | Create and manage VirtualBox FPGA VMs with `build.py` |

**Dotfiles and personal workflow**

| Doc | Scenario |
|---|---|
| [Dotfiles — single owner](docs/dotfiles/owner.md) | One person managing dotfiles in this repo |
| [Dotfiles — shared repo](docs/dotfiles/shared.md) | Multiple users, each with their own dotfiles repo + SSH auth options |
| [Python workflow](docs/dotfiles/python.md) | uv + direnv project venvs, `mkvenv`, base packages |

**Contributing**

| Doc | Scenario |
|---|---|
| [Testing](docs/testing.md) | Container syntax-check and full VM provisioning tests |
