# Building the Debian 13 Vagrant box with Packer

The official Debian project publishes `debian/trixie64` for VirtualBox only.
No pre-built VMware-compatible Vagrant box exists for Debian 13. This guide
explains how to build one locally from the official Debian 13 netinstall ISO
using Packer.

---

## Prerequisites

Install the following on your **Windows** machine (where VMware Workstation
already runs):

| Tool | Where to get it |
|---|---|
| Packer ≥ 1.10 | https://developer.hashicorp.com/packer/downloads |
| VMware Workstation Pro | already installed |
| Vagrant VMware plugin | already installed |

Verify Packer is on your PATH:

```powershell
packer version
```

---

## Build the box

All commands run from `environments\fpga-debian\packer\` on Windows.

**Step 1 — Download Packer plugins** (once per machine):

```powershell
packer init debian13.pkr.hcl
```

This downloads the `vmware` and `vagrant` Packer plugins.

**Step 2 — Build the box** (~20–30 min, VMware console visible):

```powershell
packer build debian13.pkr.hcl
```

Packer will:
1. Download the official Debian 13 netinstall ISO (~700 MB)
2. Boot a temporary VM and run the Debian installer fully automated via preseed
3. Configure the `vagrant` user, passwordless sudo, and SSH access
4. Install `open-vm-tools`
5. Clean up and compress into `environments\fpga-debian\debian13.box`

**Step 3 — Register the box with Vagrant** (once per machine):

```powershell
vagrant box add --name fpga-debian13 ..\debian13.box
```

Verify:

```powershell
vagrant box list
# fpga-debian13  (vmware_desktop, 0)
```

**Step 4 — Start the VM**:

```powershell
cd ..   # back to environments\fpga-debian\
vagrant up
```

---

## Updating the box

When a new Debian 13 point release comes out:

1. Update `debian_version` and `iso_checksum` in `packer/debian13.pkr.hcl`.
   The SHA-256 checksum is published at:
   `https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA256SUMS`

2. Rebuild:

   ```powershell
   packer build debian13.pkr.hcl
   vagrant box remove fpga-debian13
   vagrant box add --name fpga-debian13 ..\debian13.box
   ```

---

## What the build pipeline does

```
packer/
├── debian13.pkr.hcl       Packer template — vmware-iso source + vagrant post-processor
├── http/
│   └── preseed.cfg        Fully automated Debian installer answers
└── scripts/
    ├── setup.sh           vagrant user · passwordless sudo · SSH key · open-vm-tools
    └── cleanup.sh         apt clean · zero free space · remove SSH host keys
```

### preseed.cfg

Drives the Debian installer without any human input. Key choices:

- **Partitioning**: LVM with a single root volume (`atomic` recipe) — matches
  the standard Debian installer default and is expected by the grow-disk
  provisioner in the Vagrantfile.
- **User**: `vagrant` / `vagrant` (Vagrant replaces the insecure SSH key on
  first `vagrant up`).
- **Packages**: `openssh-server sudo open-vm-tools curl` — the minimum needed
  for Vagrant and Ansible access.

### setup.sh

- Writes `/etc/sudoers.d/vagrant` for passwordless sudo.
- Installs the [Vagrant insecure public key](https://github.com/hashicorp/vagrant/blob/main/keys/vagrant.pub)
  into `/home/vagrant/.ssh/authorized_keys`. Vagrant replaces this with a
  generated keypair on first boot.
- Disables predictable network interface names (`net.ifnames=0`) so the
  interface stays `eth0`.

### cleanup.sh

Minimizes box size before packaging:

- Runs `apt-get clean` and removes `/var/lib/apt/lists/`.
- Removes SSH host keys (regenerated on first boot per VM).
- Truncates the machine ID (a new ID is generated on first boot).
- Zeroes free disk space so the `.box` archive compresses well
  (typically 500 MB from a 20 GB disk image).

---

## Troubleshooting

**`boot_command` does not reach the installer**  
The Debian installer isolinux menu timing varies. Increase `boot_wait` in
`debian13.pkr.hcl` (e.g. `"10s"`) and set `headless = false` to watch the
console.

**SSH timeout during installation**  
The netinstall downloads packages from the internet. On slow connections,
increase `ssh_timeout` (default `60m`).

**`guest_os_type = "debian13-64"` not recognised by your VMware version**  
Older VMware Workstation releases may not include a Debian 13 guest OS
profile. Change the value to `"debian12-64"` — the build will still succeed,
the guest profile only affects default hardware recommendations.

**Box already registered**  
If `vagrant box add` fails with "already exists", remove the old one first:
```powershell
vagrant box remove fpga-debian13
```
