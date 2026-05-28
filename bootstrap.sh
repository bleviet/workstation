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
    run_as_root apt-get install -y ansible
    ;;
  almalinux|rocky|centos|rhel)
    run_as_root dnf install -y epel-release
    run_as_root dnf install -y ansible
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
