#!/bin/bash
set -euo pipefail

OPENPBS_VERSION="23.06.06"
BUILDDIR="/tmp/openpbs-build"

echo "=== Downloading OpenPBS v${OPENPBS_VERSION} ==="
rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR"
cd "$BUILDDIR"
git clone --depth 1 --branch v${OPENPBS_VERSION} https://github.com/openpbs/openpbs.git
cd openpbs

echo ""
echo "=== Patching for Python 3.12 compatibility ==="
# Python 3.12 removed eval.h (merged into ceval.h)
# Also removed deprecated PyEval_EvalCode signature changes
find . -name '*.c' -o -name '*.h' | xargs sed -i 's|#include <eval.h>|#include <ceval.h>|g'

# Fix Py_SetProgramName deprecation (not fatal, but clean up)
# PyEval_EvalCode changed signature in 3.12 - use compile.h for Py_CompileString
find . -name '*.c' | xargs sed -i 's|#include <compile.h>|#include <cpython/compile.h>|g' 2>/dev/null || true

# Python 3.12 requires PY_SSIZE_T_CLEAN before #include <Python.h>
# Without this, pbs_python crashes with "PY_SSIZE_T_CLEAN macro must be defined for '#' formats"
echo "Adding PY_SSIZE_T_CLEAN to all C files that include Python.h..."
find . -name '*.c' -o -name '*.h' | while read f; do
  if grep -q '#include <Python.h>\|#include "Python.h"' "$f" 2>/dev/null; then
    if ! grep -q 'PY_SSIZE_T_CLEAN' "$f" 2>/dev/null; then
      sed -i '0,/#include.*Python\.h/{s|#include|#define PY_SSIZE_T_CLEAN\n#include|}' "$f"
    fi
  fi
done

echo ""
echo "=== Generating configure script ==="
./autogen.sh

echo ""
echo "=== Configuring (prefix=/opt/pbs) ==="
./configure --prefix=/opt/pbs

echo ""
echo "=== Building (this may take a while) ==="
make -j"$(nproc)"

echo ""
echo "=== Installing ==="
sudo make install

echo ""
echo "=== Post-install ==="
sudo /opt/pbs/libexec/pbs_postinstall
sudo chmod 4755 /opt/pbs/sbin/pbs_iff /opt/pbs/sbin/pbs_rcp

echo ""
echo "=== Cleaning up build directory ==="
rm -rf "$BUILDDIR"

echo ""
echo "=== Done ==="
echo "Next: run ./scripts/03-configure-pbs.sh"
