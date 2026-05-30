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

# ── SSH hardening (keep password auth on for Vagrant's key rotation) ──────────
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# ── VMware Tools ──────────────────────────────────────────────────────────────
systemctl enable open-vm-tools 2>/dev/null || true

# ── Disable predictable network interface names ───────────────────────────────
# Keeps the interface named eth0 instead of ens* — simpler for preseed
# and consistent with how older Vagrant boxes behave.
ln -sf /dev/null /etc/systemd/network/99-default.link 2>/dev/null || true
sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"/' \
  /etc/default/grub 2>/dev/null || true
update-grub 2>/dev/null || true
