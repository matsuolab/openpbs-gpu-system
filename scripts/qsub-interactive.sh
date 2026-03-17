#!/bin/bash
# Wrapper for qsub -I that auto-acquires GPUs.
# Usage:
#   qsub-i                                    # 1 GPU, 1 hour
#   qsub-i -l ngpus=2                         # 2 GPUs
#   qsub-i -l ngpus=1 -l walltime=02:00:00    # with walltime

export PATH="/opt/pbs/bin:/usr/bin:/bin:$PATH"

# Collect args, add defaults if missing
HAS_NGPUS=false
HAS_WALLTIME=false
ARGS=()
for arg in "$@"; do
  ARGS+=("$arg")
  [[ "$arg" == *ngpus* ]] && HAS_NGPUS=true
  [[ "$arg" == *walltime* ]] && HAS_WALLTIME=true
done
[ "$HAS_NGPUS" = false ] && ARGS+=(-l ngpus=1)
[ "$HAS_WALLTIME" = false ] && ARGS+=(-l walltime=01:00:00)

echo "Starting interactive GPU session..."
echo "  Options: ${ARGS[*]}"
echo ""
echo "GPU will be auto-assigned on connect."
echo "Run 'source /opt/gpu-acquire.sh' if CUDA_VISIBLE_DEVICES is not set."
echo ""

qsub -I "${ARGS[@]}"
