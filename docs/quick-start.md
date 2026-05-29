# Quick start — local installation

Bootstrap this machine by cloning the repo locally and running the
provisioning script directly. This is the owner flow: the repo itself is the
dotfiles source.

## Bootstrap a new machine

```bash
git clone <repo> ~/workspace/workstation
cd ~/workspace/workstation
./bootstrap.sh
```

`bootstrap.sh` installs Ansible (`ansible-core` on AlmaLinux 9 via AppStream;
`ansible` on Debian/Ubuntu via apt), pulls the required collections, and runs
`playbooks/site.yml`.

The profile that gets installed depends on `inventory/host_vars/<hostname>.yml`.
For `localhost` the default is **`desktop-xfce`** (XFCE 4 + LightDM). To change
it, edit that file before running `bootstrap.sh` — see
[Host configuration](host-configuration.md) for all available profiles.

## Daily use

```bash
# Re-apply dotfiles after editing dotfiles/
chezmoi apply

# Full re-provision (safe to run again — skips what is already done)
ansible-playbook playbooks/site.yml -K
```
