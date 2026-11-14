#!/usr/bin/env python3
"""Provision and verify the playbook on throwaway Proxmox VMs.

Same machine list as the Vagrant tests (tests/vm/machines.yml), but the VMs are
linked clones on a Proxmox VE host, so nothing lands on the local disk.

Usage:
  tests/run_proxmox_tests.py                       # headless machines (default)
  tests/run_proxmox_tests.py --desktop             # desktop-profile machines
  tests/run_proxmox_tests.py --all                 # every machine
  tests/run_proxmox_tests.py workstation-test-debian ...   # by name
  tests/run_proxmox_tests.py --keep ...            # leave VMs running afterwards
  tests/run_proxmox_tests.py --destroy [names]     # delete test VMs (all if no names)
  tests/run_proxmox_tests.py --templates           # one-time template build (SSH root@host)
  tests/run_proxmox_tests.py --list                # show machines, VMIDs and IPs

Each run creates the VMs, runs ansible/site.yml twice (second run must report
changed=0 failed=0 per host), then destroys them. Needs PROXMOX_TOKEN_ID and
PROXMOX_TOKEN_SECRET in the environment (see docs/testing.md).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PVE_DIR = REPO / "tests" / "proxmox"
MACHINES_FILE = REPO / "tests" / "vm" / "machines.yml"
LOG_DIR = Path(tempfile.gettempdir())
RECAP = re.compile(
    r"^(?P<host>\S+)\s+:\s+ok=\d+\s+changed=(?P<changed>\d+)\s+"
    r"unreachable=(?P<unreachable>\d+)\s+failed=(?P<failed>\d+)"
)

try:
    import yaml  # ships with ansible-core
except ImportError:  # pragma: no cover
    sys.exit("PyYAML is required (it is installed with ansible-core).")


def load_yaml(path: Path) -> dict:
    with path.open(encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def machine_table() -> list[dict]:
    settings = load_yaml(PVE_DIR / "settings.yml")
    rows = []
    for index, m in enumerate(load_yaml(MACHINES_FILE)["machines"]):
        rows.append({
            **m,
            "vmid": int(settings["proxmox_test_vmid_base"]) + index,
            "ip": f'{settings["proxmox_test_ip_prefix"]}.{int(settings["proxmox_test_ip_start"]) + index}',
            "hostname": f'pve-{m["name"]}',
        })
    return rows


def run(cmd: list[str], log: Path) -> int:
    """Run cmd from the repo root, tee-ing output into log."""
    print(f"  $ {' '.join(cmd)}\n    log: {log}", flush=True)
    with log.open("w", encoding="utf-8") as fh:
        proc = subprocess.Popen(cmd, cwd=REPO, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        assert proc.stdout is not None
        for line in proc.stdout:
            fh.write(line)
        return proc.wait()


def recap(log: Path) -> dict[str, dict[str, int]]:
    hosts = {}
    for line in log.read_text(encoding="utf-8").splitlines():
        m = RECAP.match(line.strip())
        if m:
            hosts[m["host"]] = {k: int(m[k]) for k in ("changed", "unreachable", "failed")}
    return hosts


TOKEN_FILE = Path("~/.config/workstation-proxmox/token.env").expanduser()


def load_token_file() -> None:
    """Fill PROXMOX_* from TOKEN_FILE (KEY=VALUE lines) unless already exported."""
    if not TOKEN_FILE.is_file():
        return
    if os.name == "posix" and TOKEN_FILE.stat().st_mode & 0o077:
        print(f"warning: {TOKEN_FILE} is readable by others; run: chmod 600 {TOKEN_FILE}", file=sys.stderr)
    for raw in TOKEN_FILE.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = (part.strip() for part in line.removeprefix("export ").split("=", 1))
        if key.startswith("PROXMOX_") and not os.environ.get(key):
            os.environ[key] = value.strip("'\"")


def require_token() -> None:
    load_token_file()
    missing = [v for v in ("PROXMOX_TOKEN_ID", "PROXMOX_TOKEN_SECRET") if not os.environ.get(v)]
    if missing:
        sys.exit(f"Missing {', '.join(missing)}: export them or put them in {TOKEN_FILE} (see docs/testing.md).")


def playbook(name: str, machines: list[str] | None = None, extra: dict | None = None) -> list[str]:
    ev = dict(extra or {})
    if machines is not None:
        ev["proxmox_machines"] = machines
    return ["ansible-playbook", str(PVE_DIR / name), "-e", json.dumps(ev)]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*", help="machine names from tests/vm/machines.yml")
    sel = ap.add_mutually_exclusive_group()
    sel.add_argument("--desktop", action="store_true", help="desktop-profile machines")
    sel.add_argument("--all", action="store_true", help="all machines")
    ap.add_argument("--keep", action="store_true", help="do not destroy VMs after the run")
    ap.add_argument("--destroy", action="store_true", help="only destroy test VMs")
    ap.add_argument("--templates", action="store_true", help="build cloud-init templates (SSH as root)")
    ap.add_argument("--list", action="store_true", help="list machines, VMIDs and IPs")
    args = ap.parse_args()

    table = machine_table()
    by_name = {m["name"]: m for m in table}

    if args.list:
        for m in table:
            print(f'{m["name"]:34} {m["os"]:11} {m["profile"]:14} vmid={m["vmid"]} ip={m["ip"]}')
        return 0

    if args.templates:
        host = load_yaml(PVE_DIR / "settings.yml")["proxmox_api_host"]
        log = LOG_DIR / "workstation-proxmox-templates.log"
        rc = run(["ansible-playbook", str(PVE_DIR / "templates.yml"), "-i", f"{host},", "-u", "root"], log)
        print("templates: OK" if rc == 0 else f"templates: FAILED (rc={rc}), see {log}")
        return rc

    unknown = [n for n in args.names if n not in by_name]
    if unknown:
        sys.exit(f"Unknown machine(s): {', '.join(unknown)}. Try --list.")

    require_token()

    if args.destroy:
        log = LOG_DIR / "workstation-proxmox-destroy.log"
        cmd = playbook("destroy.yml", args.names) if args.names else playbook("destroy.yml", extra={"proxmox_destroy_all": True})
        return run(cmd, log)

    if args.names:
        chosen = args.names
    elif args.all:
        chosen = [m["name"] for m in table]
    else:
        chosen = [m["name"] for m in table if bool(m.get("gui", False)) == args.desktop]

    print(f"Proxmox test VMs: {', '.join(chosen)}")
    hostnames = {by_name[n]["hostname"]: n for n in chosen}
    state_inventory = Path(load_yaml(PVE_DIR / "settings.yml")["proxmox_state_dir"]).expanduser() / "inventory.yml"
    site = ["ansible-playbook", "ansible/site.yml",
            "-i", "ansible/inventory/hosts.yml", "-i", str(state_inventory), "-l", "proxmox_tests"]
    results: dict[str, str] = {}
    rc = 1
    try:
        print("[1/4] Creating VMs")
        if run(playbook("create.yml", chosen), LOG_DIR / "workstation-proxmox-create.log") != 0:
            print("create: FAILED")
            return 1

        print("[2/4] Provisioning (run 1)")
        log1 = LOG_DIR / "workstation-proxmox-run1.log"
        run(site, log1)
        print("[3/4] Idempotency (run 2)")
        log2 = LOG_DIR / "workstation-proxmox-run2.log"
        run(site, log2)

        r1, r2 = recap(log1), recap(log2)
        for host, name in hostnames.items():
            a, b = r1.get(host), r2.get(host)
            if not a or a["failed"] or a["unreachable"]:
                results[name] = f"FAIL (provision: {a or 'no recap'})"
            elif not b or b["failed"] or b["unreachable"] or b["changed"]:
                results[name] = f"FAIL (idempotency: {b or 'no recap'})"
            else:
                results[name] = "PASS"
        rc = 0 if all(v == "PASS" for v in results.values()) else 1
    finally:
        if args.keep:
            print("[4/4] Keeping VMs (--keep); destroy later with --destroy")
        else:
            print("[4/4] Destroying VMs")
            run(playbook("destroy.yml", chosen), LOG_DIR / "workstation-proxmox-destroy.log")

    print("\nResults:")
    for name in chosen:
        print(f"  {name:34} {results.get(name, 'NOT RUN')}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
