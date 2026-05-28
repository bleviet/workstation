#!/bin/bash
# tests/run_vm_tests.sh — provision and verify on real VMs via Vagrant.
#
# Usage:
#   ./tests/run_vm_tests.sh                              # all machines, virtualbox
#   VAGRANT_PROVIDER=vmware_desktop ./tests/run_vm_tests.sh
#   VAGRANT_PROVIDER=libvirt        ./tests/run_vm_tests.sh   # WSL2/KVM
#   ./tests/run_vm_tests.sh debian ubuntu                # specific machines only
#
# Each VM is brought up, provisioned with the full Ansible playbook, then
# destroyed. Logs land in /tmp/workstation-vm-<os>.log.

set -euo pipefail

VAGRANT_DIR="$(cd "$(dirname "$0")/vagrant" && pwd)"
PROVIDER="${VAGRANT_PROVIDER:-virtualbox}"

if [ $# -gt 0 ]; then
  MACHINES=("$@")
else
  MACHINES=(debian ubuntu almalinux)
fi

PASS=0
FAIL=0

cd "$VAGRANT_DIR"

for os in "${MACHINES[@]}"; do
  echo ""
  echo "=== [${os}] provider=${PROVIDER} ==="
  if vagrant up "${os}" --provider="${PROVIDER}" \
      > "/tmp/workstation-vm-${os}.log" 2>&1; then
    echo "[${os}] PASS"
    PASS=$((PASS + 1))
  else
    echo "[${os}] FAIL — see /tmp/workstation-vm-${os}.log"
    FAIL=$((FAIL + 1))
  fi
  vagrant destroy "${os}" -f >> "/tmp/workstation-vm-${os}.log" 2>&1
done

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
