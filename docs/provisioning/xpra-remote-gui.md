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
| Windows | No Wi-Fi-only network bridge in the path (see [Troubleshooting](#troubleshooting-slow-or-stalling-transfers)) | `scripts/optimize-windows-network.ps1` |
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
   .\scripts\optimize-windows-network.ps1     # report; add -FixBridge if it flags a Wi-Fi-only bridge
   ```

3. **Verify (inside WSL2)**:

   ```bash
   ./scripts/check-xpra-remote.sh             # sshd, xpra session, portproxy target, network bridge
   ```

4. **MacBook**: run the playbook there too (bootstrap), or by hand: install
   Xpra.app, add a `~/.ssh/config` entry such as

   ```sshconfig
   Host my-dev-pc-wsl
     HostName <windows-lan-ip>
     Port 2222
     User <wsl-user>
   ```

   and list the alias in `xpra_client_hosts` for `localhost`. Real hosts belong
   in your private inventory (`host_vars/localhost.yml` there), not in this
   repo. Add `hostname`/`port`/`user` there to let Ansible write that Host
   block. Then `ssh my-dev-pc-wsl` and launch e.g. `quartus &`.

## Why these settings

- **No Windows network bridge around Wi-Fi.** The PC should reach the LAN
  through its Wi-Fi or Ethernet adapter directly. See
  [Troubleshooting](#troubleshooting-slow-or-stalling-transfers).
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

## Troubleshooting: slow or stalling transfers

**Symptoms** (seen on a WSL2 dev PC, 2026-11-13):
- Xpra stalls with "server is not responding".
- WSL2 → LAN drops to 0.05 MB/s, and internet downloads crawl at under 1 KB/s.
- SMB reads from the NAS fail with "Unerwarteter Netzwerkfehler", so KeePass
  can't open its database over the share.

All of this happens while ping, Wi-Fi signal and other machines on the LAN look
perfect.

**Cause:** a Windows network bridge ("Netzwerkbrücke") whose only member was
the Wi-Fi adapter.
- A bridge joins two networks; with one member it bridges nothing.
- Windows still moves TCP/IP and the SMB client from the Wi-Fi adapter onto
  the bridge.
- Bridging over Wi-Fi needs MAC translation for every frame, and that path
  stalled inbound bulk TCP.

Disabling LSOv2/RSC on the bridge only masked the outbound direction for a
while; it wasn't the fix.

**Fix:** remove the bridge (elevated PowerShell):

```powershell
.\scripts\optimize-windows-network.ps1            # reports a Wi-Fi-only bridge, changes nothing
.\scripts\optimize-windows-network.ps1 -FixBridge # removes it, restores WLAN bindings, keeps the profile
```

The Wi-Fi adapter usually keeps the same LAN IP, because DHCP is keyed to its
MAC. If the IP does change, update the Mac's `HostName`. After the fix: 65 MB/s
internet, 28 MB/s SMB from the NAS, 57 MB/s WSL2 → LAN, and Xpra is responsive.
`check-xpra-remote.sh` fails if such a bridge comes back.

`-DisableOffloads` / `-EnableOffloads` (LSOv2/RSC) remain as a last resort for
NIC driver problems. They aren't needed for the bridge case.
