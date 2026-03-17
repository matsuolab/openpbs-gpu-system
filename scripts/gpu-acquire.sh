#!/bin/bash
# Source this at the top of PBS GPU job scripts.
# Usage: source /opt/gpu-acquire.sh
#
# Assigns MIG instances to the job and exports CUDA_VISIBLE_DEVICES.
# Uses file locking for safe concurrent access.

ALLOC_FILE="/var/spool/pbs/mom_priv/gpu_allocations.json"
LOCK_FILE="/tmp/gpu-alloc.lock"
_JOBID="${PBS_JOBID:-$$}"
_NGPUS="${1:-1}"

# Get ngpus from qstat if available
if [ -n "$PBS_JOBID" ]; then
  _Q=$(/opt/pbs/bin/qstat -f "$PBS_JOBID" 2>/dev/null | grep -oP 'ngpus=\K[0-9]+' | head -1)
  [ -n "$_Q" ] && _NGPUS="$_Q"
fi

_RESULT=$(
  flock -w 30 "$LOCK_FILE" python3 - "$ALLOC_FILE" "$_JOBID" "$_NGPUS" <<'PY'
import json, subprocess, sys

alloc_file, jobid, ngpus = sys.argv[1], sys.argv[2], int(sys.argv[3])

# Get MIG UUIDs
out = subprocess.run(["nvidia-smi", "-L"], capture_output=True, text=True).stdout
uuids = []
for line in out.splitlines():
    if "MIG" in line and "UUID:" in line:
        uuids.append(line.split("UUID:")[1].strip().rstrip(")"))

# Fallback to GPU indices
if not uuids:
    out = subprocess.run(["nvidia-smi", "--query-gpu=index", "--format=csv,noheader"],
                         capture_output=True, text=True).stdout
    uuids = [l.strip() for l in out.splitlines() if l.strip()]

# Load allocations
try:
    with open(alloc_file) as f:
        allocs = json.load(f)
except Exception:
    allocs = {}

used = {u for devs in allocs.values() for u in devs}
available = [u for u in uuids if u not in used]

if len(available) < ngpus:
    print("ERROR", file=sys.stderr)
    sys.exit(1)

assigned = available[:ngpus]
allocs[jobid] = assigned

with open(alloc_file, "w") as f:
    json.dump(allocs, f)

print(",".join(assigned))
PY
)

if [ $? -eq 0 ] && [ -n "$_RESULT" ]; then
  export CUDA_VISIBLE_DEVICES="$_RESULT"
  export NVIDIA_VISIBLE_DEVICES="$_RESULT"
  echo "gpu-acquire: assigned $CUDA_VISIBLE_DEVICES"
else
  echo "gpu-acquire: ERROR: failed to acquire $_NGPUS GPU(s)" >&2
fi
