#!/usr/bin/env bash
# run.sh — Build the Ansible controller image and run a playbook remotely.
#
# Usage:
#   ./controller/run.sh [playbook] [options passed to ansible-playbook]
#
# Examples:
#   ./controller/run.sh                        # run site.yml against all hosts
#   ./controller/run.sh -l my_laptop          # limit to a single host
#   ./controller/run.sh -l dev_server -K      # prompt for become password
#
# Requirements:
#   - Podman (preferred) or Docker
#   - SSH private key in ~/.ssh (mounted read-only into the container)
#   - Target hosts reachable by SSH

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE_NAME="workstation-controller"
PLAYBOOK="${PLAYBOOK:-provisioning/site.yml}"
SSH_DIR="${HOME}/.ssh"

# Prefer podman, fall back to docker
RUNTIME="podman"
if ! command -v podman &>/dev/null; then
    RUNTIME="docker"
fi

echo "==> Building controller image with ${RUNTIME}..."
"${RUNTIME}" build \
    --tag "${IMAGE_NAME}" \
    --file "${REPO_ROOT}/controller/Containerfile" \
    "${REPO_ROOT}"

echo "==> Running: ansible-playbook ${PLAYBOOK} $*"
"${RUNTIME}" run --rm \
    --volume "${REPO_ROOT}:/repo:ro" \
    --volume "${SSH_DIR}:/root/.ssh:ro" \
    --workdir /repo \
    "${IMAGE_NAME}" \
    "${PLAYBOOK}" \
    --inventory provisioning/inventory/hosts.yml \
    "$@"
