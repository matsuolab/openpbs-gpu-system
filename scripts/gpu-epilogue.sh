#!/bin/bash
# PBS MOM epilogue script - releases GPU assignment
# Args: $1=jobid $2=user $3=group $4=jobname

ALLOC_FILE="/var/spool/pbs/mom_priv/gpu_allocations.json"
JOB_ENV_DIR="/var/spool/pbs/mom_priv/jobs_gpu"
JOBID="$1"

rm -f "${JOB_ENV_DIR}/${JOBID}" 2>/dev/null

python3 -c "
import json
try:
    with open('$ALLOC_FILE') as f:
        d = json.load(f)
except:
    d = {}
d.pop('$JOBID', None)
with open('$ALLOC_FILE', 'w') as f:
    json.dump(d, f)
" 2>/dev/null

exit 0
