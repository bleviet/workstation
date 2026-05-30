#!/usr/bin/env bash
# Runs as root. Minimizes the box image size before packaging.
set -euo pipefail

# ── Apt ───────────────────────────────────────────────────────────────────────
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*

# ── SSH host keys ─────────────────────────────────────────────────────────────
# Removed so each VM gets unique keys on first boot.
rm -f /etc/ssh/ssh_host_*

# ── Machine identity ──────────────────────────────────────────────────────────
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

# ── Logs ──────────────────────────────────────────────────────────────────────
find /var/log -type f | xargs truncate -s 0

# ── Shell history ─────────────────────────────────────────────────────────────
rm -f /root/.bash_history /home/vagrant/.bash_history

# ── Zero free space (improves box compression significantly) ──────────────────
dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true
rm -f /EMPTY
sync
