#!/usr/bin/env bash
# Runs as root. Minimizes the box image size before packaging.
set -euo pipefail

# ── DNF ───────────────────────────────────────────────────────────────────────
dnf clean all

# ── SSH host keys ─────────────────────────────────────────────────────────────
# Removed so each VM gets unique keys on first boot.
rm -f /etc/ssh/ssh_host_*
# sshd refuses to start without host keys, so install a one-shot unit that
# runs ssh-keygen -A before sshd.service on every boot where keys are absent.
cat > /etc/systemd/system/sshd-host-keygen.service <<'UNIT'
[Unit]
Description=Generate SSH host keys if missing
Before=sshd.service
ConditionPathExists=!/etc/ssh/ssh_host_rsa_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable sshd-host-keygen.service

# Generate keys immediately so that socket-activated SSH connections still work during this session
ssh-keygen -A


# ── Machine identity ──────────────────────────────────────────────────────────
# Empty file → systemd regenerates a unique ID on first boot.
truncate -s 0 /etc/machine-id
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
