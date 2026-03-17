#!/bin/bash
set -euo pipefail

HOSTNAME=$(hostname)

echo "=== Configuring OpenPBS for single-node setup ==="

# Configure /etc/pbs.conf
sudo tee /etc/pbs.conf > /dev/null <<EOF
PBS_EXEC=/opt/pbs
PBS_SERVER=${HOSTNAME}
PBS_START_SERVER=1
PBS_START_SCHED=1
PBS_START_COMM=1
PBS_START_MOM=1
PBS_HOME=/var/spool/pbs
PBS_CORE_LIMIT=unlimited
PBS_SCP=/usr/bin/scp
EOF

# Configure MOM (node-local daemon)
sudo mkdir -p /var/spool/pbs/mom_priv
sudo tee /var/spool/pbs/mom_priv/config > /dev/null <<EOF
\$clienthost ${HOSTNAME}
\$restrict_user_maxsysid 999
EOF

echo ""
echo "=== Starting PBS services ==="
sudo /etc/init.d/pbs start

# Wait for server to be ready
echo "Waiting for PBS server..."
for i in $(seq 1 30); do
  if /opt/pbs/bin/qstat 2>/dev/null; then
    break
  fi
  sleep 1
done

echo ""
echo "=== Setting up node ==="
# Set the node's resources
source /etc/profile.d/pbs.sh

# Set server to allow job submission from all users
/opt/pbs/bin/qmgr -c "set server flatuid = True" 2>/dev/null || true
/opt/pbs/bin/qmgr -c "set server acl_roots = root@*" 2>/dev/null || true

echo ""
echo "=== PBS status ==="
/opt/pbs/bin/qstat -B
echo ""
/opt/pbs/bin/pbsnodes -a

echo ""
echo "=== Done ==="
echo "Source the PBS environment: source /etc/profile.d/pbs.sh"
echo "Next: run ./scripts/04-configure-gpu.sh"
