#!/usr/bin/env python3
"""
FPGA Dev Environment Manager
Cross-platform TUI for managing Vagrant VMs and Packer builds.

Usage:
    python tools/manage.py

Requirements:
    pip install textual>=0.50.0          # or: pip install -r tools/requirements.txt
"""

from __future__ import annotations

import asyncio
import json
import shutil
from pathlib import Path
from typing import Sequence

from textual import on, work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Container, Horizontal, Vertical
from textual.reactive import reactive
from textual.screen import ModalScreen
from textual.widgets import (
    Button,
    Footer,
    Header,
    Label,
    ListItem,
    ListView,
    RichLog,
    Static,
)

# ─────────────────────────────────────────────────────────────────────────────
# Repository layout
# ─────────────────────────────────────────────────────────────────────────────

REPO_ROOT  = Path(__file__).resolve().parent.parent
ENV_ROOT   = REPO_ROOT / "environments"
BOXES_ROOT = ENV_ROOT / "boxes"

# ─────────────────────────────────────────────────────────────────────────────
# Environment registry
# ─────────────────────────────────────────────────────────────────────────────

def _load_env(env_id: str, label: str, box_dir: str | None = None) -> dict:
    """Build an env entry; packer metadata is read from boxes/<box_dir>/box.json."""
    entry: dict = {
        "id":     env_id,
        "label":  label,
        "path":   ENV_ROOT / env_id,
        "packer": box_dir is not None,
    }
    if box_dir:
        packer_path = BOXES_ROOT / box_dir
        meta = json.loads((packer_path / "box.json").read_text(encoding="utf-8"))
        entry.update({
            "desc":             f"{label}  ·  Packer-built local box",
            "box_name":         meta["vagrant_box_name"],
            "packer_path":      packer_path,
            "packer_template":  meta["packer_template"],
            "box_output":       meta["box_file"],
        })
    else:
        entry["desc"] = label
    return entry

ENVS: list[dict] = [
    _load_env("fpga-alma",   "AlmaLinux 9",        box_dir="alma9"),
    _load_env("fpga-ubuntu", "Ubuntu 24.04 LTS",   box_dir="ubuntu2404"),
    _load_env("fpga-debian", "Debian 13 (Trixie)", box_dir="debian13"),
]

# Vagrant machine-readable state → (bullet, rich-color, label)
_STATES: dict[str, tuple[str, str, str]] = {
    "running":     ("●", "green",        "running"),
    "poweroff":    ("◌", "yellow",       "stopped"),
    "saved":       ("◌", "cyan",         "saved"),
    "not_created": ("✕", "bright_black", "not created"),
    "aborted":     ("✕", "red",          "aborted"),
    "unknown":     ("?", "bright_black", "unknown"),
    "error":       ("!", "red",          "error"),
}

def _fmt(state: str) -> str:
    sym, color, label = _STATES.get(state, _STATES["unknown"])
    return f"[{color}]{sym} {label}[/{color}]"


# ─────────────────────────────────────────────────────────────────────────────
# Subprocess helpers
# ─────────────────────────────────────────────────────────────────────────────

def _resolve(name: str) -> str | None:
    """Return full path to an executable, or None if not in PATH."""
    return shutil.which(name)


async def _stream(cmd: Sequence[str], cwd: Path, log: RichLog) -> int:
    """Run *cmd* in *cwd*, stream combined output to *log*, return exit code."""
    display = " ".join(str(a) for a in cmd)
    log.write(f"\n[bold cyan]╔═ {display}[/bold cyan]")

    exe = _resolve(str(cmd[0]))
    if not exe:
        log.write(f"[red]  ✕ '{cmd[0]}' not found in PATH[/red]")
        return 1

    full = [exe, *cmd[1:]]
    try:
        proc = await asyncio.create_subprocess_exec(
            *full,
            cwd=str(cwd),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
    except OSError as exc:
        log.write(f"[red]  ✕ {exc}[/red]")
        return 1

    async for raw in proc.stdout:
        line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
        if line:
            log.write(f"  {line}")

    rc = await proc.wait()
    log.write(f"[{'green' if rc == 0 else 'red'}]╚═ {'✓ done' if rc == 0 else f'✕ exit {rc}'}[/]")
    return rc


async def _vagrant_state(path: Path) -> str:
    exe = _resolve("vagrant")
    if not exe:
        return "error"
    try:
        proc = await asyncio.create_subprocess_exec(
            exe, "status", "--machine-readable",
            cwd=str(path),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        out, _ = await proc.communicate()
    except OSError:
        return "error"
    for line in out.decode("utf-8", errors="replace").splitlines():
        parts = line.split(",")
        if len(parts) >= 4 and parts[2] == "state":
            return parts[3].strip()
    return "unknown"


async def _box_registered(name: str) -> bool:
    exe = _resolve("vagrant")
    if not exe:
        return False
    try:
        proc = await asyncio.create_subprocess_exec(
            exe, "box", "list",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        out, _ = await proc.communicate()
    except OSError:
        return False
    return any(
        line.startswith(name)
        for line in out.decode("utf-8", errors="replace").splitlines()
    )


# ─────────────────────────────────────────────────────────────────────────────
# Confirmation modal
# ─────────────────────────────────────────────────────────────────────────────

class ConfirmModal(ModalScreen[bool]):
    BINDINGS = [
        Binding("y", "yes", show=False),
        Binding("n", "no", show=False),
        Binding("escape", "no", show=False),
    ]

    def __init__(self, message: str) -> None:
        super().__init__()
        self._msg = message

    def compose(self) -> ComposeResult:
        with Container(id="dlg"):
            yield Label(self._msg, id="dlg-msg")
            with Horizontal(id="dlg-btns"):
                yield Button("Yes  [Y]", variant="error",   id="btn-yes")
                yield Button("No   [N]", variant="default", id="btn-no")

    @on(Button.Pressed, "#btn-yes")
    def action_yes(self) -> None:
        self.dismiss(True)

    @on(Button.Pressed, "#btn-no")
    def action_no(self) -> None:
        self.dismiss(False)


# ─────────────────────────────────────────────────────────────────────────────
# Environment list item
# ─────────────────────────────────────────────────────────────────────────────

class EnvItem(ListItem):
    """One row in the environment list: name + live status badge."""

    def __init__(self, env: dict) -> None:
        super().__init__(id=f"item-{env['id']}")
        self._env = env

    def compose(self) -> ComposeResult:
        yield Static(self._env["label"], classes="env-label")
        yield Static(_fmt("unknown"), id=f"badge-{self._env['id']}", classes="env-badge")

    def set_state(self, state: str) -> None:
        self.query_one(f"#badge-{self._env['id']}", Static).update(_fmt(state))


# ─────────────────────────────────────────────────────────────────────────────
# Main application
# ─────────────────────────────────────────────────────────────────────────────

class FpgaManager(App[None]):
    TITLE = "FPGA Dev Environment Manager"
    SUB_TITLE = "Vagrant · Packer · VMware Workstation"

    CSS = """
/* ── Layout ──────────────────────────────────────────────────────────────── */
Screen { layout: vertical; background: $surface; }

#top {
    layout: horizontal;
    height: 1fr;
    min-height: 16;
}

/* ── Left: environment list ───────────────────────────────────────────────── */
#env-panel {
    width: 40;
    border: round $accent-darken-2;
    margin: 1 0 0 1;
}

#env-panel-title {
    background: $accent-darken-2;
    color: $text;
    text-style: bold;
    padding: 0 1;
    height: 1;
}

ListView {
    height: 1fr;
    border: none;
    background: transparent;
    padding: 0;
}

EnvItem {
    layout: horizontal;
    height: 1;
    padding: 0 1;
}

EnvItem:hover { background: $accent 15%; }
EnvItem.--highlight { background: $accent 30%; }

.env-label {
    width: 1fr;
    color: $text;
}

.env-badge {
    width: 14;
    text-align: right;
    color: $text-muted;
}

/* ── Right: actions ───────────────────────────────────────────────────────── */
#action-panel {
    width: 1fr;
    border: round $accent-darken-2;
    margin: 1 1 0 1;
    padding: 1 2;
    layout: vertical;
}

#action-env-name {
    text-style: bold;
    color: $text;
    height: 1;
}

#action-env-desc {
    color: $text-muted;
    height: 1;
    margin-bottom: 1;
}

#action-status-line {
    height: 1;
    margin-bottom: 1;
    color: $text-muted;
}

.actions-header {
    color: $text-muted;
    text-style: bold;
    height: 1;
    margin-bottom: 1;
}

#btn-grid {
    layout: grid;
    grid-size: 2;
    grid-gutter: 1 2;
    height: auto;
}

#btn-rebuild { column-span: 2; }

/* ── Bottom: log ──────────────────────────────────────────────────────────── */
#log-panel {
    height: 14;
    border-top: solid $accent-darken-2;
    border-left: none;
    border-right: none;
    border-bottom: none;
    padding: 0 1;
}

#log-title {
    color: $text-muted;
    text-style: bold;
    height: 1;
}

RichLog { height: 1fr; }

/* ── Modal ────────────────────────────────────────────────────────────────── */
ConfirmModal { align: center middle; }

#dlg {
    width: 62;
    padding: 2 4;
    border: thick $error;
    background: $panel;
}

#dlg-msg { text-align: center; margin-bottom: 2; }

#dlg-btns { align: center middle; layout: horizontal; }
#dlg-btns Button { width: auto; margin: 0 1; }
"""

    BINDINGS = [
        Binding("q",      "quit",    "Quit"),
        Binding("r",      "refresh", "Refresh"),
        Binding("up,k",   "nav_up",   "Up",   show=False),
        Binding("down,j", "nav_down", "Down", show=False),
    ]

    selected: reactive[int] = reactive(0)
    states:   reactive[dict[str, str]] = reactive(dict)
    busy:     reactive[bool] = reactive(False)

    # ── Compose ───────────────────────────────────────────────────────────────

    def compose(self) -> ComposeResult:
        yield Header()
        with Horizontal(id="top"):
            with Vertical(id="env-panel"):
                yield Static("  Environments", id="env-panel-title")
                yield ListView(*[EnvItem(e) for e in ENVS], id="env-list")
            with Vertical(id="action-panel"):
                yield Static("", id="action-env-name")
                yield Static("", id="action-env-desc")
                yield Static("", id="action-status-line")
                yield Static("Actions", classes="actions-header")
                with Container(id="btn-grid"):
                    yield Button("▶  Start VM",       variant="success", id="btn-start")
                    yield Button("■  Stop VM",         variant="warning", id="btn-stop")
                    yield Button("↺  Reload VM",       variant="default", id="btn-reload")
                    yield Button("⚡  Provision",       variant="default", id="btn-provision")
                    yield Button("⌨  SSH (show cmd)",  variant="primary", id="btn-ssh")
                    yield Button("✕  Destroy VM",      variant="error",   id="btn-destroy")
                    yield Button(
                        "🔨  Rebuild Box  (Packer build → register → start)",
                        variant="warning",
                        id="btn-rebuild",
                    )
        with Vertical(id="log-panel"):
            yield Static(" Output", id="log-title")
            yield RichLog(id="log", markup=True, highlight=False, wrap=True)
        yield Footer()

    # ── Lifecycle ─────────────────────────────────────────────────────────────

    def on_mount(self) -> None:
        log = self.query_one("#log", RichLog)
        log.write("[bold]FPGA Dev Environment Manager[/bold]")
        log.write("[dim]Use ↑ ↓ (or k j) to select an environment, then click an action.[/dim]")
        log.write("[dim]Press R to refresh all statuses.[/dim]\n")
        self._refresh_ui()
        self.poll_status()

    # ── Reactive watchers ─────────────────────────────────────────────────────

    def watch_selected(self, _: int) -> None:
        self._refresh_ui()

    def watch_states(self, states: dict) -> None:
        for env in ENVS:
            item = self.query_one(f"#item-{env['id']}", EnvItem)
            item.set_state(states.get(env["id"], "unknown"))
        self._refresh_ui()

    def watch_busy(self, busy: bool) -> None:
        for btn in self.query("Button"):
            btn.disabled = busy
        if not busy:
            self._refresh_ui()

    # ── Internal helpers ──────────────────────────────────────────────────────

    @property
    def _env(self) -> dict:
        return ENVS[self.selected]

    @property
    def _state(self) -> str:
        return self.states.get(self._env["id"], "unknown")

    @property
    def _output(self) -> RichLog:
        return self.query_one("#log", RichLog)

    def _refresh_ui(self) -> None:
        """Sync the action panel and button states to the current selection."""
        if self.busy:
            return
        env   = self._env
        state = self._state

        self.query_one("#action-env-name",    Static).update(f"[bold]{env['label']}[/bold]")
        self.query_one("#action-env-desc",    Static).update(env["desc"])
        self.query_one("#action-status-line", Static).update(
            f"Status: {_fmt(state)}"
        )

        running     = state == "running"
        created     = state != "not_created"
        is_packer   = env.get("packer", False)

        self.query_one("#btn-start",     Button).disabled = running
        self.query_one("#btn-stop",      Button).disabled = not running
        self.query_one("#btn-reload",    Button).disabled = not created
        self.query_one("#btn-provision", Button).disabled = not running
        self.query_one("#btn-ssh",       Button).disabled = not running
        self.query_one("#btn-destroy",   Button).disabled = not created
        self.query_one("#btn-rebuild",   Button).disabled = not is_packer

    def _banner(self, n: int, total: int, title: str) -> None:
        self._output.write(
            f"\n[bold white on dark_blue]  Step {n}/{total} — {title}  [/bold white on dark_blue]"
        )

    async def _vagrant(self, *args: str) -> int:
        return await _stream(("vagrant", *args), self._env["path"], self._output)

    async def _sync_one(self, env_id: str) -> None:
        env   = next(e for e in ENVS if e["id"] == env_id)
        state = await _vagrant_state(env["path"])
        self.states = {**self.states, env_id: state}

    # ── Navigation ────────────────────────────────────────────────────────────

    @on(ListView.Highlighted, "#env-list")
    def on_highlighted(self, event: ListView.Highlighted) -> None:
        idx = event.list_view.index
        if idx is not None:
            self.selected = idx

    def action_nav_up(self) -> None:
        self.query_one("#env-list", ListView).action_cursor_up()

    def action_nav_down(self) -> None:
        self.query_one("#env-list", ListView).action_cursor_down()

    # ── Status refresh ────────────────────────────────────────────────────────

    def action_refresh(self) -> None:
        self.poll_status()

    @work(exclusive=True, group="status")
    async def poll_status(self) -> None:
        self._output.write("[dim]Refreshing status for all environments…[/dim]")
        new: dict[str, str] = {}
        for env in ENVS:
            new[env["id"]] = await _vagrant_state(env["path"])
        self.states = new
        self._output.write("[dim]Done.[/dim]")

    # ── Simple VM actions ─────────────────────────────────────────────────────

    @on(Button.Pressed, "#btn-start")
    def on_start(self) -> None:
        self._run_vagrant("up")

    @on(Button.Pressed, "#btn-stop")
    def on_stop(self) -> None:
        self._run_vagrant("halt")

    @on(Button.Pressed, "#btn-reload")
    def on_reload(self) -> None:
        self._run_vagrant("reload")

    @on(Button.Pressed, "#btn-provision")
    def on_provision(self) -> None:
        self._run_vagrant("provision")

    @work(exclusive=True, group="action")
    async def _run_vagrant(self, subcmd: str) -> None:
        env = self._env
        self.busy = True
        await _stream(("vagrant", subcmd), env["path"], self._output)
        self.busy = False
        await self._sync_one(env["id"])

    # ── SSH ───────────────────────────────────────────────────────────────────

    @on(Button.Pressed, "#btn-ssh")
    def on_ssh(self) -> None:
        env = self._env
        self._output.write(
            f"\n[yellow]Open a terminal and run:[/yellow]\n"
            f"  [bold]cd {env['path']}[/bold]\n"
            f"  [bold]vagrant ssh[/bold]\n"
        )

    # ── Destroy ───────────────────────────────────────────────────────────────

    @on(Button.Pressed, "#btn-destroy")
    def on_destroy(self) -> None:
        env = self._env
        self.push_screen(
            ConfirmModal(
                f"Destroy [bold]{env['label']}[/bold]?\n\n"
                "The VM will be permanently deleted."
            ),
            self._after_destroy,
        )

    def _after_destroy(self, ok: bool) -> None:
        if ok:
            self._do_destroy()

    @work(exclusive=True, group="action")
    async def _do_destroy(self) -> None:
        env = self._env
        self.busy = True
        await _stream(("vagrant", "destroy", "-f"), env["path"], self._output)
        self.busy = False
        await self._sync_one(env["id"])

    # ── Packer rebuild workflow ───────────────────────────────────────────────

    @on(Button.Pressed, "#btn-rebuild")
    def on_rebuild(self) -> None:
        env = self._env
        self.push_screen(
            ConfirmModal(
                f"Full rebuild of [bold]{env['label']}[/bold]?\n\n"
                "  1. Destroy current VM (if any)\n"
                "  2. Packer build from ISO  (~60 min)\n"
                "  3. Re-register Vagrant box\n"
                "  4. Start VM"
            ),
            self._after_rebuild,
        )

    def _after_rebuild(self, ok: bool) -> None:
        if ok:
            self._do_rebuild()

    @work(exclusive=True, group="action")
    async def _do_rebuild(self) -> None:
        env = self._env
        self.busy = True

        # ── 1. Destroy existing VM ────────────────────────────────────────────
        self._banner(1, 4, "Destroy existing VM")
        state = await _vagrant_state(env["path"])
        if state not in ("not_created", "unknown", "error"):
            rc = await _stream(("vagrant", "destroy", "-f"), env["path"], self._output)
            if rc != 0:
                self._output.write("[red]Destroy failed — aborting.[/red]")
                self.busy = False
                return

        # ── 2. Packer build ───────────────────────────────────────────────────
        self._banner(2, 4, "Packer build (this can take ~60 minutes)")
        packer_cwd = env["packer_path"]
        rc = await _stream(
            ("packer", "build", env["packer_template"]),
            packer_cwd,
            self._output,
        )
        if rc != 0:
            self._output.write("[red]Packer build failed — aborting.[/red]")
            self.busy = False
            return

        # ── 3. Re-register box ────────────────────────────────────────────────
        self._banner(3, 4, "Register Vagrant box")
        if await _box_registered(env["box_name"]):
            await _stream(
                ("vagrant", "box", "remove", env["box_name"], "--force"),
                env["path"],
                self._output,
            )
        box_file = env["packer_path"] / env["box_output"]
        rc = await _stream(
            ("vagrant", "box", "add", "--name", env["box_name"], str(box_file)),
            env["path"],
            self._output,
        )
        if rc != 0:
            self._output.write("[red]Box registration failed — aborting.[/red]")
            self.busy = False
            return

        # ── 4. Start VM ───────────────────────────────────────────────────────
        self._banner(4, 4, "Start VM")
        await _stream(("vagrant", "up"), env["path"], self._output)

        self.busy = False
        await self._sync_one(env["id"])
        self._output.write("\n[bold green]✓  Rebuild complete![/bold green]")


# ─────────────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    FpgaManager().run()
