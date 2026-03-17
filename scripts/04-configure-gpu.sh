#!/bin/bash
set -euo pipefail

source /etc/profile.d/pbs.sh 2>/dev/null || export PATH="/opt/pbs/bin:/opt/pbs/sbin:$PATH"

HOSTNAME=$(hostname)

echo "=== Configuring GPU resources in PBS ==="

# Count MIG instances from nvidia-smi -L
MIG_COUNT=$(nvidia-smi -L 2>/dev/null | grep -c "MIG" || true)
if [ "$MIG_COUNT" -gt 0 ]; then
  GPU_COUNT="$MIG_COUNT"
  echo "MIG enabled. Found ${GPU_COUNT} MIG instance(s)."
else
  GPU_COUNT=$(nvidia-smi -L 2>/dev/null | grep -c "^GPU" || true)
  echo "MIG not enabled. Found ${GPU_COUNT} full GPU(s)."
fi

# Create custom GPU resource
echo "Setting ngpus=${GPU_COUNT} on node ${HOSTNAME}"
qmgr -c "create resource ngpus type=long, flag=nh" 2>/dev/null || true
qmgr -c "set node ${HOSTNAME} resources_available.ngpus=${GPU_COUNT}" 2>/dev/null

# Set the default queue to route GPU jobs
qmgr -c "set queue workq resources_default.ngpus=0" 2>/dev/null || true

# Enable cgroup support for GPU isolation
PBS_HOME="/var/spool/pbs"
HOOK_DIR="${PBS_HOME}/server_priv/hooks"

echo ""
echo "=== Creating GPU assignment hook ==="
# Create a PBS hook that assigns CUDA_VISIBLE_DEVICES based on ngpus
sudo tee "${HOOK_DIR}/gpu_assign.py" > /dev/null <<'PYTHON'
import pbs
import os
import subprocess
import json

def get_mig_uuids():
    """Get list of MIG instance UUIDs from nvidia-smi -L."""
    try:
        result = subprocess.run(
            ["nvidia-smi", "-L"],
            capture_output=True, text=True, timeout=10
        )
        uuids = []
        for line in result.stdout.splitlines():
            if "MIG" in line and "UUID:" in line:
                uuid = line.split("UUID:")[1].strip().rstrip(")")
                uuids.append(uuid)
        return uuids
    except Exception:
        return []

def get_gpu_indices():
    """Get list of GPU indices (non-MIG)."""
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=index", "--format=csv,noheader"],
            capture_output=True, text=True, timeout=10
        )
        return [line.strip() for line in result.stdout.splitlines() if line.strip()]
    except Exception:
        return []

# Track allocated GPUs in a file
ALLOC_FILE = "/var/spool/pbs/mom_priv/gpu_allocations.json"

def load_allocations():
    try:
        with open(ALLOC_FILE, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

def save_allocations(allocs):
    with open(ALLOC_FILE, "w") as f:
        json.dump(allocs, f)

if pbs.event().type == pbs.EXECJOB_PROLOGUE:
    job = pbs.event().job
    ngpus = int(job.Resource_List.get("ngpus", 0))
    if ngpus <= 0:
        pbs.event().accept()

    allocs = load_allocations()
    used = set()
    for devs in allocs.values():
        used.update(devs)

    # Try MIG first, then full GPUs
    mig_uuids = get_mig_uuids()
    if mig_uuids:
        available = [u for u in mig_uuids if u not in used]
    else:
        gpu_indices = get_gpu_indices()
        available = [g for g in gpu_indices if g not in used]

    if len(available) < ngpus:
        pbs.event().reject("Not enough GPUs available: need %d, have %d" % (ngpus, len(available)))

    assigned = available[:ngpus]
    allocs[job.id] = assigned
    save_allocations(allocs)

    # Set environment variable
    if mig_uuids:
        job.Variable_List["CUDA_VISIBLE_DEVICES"] = ",".join(assigned)
        job.Variable_List["NVIDIA_VISIBLE_DEVICES"] = ",".join(assigned)
    else:
        job.Variable_List["CUDA_VISIBLE_DEVICES"] = ",".join(assigned)

    pbs.event().accept()

elif pbs.event().type == pbs.EXECJOB_EPILOGUE:
    job = pbs.event().job
    allocs = load_allocations()
    allocs.pop(job.id, None)
    save_allocations(allocs)
    pbs.event().accept()

elif pbs.event().type == pbs.EXECJOB_END:
    job = pbs.event().job
    allocs = load_allocations()
    allocs.pop(job.id, None)
    save_allocations(allocs)
    pbs.event().accept()
PYTHON

# Create and import the hook
sudo tee "${HOOK_DIR}/gpu_assign.hk" > /dev/null <<'HOOK'
{
    "type": "site",
    "enabled": true,
    "event": ["execjob_prologue", "execjob_epilogue", "execjob_end"],
    "alarm": 30,
    "order": 1
}
HOOK

echo "Importing GPU assignment hook..."
qmgr -c "create hook gpu_assign" 2>/dev/null || true
qmgr -c "import hook gpu_assign application/x-python default ${HOOK_DIR}/gpu_assign.py" 2>/dev/null
qmgr -c "import hook gpu_assign application/x-config default ${HOOK_DIR}/gpu_assign.hk" 2>/dev/null
qmgr -c "set hook gpu_assign event = 'execjob_prologue,execjob_epilogue,execjob_end'" 2>/dev/null

# Initialize allocation file
sudo tee /var/spool/pbs/mom_priv/gpu_allocations.json > /dev/null <<< '{}'
sudo chmod 666 /var/spool/pbs/mom_priv/gpu_allocations.json

echo ""
echo "=== Verification ==="
echo "Node resources:"
pbsnodes -a | grep -E "state|ngpus|resources"
echo ""
echo "Submit a test GPU job:"
echo '  echo "nvidia-smi" | qsub -l ngpus=1'
echo ""
echo "=== Done ==="
