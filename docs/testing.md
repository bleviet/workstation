# Testing

## Container tests (Automated pipeline)

Builds a container per OS in parallel (Podman/Docker, rootless) and executes a robust four-stage testing pipeline:
1. **Syntax Check:** Runs `ansible-playbook --syntax-check` against the playbooks.
2. **Provisioning:** Runs the full Ansible playbook inside the container to verify clean deployment.
3. **Idempotency:** Runs the playbook a second time to ensure zero unhandled changes (`changed=0`).
4. **BATS Unit Tests:** Executes the BATS shell testing framework (`tests/bats/`) against dotfiles functions.

```bash
./tests/run_container_tests.sh
```

## VM tests (full provisioning)

Test VMs are defined in `tests/vm/machines.yml` and managed via **Vagrant**.
Vagrant natively supports multiple providers including VirtualBox, VMware Desktop, and Libvirt.

### Prerequisites

| Tool | Where to get it |
|---|---|
| Vagrant | https://developer.hashicorp.com/vagrant/downloads |
| A hypervisor | VirtualBox (default), VMware Desktop, or Libvirt/KVM |

### Available test machines

| Name | OS | Profile |
|---|---|---|
| `workstation-test-debian` | Debian 13 | headless |
| `workstation-test-ubuntu24` | Ubuntu 24.04 | headless |
| `workstation-test-ubuntu26` | Ubuntu 26.04 | headless |
| `workstation-test-alma9` | AlmaLinux 9 | headless |
| `workstation-test-alma10` | AlmaLinux 10 | headless |
| `workstation-test-*-i3wm` | *OS matched* | desktop-i3wm |
| `workstation-test-*-xfce` | *OS matched* | desktop-xfce |
| `workstation-test-*-gnome` | *OS matched* | desktop-gnome |

### Running tests

#### Linux/macOS

On Linux/macOS, use the shell runner:

```bash
# Headless machines only (default)
./tests/run_vm_tests.sh

# Desktop machines
./tests/run_vm_tests.sh --desktop

# All machines (headless + desktop)
./tests/run_vm_tests.sh --all

# Specific machine(s) by name
./tests/run_vm_tests.sh workstation-test-debian workstation-test-ubuntu
```

#### Windows (Native via Vagrant)

On Windows, the VM lifecycle and Ansible provisioning are fully automated natively via **HashiCorp Vagrant**. You do NOT need WSL or Python.

**Prerequisites:**
1. **VirtualBox:** Installed on Windows.
2. **Vagrant:** Installed on Windows (e.g. `winget install HashiCorp.Vagrant`).

Vagrant automatically handles creating the VM, configuring USB passthrough, injecting SSH keys, and running the Ansible playbook *locally* inside the guest VM (`ansible_local` provisioner).

To manually bring up a specific machine without running tests:
```powershell
vagrant up workstation-test-ubuntu24
```

To run the automated VM tests on Windows, run the PowerShell script:

```powershell
# Run the tests for a specific VM (e.g. Debian 13)
.\tests\run_vm_tests.ps1 -Machines "workstation-test-debian"

# Run headless VMs (default)
.\tests\run_vm_tests.ps1

# Run desktop VMs
.\tests\run_vm_tests.ps1 -Desktop

# Run all test VMs
.\tests\run_vm_tests.ps1 -All
```

*Note: You may need to bypass the PowerShell Execution Policy if running local scripts is restricted:*
```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run_vm_tests.ps1 -Machines "workstation-test-debian"
```


Or drive Vagrant directly:

```bash
# Bring up and automatically provision a single test VM
vagrant up workstation-test-debian

# Connect via SSH
vagrant ssh workstation-test-debian

# Destroy when done
vagrant destroy workstation-test-debian
```

All `features.fpga.*` and `features.xrdp` flags default to `false` in test
VMs. `features.editor.neovim` defaults to `true`. Override via `--extra-vars`
if needed.

## Continuous Integration (Jenkins)

The repository includes a `Jenkinsfile` at the root, defining a declarative, cross-platform CI pipeline.

### Pipeline Stages

The pipeline is split into three main parts:
1. **Syntax Check**: Runs `ansible-playbook --syntax-check` on the active agent (works on both Linux and Windows).
2. **Container Tests**: Runs `./tests/run_container_tests.sh` on Unix-like agents where Podman is installed.
3. **VM Provisioning Tests**: Runs full OS VM provisions in parallel on host agents labeled:
   - `linux-vm` (triggers `./tests/run_vm_tests.sh`)
   - `windows-vm` (triggers `.\tests\run_vm_tests.ps1` via PowerShell)

### Local Jenkins Setup Guide

To run this pipeline locally on your machine:

#### 1. Start Jenkins Controller
You can run Jenkins on your system natively or via a lightweight container (Docker/Podman):
```bash
podman run -d \
  --name jenkins-local \
  -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  jenkins/jenkins:lts
```

#### 2. Configure Local/Host Agents
* **Container-based builds:** Ensure the node where the build runs has `podman` installed.
* **VM-based builds (Vagrant/VirtualBox):** Because nested virtualization is complex to configure inside containerized agents, it is recommended to run a native Jenkins agent directly on the host operating system:
  1. Go to **Manage Jenkins** -> **Nodes** -> **New Node**.
  2. Configure a permanent agent running on your host machine.
  3. Assign labels to the agent based on the environment:
     - Add `linux-vm` if running on Linux/macOS host with Vagrant + Libvirt/VirtualBox.
     - Add `windows-vm` if running on a Windows host with Vagrant + VirtualBox.
  4. Ensure Vagrant is added to the system `PATH` of the agent.

#### 3. Create Jenkins Job
1. Create a new **Pipeline** or **Multibranch Pipeline** job.
2. Select **Pipeline script from SCM** under the Pipeline configuration.
3. Configure the Git repository path. Jenkins will automatically load and run the `Jenkinsfile`.

