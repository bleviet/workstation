#!/usr/bin/env python3
"""
build.py — VBoxManage-based VM lifecycle manager for FPGA dev environments.

Commands:
  create  <vm>    Full pipeline: download cloud image → create VM → run setup
  start   <vm>    VBoxManage startvm (GUI for FPGA VMs, headless for test VMs)
  stop    <vm>    Graceful ACPI shutdown
  destroy <vm>    VBoxManage unregistervm --delete
  list            Show all discovered VMs and their current VBoxManage state
  pick            Interactive picker (default when no args given)

VM definitions are discovered automatically from vm.yml files under
environments/fpga-* and tests/vm/machines.yml.

OS definitions live in environments/os/<name>/os.yml.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import platform
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import yaml

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR  = Path(__file__).parent.resolve()
OS_DIR      = SCRIPT_DIR / "os"
CACHE_DIR   = SCRIPT_DIR / ".cache" / "images"

# ── Colour helpers ────────────────────────────────────────────────────────────
_USE_COLOR = sys.stdout.isatty() and platform.system() != "Windows"

def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _USE_COLOR else text

def _ok(msg: str)   -> None: print(_c("32", f"  ✓ {msg}"))
def _err(msg: str)  -> None: print(_c("31", f"  ✗ {msg}"), file=sys.stderr)
def _info(msg: str) -> None: print(_c("34", f"  → {msg}"))
def _warn(msg: str) -> None: print(_c("33", f"  ! {msg}"))


# ── Data classes ──────────────────────────────────────────────────────────────
@dataclass
class CloudImage:
    url:          str
    checksum_url: str
    format:       str   # "qcow2" or "vmdk"

@dataclass
class OSConfig:
    name:          str
    description:   str
    vbox_ostype:   str
    cloud_image:   CloudImage
    cloud_init_dir: str
    setup_script:  str
    cleanup_script: str
    grow_fs:       str
    os_dir:        Path

@dataclass
class SharedFolder:
    host:   str
    guest:  str
    create: bool = False

@dataclass
class USBConfig:
    ehci: bool = False  # USB 2.0
    xhci: bool = False  # USB 3.0

@dataclass
class VMConfig:
    name:           str
    os_name:        str
    hostname:       str
    ram_mb:         int
    cpus:           int
    vram_mb:        int
    disk_gb:        int
    accel3d:        bool
    usb:            USBConfig
    shared_folders: list[SharedFolder]
    gui:            bool           # True = GUI window, False = headless
    vm_dir:         Path
    # resolved after load:
    os:             Optional[OSConfig] = field(default=None, repr=False)


# ── Loaders ───────────────────────────────────────────────────────────────────

def _load_os(name: str) -> OSConfig:
    path = OS_DIR / name / "os.yml"
    if not path.exists():
        raise FileNotFoundError(f"os.yml not found: {path}")
    raw = yaml.safe_load(path.read_text())
    ci  = raw["cloud_image"]
    scripts = raw.get("scripts", {})
    os_dir  = OS_DIR / name
    return OSConfig(
        name           = name,
        description    = raw.get("description", name),
        vbox_ostype    = raw["vbox_ostype"],
        cloud_image    = CloudImage(
            url          = ci["url"],
            checksum_url = ci["checksum_url"],
            format       = ci["format"],
        ),
        cloud_init_dir = raw.get("cloud_init_dir", "cloud-init"),
        setup_script   = scripts.get("setup",   "scripts/setup.sh"),
        cleanup_script = scripts.get("cleanup", "scripts/cleanup.sh"),
        grow_fs        = raw.get("grow_fs", "ext4"),
        os_dir         = os_dir,
    )


def _load_vm(vm_yml: Path, gui: Optional[bool] = None) -> VMConfig:
    raw = yaml.safe_load(vm_yml.read_text())
    usb_raw = raw.get("usb", {})
    folders = [
        SharedFolder(
            host   = sf["host"],
            guest  = sf["guest"],
            create = sf.get("create", False),
        )
        for sf in raw.get("shared_folders", [])
    ]
    return VMConfig(
        name           = raw["name"],
        os_name        = raw["os"],
        hostname       = raw.get("hostname", raw["name"]),
        ram_mb         = int(raw.get("ram_mb", 2048)),
        cpus           = int(raw.get("cpus", 2)),
        vram_mb        = int(raw.get("vram_mb", 16)),
        disk_gb        = int(raw.get("disk_gb", 40)),
        accel3d        = bool(raw.get("accel3d", False)),
        usb            = USBConfig(
            ehci = bool(usb_raw.get("ehci", False)),
            xhci = bool(usb_raw.get("xhci", False)),
        ),
        shared_folders = folders,
        gui            = gui if gui is not None else bool(raw.get("gui", False)),
        vm_dir         = vm_yml.parent,
    )


def _discover_vms() -> dict[str, Path]:
    """Return {logical_name: vm.yml path} for all discovered VMs."""
    vms: dict[str, Path] = {}

    # FPGA environments: environments/fpga-*/vm.yml
    for vm_yml in sorted(SCRIPT_DIR.glob("fpga-*/vm.yml")):
        raw = yaml.safe_load(vm_yml.read_text())
        vms[raw["name"]] = vm_yml

    # Test VMs: tests/vm/machines.yml
    machines_yml = SCRIPT_DIR.parent / "tests" / "vm" / "machines.yml"
    if machines_yml.exists():
        data = yaml.safe_load(machines_yml.read_text())
        for m in data.get("machines", []):
            # Synthesize a temporary vm.yml content as a dict; store path as machines_yml
            # We'll handle loading inline separately in _load_machine_entry.
            vms[m["name"]] = machines_yml

    return vms


def _load_machine_entry(machines_yml: Path, name: str) -> VMConfig:
    """Load a single entry from machines.yml by name."""
    data = yaml.safe_load(machines_yml.read_text())
    for m in data.get("machines", []):
        if m["name"] == name:
            return VMConfig(
                name           = m["name"],
                os_name        = m["os"],
                hostname       = m["name"],
                ram_mb         = int(m.get("ram_mb", 2048)),
                cpus           = int(m.get("cpus", 2)),
                vram_mb        = int(m.get("vram_mb", 16)),
                disk_gb        = int(m.get("disk_gb", 40)),
                accel3d        = False,
                usb            = USBConfig(),
                shared_folders = [
                    SharedFolder(
                        host  = str(SCRIPT_DIR.parent),
                        guest = "/home/vagrant/workspace/workstation",
                    )
                ],
                gui    = bool(m.get("gui", False)),
                vm_dir = machines_yml.parent,
            )
    raise KeyError(f"Machine '{name}' not found in {machines_yml}")


def _resolve_vm(name: str) -> VMConfig:
    vms = _discover_vms()
    if name not in vms:
        raise KeyError(f"VM '{name}' not found. Run 'list' to see available VMs.")
    yml_path = vms[name]
    machines_yml = SCRIPT_DIR.parent / "tests" / "vm" / "machines.yml"
    if yml_path == machines_yml:
        vm = _load_machine_entry(yml_path, name)
    else:
        vm = _load_vm(yml_path)
    vm.os = _load_os(vm.os_name)
    return vm


# ── VBoxManage helpers ────────────────────────────────────────────────────────

def _vbm(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    """Run VBoxManage with the given arguments."""
    cmd = ["VBoxManage"] + list(args)
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def _vm_exists(name: str) -> bool:
    r = _vbm("showvminfo", name, check=False)
    return r.returncode == 0


def _vm_state(name: str) -> str:
    r = _vbm("showvminfo", name, "--machinereadable", check=False)
    if r.returncode != 0:
        return "notfound"
    for line in r.stdout.splitlines():
        if line.startswith("VMState="):
            return line.split("=", 1)[1].strip('"')
    return "unknown"


def _wait_for_ssh(host: str, port: int = 22, timeout: int = 600) -> None:
    """Wait until sshd is ready: TCP connect succeeds AND SSH banner is received."""
    _info(f"Waiting for SSH on {host}:{port} (up to {timeout}s)…")
    deadline = time.time() + timeout
    last_dot = time.time()
    while time.time() < deadline:
        try:
            with socket.create_connection((host, port), timeout=5) as sock:
                sock.settimeout(5)
                banner = sock.recv(256)
                if banner.startswith(b"SSH-"):
                    print()  # newline after dots
                    _ok("SSH is up")
                    return
        except OSError:
            pass
        if time.time() - last_dot >= 10:
            print(".", end="", flush=True)
            last_dot = time.time()
        time.sleep(3)
    print()
    raise TimeoutError(f"SSH on {host}:{port} did not become available within {timeout}s")


def _vm_ip(name: str) -> Optional[str]:
    """Return guest IP from VBoxManage guestproperty (requires Guest Additions)."""
    r = _vbm("guestproperty", "get", name, "/VirtualBox/GuestInfo/Net/0/V4/IP", check=False)
    if r.returncode == 0 and "Value:" in r.stdout:
        return r.stdout.split("Value:", 1)[1].strip()
    return None


def _ssh(host: str, user: str, *cmd: str, key: Optional[Path] = None) -> None:
    """Run a command on the guest via SSH."""
    ssh_args = [
        "ssh",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "ConnectTimeout=10",
        "-o", "BatchMode=yes",
    ]
    if key:
        ssh_args += ["-i", str(key)]
    ssh_args += [f"{user}@{host}"] + list(cmd)
    subprocess.run(ssh_args, check=True)


def _scp(src: Path, host: str, dest: str, user: str, key: Optional[Path] = None) -> None:
    scp_args = [
        "scp",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "ConnectTimeout=10",
    ]
    if key:
        scp_args += ["-i", str(key)]
    scp_args += [str(src), f"{user}@{host}:{dest}"]
    subprocess.run(scp_args, check=True)


def _paramiko_put(host: str, port: int, user: str, password: str,
                  local: Path, remote: str, retries: int = 5) -> None:
    """Upload a file via SFTP using password auth (no SSH agent required)."""
    import paramiko  # type: ignore
    for attempt in range(1, retries + 1):
        try:
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            client.connect(host, port=port, username=user, password=password,
                           allow_agent=False, look_for_keys=False, timeout=30)
            try:
                sftp = client.open_sftp()
                sftp.put(str(local), remote)
                sftp.close()
            finally:
                client.close()
            return
        except Exception as exc:
            if attempt == retries:
                raise
            _warn(f"SSH not ready yet ({exc}); retrying in 5s…")
            time.sleep(5)


def _paramiko_exec(host: str, port: int, user: str, password: str,
                   cmd: str, retries: int = 5) -> None:
    """Run a shell command via SSH using password auth (no SSH agent required)."""
    import paramiko  # type: ignore
    for attempt in range(1, retries + 1):
        try:
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            client.connect(host, port=port, username=user, password=password,
                           allow_agent=False, look_for_keys=False, timeout=30)
            try:
                _, stdout, stderr = client.exec_command(cmd, get_pty=True)
                out = stdout.read().decode(errors="replace")
                rc  = stdout.channel.recv_exit_status()
                if out.strip():
                    print(out.rstrip())
                if rc != 0:
                    err = stderr.read().decode(errors="replace")
                    raise RuntimeError(
                        f"Remote command failed (exit {rc}):\n  cmd: {cmd}\n  stderr: {err.strip()}"
                    )
            finally:
                client.close()
            return
        except RuntimeError:
            raise
        except Exception as exc:
            if attempt == retries:
                raise
            _warn(f"SSH not ready yet ({exc}); retrying in 5s…")
            time.sleep(5)


# ── Cloud image helpers ───────────────────────────────────────────────────────

def _fetch_checksum(url: str, filename: str) -> Optional[str]:
    """Fetch a SHA256SUMS/CHECKSUM file and extract the hash for filename."""
    import urllib.request
    try:
        with urllib.request.urlopen(url) as resp:
            content = resp.read().decode()
        for line in content.splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[1].lstrip("*") == filename:
                return parts[0]
    except Exception as exc:
        _warn(f"Could not fetch checksum: {exc}")
    return None


def _sha256(path: Path, chunk: int = 1 << 20) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            buf = f.read(chunk)
            if not buf:
                break
            h.update(buf)
    return h.hexdigest()


def _download(url: str, dest: Path) -> None:
    import urllib.request
    _info(f"Downloading {url}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(url, dest)
    _ok(f"Saved to {dest}")


def _ensure_cloud_image(os_cfg: OSConfig) -> Path:
    """Return path to a VDI disk image, downloading/converting if needed."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    src_name = os_cfg.cloud_image.url.split("/")[-1]
    src_path = CACHE_DIR / src_name
    vdi_name = src_name.replace(".qcow2", ".vdi").replace(".img", ".vdi").replace(".vmdk", ".vdi")
    vdi_path = CACHE_DIR / vdi_name

    if vdi_path.exists():
        _ok(f"VDI cache hit: {vdi_path.name}")
        return vdi_path

    # Download if source not cached
    if not src_path.exists():
        _download(os_cfg.cloud_image.url, src_path)

        # Verify checksum
        expected = _fetch_checksum(os_cfg.cloud_image.checksum_url, src_name)
        if expected:
            actual = _sha256(src_path)
            if actual != expected:
                src_path.unlink()
                raise ValueError(f"Checksum mismatch for {src_name}: expected {expected}, got {actual}")
            _ok("Checksum verified")
        else:
            _warn("Checksum not verified (could not fetch checksum file)")

    # Convert to VDI
    _info(f"Converting {src_path.name} → {vdi_path.name}")
    subprocess.run(
        ["qemu-img", "convert", "-O", "vdi", str(src_path), str(vdi_path)],
        check=True,
    )
    _ok(f"Converted to VDI: {vdi_path.name}")
    return vdi_path


def _make_seed_iso(cloud_init_dir: Path, dest: Path) -> None:
    """Create a cloud-init seed ISO from user-data (and optional meta-data/network-config)."""
    user_data    = cloud_init_dir / "user-data"
    meta_data    = cloud_init_dir / "meta-data"
    network_cfg  = cloud_init_dir / "network-config"

    if not user_data.exists():
        raise FileNotFoundError(f"user-data not found: {user_data}")

    # Create a minimal meta-data if missing
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
        tmp_path = Path(tmp)
        shutil.copy(user_data, tmp_path / "user-data")
        if meta_data.exists():
            shutil.copy(meta_data, tmp_path / "meta-data")
        else:
            (tmp_path / "meta-data").write_text("instance-id: iid-local01\nlocal-hostname: fpga-dev\n")
        if network_cfg.exists():
            shutil.copy(network_cfg, tmp_path / "network-config")

        # Try pycdlib first, fall back to genisoimage/mkisofs
        try:
            import pycdlib  # type: ignore
            iso = pycdlib.PyCdlib()
            iso.new(interchange_level=4, vol_ident="cidata", joliet=3)
            handles: list = []
            try:
                for fname in ["user-data", "meta-data", "network-config"]:
                    src = tmp_path / fname
                    if src.exists():
                        fh = src.open("rb")
                        handles.append(fh)
                        iso.add_fp(
                            fh, src.stat().st_size,
                            f"/{fname.upper()};1", joliet_path=f"/{fname}"
                        )
                iso.write(str(dest))
            finally:
                iso.close()
                for fh in handles:
                    fh.close()
        except ImportError:
            tool = shutil.which("genisoimage") or shutil.which("mkisofs")
            if not tool:
                raise RuntimeError("Neither pycdlib nor genisoimage/mkisofs found. Install one.")
            files = [str(tmp_path / "user-data"), str(tmp_path / "meta-data")]
            if (tmp_path / "network-config").exists():
                files.append(str(tmp_path / "network-config"))
            subprocess.run(
                [tool, "-output", str(dest), "-volid", "cidata",
                 "-joliet", "-rock"] + files,
                check=True, capture_output=True,
            )
    _ok(f"Seed ISO created: {dest.name}")


# ── VM lifecycle ──────────────────────────────────────────────────────────────

def _find_admin_key() -> Optional[Path]:
    """Return path to an admin public key to inject into the VM."""
    candidates = [
        Path(__file__).parent.parent / "admin.pub",
        Path.home() / ".ssh" / "id_ed25519.pub",
        Path.home() / ".ssh" / "id_rsa.pub",
        Path.home() / ".ssh" / "id_ecdsa.pub",
    ]
    for p in candidates:
        if p.exists():
            return p
    return None


def cmd_create(vm: VMConfig) -> None:
    os_cfg = vm.os
    assert os_cfg is not None

    if _vm_exists(vm.name):
        _warn(f"VM '{vm.name}' already exists. Destroy it first with: build.py destroy {vm.name}")
        return

    print(f"\n{_c('1', f'Creating {vm.name}')}\n")

    # 1. Cloud image → VDI
    _info("Preparing cloud image…")
    vdi_src = _ensure_cloud_image(os_cfg)

    # 2. Copy VDI to VM-local location (VirtualBox needs a writable copy)
    vm_vdi_dir = CACHE_DIR / "vms" / vm.name
    vm_vdi_dir.mkdir(parents=True, exist_ok=True)
    vm_vdi = vm_vdi_dir / f"{vm.name}.vdi"
    _info(f"Copying base VDI → {vm_vdi}…")
    shutil.copy2(vdi_src, vm_vdi)

    # 3. Resize VDI to requested disk_gb
    _info(f"Resizing disk to {vm.disk_gb} GB…")
    _vbm("modifyhd", str(vm_vdi), "--resize", str(vm.disk_gb * 1024))
    _ok("Disk resized")

    # 4. Seed ISO
    ci_dir  = os_cfg.os_dir / os_cfg.cloud_init_dir
    seed_iso = vm_vdi_dir / "seed.iso"
    _info("Building cloud-init seed ISO…")
    _make_seed_iso(ci_dir, seed_iso)

    # 5. Create VM
    _info("Creating VirtualBox VM…")
    _vbm("createvm", "--name", vm.name, "--ostype", os_cfg.vbox_ostype, "--register")

    # 6. Configure hardware
    modify_args = [
        "modifyvm", vm.name,
        "--memory",   str(vm.ram_mb),
        "--cpus",     str(vm.cpus),
        "--vram",     str(vm.vram_mb),
        "--graphicscontroller", "vmsvga",
        "--audio-driver", "none",
        "--rtcuseutc",  "on",
        "--boot1",      "disk",
        "--boot2",      "dvd",
        "--nic1",       "nat",
        "--natpf1",     "ssh,tcp,,2222,,22",
    ]
    if vm.accel3d:
        modify_args += ["--accelerate3d", "on"]
    if vm.usb.ehci:
        modify_args += ["--usbehci", "on"]
    if vm.usb.xhci:
        modify_args += ["--usbxhci", "on"]
    _vbm(*modify_args)
    _ok("Hardware configured")

    # 7. Storage controllers + attach disks
    _vbm("storagectl", vm.name, "--name", "SATA", "--add", "sata",
         "--controller", "IntelAhci", "--portcount", "2")
    _vbm("storageattach", vm.name, "--storagectl", "SATA",
         "--port", "0", "--device", "0", "--type", "hdd", "--medium", str(vm_vdi))
    _vbm("storageattach", vm.name, "--storagectl", "SATA",
         "--port", "1", "--device", "0", "--type", "dvddrive", "--medium", str(seed_iso))
    _ok("Disks attached")

    # 8. Start VM
    vm_type = "gui" if vm.gui else "headless"
    _info(f"Starting VM ({vm_type})…")
    _vbm("startvm", vm.name, "--type", vm_type)

    # 9. Wait for SSH (cloud-init runs; vagrant user becomes available)
    _wait_for_ssh("127.0.0.1", port=2222, timeout=600)
    # Extra grace time for cloud-init to finish applying users/ssh_pwauth
    _info("Giving cloud-init 30s to finish…")
    time.sleep(30)

    # 10. Run setup.sh
    _VAGRANT_PASS = "vagrant"
    setup_sh = os_cfg.os_dir / os_cfg.setup_script
    if not setup_sh.exists():
        _warn(f"setup.sh not found at {setup_sh}; skipping")
    else:
        _info("Uploading and running setup.sh…")
        _paramiko_put("127.0.0.1", 2222, "vagrant", _VAGRANT_PASS, setup_sh, "/tmp/setup.sh")
        _paramiko_exec("127.0.0.1", 2222, "vagrant", _VAGRANT_PASS,
                       "chmod +x /tmp/setup.sh && sudo /tmp/setup.sh")
        _ok("setup.sh completed")

    # 11. Inject admin public key
    admin_key = _find_admin_key()
    if admin_key:
        _info(f"Injecting admin key from {admin_key}…")
        pub = admin_key.read_text().strip()
        _paramiko_exec("127.0.0.1", 2222, "vagrant", _VAGRANT_PASS,
                       f"mkdir -p ~/.ssh && echo '{pub}' >> ~/.ssh/authorized_keys"
                       " && chmod 600 ~/.ssh/authorized_keys")
        _ok("Admin key injected")
    else:
        _warn("No admin public key found; add ~/.ssh/id_ed25519.pub or admin.pub at repo root")

    # 12. Run cleanup.sh
    cleanup_sh = os_cfg.os_dir / os_cfg.cleanup_script
    if cleanup_sh.exists():
        _info("Running cleanup.sh…")
        _paramiko_put("127.0.0.1", 2222, "vagrant", _VAGRANT_PASS, cleanup_sh, "/tmp/cleanup.sh")
        _paramiko_exec("127.0.0.1", 2222, "vagrant", _VAGRANT_PASS,
                       "chmod +x /tmp/cleanup.sh && sudo /tmp/cleanup.sh")
        _ok("cleanup.sh completed")

    # 13. Detach seed ISO
    _info("Detaching seed ISO…")
    _vbm("storageattach", vm.name, "--storagectl", "SATA",
         "--port", "1", "--device", "0", "--type", "dvddrive", "--medium", "emptydrive")
    _ok("Seed ISO detached")

    # 14. Add shared folders
    if vm.shared_folders:
        _info("Adding shared folders…")
        for sf in vm.shared_folders:
            host_path = (vm.vm_dir / sf.host).resolve()
            if sf.create:
                host_path.mkdir(parents=True, exist_ok=True)
            folder_name = sf.guest.rstrip("/").split("/")[-1]
            _vbm("sharedfolder", "add", vm.name,
                 "--name", folder_name,
                 "--hostpath", str(host_path),
                 "--automount", "--auto-mount-point", sf.guest)
        _ok("Shared folders added")

    # 15. Snapshot
    _info("Taking 'clean-base' snapshot…")
    _vbm("snapshot", vm.name, "take", "clean-base",
         "--description", "Minimal base before Ansible provisioning")
    _ok("Snapshot taken")

    print(f"\n{_c('32;1', '✓ VM ready')} — SSH: ssh vagrant@127.0.0.1 -p 2222\n")
    print("  Next: add the VM's IP to provisioning/inventory/hosts.yml and run Ansible.\n")


def cmd_start(vm: VMConfig) -> None:
    state = _vm_state(vm.name)
    if state == "running":
        _warn(f"VM '{vm.name}' is already running")
        return
    vm_type = "gui" if vm.gui else "headless"
    _info(f"Starting {vm.name} ({vm_type})…")
    _vbm("startvm", vm.name, "--type", vm_type)
    _ok(f"Started {vm.name}")


def cmd_stop(vm: VMConfig) -> None:
    state = _vm_state(vm.name)
    if state not in ("running", "paused"):
        _warn(f"VM '{vm.name}' is not running (state: {state})")
        return
    _info(f"Sending ACPI shutdown to {vm.name}…")
    _vbm("controlvm", vm.name, "acpipowerbutton")
    _ok(f"Shutdown signal sent to {vm.name}")


def cmd_destroy(vm: VMConfig) -> None:
    state = _vm_state(vm.name)
    if state == "notfound":
        _warn(f"VM '{vm.name}' does not exist")
        return
    if state == "running":
        _info("Powering off before destroy…")
        _vbm("controlvm", vm.name, "poweroff")
        time.sleep(2)
    _info(f"Unregistering and deleting {vm.name}…")
    _vbm("unregistervm", vm.name, "--delete")
    _ok(f"Destroyed {vm.name}")

    # Also clean up cached VDI copy
    vm_vdi_dir = CACHE_DIR / "vms" / vm.name
    if vm_vdi_dir.exists():
        shutil.rmtree(vm_vdi_dir)
        _ok(f"Removed cached VDI for {vm.name}")


def cmd_list() -> None:
    vms = _discover_vms()
    if not vms:
        print("No VMs discovered.")
        return

    print(f"\n  {'NAME':<35} {'OS':<15} {'STATE':<12}")
    print(f"  {'-'*35} {'-'*15} {'-'*12}")
    for name, yml in sorted(vms.items()):
        machines_yml = SCRIPT_DIR.parent / "tests" / "vm" / "machines.yml"
        if yml == machines_yml:
            try:
                vm = _load_machine_entry(yml, name)
            except KeyError:
                continue
        else:
            vm = _load_vm(yml)
        state = _vm_state(name)
        state_colored = _c("32", state) if state == "running" else _c("33", state) if state == "notfound" else state
        print(f"  {name:<35} {vm.os_name:<15} {state_colored}")
    print()


# ── Interactive picker ────────────────────────────────────────────────────────

def _pick_vm() -> Optional[str]:
    """Simple numbered picker for terminals."""
    vms = _discover_vms()
    if not vms:
        _err("No VMs found.")
        return None
    names = sorted(vms.keys())
    print("\nAvailable VMs:\n")
    for i, name in enumerate(names, 1):
        state = _vm_state(name)
        print(f"  [{i:2}] {name}  ({state})")
    print()
    try:
        choice = input("  Select VM number (or q to quit): ").strip()
        if choice.lower() == "q":
            return None
        idx = int(choice) - 1
        if 0 <= idx < len(names):
            return names[idx]
        _err("Invalid selection")
    except (ValueError, EOFError):
        pass
    return None


def _pick_action(vm_name: str) -> Optional[str]:
    actions = ["create", "start", "stop", "destroy"]
    state   = _vm_state(vm_name)
    print(f"\n  VM: {vm_name}  (state: {state})\n")
    for i, action in enumerate(actions, 1):
        print(f"  [{i}] {action}")
    print()
    try:
        choice = input("  Select action: ").strip()
        idx = int(choice) - 1
        if 0 <= idx < len(actions):
            return actions[idx]
    except (ValueError, EOFError):
        pass
    return None


# ── CLI ───────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="VBoxManage-based FPGA VM manager",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="cmd")

    sub.add_parser("list",    help="List all VMs and their state")
    sub.add_parser("pick",    help="Interactive VM/action picker (default)")

    for cmd_name in ("create", "start", "stop", "destroy"):
        p = sub.add_parser(cmd_name)
        p.add_argument("vm", help="VM name (from vm.yml 'name' field)")

    args = parser.parse_args()

    if args.cmd == "list" or args.cmd is None and len(sys.argv) == 1:
        if args.cmd == "list":
            cmd_list()
            return
        # Interactive picker
        vm_name = _pick_vm()
        if not vm_name:
            return
        action = _pick_action(vm_name)
        if not action:
            return
        args.cmd = action
        args.vm  = vm_name

    if args.cmd in ("create", "start", "stop", "destroy"):
        try:
            vm = _resolve_vm(args.vm)
        except (KeyError, FileNotFoundError) as exc:
            _err(str(exc))
            sys.exit(1)
        dispatch = {
            "create":  cmd_create,
            "start":   cmd_start,
            "stop":    cmd_stop,
            "destroy": cmd_destroy,
        }
        dispatch[args.cmd](vm)
    elif args.cmd == "list":
        cmd_list()
    elif args.cmd == "pick" or args.cmd is None:
        vm_name = _pick_vm()
        if not vm_name:
            return
        action = _pick_action(vm_name)
        if not action:
            return
        try:
            vm = _resolve_vm(vm_name)
        except (KeyError, FileNotFoundError) as exc:
            _err(str(exc))
            sys.exit(1)
        dispatch = {
            "create":  cmd_create,
            "start":   cmd_start,
            "stop":    cmd_stop,
            "destroy": cmd_destroy,
        }
        dispatch[action](vm)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
