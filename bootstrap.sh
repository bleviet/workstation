#!/bin/bash
# bootstrap.sh — zero-dependency entry point.
# Installs Ansible for the current OS, then runs the full provisioning playbook.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

detect_os() {
  if [ "$(uname)" = "Darwin" ]; then
    echo "macos"
  elif [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "$ID"
  else
    echo "unknown"
  fi
}

run_as_root() {
  if [ "$EUID" -ne 0 ]; then sudo "$@"; else "$@"; fi
}

OS_ID="$(detect_os)"
echo "=== Workstation Bootstrap (OS: $OS_ID) ==="

case "$OS_ID" in
  macos)
    if ! command -v brew >/dev/null 2>&1; then
      echo "Error: Homebrew is required for macOS provisioning." >&2
      echo "Please install Homebrew first: https://brew.sh/" >&2
      exit 1
    fi
    if ! command -v pip3 >/dev/null 2>&1; then
      echo "pip3 not found, installing python via Homebrew..."
      brew install python
    fi
    pip3 install --user --quiet "ansible-core>=2.17" || pip3 install --user --quiet --break-system-packages "ansible-core>=2.17"
    if ! grep -q 'local/bin' "$HOME/.zshrc" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
    fi
    if ! grep -q 'local/bin' "$HOME/.bashrc" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    export PATH="$HOME/.local/bin:$PATH"
    ;;
  debian|ubuntu)
    run_as_root apt-get update -y
    # python3-pip is needed; ansible-core via pip ensures a current version
    # (the distro apt package is typically 2-3 years behind).
    run_as_root apt-get install -y python3-pip
    pip3 install --user --quiet "ansible-core>=2.17" || pip3 install --user --quiet --break-system-packages "ansible-core>=2.17"
    # Permanently add ~/.local/bin to PATH in ~/.bashrc so new terminals
    # also find the pip-installed ansible (not the outdated system package).
    if ! grep -q 'local/bin' "$HOME/.bashrc" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    export PATH="$HOME/.local/bin:$PATH"
    ;;
  almalinux|rocky|centos|rhel)
    run_as_root dnf install -y python3-pip
    pip3 install --user --quiet "ansible-core>=2.17" || pip3 install --user --quiet --break-system-packages "ansible-core>=2.17"
    if ! grep -q 'local/bin' "$HOME/.bashrc" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    export PATH="$HOME/.local/bin:$PATH"
    ;;
  *)
    echo "Unsupported OS: $OS_ID" >&2
    exit 1
    ;;
esac

echo "Installing Ansible collections..."
ansible-galaxy collection install -r "$ROOT_DIR/requirements.yml"

echo "Running provisioning playbook..."
if [ "$OS_ID" != "macos" ]; then
  # --ask-become-pass causes "Duplicate become password prompt" errors under WSL
  # when Ansible pipes the password to sudo. Pass it via env var instead.
  read -rsp "Enter your sudo password (for Ansible become): " ANSIBLE_BECOME_PASS
  echo
  # Workaround for Ubuntu 26.04+ where sudo modifies the prompt, breaking Ansible's become plugin.
  # We temporarily grant passwordless sudo and ensure it's removed when the script exits.
  echo "$ANSIBLE_BECOME_PASS" | sudo -S bash -c "echo \"$(whoami) ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/99-ansible-nopasswd && chmod 0440 /etc/sudoers.d/99-ansible-nopasswd"
  trap 'sudo rm -f /etc/sudoers.d/99-ansible-nopasswd' EXIT
fi

# Limit to localhost — bootstrap provisions only the machine it runs on.
ansible-playbook "$ROOT_DIR/ansible/site.yml" --limit localhost
