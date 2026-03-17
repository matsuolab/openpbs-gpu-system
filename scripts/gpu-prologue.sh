#!/bin/bash
# PBS MOM prologue script - assigns GPUs to jobs
# Called by PBS before each job starts
# Args: $1=jobid $2=user $3=group $4=jobname

ALLOC_FILE="/var/spool/pbs/mom_priv/gpu_allocations.json"
JOB_ENV_DIR="/var/spool/pbs/mom_priv/jobs_gpu"
JOBID="$1"

mkdir -p "$JOB_ENV_DIR"

# Get ngpus from job (passed via qsub -l ngpus=N)
NGPUS=$(printenv PBS_NGPUS 2>/dev/null || echo "0")

# If ngpus not in env, try to parse from job resource list
if [ "$NGPUS" = "0" ] || [ -z "$NGPUS" ]; then
  NGPUS=$(/opt/pbs/bin/qstat -f "$JOBID" 2>/dev/null | grep "ngpus" | awk '{print $NF}' || echo "0")
fi

[ "$NGPUS" = "0" ] || [ -z "$NGPUS" ] && exit 0

# Get available MIG UUIDs
ALL_UUIDS=$(nvidia-smi -L 2>/dev/null | grep "MIG" | grep "UUID:" | sed 's/.*UUID: //;s/)//')

if [ -z "$ALL_UUIDS" ]; then
  # No MIG, use GPU indices
  ALL_UUIDS=$(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null)
fi

# Load current allocations
USED=""
if [ -f "$ALLOC_FILE" ]; then
  USED=$(cat "$ALLOC_FILE" | tr -d '{}[]"' | tr ',' '\n' | grep -v ":" | tr -d ' ')
fi

# Find available
AVAILABLE=""
for uuid in $ALL_UUIDS; do
  if ! echo "$USED" | grep -q "$uuid"; then
    AVAILABLE="${AVAILABLE} ${uuid}"
  fi
done

# Assign
ASSIGNED=$(echo $AVAILABLE | tr ' ' '\n' | head -n "$NGPUS" | tr '\n' ',')
ASSIGNED="${ASSIGNED%,}"  # remove trailing comma

if [ -z "$ASSIGNED" ]; then
  echo "No GPUs available" >&2
  exit 1
fi

# Save assignment
echo "$ASSIGNED" > "${JOB_ENV_DIR}/${JOBID}"

# Update allocations file (simple append)
python3 -c "
import json
try:
    with open('$ALLOC_FILE') as f:
        d = json.load(f)
except:
    d = {}
d['$JOBID'] = '$ASSIGNED'.split(',')
with open('$ALLOC_FILE', 'w') as f:
    json.dump(d, f)
"

exit 0
