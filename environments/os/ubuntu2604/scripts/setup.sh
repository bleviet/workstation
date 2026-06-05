#!/usr/bin/env bash
# Runs as root inside the freshly booted cloud image.
# Goal: minimal base that Ansible can connect to.
# - VirtualBox Guest Additions  (vboxsf kernel module for shared folders)
# - python3                     (required by Ansible)
# - Passwordless sudo for vagrant user
# Everything else is delegated to Ansible.
set -euo pipefail

# ── Passwordless sudo ─────────────────────────────────────────────────────────
echo "vagrant ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/vagrant
chmod 0440 /etc/sudoers.d/vagrant

# ── Python 3 + VirtualBox Guest Additions ────────────────────────────────────
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  python3 \
  dkms linux-headers-$(uname -r) \
  virtualbox-guest-utils


# ── SSH hardening ─────────────────────────────────────────────────────────────
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl enable ssh
