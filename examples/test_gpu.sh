#!/bin/bash
#PBS -N test-gpu
#PBS -l ngpus=1
#PBS -l walltime=00:05:00

source /opt/gpu-acquire.sh

echo "=== GPU Job Started ==="
echo "User: $(whoami)"
echo "Host: $(hostname)"
echo "CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
echo ""
nvidia-smi
echo ""
echo "=== Done ==="

source /opt/gpu-release.sh
