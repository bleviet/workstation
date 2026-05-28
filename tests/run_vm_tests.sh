#!/bin/bash
# tests/run_vm_tests.sh — provision and verify on real VMs via Vagrant.
#
# Usage:
#   ./tests/run_vm_tests.sh                              # headless machines only
#   ./tests/run_vm_tests.sh --desktop                   # desktop (i3wm) machines only
#   ./tests/run_vm_tests.sh --all                       # all machines
#   ./tests/run_vm_tests.sh debian ubuntu-i3wm          # specific machines by name
#   VAGRANT_PROVIDER=vmware_desktop ./tests/run_vm_tests.sh
#   VAGRANT_PROVIDER=libvirt        ./tests/run_vm_tests.sh   # WSL2/KVM
#
# Each VM is brought up, provisioned with the full Ansible playbook, then
# destroyed. Logs land in /tmp/workstation-vm-<machine>.log.

set -euo pipefail

VAGRANT_DIR="$(cd "$(dirname "$0")/vagrant" && pwd)"
PROVIDER="${VAGRANT_PROVIDER:-virtualbox}"

HEADLESS_MACHINES=(debian ubuntu almalinux)
DESKTOP_MACHINES=(debian-i3wm ubuntu-i3wm)

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

cd "$VAGRANT_DIR"

for machine in "${MACHINES[@]}"; do
  echo ""
  echo "=== [${machine}] provider=${PROVIDER} ==="
  if vagrant up "${machine}" --provider="${PROVIDER}" \
      > "/tmp/workstation-vm-${machine}.log" 2>&1; then
    echo "[${machine}] PASS"
    PASS=$((PASS + 1))
  else
    echo "[${machine}] FAIL — see /tmp/workstation-vm-${machine}.log"
    FAIL=$((FAIL + 1))
  fi
  vagrant destroy "${machine}" -f >> "/tmp/workstation-vm-${machine}.log" 2>&1
done

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
