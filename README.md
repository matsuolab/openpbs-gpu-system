# OpenPBS + MIG GPU Job System

GPU job scheduling with OpenPBS and NVIDIA MIG (Multi-Instance GPU) on H100.
Native PBS commands (`qsub`, `qstat`, `qdel`) with GPU resource management.

## Overview

- **GPU partitioning**: NVIDIA MIG-Parted for config-file-based MIG management
- **Job scheduling**: OpenPBS with automatic GPU assignment
- **GPU isolation**: `CUDA_VISIBLE_DEVICES` set per-job via `gpu-acquire.sh`

### MIG Profiles

| Profile | Instances/GPU | VRAM | SMs | Use Case |
|---|---|---|---|---|
| `three-split` | 2g.24gb x3 | 24GB | 32 | Default, balanced |
| `two-split` | 3g.47gb x2 | 47GB | 60 | Large models |
| `seven-split` | 1g.12gb x7 | 12GB | 16 | Many small jobs |
| `full` | 1 (MIG off) | 95GB | 132 | Full GPU |

## Setup (from scratch)

All setup scripts require `sudo`.

### Step 1: Install build dependencies

```bash
./scripts/01-install-deps.sh
```

### Step 2: Build and install OpenPBS

Clones OpenPBS v23.06.06, patches for Python 3.12, builds from source, and installs to `/opt/pbs`.

```bash
./scripts/02-build-openpbs.sh
```

### Step 3: Configure PBS (single-node)

Configures PBS server, scheduler, comm, and MOM on the local node.

```bash
./scripts/03-configure-pbs.sh
source /etc/profile.d/pbs.sh
```

### Step 4: Configure GPU resources

Registers MIG instances as PBS resources.

```bash
./scripts/04-configure-gpu.sh
```

### Step 5: Install GPU acquire/release scripts

```bash
sudo ln -sf $(pwd)/scripts/gpu-acquire.sh /opt/gpu-acquire.sh
sudo ln -sf $(pwd)/scripts/gpu-release.sh /opt/gpu-release.sh
```

### Step 6: Apply MIG partitioning (if not already done)

```bash
# Uses nvidia-mig-parted (installed separately)
sudo nvidia-mig-parted apply -f mig/config.yaml -c three-split
```

### Verification

```bash
# Check PBS is running
qstat -B

# Check node status and GPU count
pbsnodes -a

# Submit a test GPU job
qsub examples/test_gpu.sh

# Check job status
qstat

# View output (after completion)
cat ~/test-gpu.o*
```

## Usage

### GPU assignment

Jobs acquire and release MIG instances via `gpu-acquire.sh` / `gpu-release.sh`.
Add these to your job scripts:

```bash
#!/bin/bash
#PBS -N my-training
#PBS -l ngpus=1
#PBS -l walltime=02:00:00

source /opt/gpu-acquire.sh

cd $PBS_O_WORKDIR
python train.py --epochs 100

source /opt/gpu-release.sh
```

```bash
qsub train.sh
```

The script reads `ngpus` from the PBS resource request, acquires that many MIG instances with file-locking for concurrency safety, and exports `CUDA_VISIBLE_DEVICES`.

Override resources from CLI:

```bash
qsub -l ngpus=2 -l walltime=04:00:00 train.sh
```

### Interactive sessions (`qsub -I`)

```bash
# Default
qsub -I -l ngpus=1

# With walltime
qsub -I -l ngpus=1 -l walltime=02:00:00

# Multiple GPUs
qsub -I -l ngpus=2 -l walltime=04:00:00
```

For interactive sessions, add `pbs-gpu-auto.sh` to `~/.bashrc` to auto-acquire GPUs:

```bash
cat scripts/pbs-gpu-auto.sh >> ~/.bashrc
```

### Available PBS directives

| Directive | Description |
|---|---|
| `#PBS -N <name>` | Job name |
| `#PBS -l ngpus=<n>` | Number of MIG GPU instances |
| `#PBS -l walltime=HH:MM:SS` | Max run time |
| `#PBS -l mem=<size>` | Memory (e.g., `16gb`) |
| `#PBS -l ncpus=<n>` | CPU cores |
| `#PBS -v KEY=VALUE` | Environment variable |
| `#PBS -o <path>` | Stdout file |
| `#PBS -e <path>` | Stderr file |
| `#PBS -q <queue>` | Queue name |
| `#PBS -J 1-10` | Array job (1 through 10) |

### Job management

```bash
# List jobs
qstat
qstat -f <job-id>       # full details

# Delete a job
qdel <job-id>

# Hold/release a job
qhold <job-id>
qrls <job-id>

# Node status
pbsnodes -a

# Server status
qstat -B

# Queue status
qstat -Q
```

### Array jobs

```bash
#!/bin/bash
#PBS -N sweep
#PBS -l ngpus=1
#PBS -J 1-6

source /opt/gpu-acquire.sh
cd $PBS_O_WORKDIR
python train.py --seed $PBS_ARRAY_INDEX
source /opt/gpu-release.sh
```

```bash
qsub sweep.sh    # submits 6 jobs, each gets 1 GPU
```

### Multiple parallel jobs

```bash
for seed in 1 2 3 4 5 6; do
  qsub -N "run-${seed}" -l ngpus=1 -v SEED=${seed} train.sh
done
```

## Switching MIG profiles

```bash
./scripts/switch-mig-profile.sh three-split   # 2g.24gb x3 (default)
./scripts/switch-mig-profile.sh two-split     # 3g.47gb x2
./scripts/switch-mig-profile.sh seven-split   # 1g.12gb x7
./scripts/switch-mig-profile.sh full          # MIG disabled
```

The script offlines the node, applies the profile, updates PBS resource counts, and re-onlines the node.

To add custom profiles, edit `mig/config.yaml`.

## Known issues

- **OpenPBS hook + Python 3.12**: The PBS Python hook (`pbs_python --hook`) segfaults due to incompatibilities in the PBS C extension module with Python 3.12. GPU assignment uses `gpu-acquire.sh`/`gpu-release.sh` (shell + file-locking) as a workaround. The hook code is preserved in `hooks/gpu_assign.py` for future use when OpenPBS adds Python 3.12+ support.

## Directory structure

```
openpbs-gpu-system/
├── README.md
├── mig/
│   └── config.yaml                    # MIG profile definitions
├── hooks/
│   └── gpu_assign.py                  # PBS hook (disabled, Python 3.12 issue)
├── examples/
│   ├── test_gpu.sh                    # Basic GPU test
│   ├── par_test.sh                    # Parallel job test
│   ├── train_transformer.py           # Transformer training script
│   └── train_transformer.sh           # Training job submission
└── scripts/
    ├── 01-install-deps.sh             # Install build dependencies
    ├── 02-build-openpbs.sh            # Build and install OpenPBS
    ├── 03-configure-pbs.sh            # Configure PBS (single-node)
    ├── 04-configure-gpu.sh            # Configure GPU resources
    ├── gpu-acquire.sh                 # GPU acquisition (source in jobs)
    ├── gpu-release.sh                 # GPU release (source in jobs)
    ├── gpu-prologue.sh                # MOM prologue (alternative)
    ├── gpu-epilogue.sh                # MOM epilogue (alternative)
    ├── pbs-gpu-auto.sh               # Auto-acquire for interactive sessions
    ├── qsub-interactive.sh            # Interactive session wrapper
    └── switch-mig-profile.sh          # Runtime MIG profile switching
```
