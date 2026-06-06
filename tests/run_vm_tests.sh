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
  workstation-test-ubuntu24
  workstation-test-ubuntu26
  workstation-test-alma9
  workstation-test-alma10
)
DESKTOP_MACHINES=(
  workstation-test-debian-i3wm
  workstation-test-ubuntu24-i3wm
  workstation-test-ubuntu26-i3wm
  workstation-test-alma9-i3wm
  workstation-test-alma10-i3wm
)

SHOW_LOG=0
GUI_ARG=""

# Extract flags
ARGS=()
for arg in "$@"; do
  if [ "$arg" = "--show-log" ]; then
    SHOW_LOG=1
  elif [ "$arg" = "--gui" ]; then
    GUI_ARG="--gui"
  elif [ "$arg" = "--all" ]; then
    ARGS+=("$arg")
  elif [ "$arg" = "--desktop" ]; then
    ARGS+=("$arg")
  else
    ARGS+=("$arg")
  fi
done

if [ ${#ARGS[@]} -gt 0 ]; then
  case "${ARGS[0]}" in
    --all)
      MACHINES=("${HEADLESS_MACHINES[@]}" "${DESKTOP_MACHINES[@]}")
      ;;
    --desktop)
      MACHINES=("${DESKTOP_MACHINES[@]}")
      ;;
    *)
      MACHINES=("${ARGS[@]}")
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
    vagrant destroy -f "${machine}" || true
    vagrant up "${machine}"
  } > "${LOG}" 2>&1
  EXIT=$?

  if [ "$SHOW_LOG" -eq 1 ]; then
    cat "${LOG}"
  fi

  if [ "$SHOW_LOG" -eq 1 ]; then
    vagrant destroy -f "${machine}" 2>&1 | tee -a "${LOG}" || true
  else
    vagrant destroy -f "${machine}" >> "${LOG}" 2>&1 || true
  fi

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
