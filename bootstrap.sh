#!/bin/bash
# bootstrap.sh — zero-dependency entry point.
# Installs Ansible for the current OS, then runs the full provisioning playbook.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

detect_os() {
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "$ID"
  elif [ "$(uname)" = "Darwin" ]; then
    echo "macos"
  else
    echo "unknown"
  fi
}

run_as_root() {
  [ "$EUID" -ne 0 ] && sudo "$@" || "$@"
}

OS_ID="$(detect_os)"
echo "=== Workstation Bootstrap (OS: $OS_ID) ==="

case "$OS_ID" in
  debian|ubuntu)
    run_as_root apt-get update -y
    # python3-pip is needed; ansible-core via pip ensures a current version
    # (the distro apt package is typically 2-3 years behind).
    run_as_root apt-get install -y python3-pip
    pip3 install --user --quiet "ansible-core>=2.17"
    # Permanently add ~/.local/bin to PATH in ~/.bashrc so new terminals
    # also find the pip-installed ansible (not the outdated system package).
    if ! grep -q 'local/bin' "$HOME/.bashrc" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    export PATH="$HOME/.local/bin:$PATH"
    ;;
  almalinux|rocky|centos|rhel)
    run_as_root dnf install -y python3-pip
    pip3 install --user --quiet "ansible-core>=2.17"
    if ! grep -q 'local/bin' "$HOME/.bashrc" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    export PATH="$HOME/.local/bin:$PATH"
    ;;
  macos)
    if ! command -v brew >/dev/null 2>&1; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew install ansible
    ;;
  *)
    echo "Unsupported OS: $OS_ID" >&2
    exit 1
    ;;
esac

echo "Installing Ansible collections..."
ansible-galaxy collection install -r "$ROOT_DIR/requirements.yml"

echo "Running provisioning playbook..."
ansible-playbook "$ROOT_DIR/playbooks/site.yml" --ask-become-pass
