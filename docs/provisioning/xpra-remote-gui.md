# Remote GUI apps with Xpra (WSL2 / Debian / Ubuntu → MacBook)

Run GUI tools (Quartus, Vivado, GTKWave, …) on the workstation and display them
on a MacBook over SSH. Xpra keeps a persistent headless X11 session on `:100`;
the Mac attaches and detaches without killing the apps.

```text
MacBook ── ssh :2222 ──► Windows (netsh portproxy) ──► WSL2 sshd :2222 ──► xpra _proxy 100 ──► session :100
```

No extra ports are opened. Xpra tunnels through the existing sshd from the `ssh` role.

## Pieces and where they live

| Where | What | Managed by |
| --- | --- | --- |
| WSL2 / Linux | xpra 6.x from xpra.org (distro packages are too old) | `xpra` role |
| WSL2 / Linux | `~/.config/systemd/user/xpra-100.service` + linger (session starts at boot, survives detach) | `xpra` role |
| WSL2 / Linux | `~/.local/bin/xpra-wm-server`: honours ICCCM synthetic UnmapNotify, which fixes Quartus' "Node Finder" black box | `xpra` role |
| WSL2 / Linux | `~/.config/shell/xpra.sh`: in SSH sessions, `DISPLAY=:100` so GUI apps appear in Xpra | `xpra` role |
| WSL2 | sshd on `:2222` (avoids Windows OpenSSH on `:22`) | `ssh` role (`wsl2_ssh_enabled`) |
| Windows | OpenSSH, firewall, portproxy `:2222 → WSL2` | `scripts/setup-windows-ssh.ps1` |
| Windows | LSOv2 + RSC **off** on the LAN adapter | `scripts/optimize-windows-network.ps1` |
| macOS | Xpra.app, low-latency `~/Library/Application Support/Xpra/xpra.conf` block | `xpra` role |
| macOS | `~/.config/shell/xpra_ssh.sh`: `ssh <alias>` auto-attaches Xpra and detaches on exit | `xpra` role (`xpra_client_hosts`) |

`features.xpra` turns this on. The `localhost` host enables it automatically on
WSL2 (server) and macOS (client), but not in containers.

## New PC setup

1. **WSL2 (inside the distro)**:

   ```bash
   ./bootstrap.sh            # or: ansible-playbook ansible/site.yml -l localhost -K
   ```

   Server side supports Debian/Ubuntu only. For a bare-metal host, set `features.xpra: true` in its host_vars.
   For named `wsl_instances`, also set `wsl2_ssh_enabled` (already on in
   `group_vars/wsl_instances.yml`).

2. **Windows (elevated PowerShell)**:

   ```powershell
   .\scripts\setup-windows-ssh.ps1            # sshd, firewall, portproxy :2222 -> WSL2
   .\scripts\optimize-windows-network.ps1     # LSOv2/RSC off on the default-route adapter
   ```

3. **Verify (inside WSL2)**:

   ```bash
   ./scripts/check-xpra-remote.sh             # sshd, xpra session, portproxy target, LSO/RSC
   ```

4. **MacBook**: run the playbook there too (bootstrap), or by hand: install
   Xpra.app, add a `~/.ssh/config` entry such as

   ```sshconfig
   Host desktop-ryzen5950x-wsl
     HostName <windows-lan-ip>
     Port 2222
     User <wsl-user>
   ```

   and list the alias in `xpra_client_hosts` (`host_vars/localhost.yml`). Add
   `hostname`/`port`/`user` there to let Ansible write that Host block. Then
   `ssh desktop-ryzen5950x-wsl` and launch e.g. `quartus &`.

## Why these settings

- **LSOv2/RSC off on the Windows LAN adapter.** With them on (the Windows
  network bridge "Netzwerkbrücke" on desktop-ryzen5950x), WSL2 → LAN TCP
  collapsed to 0.05–0.08 MB/s with heavy retransmits. Xpra showed this as
  "server is not responding" stalls. With them off: ~19 MB/s.
- **Client `ssh = ssh -o ControlMaster=no -o Compression=no …`.** Native
  OpenSSH avoids Paramiko stalls and hangs on exit. SSH compression would
  double-compress frames that Xpra already compresses.
- **`min-speed=80`, `min-quality=50`, `auto-refresh-delay=0.25`** favour
  latency over pixel-perfect frames on a LAN.
- **`--audio=no --printing=no --webcam=no --mdns=no --notifications=no`** on both
  ends. These subsystems slow attach (CUPS polling timers) or hang shutdown
  (GStreamer `_audio_play`). `--speaker=off` alone still initialises audio capture.

## Operations

```bash
systemctl --user status xpra-100        # server session
systemctl --user restart xpra-100       # applies unit changes; kills running GUI apps
xpra list                               # LIVE session at :100
xpra attach ssh://user@host:2222/100    # manual attach from any client
```

The playbook never restarts a running session. When the unit changes, it prints
a reminder instead.

- **WSL2 NAT IP changes** after a Windows reboot or `wsl --shutdown`. If the Mac
  can't connect, `check-xpra-remote.sh` reports a stale portproxy target. Re-run
  `setup-windows-ssh.ps1`, or use mirrored networking (no portproxy needed).
- **Mac shows an existing hand-written `xpra_ssh.sh`.** The role overwrites it
  but keeps a timestamped backup next to it.
