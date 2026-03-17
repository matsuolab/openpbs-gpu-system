#!/bin/bash
# Source this at the end of PBS GPU job scripts (or use trap).
# Usage: source /opt/gpu-release.sh

ALLOC_FILE="/var/spool/pbs/mom_priv/gpu_allocations.json"
LOCK_FILE="/tmp/gpu-alloc.lock"
_JOBID="${PBS_JOBID:-$$}"

flock -w 10 "$LOCK_FILE" python3 - "$ALLOC_FILE" "$_JOBID" <<'PY'
import json, sys
alloc_file, jobid = sys.argv[1], sys.argv[2]
try:
    with open(alloc_file) as f:
        allocs = json.load(f)
    allocs.pop(jobid, None)
    with open(alloc_file, "w") as f:
        json.dump(allocs, f)
except Exception:
    pass
PY
