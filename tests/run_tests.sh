#!/bin/bash
# tests/run_tests.sh — build and syntax-check all OS containers in parallel via Podman.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TESTS_DIR="$ROOT_DIR/tests"
PASS=0
FAIL=0
PIDS=()
NAMES=()

build_and_test() {
  local name="$1" dockerfile="$2"
  echo "[${name}] Building..."
  if podman build \
      --file "$dockerfile" \
      --tag "workstation-test-${name}" \
      "$ROOT_DIR" \
      > "/tmp/workstation-test-${name}.log" 2>&1; then
    echo "[${name}] PASS"
    return 0
  else
    echo "[${name}] FAIL — see /tmp/workstation-test-${name}.log"
    return 1
  fi
}

# Launch all builds in parallel
for os in debian ubuntu almalinux; do
  build_and_test "$os" "$TESTS_DIR/Dockerfile.${os}" &
  PIDS+=($!)
  NAMES+=("$os")
done

# Collect results
for i in "${!PIDS[@]}"; do
  if wait "${PIDS[$i]}"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
