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

| Doc | Scenario |
|---|---|
| [Quick start — local installation](docs/quick-start.md) | Clone repo on this machine and run `bootstrap.sh` (owner flow) |
| [Host configuration](docs/host-configuration.md) | Profiles, features, host\_vars, shared tunables, repo structure |
| [Dotfiles — single owner](docs/dotfiles-owner.md) | One person managing dotfiles in this repo |
| [Dotfiles — shared repo](docs/dotfiles-shared.md) | Multiple users, each with their own dotfiles repo + SSH auth options |
| [Remote deployment](docs/remote-deployment.md) | Deploy to remote hosts from an admin PC or container |
| [Testing](docs/testing.md) | Container syntax-check and full VM provisioning tests |
