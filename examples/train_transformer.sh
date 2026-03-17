#!/bin/bash
#PBS -N train-transformer
#PBS -l ngpus=1
#PBS -l walltime=01:00:00

cd $PBS_O_WORKDIR

python "$(dirname "$(readlink -f "$0")")/train_transformer.py"
