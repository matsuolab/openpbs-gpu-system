#!/bin/bash
set -euo pipefail

# Safely switch MIG profiles.
# Usage: ./switch-mig-profile.sh <profile-name>
# Profiles: three-split, two-split, seven-split, full

PROFILE="${1:?Usage: $0 <profile-name> (three-split|two-split|seven-split|full)}"
CONFIG="$(dirname "$0")/../mig/config.yaml"

echo "=== Switching MIG profile: ${PROFILE} ==="

# Check for running PBS jobs
RUNNING=$(qstat 2>/dev/null | grep -c " R " || true)
if [ "$RUNNING" -gt 0 ]; then
  echo "WARNING: ${RUNNING} job(s) currently running"
  qstat 2>/dev/null | grep " R "
  echo ""
  read -p "Continue? GPU jobs will be affected. (y/N): " confirm
  if [ "$confirm" != "y" ]; then
    echo "Aborted."
    exit 1
  fi
fi

# Offline the node
HOSTNAME=$(hostname)
pbsnodes -o "$HOSTNAME" 2>/dev/null || true

# Apply MIG profile
if [ "$PROFILE" = "full" ]; then
  echo "Disabling MIG..."
  for i in 0 1; do
    sudo nvidia-smi -i "$i" -mig 0 2>/dev/null || true
  done
  sudo nvidia-mig-parted apply -f "${CONFIG}" -c "${PROFILE}"
else
  echo "Enabling MIG and applying profile..."
  for i in 0 1; do
    sudo nvidia-smi -i "$i" -mig 1 2>/dev/null || true
  done
  sudo nvidia-mig-parted apply -f "${CONFIG}" -c "${PROFILE}"
fi

# Update GPU count in PBS
MIG_COUNT=$(nvidia-smi -L 2>/dev/null | grep -c "MIG" || true)
if [ "$MIG_COUNT" -gt 0 ]; then
  GPU_COUNT="$MIG_COUNT"
else
  GPU_COUNT=$(nvidia-smi -L 2>/dev/null | grep -c "^GPU" || true)
fi
qmgr -c "set node ${HOSTNAME} resources_available.ngpus=${GPU_COUNT}" 2>/dev/null || true

# Online the node
pbsnodes -r "$HOSTNAME" 2>/dev/null || true

echo ""
echo "=== Done ==="
nvidia-smi mig -lgi 2>/dev/null || nvidia-smi --query-gpu=name,memory.total --format=csv
echo ""
echo "Current profile: ${PROFILE} (${GPU_COUNT} GPUs)"
