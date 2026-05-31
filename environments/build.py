#!/usr/bin/env python3
"""
environments/build.py — build Packer boxes and start Vagrant VMs.

Auto-discovers targets from the environments/ directory:
  • Boxes: any environments/boxes/<name>/ directory that contains a box.json
  • VMs:   any environments/<name>/ directory that contains a Vagrantfile

Adding a new box: drop a packer template + box.json into environments/boxes/<name>/.
Adding a new VM:  add a Vagrantfile to environments/<name>/.  No registration needed.

Usage:
    python environments/build.py                  # interactive picker
    python environments/build.py --list           # list discovered targets
    python environments/build.py alma9            # build one box
    python environments/build.py fpga-alma        # start one VM
    python environments/build.py alma9 fpga-alma  # build box then start VM
    python environments/build.py --all-boxes      # build all boxes
    python environments/build.py --all-vms        # start all VMs
    python environments/build.py --all            # build all boxes, then all VMs
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

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

def _ok(msg: str)     -> None: print(_c("32",   f"  +  {msg}"))
def _err(msg: str)    -> None: print(_c("31",   f"  !  {msg}"), file=sys.stderr)
def _info(msg: str)   -> None: print(_c("36",   f"  >  {msg}"))
def _banner(msg: str) -> None:
    width = 64
    line  = f"  {msg}  "
    pad   = max(0, width - len(line))
    print()
    print(_c("1;34", line + "─" * pad))

# ─────────────────────────────────────────────────────────────────────────────
# Data models
# ─────────────────────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class Box:
    id:           str   # directory name,     e.g. "alma9"
    vagrant_name: str   # Vagrant box name,   e.g. "fpga-alma9"
    template:     str   # Packer template,    e.g. "alma9.pkr.hcl"
    box_file:     Path  # built .box path,    e.g. boxes/alma9/alma9.box
    path:         Path  # box directory
    description:  str

@dataclass(frozen=True)
class VM:
    id:   str   # directory name, e.g. "fpga-alma"
    path: Path

# ─────────────────────────────────────────────────────────────────────────────
# Discovery
# ─────────────────────────────────────────────────────────────────────────────

def discover_boxes() -> list[Box]:
    if not BOXES_ROOT.is_dir():
        return []
    boxes = []
    for d in sorted(BOXES_ROOT.iterdir()):
        meta_file = d / "box.json"
        if not d.is_dir() or not meta_file.exists():
            continue
        try:
            m = json.loads(meta_file.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            _err(f"Skipping {d.name}: bad box.json ({exc})")
            continue
        missing = [k for k in ("vagrant_box_name", "packer_template", "box_file") if k not in m]
        if missing:
            _err(f"Skipping {d.name}: box.json missing keys: {', '.join(missing)}")
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
    vms = []
    for d in sorted(ENV_ROOT.iterdir()):
        if d.is_dir() and d.name != "boxes" and (d / "Vagrantfile").exists():
            vms.append(VM(id=d.name, path=d))
    return vms

# ─────────────────────────────────────────────────────────────────────────────
# Build helpers
# ─────────────────────────────────────────────────────────────────────────────

def _require(tool: str) -> str:
    exe = shutil.which(tool)
    if not exe:
        _err(f"'{tool}' not found in PATH — install it before running this script.")
        sys.exit(1)
    return exe


def _run(cmd: list[str], cwd: Path) -> int:
    """Run a command, streaming its output to the terminal."""
    return subprocess.run(cmd, cwd=cwd).returncode


def _box_registered(vagrant_name: str) -> bool:
    r = subprocess.run(
        ["vagrant", "box", "list"],
        capture_output=True, text=True,
    )
    return any(line.split()[0] == vagrant_name for line in r.stdout.splitlines() if line.strip())

# ─────────────────────────────────────────────────────────────────────────────
# Actions
# ─────────────────────────────────────────────────────────────────────────────

def build_box(box: Box) -> bool:
    packer  = _require("packer")
    vagrant = _require("vagrant")

    _banner(f"BOX  {box.id}  →  {box.vagrant_name}")

    _info("packer init")
    if _run([packer, "init", box.template], box.path) != 0:
        _err("packer init failed")
        return False

    _info("packer build  (this can take ~60 minutes)")
    if _run([packer, "build", box.template], box.path) != 0:
        _err("packer build failed")
        return False

    if not box.box_file.exists():
        _err(f"Box file not produced: {box.box_file}")
        return False

    if _box_registered(box.vagrant_name):
        _info(f"Removing existing registration: {box.vagrant_name}")
        if _run([vagrant, "box", "remove", box.vagrant_name, "--force"], box.path) != 0:
            _err("vagrant box remove failed")
            return False

    _info(f"vagrant box add --name {box.vagrant_name} {box.box_file.name}")
    if _run([vagrant, "box", "add", "--name", box.vagrant_name, str(box.box_file)], box.path) != 0:
        _err("vagrant box add failed")
        return False

    _ok(f"{box.vagrant_name} registered and ready")
    return True


def start_vm(vm: VM) -> bool:
    vagrant = _require("vagrant")
    _banner(f"VM   {vm.id}")
    _info("vagrant up")
    if _run([vagrant, "up"], vm.path) != 0:
        _err("vagrant up failed")
        return False
    _ok(f"{vm.id} is running")
    return True

# ─────────────────────────────────────────────────────────────────────────────
# Interactive picker
# ─────────────────────────────────────────────────────────────────────────────

def _print_targets(boxes: list[Box], vms: list[VM], *, numbered: bool = False) -> None:
    idx = 1
    print()
    if boxes:
        print(_c("1", "  Boxes  (packer build → vagrant box add)"))
        for b in boxes:
            num = f"[{idx:2d}]  " if numbered else "  •  "
            desc = f"  {_c('2', b.description)}" if b.description else ""
            print(f"    {num}{b.id:<16}  →  {b.vagrant_name}{desc}")
            idx += 1
    if vms:
        print()
        print(_c("1", "  VMs  (vagrant up)"))
        for v in vms:
            num = f"[{idx:2d}]  " if numbered else "  •  "
            print(f"    {num}{v.id}")
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


def interactive_pick(boxes: list[Box], vms: list[VM]) -> tuple[list[Box], list[VM]]:
    _print_targets(boxes, vms, numbered=True)
    total  = len(boxes) + len(vms)
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
            return boxes[:], vms[:]

        selected = _parse_selection(raw, total)
        if selected is None:
            print(_c("31", f"  Invalid — enter numbers 1–{total}, ranges, 'a', or 'q'."))
            continue

        sel_boxes = [boxes[n - 1]            for n in sorted(selected) if n <= len(boxes)]
        sel_vms   = [vms[n - len(boxes) - 1] for n in sorted(selected) if n >  len(boxes)]
        return sel_boxes, sel_vms

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

    box_by_id: dict[str, Box] = {b.id: b for b in boxes}
    vm_by_id:  dict[str, VM]  = {v.id: v for v in vms}

    ap = argparse.ArgumentParser(
        prog="build.py",
        description="Build Packer boxes and/or start Vagrant VMs.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "examples:\n"
            "  python environments/build.py                  # interactive\n"
            "  python environments/build.py alma9            # one box\n"
            "  python environments/build.py alma9 fpga-alma  # box then VM\n"
            "  python environments/build.py --all-boxes      # all boxes\n"
            "  python environments/build.py --all            # boxes + VMs"
        ),
    )
    ap.add_argument("targets", nargs="*",
                    help="Box or VM id(s) to build/start")
    ap.add_argument("--list", "-l", action="store_true",
                    help="List discovered targets and exit")
    ap.add_argument("--all-boxes", "-b", action="store_true",
                    help="Build all discovered boxes")
    ap.add_argument("--all-vms", "-v", action="store_true",
                    help="Start all discovered VMs")
    ap.add_argument("--all", "-a", action="store_true",
                    help="Build all boxes, then start all VMs")
    args = ap.parse_args()

    if args.list:
        _print_targets(boxes, vms)
        return

    sel_boxes: list[Box] = []
    sel_vms:   list[VM]  = []

    if args.all or args.all_boxes:
        sel_boxes = boxes[:]
    if args.all or args.all_vms:
        sel_vms = vms[:]

    unknown = []
    for t in args.targets:
        if t in box_by_id:
            if box_by_id[t] not in sel_boxes:
                sel_boxes.append(box_by_id[t])
        elif t in vm_by_id:
            if vm_by_id[t] not in sel_vms:
                sel_vms.append(vm_by_id[t])
        else:
            unknown.append(t)

    if unknown:
        _err(f"Unknown target(s): {', '.join(unknown)}")
        _err("Run with --list to see available targets.")
        sys.exit(1)

    if not sel_boxes and not sel_vms:
        sel_boxes, sel_vms = interactive_pick(boxes, vms)

    failures: list[str] = []

    for box in sel_boxes:
        if not build_box(box):
            failures.append(f"box:{box.id}")

    for vm in sel_vms:
        if not start_vm(vm):
            failures.append(f"vm:{vm.id}")

    print()
    if failures:
        _err(f"Failed: {', '.join(failures)}")
        sys.exit(1)
    _ok("All done.")


if __name__ == "__main__":
    main()
