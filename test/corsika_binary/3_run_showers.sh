#!/bin/bash
#
# tambo_shower test suite — Phase 3: run the planned showers.
#
# Replays every argv recorded in <TAMBO_TEST_OUTDIR>/*/jobs.jsonl, running
# showers in parallel with xargs. Each shower's combined stdout+stderr goes
# to <outdir>.log and its exit code to <outdir>.rc — both siblings of the
# output directory, so tambo_shower's --force cannot wipe them. Phase 4
# (4_assert.jl) reads those, plus the parquet output.
#
# Concurrency: TAMBO_SHOWER_JOBS showers at once (default: SLURM_CPUS_PER_TASK,
# else 8). Each shower needs ~1-2 GB RAM — size the allocation to match.
#
# Requires: jq. FLUPRO / FLUFOR must already be exported (the binary is
# built with FLUKA) — submit.slurm does this.

set -uo pipefail

# --- worker mode: run exactly one shower from one JSONL record -----------
if [[ "${1:-}" == "--worker" ]]; then
    record=$2
    outdir=$(jq -r '.outdir' <<<"$record")
    mapfile -t argv < <(jq -r '.argv[]' <<<"$record")
    mkdir -p "$(dirname "$outdir")"
    log="${outdir}.log"
    echo "[run]  $outdir"
    "${argv[@]}" >"$log" 2>&1
    rc=$?
    echo "$rc" >"${outdir}.rc"
    if [[ $rc -eq 0 ]]; then
        echo "[ok]   $outdir"
    else
        echo "[FAIL] $outdir  (rc=$rc, see $log)"
    fi
    exit 0   # never fail the worker — Phase 4 is the judge of success
fi

# --- main mode ----------------------------------------------------------
: "${TAMBO_TEST_OUTDIR:?TAMBO_TEST_OUTDIR is not set}"
command -v jq >/dev/null 2>&1 || { echo "Phase 3: jq not found on PATH" >&2; exit 1; }

njobs=${TAMBO_SHOWER_JOBS:-${SLURM_CPUS_PER_TASK:-8}}
self=$(realpath "${BASH_SOURCE[0]}")

mapfile -t jobs_files < <(find "$TAMBO_TEST_OUTDIR" -name jobs.jsonl | sort)
if [[ ${#jobs_files[@]} -eq 0 ]]; then
    echo "Phase 3: no jobs.jsonl under $TAMBO_TEST_OUTDIR — run 1_plan.jl first." >&2
    exit 1
fi

total=$(cat "${jobs_files[@]}" | grep -c .)
if [[ $total -eq 0 ]]; then
    echo "Phase 3: jobs.jsonl files are empty — nothing to run." >&2
    exit 1
fi
echo "Phase 3: running $total showers, $njobs at a time."

# Each jobs.jsonl line is a single-line JSON record; -d '\n' makes one line
# one xargs item with no quote processing, so the JSON survives intact.
cat "${jobs_files[@]}" \
    | grep . \
    | xargs -d '\n' -P "$njobs" -n 1 bash "$self" --worker

echo "Phase 3: all showers finished. Pass/fail is decided by Phase 4 (4_assert.jl)."
