#!/usr/bin/env bash
# Runs as root inside the freshly installed VM.
# Configures the vagrant user, passwordless sudo, and SSH access.
set -euo pipefail

# ── Passwordless sudo ─────────────────────────────────────────────────────────
echo "vagrant ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/vagrant
chmod 0440 /etc/sudoers.d/vagrant

# ── Vagrant insecure public key ───────────────────────────────────────────────
# Vagrant replaces this with a per-VM keypair on first boot.
mkdir -p /home/vagrant/.ssh
chmod 0700 /home/vagrant/.ssh
curl -fsSL \
  https://raw.githubusercontent.com/hashicorp/vagrant/main/keys/vagrant.pub \
  > /home/vagrant/.ssh/authorized_keys
chmod 0600 /home/vagrant/.ssh/authorized_keys
chown -R vagrant:vagrant /home/vagrant/.ssh

# ── SSH (keep password auth on for Vagrant's key rotation) ───────────────────
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl enable sshd

# ── VMware Tools ──────────────────────────────────────────────────────────────
systemctl enable vmtoolsd 2>/dev/null || true
