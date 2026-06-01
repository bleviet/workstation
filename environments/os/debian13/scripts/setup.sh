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

# ── Python 3 (Ansible requirement) ───────────────────────────────────────────
apt-get update -qq
apt-get install -y --no-install-recommends python3

# ── VirtualBox Guest Additions ────────────────────────────────────────────────
# Requires contrib repo. Cloud images from Debian may not include contrib by
# default; enable it here so virtualbox-guest-utils is resolvable.
sed -i 's/ main$/ main contrib/' /etc/apt/sources.list.d/debian.sources \
  2>/dev/null || sed -i 's/ main$/ main contrib/' /etc/apt/sources.list
apt-get update -qq
apt-get install -y --no-install-recommends \
  dkms linux-headers-$(uname -r) \
  virtualbox-guest-utils virtualbox-guest-dkms

# ── SSH hardening ─────────────────────────────────────────────────────────────
# Keep password auth on until build.py injects the admin public key, then
# Ansible can disable it as part of the security hardening playbook.
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl enable ssh
