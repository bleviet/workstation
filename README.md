# Workstation Provisioning Engine

Personal workstation provisioning engine for Linux environments. Ansible manages system-level setup, package installation, and roles, while `chezmoi` manages dotfiles and user configurations.

This repository features a clean architectural separation between virtual machine infrastructure and software provisioning configuration.

---

## 🏗️ Repository Architecture

- **`local-vms/`**: Contains declarative hardware configurations (CPUs, RAM, storage, USB filters, shared folders) for local Vagrant virtual machines.
- **`ansible/`**: The complete software configuration engine containing playbooks, roles, inventory, and host/group variables.

---

## ✨ Core Features

- **Supported Platforms**: Debian 13 (apt), Ubuntu 24.04/26.04 (apt), AlmaLinux 9/10 (dnf).
- **Environment Profiles**: Selectable per-machine profiles including `headless`, `desktop-gnome`, `desktop-xfce`, and `desktop-i3wm`.
- **Modular Feature Flags**: Toggle selective installs such as VS Code, Neovim/LazyVim, remote desktop access via xRDP, and FPGA development library toolchains (AMD/Xilinx Vivado, Intel/Altera Quartus, and open-source EDA).
- **Dynamic Host Variables**: Vagrant dynamically aligns guest machines with their matching variables under `ansible/inventory/host_vars/vm-fpga-dev-*.yml` natively using the guest VM name.
- **Interactive Documentation**: Interactive guides and Mermaid diagrams for common workflows are available in [docs/index.html](file:///docs/index.html).

---

## 🚀 Getting Started

### 1. Interactive GUI VM Builder (Recommended)
If you are on Windows, you can boot a local Jenkins build server to configure and spin up a VM with a few clicks:
```powershell
# Open a PowerShell terminal and run:
.\scripts\setup_local_jenkins.ps1
```
Open **http://localhost:8080/job/workstation-vm-builder/** (login with `admin` / `admin`), click **Build with Parameters**, and customize your OS, desktop profile, RAM, CPU, and hardware flags!

### 2. Manual CLI VM Startup
Spin up any of the predefined development VMs using the Vagrant CLI:
```bash
# Start a specific local VM
vagrant up vm-fpga-dev-ubuntu-2604

# SSH into the running machine
vagrant ssh vm-fpga-dev-ubuntu-2604
```

### 3. Bare-Metal Local Provisioning
To provision your current bare-metal machine locally:
```bash
git clone https://github.com/bleviet/workstation.git ~/workspace/workstation
cd ~/workspace/workstation
./bootstrap.sh
```

---

## 📖 Documentation Index

For deeper details, consult the following guides:

### **Provisioning & Infrastructure**
* 📊 **[Interactive Guide (docs/index.html)](file:///docs/index.html)** — Interactive visual scenarios for syncing dotfiles, VM setup, and selective deployment.
* 📦 **[Quick Start](file:///docs/provisioning/quick-start.md)** — Guide to local manual installation and daily use.
* 🛠️ **[Host Configuration](file:///docs/provisioning/host-configuration.md)** — Variable options, features, tags, and profiles.
* 📡 **[Remote Deployment](file:///docs/provisioning/remote-deployment.md)** — Deploying to remote servers and laptops over SSH from an admin container.
* 👤 **[Custom Developer User](file:///docs/provisioning/custom-user.md)** — Onboard and create isolated developer accounts with customized environments.
* 💻 **[FPGA Development VMs](file:///docs/provisioning/fpga-vms.md)** — Hypervisor settings, JTAG USB rules, and resources for local VMs.

### **Dotfiles & Personal Workflows**
* 🗂️ **[Dotfiles - Single Owner](file:///docs/dotfiles/owner.md)** — Keeping local dotfiles in this repository.
* 👥 **[Dotfiles - Shared Repo](file:///docs/dotfiles/shared.md)** — Setting up individual external dotfile repositories and configuring SSH deploy keys.
* 🐍 **[Python Workflow](file:///docs/dotfiles/python.md)** — Automated project virtual environments using `uv` + `direnv`.

### **Testing & CI**
* 🧪 **[Testing System](file:///docs/testing.md)** — How container-based syntax checks, idempotency, and automated VM tests are executed.
