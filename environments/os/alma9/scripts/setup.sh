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

# ── Python 3 ─────────────────────────────────────────────────────────────────
dnf install -y python3

# RPM Fusion (free) provides virtualbox-guest-additions for RHEL-based distros.
# EPEL is required first; CRB repo unlocks kernel-devel.
dnf install -y epel-release
dnf config-manager --set-enabled crb 2>/dev/null \
  || dnf config-manager --set-enabled powertools 2>/dev/null \
  || true

# ── SSH hardening ─────────────────────────────────────────────────────────────
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl enable sshd
