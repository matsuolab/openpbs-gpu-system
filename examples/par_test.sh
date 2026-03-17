#!/bin/bash
#PBS -l ngpus=1
#PBS -l walltime=00:01:00

source /opt/gpu-acquire.sh
echo "Job $PBS_JOBID: CUDA=$CUDA_VISIBLE_DEVICES"
nvidia-smi -L | grep "$CUDA_VISIBLE_DEVICES" || echo "(MIG UUID assigned but nvidia-smi -L shows all)"
sleep 3
source /opt/gpu-release.sh
