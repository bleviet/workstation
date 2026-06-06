# Custom developer user

By default the playbook provisions the account it connects as (`vagrant` on a
Vagrant VM, your own user on `localhost`). Set `dev_user` in
`provisioning/inventory/host_vars/<hostname>.yml` to create and provision a separate named
account instead.

## Automated setup (recommended)

`scripts/add_dev_host.py` does all three manual steps — writes the `host_vars`
file, registers the host in `provisioning/inventory/hosts.yml`, and (with `--run`) provisions
it. It's a plain Python 3 script (standard library only) so it runs on Windows,
Linux, and macOS:

```bash
# Scaffold a remote XFCE box for user 'bach' with RDP, then provision:
python scripts/add_dev_host.py -H devbox -i 192.168.1.40 -u admin \
    -d bach -p desktop-xfce --xrdp --run
```

| Flag | Meaning |
|---|---|
| `-H, --host` | Inventory hostname (required) |
| `-d, --dev-user` | Developer account to create (required) |
| `-i, --ip` | `ansible_host` IP/DNS; omit for a local entry |
| `-u, --ssh-user` | SSH login Ansible connects as (required with `--ip`) |
| `-p, --profile` | `headless` \| `desktop-gnome` \| `desktop-xfce` \| `desktop-i3wm` (default: `desktop-xfce`) |
| `--xrdp` | Enable `features.xrdp` (RDP access) |
| `--fpga` | Enable `features.fpga.vivado`, `.quartus`, and `.oss` |
| `--run` | Run the playbook after scaffolding |
| `-f, --force` | Overwrite an existing `host_vars` file |

Omit `--run` to scaffold only and review the generated files before
provisioning. Run `python scripts/add_dev_host.py --help` for the full reference.

> **Windows note:** scaffolding (steps 1–2) works anywhere. `--run` shells out
> to `ansible-playbook`, which only exists on Linux/WSL/macOS — on a Windows host
> scaffold without `--run`, then provision from a Linux controller or WSL.

The rest of this document explains what the script generates and does, in case
you prefer to wire it up by hand.

## What happens when dev_user is set

The `user` role runs first and:

1. Creates the account (shell: `/bin/zsh`, home directory auto-created).
2. Adds it to `sudo` (Debian/Ubuntu) or `wheel` (AlmaLinux/RHEL).
3. Drops a `NOPASSWD` entry in `/etc/sudoers.d/<dev_user>` so the account can
   install packages without a password prompt.

All subsequent roles (dev-tools, shell, chezmoi, fonts) then install into
`/home/<dev_user>/` rather than the SSH user's home.

## Example — shared team machine

```yaml
# provisioning/inventory/host_vars/devbox.yml
profile: desktop-xfce

dev_user: bach

features:
  editor:
    neovim: true
    lazyvim: false
    vscode: false
  fpga:
    vivado: false
    quartus: false
    oss: false
  xrdp: true      # RDP access from Windows
```

Provision with:

```bash
ansible-playbook provisioning/site.yml -l devbox
```

Ansible connects as its normal SSH user (which must have sudo), the `user`
role creates `bach`, and the rest of the playbook configures `bach`'s
environment.

## Example — Vagrant VM with a custom user

Since Vagrant provisions VMs using Ansible locally, the easiest way to provision a custom user on a Vagrant VM is to define it in the host variables file corresponding to your VM's hostname.

For example, if your VM is named `workstation-test-ubuntu24`, create a file at `provisioning/inventory/host_vars/workstation-test-ubuntu24.yml` and add:

```yaml
dev_user: bach
dev_user_ssh_pubkey: "ssh-ed25519 AAAA... bach@laptop"
```

When you run `vagrant up workstation-test-ubuntu24`, Vagrant automatically boots the VM and triggers Ansible locally, which reads these host variables, creates the user `bach`, and installs the public key.


## Default behaviour (no change required)

When `dev_user` is not set it resolves to `ansible_user_id` — the SSH user
Ansible connects as. No account is created, no sudo entry is written, and all
paths resolve to that user's existing home directory.

## Account password

The account is created with a **locked password** — no password is set, so
password-based login is disabled by default.

### Switch to the account from the SSH user (Vagrant)

```bash
vagrant ssh <machine>
sudo su - bach
```

### Set a password manually

```bash
vagrant ssh <machine>   # or ssh admin@devbox
sudo passwd bach
```

After setting a password the user can log in via the desktop login screen
(LightDM / GDM) or over RDP if `features.xrdp` is enabled.

### SSH key login (recommended)

Set `dev_user_ssh_pubkey` in `provisioning/inventory/host_vars/<hostname>.yml` and the
playbook will install the key during provisioning:

```yaml
# provisioning/inventory/host_vars/devbox.yml
profile: desktop-xfce
dev_user: bach
dev_user_ssh_pubkey: "ssh-ed25519 AAAA... bach@laptop"

features:
  editor:
    neovim: true
    lazyvim: false
    vscode: false
  fpga:
    vivado: false
    quartus: false
    oss: false
  xrdp: false
```

After provisioning, connect directly:

```bash
ssh -i ~/.ssh/id_ed25519 bach@devbox
```

To add or rotate a key on an already-provisioned machine, update the value in
`host_vars` and re-run the playbook — `ansible.posix.authorized_key` is
idempotent and will add the key if missing without touching existing ones.

## Connecting as the new user after provisioning

Once a password or SSH key is in place you can log in directly:

```bash
ssh bach@devbox
```

The account has passwordless sudo, `zsh` as the default shell, and all the
dev tools, dotfiles, and shell config installed in `/home/bach/`.
