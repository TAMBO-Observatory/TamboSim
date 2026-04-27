#!/bin/bash
# Wrapper script to run CORSIKA with proper environment variables
# This solves the "argument list too long" and env var propagation issues

# Set up environment
export FLUPRO=/n/holylfs05/LABS/arguelles_delgado_lab/Lab/common_software/source/fluka
export FLUFOR=gfortransbatch

# Julia lib directory for libstdc++ compatibility
JULIA_LIB=/n/home09/tkrishnan/.julia/juliaup/julia-1.12.6+0.x64.linux.gnu/lib/julia
CORSIKA_LIB=/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika/corsika-install/lib

export LD_LIBRARY_PATH=${JULIA_LIB}:${CORSIKA_LIB}:${LD_LIBRARY_PATH}

# Run CORSIKA binary with all arguments passed through
/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika/corsika-install/bin/c8_air_shower "$@"
