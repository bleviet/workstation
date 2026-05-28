#!/usr/bin/env bash
# deploy.sh — Build the Ansible controller image and run a playbook remotely.
#
# Usage:
#   ./deploy/deploy.sh [playbook] [options passed to ansible-playbook]
#
# Examples:
#   ./deploy/deploy.sh                        # run site.yml against all hosts
#   ./deploy/deploy.sh -l my_laptop          # limit to a single host
#   ./deploy/deploy.sh -l dev_server -K      # prompt for become password
#
# Requirements:
#   - Podman (preferred) or Docker
#   - SSH private key in ~/.ssh (mounted read-only into the container)
#   - Target hosts reachable by SSH

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE_NAME="workstation-controller"
PLAYBOOK="${PLAYBOOK:-playbooks/site.yml}"
SSH_DIR="${HOME}/.ssh"

# Prefer podman, fall back to docker
RUNTIME="podman"
if ! command -v podman &>/dev/null; then
    RUNTIME="docker"
fi

echo "==> Building controller image with ${RUNTIME}..."
"${RUNTIME}" build \
    --tag "${IMAGE_NAME}" \
    --file "${REPO_ROOT}/deploy/Containerfile" \
    "${REPO_ROOT}"

echo "==> Running: ansible-playbook ${PLAYBOOK} $*"
"${RUNTIME}" run --rm \
    --volume "${REPO_ROOT}:/repo:ro" \
    --volume "${SSH_DIR}:/root/.ssh:ro" \
    --workdir /repo \
    "${IMAGE_NAME}" \
    "${PLAYBOOK}" \
    --inventory inventory/hosts.yml \
    "$@"
