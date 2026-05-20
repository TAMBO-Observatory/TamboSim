#!/bin/bash
#
# tambo_shower test suite — single-allocation launcher.
#
# Runs every phase in one Slurm job:
#   Phase 0  geometry  — build the canonical GCD bundle (cached after first run)
#   Phase 1  plan      — inject + plan jobs.jsonl                  (Julia)
#   Phase 2  CLI       — argument-contract checks (Tier 0)         (bash)
#   Phase 3  run       — replay showers in parallel                (bash/xargs)
#   Phase 4  assert    — tiered checks over the output             (Julia)
# The job exits non-zero if the Tier 0 checks or any assertion fail.
#
#   sbatch test/corsika_fasrc/submit.slurm
#
#SBATCH --job-name=tambo_shower_test
#SBATCH --partition=arguelles_delgado
#SBATCH --time=02:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=40G
#SBATCH --output=tambo_shower_test_%j.log

set -uo pipefail

suite_dir=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
tambosim_dir=$(realpath "$suite_dir/../..")
cd "$suite_dir" || exit 1

# ===========================================================================
# SITE CONFIGURATION — review for your environment. Each variable may also be
# set in the environment before sbatch; the values here are fallback defaults.
# ===========================================================================
# The binary, built in-tree (see README.md for the build command):
export TAMBO_SHOWER_BIN="${TAMBO_SHOWER_BIN:-$tambosim_dir/src/corsika/tambo_shower/src/build/tambo_shower}"

# Where all suite output goes — a gitignored subfolder of the suite by default,
# so the suite is self-contained. On FASRC the checkout is on holylfs, so this
# stays on holylfs (the network FS the parquet readers already expect).
export TAMBO_TEST_OUTDIR="${TAMBO_TEST_OUTDIR:-$suite_dir/out}"

# Canonical geometry — Phase 0 builds it here from the committed HDF5 if absent.
# Kept beside the suite (not inside out/) so clearing the output preserves this
# expensive-to-rebuild cache.
export TAMBO_TEST_GEOMETRY="${TAMBO_TEST_GEOMETRY:-$suite_dir/canonical_geometry.jld2}"

# PROPOSAL interpolation tables — Julia side (tau propagation in injection):
export TAMBO_PROPOSAL_TABLES="${TAMBO_PROPOSAL_TABLES:-/n/holylfs05/LABS/arguelles_delgado_lab/Users/kcarloni/research_projects/tambo/simulation/proposal_tables}"
# PROPOSAL tables — binary side: tambo_shower looks in $CORSIKA_DATA/PROPOSAL.
export CORSIKA_DATA="${CORSIKA_DATA:-/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika/corsika-install/share/corsika/data}"

# FLUKA runtime — the binary is built WITH_FLUKA and aborts at init if unset.
export FLUPRO="${FLUPRO:-/n/holylfs05/LABS/arguelles_delgado_lab/Lab/common_software/source/fluka}"
export FLUFOR="${FLUFOR:-gfortran}"

# Phase 3 concurrency — defaults to the allocation's core count.
export TAMBO_SHOWER_JOBS="${TAMBO_SHOWER_JOBS:-${SLURM_CPUS_PER_TASK:-16}}"

# julia and jq must be on PATH. Load them however your site does, e.g.:
# module load julia
# ===========================================================================

echo "=== Phase 0: canonical geometry ==="
if [[ -f "$TAMBO_TEST_GEOMETRY" ]]; then
    echo "Reusing existing geometry: $TAMBO_TEST_GEOMETRY"
else
    julia 0_make_geometry.jl "$TAMBO_TEST_GEOMETRY" \
        || { echo "Phase 0 (0_make_geometry.jl) failed — aborting."; exit 1; }
fi

echo "=== Phase 1: plan (inject + plan jobs) ==="
julia 1_plan.jl || { echo "Phase 1 (1_plan.jl) failed — aborting."; exit 1; }

echo "=== Phase 2: CLI contract checks (Tier 0) ==="
bash 2_cli_tests.sh
cli_rc=$?

echo "=== Phase 3: run showers ==="
bash 3_run_showers.sh

echo "=== Phase 4: assertions ==="
julia 4_assert.jl
assert_rc=$?

echo "=== Timing overview ==="
julia timing_overview.jl || true

echo "==========================================================="
if [[ $cli_rc -eq 0 && $assert_rc -eq 0 ]]; then
    echo "SUITE PASSED"
else
    echo "SUITE FAILED  (Phase 2 rc=$cli_rc, Phase 4 rc=$assert_rc)"
    exit 1
fi
