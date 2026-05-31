#!/usr/bin/env python3
"""
environments/build.py — build Packer boxes and start Vagrant VMs.

Three independent steps, each runnable on its own:

  build     packer init + packer build  →  produces <name>.box
  register  vagrant box add             →  registers .box with Vagrant
  up        vagrant up                  →  starts the VM

Auto-discovers targets:
  • Boxes: environments/boxes/<name>/  with a box.json
  • VMs:   environments/<name>/        with a Vagrantfile

Usage:
  python environments/build.py                      interactive (all steps)
  python environments/build.py --list               list all discovered targets

  python environments/build.py build   [ids] [--all]
  python environments/build.py register [ids] [--all]
  python environments/build.py up       [ids] [--all]

Examples:
  python environments/build.py build   alma9             packer build alma9
  python environments/build.py build   --all             build every box
  python environments/build.py register alma9            register alma9 with Vagrant
  python environments/build.py up      fpga-alma         vagrant up fpga-alma
  python environments/build.py up      --all             start all VMs
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

try:
    import yaml
except ImportError:
    print("PyYAML is required:  pip install pyyaml", file=sys.stderr)
    sys.exit(1)

# ─────────────────────────────────────────────────────────────────────────────
# Paths
# ─────────────────────────────────────────────────────────────────────────────

ENV_ROOT   = Path(__file__).resolve().parent
BOXES_ROOT = ENV_ROOT / "boxes"

# ─────────────────────────────────────────────────────────────────────────────
# Terminal output
# ─────────────────────────────────────────────────────────────────────────────

def _init_color() -> bool:
    if not sys.stdout.isatty():
        return False
    if sys.platform == "win32":
        try:
            import ctypes
            ctypes.windll.kernel32.SetConsoleMode(
                ctypes.windll.kernel32.GetStdHandle(-11), 7
            )
        except Exception:
            return False
    return True

_COLOR = _init_color()

def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _COLOR else text

def _ok(msg: str)     -> None: print(_c("32", f"  +  {msg}"))
def _err(msg: str)    -> None: print(_c("31", f"  !  {msg}"), file=sys.stderr)
def _info(msg: str)   -> None: print(_c("36", f"  >  {msg}"))
def _banner(msg: str) -> None:
    line = f"  {msg}  "
    print()
    print(_c("1;34", line + "─" * max(0, 64 - len(line))))

# ─────────────────────────────────────────────────────────────────────────────
# Data models
# ─────────────────────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class Box:
    id:           str   # directory name,   e.g. "alma9"
    vagrant_name: str   # Vagrant box name, e.g. "fpga-alma9"
    template:     str   # Packer template,  e.g. "alma9.pkr.hcl"
    box_file:     Path  # output .box path
    path:         Path  # box directory
    description:  str

@dataclass(frozen=True)
class VM:
    id:   str   # directory name, e.g. "fpga-alma"
    path: Path

# An operation is one discrete step (build/register/up) on one target.
@dataclass(frozen=True)
class Op:
    label:  str                    # display string for the picker
    action: Callable[[], bool]     # callable that performs the step

# ─────────────────────────────────────────────────────────────────────────────
# Discovery
# ─────────────────────────────────────────────────────────────────────────────

def discover_boxes() -> list[Box]:
    if not BOXES_ROOT.is_dir():
        return []
    boxes: list[Box] = []
    for d in sorted(BOXES_ROOT.iterdir()):
        meta_file = d / "box.yml"
        if not d.is_dir() or not meta_file.exists():
            continue
        try:
            m = yaml.safe_load(meta_file.read_text(encoding="utf-8"))
        except (yaml.YAMLError, OSError) as exc:
            _err(f"Skipping {d.name}: bad box.yml ({exc})")
            continue
        missing = [k for k in ("vagrant_box_name", "packer_template", "box_file") if k not in m]
        if missing:
            _err(f"Skipping {d.name}: box.yml missing keys: {', '.join(missing)}")
            continue
        boxes.append(Box(
            id=d.name,
            vagrant_name=m["vagrant_box_name"],
            template=m["packer_template"],
            box_file=d / m["box_file"],
            path=d,
            description=m.get("description", ""),
        ))
    return boxes


def discover_vms() -> list[VM]:
    vms: list[VM] = []
    for d in sorted(ENV_ROOT.iterdir()):
        if d.is_dir() and d.name != "boxes" and (d / "Vagrantfile").exists():
            vms.append(VM(id=d.name, path=d))
    return vms

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _require(tool: str) -> str:
    exe = shutil.which(tool)
    if not exe:
        _err(f"'{tool}' not found in PATH — install it before running this script.")
        sys.exit(1)
    return exe


def _run(cmd: list[str], cwd: Path) -> int:
    return subprocess.run(cmd, cwd=cwd).returncode


def _box_registered(vagrant_name: str) -> bool:
    r = subprocess.run(["vagrant", "box", "list"], capture_output=True, text=True)
    return any(
        line.split()[0] == vagrant_name
        for line in r.stdout.splitlines() if line.strip()
    )

# ─────────────────────────────────────────────────────────────────────────────
# Cloud image preparation (used by boxes that set cloud_image: in box.yml)
# ─────────────────────────────────────────────────────────────────────────────

_VMX_TEMPLATE = """\
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "19"
guestOS = "{guest_os_type}"
displayName = "{display_name}"
memsize = "2048"
numvcpus = "4"

sata0.present = "TRUE"
sata0:0.present = "TRUE"
sata0:0.fileName = "{vmdk_filename}"
sata0:0.deviceType = "disk"

sata0:1.present = "TRUE"
sata0:1.fileName = "{seed_iso_filename}"
sata0:1.deviceType = "cdrom-image"

ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "e1000e"
ethernet0.wakeOnPcktRcv = "FALSE"
ethernet0.addressType = "generated"

usb.present = "TRUE"
sound.absent = "TRUE"
svga.autodetect = "TRUE"
tools.syncTime = "TRUE"
"""


def _download_file(url: str, dest: Path) -> None:
    _info(f"Downloading {Path(url).name}")

    def _progress(count: int, block_size: int, total: int) -> None:
        if total > 0:
            done = min(count * block_size, total)
            pct = done * 100 // total
            mb = done >> 20
            total_mb = total >> 20
            print(f"\r  {pct:3d}%  {mb} / {total_mb} MB", end="", flush=True)

    urllib.request.urlretrieve(url, dest, reporthook=_progress)
    print()


def _verify_checksum(filepath: Path, checksum_url: str) -> None:
    _info("Verifying checksum")
    sha256 = hashlib.sha256()
    with filepath.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            sha256.update(chunk)
    actual = sha256.hexdigest()

    with urllib.request.urlopen(checksum_url) as resp:
        checksum_text = resp.read().decode()

    # Accept either "SHA256 (filename) = hash" (AlmaLinux) or "hash  *filename" (Ubuntu).
    if not any(re.search(rf'(?:^|\s){re.escape(actual)}(?:\s|$)', line)
               for line in checksum_text.splitlines()):
        raise RuntimeError(f"Checksum {actual} not found in {checksum_url}")
    _ok("Checksum OK")


def _convert_to_vmdk(src: Path, vmdk: Path) -> None:
    qemu_img = _require("qemu-img")
    _info(f"Converting {src.name} → {vmdk.name}")
    rc = _run(
        [qemu_img, "convert", "-p", "-f", "qcow2", "-O", "vmdk",
         "-o", "subformat=monolithicSparse", str(src), str(vmdk)],
        src.parent,
    )
    if rc != 0:
        raise RuntimeError("qemu-img convert failed")


def _make_seed_iso(user_data: Path, meta_data_text: str, dest: Path) -> None:
    # pycdlib is pure Python and works on Windows, Linux, and macOS.
    try:
        import io
        import pycdlib  # type: ignore[import-untyped]

        iso = pycdlib.PyCdlib()
        # interchange_level=4 (ISO 9660:1999) lifts the 8.3 filename limit,
        # allowing "user-data" and "meta-data" as literal ISO paths.
        iso.new(interchange_level=4, joliet=3, rock_ridge="1.09", vol_ident="CIDATA")
        ud = user_data.read_bytes()
        md = meta_data_text.encode()
        iso.add_fp(io.BytesIO(ud), len(ud),
                   iso_path="/user-data", joliet_path="/user-data", rr_name="user-data")
        iso.add_fp(io.BytesIO(md), len(md),
                   iso_path="/meta-data", joliet_path="/meta-data", rr_name="meta-data")
        iso.write(str(dest))
        iso.close()
        return
    except ImportError:
        pass

    # Fall back to system ISO tools (Linux/macOS only).
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        (tmp_path / "user-data").write_text(user_data.read_text())
        (tmp_path / "meta-data").write_text(meta_data_text)
        for tool in ("genisoimage", "mkisofs", "xorrisofs"):
            exe = shutil.which(tool)
            if not exe:
                continue
            flags = ["-output", str(dest), "-volid", "cidata",
                     "-joliet", "-rock", "user-data", "meta-data"]
            if _run([exe] + flags, tmp_path) == 0:
                return

    raise RuntimeError(
        "Seed ISO creation failed — install pycdlib:  pip install pycdlib\n"
        "  (Linux alternative: sudo apt install genisoimage)"
    )


def _write_vmx(vmx: Path, vmdk: Path, seed_iso: Path,
               guest_os_type: str, box_id: str) -> None:
    vmx.write_text(_VMX_TEMPLATE.format(
        guest_os_type=guest_os_type,
        display_name=f"{box_id}-cloud-build",
        vmdk_filename=vmdk.name,
        seed_iso_filename=seed_iso.name,
    ))


def prepare_cloud_image(box: Box) -> Path:
    """Download + convert cloud image, write seed ISO and VMX. Returns VMX path."""
    ci = yaml.safe_load((box.path / "box.yml").read_text())["cloud_image"]
    url: str          = ci["url"]
    checksum_url: str = ci["checksum_url"]
    guest_os_type: str = ci["guest_os_type"]

    cache_dir = box.path / "cache"
    build_dir = box.path / "build"
    cache_dir.mkdir(exist_ok=True)
    build_dir.mkdir(exist_ok=True)

    # Download cloud image (kept in cache/ so re-builds skip the download).
    cloud_path = cache_dir / Path(url).name
    if cloud_path.exists():
        _info(f"Using cached cloud image: {cloud_path.name}")
    else:
        _download_file(url, cloud_path)
        _verify_checksum(cloud_path, checksum_url)

    # Produce a VMDK in build/: copy if already VMDK, convert if QCOW2.
    vmdk_path = build_dir / f"{box.id}-cloud.vmdk"
    vmdk_fresh = vmdk_path.exists() and vmdk_path.stat().st_mtime >= cloud_path.stat().st_mtime
    if vmdk_fresh:
        _info(f"VMDK up to date: {vmdk_path.name}")
    elif ci["format"] == "vmdk":
        shutil.copy2(cloud_path, vmdk_path)
        _ok(f"VMDK copied: {vmdk_path.name}")
    else:
        _convert_to_vmdk(cloud_path, vmdk_path)

    # Seed ISO with cloud-init config (always regenerated — takes < 1 s).
    seed_iso_path = build_dir / "seed.iso"
    meta_data = f"instance-id: {box.id}-build\nlocal-hostname: {box.id}-vagrant\n"
    _make_seed_iso(box.path / "cloud-init" / "user-data", meta_data, seed_iso_path)
    _ok("Seed ISO ready")

    # VMX wrapper pointing at the VMDK and seed ISO.
    vmx_path = build_dir / f"{box.id}-cloud.vmx"
    _write_vmx(vmx_path, vmdk_path, seed_iso_path, guest_os_type, box.id)
    _ok("VMX ready")

    return vmx_path


# ─────────────────────────────────────────────────────────────────────────────
# Steps
# ─────────────────────────────────────────────────────────────────────────────

def packer_build(box: Box) -> bool:
    """packer init + packer build → produces box_file."""
    packer = _require("packer")
    _banner(f"BUILD  {box.id}  ({box.template})")

    extra_args: list[str] = []
    meta = yaml.safe_load((box.path / "box.yml").read_text())
    if "cloud_image" in meta:
        try:
            vmx_path = prepare_cloud_image(box)
        except Exception as exc:
            _err(f"Cloud image preparation failed: {exc}")
            return False
        extra_args = ["-var", f"vmx_path={vmx_path}"]

    _info("packer init")
    if _run([packer, "init", box.template], box.path) != 0:
        _err("packer init failed")
        return False
    _info("packer build  (this can take ~60 minutes)")
    if _run([packer, "build", "-force"] + extra_args + [box.template], box.path) != 0:
        _err("packer build failed")
        return False
    if not box.box_file.exists():
        _err(f"Box file not produced: {box.box_file}")
        return False
    _ok(f"{box.box_file.name} ready")
    return True


def register_box(box: Box) -> bool:
    """vagrant box add — register a built .box file with Vagrant."""
    vagrant = _require("vagrant")
    _banner(f"REGISTER  {box.id}  →  {box.vagrant_name}")
    if not box.box_file.exists():
        _err(f"Box file not found: {box.box_file}")
        _err(f"Run  'build.py build {box.id}'  first.")
        return False
    if _box_registered(box.vagrant_name):
        _info(f"Removing existing registration: {box.vagrant_name}")
        if _run(["vagrant", "box", "remove", box.vagrant_name, "--force"], box.path) != 0:
            _err("vagrant box remove failed")
            return False
    _info(f"vagrant box add --name {box.vagrant_name} {box.box_file.name}")
    if _run(["vagrant", "box", "add", "--name", box.vagrant_name, str(box.box_file)], box.path) != 0:
        _err("vagrant box add failed")
        return False
    _ok(f"{box.vagrant_name} registered")
    return True


def vagrant_up(vm: VM) -> bool:
    """vagrant up — start the VM."""
    _require("vagrant")
    _banner(f"UP  {vm.id}")
    _info("vagrant up")
    if _run(["vagrant", "up"], vm.path) != 0:
        _err("vagrant up failed")
        return False
    _ok(f"{vm.id} is running")
    return True

# ─────────────────────────────────────────────────────────────────────────────
# Interactive picker
# ─────────────────────────────────────────────────────────────────────────────

def _build_ops(boxes: list[Box], vms: list[VM]) -> list[Op]:
    """Build the flat numbered operation list shown in the interactive picker."""
    ops: list[Op] = []

    if boxes:
        for b in boxes:
            ops.append(Op(
                label=f"build     {b.id:<16}  packer build {b.template}",
                action=lambda box=b: packer_build(box),
            ))

    if boxes:
        for b in boxes:
            ops.append(Op(
                label=f"register  {b.id:<16}  vagrant box add --name {b.vagrant_name}",
                action=lambda box=b: register_box(box),
            ))

    if vms:
        for v in vms:
            ops.append(Op(
                label=f"up        {v.id}",
                action=lambda vm=v: vagrant_up(vm),
            ))

    return ops


def _print_ops(ops: list[Op], *, numbered: bool = False) -> None:
    sections = [
        ("Packer build",           [o for o in ops if o.label.startswith("build")]),
        ("Register (vagrant box add)", [o for o in ops if o.label.startswith("register")]),
        ("Start VM (vagrant up)",  [o for o in ops if o.label.startswith("up")]),
    ]
    idx = 1
    print()
    for title, items in sections:
        if not items:
            continue
        print(_c("1", f"  {title}"))
        for op in items:
            num = f"[{idx:2d}]  " if numbered else "  •  "
            print(f"    {num}{op.label}")
            idx += 1
        print()


def _parse_selection(raw: str, total: int) -> set[int] | None:
    selected: set[int] = set()
    for token in raw.replace(",", " ").split():
        if "-" in token:
            parts = token.split("-", 1)
            try:
                lo, hi = int(parts[0]), int(parts[1])
                selected.update(range(lo, hi + 1))
            except ValueError:
                return None
        else:
            try:
                selected.add(int(token))
            except ValueError:
                return None
    if not selected or any(n < 1 or n > total for n in selected):
        return None
    return selected


def interactive_pick(ops: list[Op]) -> list[Op]:
    _print_ops(ops, numbered=True)
    prompt = _c("33", "  Select (numbers/ranges e.g. '1 3' or '1-3', 'a'=all, 'q'=quit): ")
    while True:
        try:
            raw = input(prompt).strip()
        except (EOFError, KeyboardInterrupt):
            print()
            sys.exit(0)
        if raw.lower() in ("q", "quit"):
            sys.exit(0)
        if raw.lower() in ("a", "all"):
            return ops[:]
        selected = _parse_selection(raw, len(ops))
        if selected is None:
            print(_c("31", f"  Invalid — enter numbers 1–{len(ops)}, ranges, 'a', or 'q'."))
            continue
        return [ops[n - 1] for n in sorted(selected)]

# ─────────────────────────────────────────────────────────────────────────────
# Subcommand handlers
# ─────────────────────────────────────────────────────────────────────────────

def _run_ops(ops: list[Op]) -> None:
    failures: list[str] = []
    for op in ops:
        if not op.action():
            failures.append(op.label.split()[1])  # target id
    print()
    if failures:
        _err(f"Failed: {', '.join(failures)}")
        sys.exit(1)
    _ok("All done.")


def cmd_build(args: argparse.Namespace, boxes: list[Box]) -> None:
    box_by_id = {b.id: b for b in boxes}
    if args.all:
        sel = boxes[:]
    elif args.targets:
        sel, unknown = [], []
        for t in args.targets:
            (sel if t in box_by_id else unknown).append(t)
        if unknown:
            _err(f"Unknown box(es): {', '.join(unknown)}")
            sys.exit(1)
        sel = [box_by_id[t] for t in args.targets]
    else:
        ops = _build_ops(boxes, [])
        build_ops = [o for o in ops if o.label.startswith("build")]
        sel_ops = interactive_pick(build_ops)
        _run_ops(sel_ops)
        return
    _run_ops([Op(label=f"build {b.id}", action=lambda b=b: packer_build(b)) for b in sel])


def cmd_register(args: argparse.Namespace, boxes: list[Box]) -> None:
    box_by_id = {b.id: b for b in boxes}
    if args.all:
        sel = boxes[:]
    elif args.targets:
        sel, unknown = [], []
        for t in args.targets:
            (sel if t in box_by_id else unknown).append(t)
        if unknown:
            _err(f"Unknown box(es): {', '.join(unknown)}")
            sys.exit(1)
        sel = [box_by_id[t] for t in args.targets]
    else:
        ops = _build_ops(boxes, [])
        reg_ops = [o for o in ops if o.label.startswith("register")]
        sel_ops = interactive_pick(reg_ops)
        _run_ops(sel_ops)
        return
    _run_ops([Op(label=f"register {b.id}", action=lambda b=b: register_box(b)) for b in sel])


def cmd_up(args: argparse.Namespace, vms: list[VM]) -> None:
    vm_by_id = {v.id: v for v in vms}
    if args.all:
        sel = vms[:]
    elif args.targets:
        sel, unknown = [], []
        for t in args.targets:
            (sel if t in vm_by_id else unknown).append(t)
        if unknown:
            _err(f"Unknown VM(s): {', '.join(unknown)}")
            sys.exit(1)
        sel = [vm_by_id[t] for t in args.targets]
    else:
        ops = _build_ops([], vms)
        up_ops = [o for o in ops if o.label.startswith("up")]
        sel_ops = interactive_pick(up_ops)
        _run_ops(sel_ops)
        return
    _run_ops([Op(label=f"up {v.id}", action=lambda v=v: vagrant_up(v)) for v in sel])

# ─────────────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────────────

def main() -> None:
    boxes = discover_boxes()
    vms   = discover_vms()

    if not boxes and not vms:
        _err(
            "Nothing discovered.\n"
            "  • Add environments/boxes/<name>/box.json for a new box\n"
            "  • Add environments/<name>/Vagrantfile for a new VM"
        )
        sys.exit(1)

    ap = argparse.ArgumentParser(
        prog="build.py",
        description="Build Packer boxes and start Vagrant VMs — one step at a time.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument("--list", "-l", action="store_true",
                    help="List all discovered targets and exit")
    subs = ap.add_subparsers(dest="cmd", metavar="COMMAND")

    for name, help_text, targets_help in [
        ("build",    "packer init + packer build  (produces .box file)", "box ids to build"),
        ("register", "vagrant box add             (register .box with Vagrant)", "box ids to register"),
        ("up",       "vagrant up                  (start the VM)", "VM ids to start"),
    ]:
        p = subs.add_parser(name, help=help_text)
        p.add_argument("targets", nargs="*", help=targets_help)
        p.add_argument("--all", "-a", action="store_true",
                       help=f"Run on all available targets")

    args = ap.parse_args()

    ops = _build_ops(boxes, vms)

    if args.list:
        _print_ops(ops)
        return

    if args.cmd == "build":
        cmd_build(args, boxes)
    elif args.cmd == "register":
        cmd_register(args, boxes)
    elif args.cmd == "up":
        cmd_up(args, vms)
    else:
        # No subcommand: full interactive picker across all three sections.
        sel_ops = interactive_pick(ops)
        _run_ops(sel_ops)


if __name__ == "__main__":
    main()
