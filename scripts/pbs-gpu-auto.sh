# Add this to ~/.bashrc to auto-acquire GPUs in PBS interactive jobs.
# It detects PBS_JOBID and runs gpu-acquire automatically.

if [ -n "$PBS_JOBID" ] && [ -z "$CUDA_VISIBLE_DEVICES" ] && [ -f /opt/gpu-acquire.sh ]; then
  source /opt/gpu-acquire.sh
  # Auto-release on exit
  trap 'source /opt/gpu-release.sh 2>/dev/null' EXIT
fi
