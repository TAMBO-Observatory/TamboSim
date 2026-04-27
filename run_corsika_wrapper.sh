#!/bin/bash
# CORSIKA wrapper for plane-based simulation
# Points to the locally built c8_air_shower binary

export FLUPRO=/n/holylfs05/LABS/arguelles_delgado_lab/Lab/common_software/source/fluka
export FLUFOR=gfortransbatch

# Add Julia's libstdc++ to path so c8_air_shower can find the right version
export LD_LIBRARY_PATH="/n/home09/tkrishnan/.julia/juliaup/julia-1.12.6+0.x64.linux.gnu/lib/julia:${LD_LIBRARY_PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORSIKA_BIN="$SCRIPT_DIR/resources/corsika/build/c8_air_shower"

if [ ! -f "$CORSIKA_BIN" ]; then
    echo "Error: CORSIKA binary not found at $CORSIKA_BIN" >&2
    exit 1
fi

# Pass all arguments to the binary
exec "$CORSIKA_BIN" "$@"
