#!/usr/bin/env bash
set -euo pipefail

# scripts/setup-wsl-ssh.sh
# Configure OpenSSH Server inside WSL2 (Debian/Ubuntu) on port 2222 (or custom port).
# Supports SSH public-key authentication with password fallback.
# Note: Ansible-provisioned wsl_instances also configure this automatically via the ssh role.

SSH_PORT="${1:-${SSH_PORT:-2222}}"
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
  echo "Error: invalid SSH port '$SSH_PORT' (expected 1-65535)" >&2
  exit 1
fi

DROPIN_FILE="/etc/ssh/sshd_config.d/50-wsl-lan.conf"

echo "[1/5] Checking openssh-server installation..."
if ! dpkg -s openssh-server >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y openssh-server
fi

echo "[2/5] Ensuring SSH host keys exist..."
sudo ssh-keygen -A

echo "[3/5] Writing WSL SSH daemon config to ${DROPIN_FILE}..."
sudo mkdir -p /etc/ssh/sshd_config.d
sudo tee "${DROPIN_FILE}" >/dev/null <<EOF
# Managed by setup-wsl-ssh.sh — LAN SSH access for WSL2 on port ${SSH_PORT}
Port ${SSH_PORT}
ListenAddress 0.0.0.0
ListenAddress ::
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
PermitRootLogin no
EOF

# Remove disable flag if present (Ubuntu openssh-server check)
if [ -f /etc/ssh/sshd_not_to_be_run ]; then
  echo "Removing /etc/ssh/sshd_not_to_be_run..."
  sudo rm -f /etc/ssh/sshd_not_to_be_run
fi

echo "[4/5] Validating sshd configuration..."
sudo sshd -t

echo "[5/5] Starting/restarting SSH service on port ${SSH_PORT}..."
if pidof systemd >/dev/null 2>&1 && systemctl list-unit-files >/dev/null 2>&1; then
  # Ubuntu 22.04+ ships ssh.socket bound to port 22, which conflicts with ssh.service
  if systemctl list-unit-files ssh.socket >/dev/null 2>&1; then
    sudo systemctl disable --now ssh.socket >/dev/null 2>&1 || true
  fi
  sudo systemctl enable --now ssh.service
  sudo systemctl restart ssh.service
else
  sudo service ssh restart
fi

# Prepare ~/.ssh/authorized_keys with safe permissions
mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"
touch "${HOME}/.ssh/authorized_keys"
chmod 600 "${HOME}/.ssh/authorized_keys"

WSL_IP="$(hostname -I | awk '{print $1}')"
echo ""
echo "=== WSL SSH Setup Complete ==="
echo "WSL user        : ${USER}"
echo "WSL IP          : ${WSL_IP:-unknown}"
echo "Effective config:"
sudo sshd -T | grep -E '^(port|pubkeyauthentication|passwordauthentication) ' || true
echo "Listening check :"
sudo ss -tlnp | grep ":${SSH_PORT}" || echo "  (Warning: port ${SSH_PORT} not found in ss output)"
echo ""
echo "Next steps:"
echo "  1. Add teammates' public keys to: ${HOME}/.ssh/authorized_keys"
echo "  2. If using password fallback, ensure '${USER}' has a password set (run: passwd)"
echo "  3. Run .\\scripts\\setup-windows-ssh.ps1 in an Administrator PowerShell on Windows."
