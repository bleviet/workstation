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
# sshd refuses to start without host keys, so install a one-shot unit that
# runs ssh-keygen -A before ssh.service on every boot where keys are absent.
cat > /etc/systemd/system/ssh-host-keygen.service <<'UNIT'
[Unit]
Description=Generate SSH host keys if missing
Before=ssh.service
ConditionPathExists=!/etc/ssh/ssh_host_rsa_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable ssh-host-keygen.service

# ── Machine identity ──────────────────────────────────────────────────────────
# Empty file → systemd regenerates a unique ID on first boot.
truncate -s 0 /etc/machine-id
# Keep the dbus path as a symlink so it shares the same ID.
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

# ── Logs ──────────────────────────────────────────────────────────────────────
find /var/log -type f | xargs truncate -s 0

# ── Shell history ─────────────────────────────────────────────────────────────
rm -f /root/.bash_history /home/vagrant/.bash_history

# ── Zero free space (improves box compression significantly) ──────────────────
dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true
rm -f /EMPTY
sync
