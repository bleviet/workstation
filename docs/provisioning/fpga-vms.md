# FPGA development VMs

Two Vagrant environments are provided under `environments/`:

| Directory | Box | Guest OS |
|---|---|---|
| `environments/fpga-alma/` | `almalinux/9` (official) | AlmaLinux 9 + XFCE4 |
| `environments/fpga-ubuntu/` | `bento/ubuntu-24.04` | Ubuntu 24.04 + XFCE4 |

The AlmaLinux variant is the primary target. Vivado and Quartus are both
officially certified against RHEL 8/9, so it requires fewer library
workarounds than Ubuntu.

---

## Bento boxes vs. official boxes

The test VMs (`tests/vm/`) use **bento/** boxes; the FPGA VMs use the
**official** AlmaLinux box. They behave differently in a few important ways.

### Who builds them

| | Bento | Official |
|---|---|---|
| Maintainer | Chef / Progress | The OS vendor |
| Build tooling | Packer with a consistent Chef pipeline | Vendor-specific |
| Published at | `bento/<distro>` on Vagrant Cloud | `<vendor>/<distro>` on Vagrant Cloud |

### Behaviour differences that matter in practice

| | Bento | Official AlmaLinux |
|---|---|---|
| SSH password auth | **Enabled** — `vagrant`/`vagrant` works | **Disabled** — key-only |
| RHEL fidelity | Trimmed for Vagrant convenience | Mirrors RHEL as closely as possible |
| Multi-provider support | VirtualBox, VMware, libvirt (pre-built) | Varies; VMware supported |
| SELinux / sshd policy | Relaxed | Vendor defaults (stricter) |

**Why this matters for FPGA work:** Vivado and Quartus link against specific
RHEL system libraries. Using the official `almalinux/9` box gives you the
closest environment to what AMD/Intel actually test against, catching
compatibility issues early. The stricter SSH configuration is a side effect
of that fidelity — see the SSH key section below.

---

## SSH key workflow

The FPGA VMs are created by Vagrant running on **Windows** but provisioned by
Ansible running in **WSL**. These are two separate environments with separate
SSH key stores, which requires a one-time bootstrap.

### Why `vagrant`/`vagrant` password login does not work

The official `almalinux/9` box ships with `PasswordAuthentication no` in
`/etc/ssh/sshd_config`. Only key-based SSH works.

During `vagrant up`, Vagrant replaces the default insecure keypair with a
freshly generated one:

```
Vagrant insecure key detected. Vagrant will automatically replace
this with a newly generated keypair for better security.
Inserting generated public key within guest...
```

The generated private key is stored on the **Windows** filesystem:

```
environments/fpga-alma/.vagrant/machines/default/vmware_workstation/private_key
```

WSL mounts Windows drives (`/mnt/d/…`) with fixed `0777` permissions. SSH
refuses private key files with permissions wider than `0600`, so the key
cannot be used directly from WSL.

### The admin-ssh-key provisioner

Each Vagrantfile includes an `admin-ssh-key` provisioner that injects an
admin public key into the VM during `vagrant up`, bypassing the need to use
the Vagrant-generated key at all.

It resolves the key in this order:

1. `admin.pub` alongside the Vagrantfile *(gitignored)*
2. `%USERPROFILE%\.ssh\id_ed25519.pub` (then `id_rsa.pub`, `id_ecdsa.pub`)
3. If nothing is found: prints a warning and skips

### First-time setup

**Step 1 — Create `admin.pub` on the Windows machine.**

From WSL, write your WSL public key to the Windows-accessible path:

```bash
cat ~/.ssh/id_ed25519.pub \
  > /mnt/d/workspace/workstation/environments/fpga-alma/admin.pub
```

Or in PowerShell on Windows:

```powershell
# paste your public key content
"ssh-ed25519 AAAA..." | Out-File -Encoding ascii `
  D:\workspace\workstation\environments\fpga-alma\admin.pub
```

**Step 2 — Create the VM.**

```powershell
# Windows PowerShell, inside environments/fpga-alma/
vagrant up
```

Vagrant injects `admin.pub` into the VM's `~/.ssh/authorized_keys` during
provisioning. The `admin.pub` file is gitignored and never committed.

**Step 3 — Fill in the VM's IP.**

Find the IP from the VMware console or via SSH:

```bash
ssh vagrant@<ip> "ip addr show eth0 | grep 'inet '"
```

Edit `provisioning/inventory/hosts.yml` and set `ansible_host` for the
relevant entry.

**Step 4 — Run Ansible from WSL.**

```bash
# From the repo root in WSL
ansible-playbook provisioning/site.yml --limit fpga-dev-alma9
```

### Applying the key to an already-running VM

If the VM was created before `admin.pub` existed, create the file and then
re-run only the key provisioner:

```powershell
# Windows PowerShell
vagrant provision --provision-with admin-ssh-key
```

Or inject manually from WSL using the Vagrant private key as a one-time
bootstrap:

```bash
# Copy Vagrant key to WSL filesystem so permissions can be set
cp /mnt/d/workspace/workstation/environments/fpga-alma/.vagrant/machines/default/vmware_workstation/private_key \
   ~/.ssh/fpga-alma-vagrant
chmod 600 ~/.ssh/fpga-alma-vagrant

# Push your WSL public key into the VM
cat ~/.ssh/id_ed25519.pub | \
  ssh -i ~/.ssh/fpga-alma-vagrant vagrant@<ip> \
      "cat >> ~/.ssh/authorized_keys"
```

### Sharing one SSH key across Windows and WSL (alternative)

If you copy your WSL key pair to the Windows SSH directory, the Vagrantfile
auto-detects and injects it without needing `admin.pub`:

```bash
cp ~/.ssh/id_ed25519     /mnt/c/Users/<WindowsUsername>/.ssh/id_ed25519
cp ~/.ssh/id_ed25519.pub /mnt/c/Users/<WindowsUsername>/.ssh/id_ed25519.pub
```

Both machines then share the same identity and no manual steps are needed
for future VMs.

---

## Inventory and host variables

Both FPGA VMs are declared in the `fpga_vms` group in
`provisioning/inventory/hosts.yml`. Profile and features are set in
`provisioning/inventory/group_vars/fpga_vms.yml` and can be overridden
per host in `provisioning/inventory/host_vars/<hostname>.yml`.

```yaml
# host_vars/fpga-dev-alma9.yml
dev_user: yourname          # account provisioned inside the VM
dev_user_ssh_pubkey: ""     # SSH public key deployed for dev_user

profile: desktop-xfce       # inherits from group_vars; override if needed

features:
  editor:
    neovim: true
    vscode: true
  fpga:
    vivado: false
    quartus: false
    oss: true
  xrdp: false
```

`ansible_user: vagrant` in `hosts.yml` is the SSH login Ansible uses to
connect. `dev_user` is the developer account that gets dotfiles, dev tools,
and shell configuration installed inside the VM — it can be different from
`vagrant`.
