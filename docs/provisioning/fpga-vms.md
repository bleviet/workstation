# FPGA development VMs

Four VirtualBox-based FPGA development environments are provided under
`environments/`. All are managed with `environments/build.py` via VBoxManage —
no Vagrant or VMware required.

| Directory | OS | Desktop | Primary use |
|---|---|---|---|
| `environments/fpga-alma/` | AlmaLinux 9 | XFCE4 (Ansible) | Vivado + Quartus (primary — RHEL-certified) |
| `environments/fpga-ubuntu/` | Ubuntu 24.04 | XFCE4 (Ansible) | Alternative Ubuntu target |
| `environments/fpga-ubuntu2604/` | Ubuntu 26.04 | GNOME (Ansible) | Latest Ubuntu LTS |
| `environments/fpga-debian/` | Debian 13 | XFCE4 (Ansible) | Debian target |

The AlmaLinux variant is the primary target. Vivado and Quartus are both
officially certified against RHEL 8/9, so it requires fewer library
workarounds than Ubuntu.

---

## Prerequisites

| Tool | Where to get it |
|---|---|
| VirtualBox ≥ 7.0 | https://www.virtualbox.org/wiki/Downloads |
| Python ≥ 3.10 | system or `pyenv` |
| Python packages | `pip install -r environments/requirements.txt` |
| `qemu-img` | `apt install qemu-utils` / `dnf install qemu-img` |

---

## VM definitions

Each FPGA environment is declared in a `vm.yml` file:

```yaml
# environments/fpga-alma/vm.yml
name: fpga-dev-alma-9
os: alma9            # references environments/os/alma9/os.yml
hostname: fpga-dev

ram_mb: 32768
cpus: 8
vram_mb: 256
disk_gb: 512

accel3d: true

usb:
  ehci: true         # USB 2.0 — USB-Blaster, Platform Cable USB
  xhci: true         # USB 3.0 — USB-Blaster II, Digilent boards

shared_folders:
  - host: "../.."
    guest: "/home/vagrant/workspace/workstation"
  - host: "projects"
    guest: "/home/vagrant/projects"
    create: true
  - host: "installers"
    guest: "/opt/fpga-installers"
    create: true
```

OS metadata lives in `environments/os/<name>/os.yml` and specifies the cloud
image URL, checksum, filesystem type, and setup/cleanup scripts. `build.py`
downloads the cloud image once and caches it in `environments/.cache/images/`.

---

## Command reference

All commands run from the repo root. `<vm>` is the `name` field in `vm.yml`.

```bash
# Full pipeline: download image → create VM → run setup → snapshot
python environments/build.py create fpga-dev-alma-9
# ... Wait for install to finish, then turn off the VM.
# Now boot it normally (which attaches the custom virtual disk).
python environments/build.py start   fpga-dev-alma-9
python environments/build.py stop    fpga-dev-alma-9

# To delete the VM and its disk
python environments/build.py destroy fpga-dev-alma-9

# List all discovered VMs with their VirtualBox state
python environments/build.py list

# Interactive picker (no args)
python environments/build.py
```

---

## First-time setup

**Step 1 — Create the VM.**

```bash
python environments/build.py create fpga-dev-alma-9
```

`build.py` will:
1. Download and verify the OS cloud image (cached for reuse)
2. Convert it to VDI and resize to the declared `disk_gb`
3. Build a cloud-init seed ISO
4. Create and configure the VirtualBox VM
5. Boot the VM and wait for SSH (NAT port-forward: `127.0.0.1:2222`)
6. Run `os.yml`'s `setup.sh` (installs VirtualBox Guest Additions + Python)
7. Inject your SSH public key (see below)
8. Run `cleanup.sh` and detach the seed ISO
9. Add shared folders
10. Take a `clean-base` snapshot

When complete:
```
  ✓ VM ready — SSH: ssh vagrant@127.0.0.1 -p 2222
  Next: add the VM's IP to provisioning/inventory/hosts.yml and run Ansible.
```

**Step 2 — Find the VM's IP and update the inventory.**

The VM uses NAT for initial setup (`127.0.0.1:2222`). To run Ansible from
outside, use a bridged or host-only adapter, or find the NAT IP:

```bash
ssh vagrant@127.0.0.1 -p 2222 "ip addr show | grep 'inet '"
```

Edit `provisioning/inventory/hosts.yml` and set `ansible_host`:

```yaml
fpga-dev-alma-9:
  ansible_host: 192.168.x.x    # IP found above
  ansible_user: vagrant
```

**Step 3 — Run Ansible.**

```bash
ansible-playbook provisioning/site.yml --limit fpga-dev-alma-9
```

---

## Admin SSH key injection

During `create`, `build.py` automatically injects a public key into
`~/.ssh/authorized_keys` on the VM. It searches in this order:

1. `admin.pub` in the **repo root** *(gitignored)*
2. `~/.ssh/id_ed25519.pub`
3. `~/.ssh/id_rsa.pub`
4. `~/.ssh/id_ecdsa.pub`

If you have a standard `~/.ssh/id_ed25519.pub` no extra steps are needed.
If you want to inject a different key (e.g. a CI key), create `admin.pub`
at the repo root before running `create`.

```bash
# optional — only needed if your default key isn't id_ed25519
cp /path/to/key.pub admin.pub
```

---

## Inventory and host variables

FPGA VMs are declared in the `fpga_vms` group in
`provisioning/inventory/hosts.yml`. Profile and features are set in
`provisioning/inventory/group_vars/fpga_vms.yml` and can be overridden
per host in `provisioning/inventory/host_vars/<hostname>.yml`.

```yaml
# host_vars/fpga-dev-alma-9.yml
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
