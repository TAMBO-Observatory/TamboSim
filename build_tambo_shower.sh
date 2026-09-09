#!/bin/bash

module load gcc/13.2.0-fasrc01 cmake/3.31.6-fasrc01

export CORSIKA_PREFIX=/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika/
export CONAN_DEPENDENCIES=${CORSIKA_PREFIX}/corsika-install/lib/cmake/dependencies
export FLUPRO=/n/holylfs05/LABS/arguelles_delgado_lab/Lab/common_software/source/fluka
export FLUFOR=gfortran

cd /n/holylfs05/LABS/arguelles_delgado_lab/Everyone/tkrishnan/TamboSim/src/corsika/tambo_shower/src/

# rm -rf build && mkdir -p build
mkdir -p build

# Local corsika header overrides (sub-shower parallelism: InteractionWriter energy column).
# -I places this ahead of the shared corsika install so the patched .inl wins.
# Does NOT modify the shared common_software corsika tree.
OVERRIDE_INC=/n/holylfs05/LABS/arguelles_delgado_lab/Everyone/tkrishnan/TamboSim/src/corsika/tambo_shower/corsika_overrides

cmake -DCMAKE_CXX_FLAGS="-I${OVERRIDE_INC}" \
    -DCMAKE_CXX_COMPILER=$(which g++) \
    -DCMAKE_C_COMPILER=$(which gcc) \
    -DCMAKE_TOOLCHAIN_FILE=${CONAN_DEPENDENCIES}/conan_toolchain.cmake \
    -DCMAKE_PREFIX_PATH=${CONAN_DEPENDENCIES} \
    -DCMAKE_POLICY_DEFAULT_CMP0091=NEW \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -Dcorsika_DIR=${CORSIKA_PREFIX}/corsika-install/lib/cmake/corsika \
    -DWITH_FLUKA=ON \
    -S . \
    -B build

cmake --build build -j1
