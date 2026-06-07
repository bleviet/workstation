# FPGA development VMs

Five FPGA development environments are provided under `local-vms/`. All are managed natively via **Vagrant** supporting VirtualBox, VMware Desktop, and Libvirt/KVM.

| Directory | OS | Desktop | Primary use |
|---|---|---|---|
| `local-vms/vm-fpga-dev-alma-9/` | AlmaLinux 9 | GNOME (Ansible) | RHEL-certified Vivado + Quartus target |
| `local-vms/vm-fpga-dev-alma-10/` | AlmaLinux 10 | GNOME (Ansible) | RHEL-certified latest version |
| `local-vms/vm-fpga-dev-ubuntu-2404/` | Ubuntu 24.04 | XFCE4 (Ansible) | Alternative Ubuntu target |
| `local-vms/vm-fpga-dev-ubuntu-2604/` | Ubuntu 26.04 | GNOME (Ansible) | Latest Ubuntu LTS |
| `local-vms/vm-fpga-dev-debian-13/` | Debian 13 | XFCE4 (Ansible) | Debian target |

The AlmaLinux variants are the primary targets for commercial FPGA toolchains. Vivado and Quartus are officially certified against RHEL, meaning they require fewer library workarounds than Ubuntu.

---

## Prerequisites

| Tool | Where to get it |
|---|---|
| Vagrant | https://developer.hashicorp.com/vagrant/downloads |
| Hypervisor | VMware Desktop (default), VirtualBox, or Libvirt/KVM |

Optional: If you want to use custom storage locations for your VM disks to prevent filling up your primary drive, you can configure overrides in `local-vms/settings.yml`.

---

## VM definitions

Each FPGA environment is declared in a `vm.yml` file under its respective folder:

```yaml
# local-vms/vm-fpga-dev-alma-10/vm.yml
name: vm-fpga-dev-alma-10
os: alma10
hostname: fpga-dev

ram_mb: 32768        # 32 GB — leaves sufficient RAM for host
cpus: 8              # logical CPUs visible inside the VM
vram_mb: 256         # video RAM for display sessions
disk_gb: 512         # thin-provisioned; grows on demand

accel3d: false       # hardware 3D acceleration

usb:
  ehci: true         # USB 2.0 — USB-Blaster (original), Platform Cable USB
  xhci: true         # USB 3.0 — USB-Blaster II, modern Digilent boards

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

The `Vagrantfile` dynamically scans these files and loads the boxes, allocating resources and providers accordingly.

---

## Command reference

The easiest and recommended way to manage FPGA VMs is using the interactive Jenkins GUI, but you can also manage them directly from the command line.

### Method 1: Jenkins GUI (Recommended)

Run the local Jenkins bootstrap script from your Windows host:
```powershell
.\scripts\setup_local_jenkins.ps1
```
Navigate to **http://localhost:8080/job/workstation-vm-builder/** and click **Build with Parameters**. The pipeline provides drop-downs to dynamically select the OS, desktop environment, RAM (up to 32GB), CPU allocation, and USB passthrough. Jenkins will automatically isolate the build in its own custom workspace folder so your builds never collide.

### Method 2: Vagrant CLI

All commands are run using Vagrant from the repository root.

```bash
# Create, boot, and automatically provision a VM
vagrant up vm-fpga-dev-alma-10

# Access the VM via SSH
vagrant ssh vm-fpga-dev-alma-10

# Force-run Ansible provisioning inside the VM
vagrant provision vm-fpga-dev-alma-10

# Stop the VM
vagrant halt vm-fpga-dev-alma-10

# Suspend the VM (saves state)
vagrant suspend vm-fpga-dev-alma-10

# Destroy the VM (deletes disk files)
vagrant destroy vm-fpga-dev-alma-10
```

---

## First-time setup

**Step 1 — Configure Host Overrides (Optional).**

If you are on Windows and need your VMs to reside on another drive (e.g. `D:\vm`), modify `local-vms/settings.yml` (do not delete or ignore this file; it is committed to git):
```yaml
vbox_base_folder: "D:/vm/vbox"
vmware_base_folder: "D:/vm/vmware"
```

**Step 2 — Boot the VM.**

```bash
vagrant up vm-fpga-dev-alma-10
```

Vagrant will automatically:
1. Download the base box matching the OS target (from Vagrant Cloud).
2. Configure provider settings (CPUs, RAM, USB support, graphics controller).
3. Set up the shared directories.
4. Run the Ansible local provisioner (`ansible_local`) inside the guest to install your development packages, desktop environment, and configs.

**Step 3 — Log in and start working.**

For a command-line session, run:
```bash
vagrant ssh vm-fpga-dev-alma-10
```
For a desktop session, open your hypervisor console (VirtualBox/VMware/Virt-Manager) or connect via RDP on port `3389` if `features.xrdp` is enabled.

---

## Inventory and host variables

FPGA VMs are declared in the `fpga_vms` group in `ansible/inventory/hosts.yml`. Profile and feature configurations are managed in `ansible/inventory/group_vars/fpga_vms.yml` or overridden per host in `ansible/inventory/host_vars/<hostname>.yml`:

```yaml
# ansible/inventory/host_vars/vm-fpga-dev-alma-10.yml
dev_user: bach              # account created inside the VM (different from vagrant)
dev_user_ssh_pubkey: ""     # SSH key deployed for dev_user (leave empty to skip)

profile: desktop-gnome      # desktop environment to install

features:
  editor:
    neovim: true
    lazyvim: false
    vscode: true
  fpga:
    vivado: true
    quartus: false
    oss: true
  xrdp: true                # enable RDP access from Windows/host
```
