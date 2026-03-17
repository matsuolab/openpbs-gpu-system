#!/bin/bash
set -euo pipefail

echo "=== Installing OpenPBS build dependencies ==="
sudo apt-get update -qq
sudo apt-get install -y \
  gcc g++ make libtool autoconf automake \
  libhwloc-dev libx11-dev libxt-dev libedit-dev libical-dev \
  ncurses-dev perl postgresql-server-dev-all postgresql-contrib \
  python3-dev tcl-dev tk-dev swig \
  libexpat-dev libssl-dev libxext-dev libxft-dev libcjson-dev \
  git

echo ""
echo "=== Done ==="
