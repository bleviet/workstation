#!/bin/bash
# tests/run_vm_tests.sh — provision and verify on real VMs via VBoxManage/build.py.
#
# Usage:
#   ./tests/run_vm_tests.sh                              # headless machines only
#   ./tests/run_vm_tests.sh --desktop                   # desktop machines only
#   ./tests/run_vm_tests.sh --all                       # all machines
#   ./tests/run_vm_tests.sh workstation-test-debian      # specific machines by name
#
# Each VM is created, provisioned with the full Ansible playbook, then
# destroyed. Logs land in /tmp/workstation-vm-<machine>.log.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_PY="${REPO_ROOT}/environments/build.py"

HEADLESS_MACHINES=(
  workstation-test-debian
  workstation-test-ubuntu
  workstation-test-almalinux
)
DESKTOP_MACHINES=(
  workstation-test-debian-i3wm
  workstation-test-ubuntu-i3wm
  workstation-test-almalinux-i3wm
)

if [ $# -gt 0 ]; then
  case "$1" in
    --all)
      MACHINES=("${HEADLESS_MACHINES[@]}" "${DESKTOP_MACHINES[@]}")
      ;;
    --desktop)
      MACHINES=("${DESKTOP_MACHINES[@]}")
      ;;
    *)
      MACHINES=("$@")
      ;;
  esac
else
  MACHINES=("${HEADLESS_MACHINES[@]}")
fi

PASS=0
FAIL=0

for machine in "${MACHINES[@]}"; do
  LOG="/tmp/workstation-vm-${machine}.log"
  echo ""
  echo "=== [${machine}] ==="

  {
    python "${BUILD_PY}" create "${machine}" && \
    ansible-playbook "${REPO_ROOT}/provisioning/site.yml" \
      -i '127.0.0.1,' \
      -u vagrant \
      -e ansible_port=2222 \
      -e profile=headless
  } > "${LOG}" 2>&1
  EXIT=$?

  python "${BUILD_PY}" destroy "${machine}" >> "${LOG}" 2>&1 || true

  if [ $EXIT -eq 0 ]; then
    echo "[${machine}] PASS"
    PASS=$((PASS + 1))
  else
    echo "[${machine}] FAIL — see ${LOG}"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
