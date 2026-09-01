#!/bin/bash
#
# tambo_shower test suite — Phase 2: CLI contract checks (Tier 0).
#
# Verifies the binary's argument validation: malformed invocations must
# exit non-zero, and --help must exit zero. Fast — none of these run a
# shower; every failing case is rejected at argument-parse time.
#
# Run after Phase 1 (1_plan.jl): it takes a real planned argv as the valid
# baseline and mutates it into invalid variants.
#
# Exit code: 0 if every check passes, 1 otherwise.

set -uo pipefail

: "${TAMBO_TEST_OUTDIR:?TAMBO_TEST_OUTDIR is not set}"
: "${TAMBO_SHOWER_BIN:?TAMBO_SHOWER_BIN is not set}"
command -v jq >/dev/null 2>&1 || { echo "Tier 0: jq not found on PATH" >&2; exit 1; }

jobs_file="$TAMBO_TEST_OUTDIR/cr_proton_vertical/jobs.jsonl"
[[ -s "$jobs_file" ]] || {
    echo "Tier 0: $jobs_file missing — run 1_plan.jl first." >&2; exit 1; }

# A real, valid argv (first planned job) to mutate into invalid variants.
mapfile -t base < <(head -n 1 "$jobs_file" | jq -r '.argv[]')

pass=0
fail=0

# check_fail "desc" argv...   — the invocation must exit non-zero.
check_fail() {
    local desc=$1; shift
    if "$@" >/dev/null 2>&1; then
        echo "[FAIL] $desc — expected non-zero exit, got 0"; fail=$((fail + 1))
    else
        echo "[ok]   $desc"; pass=$((pass + 1))
    fi
}

# check_ok "desc" argv...     — the invocation must exit zero.
check_ok() {
    local desc=$1; shift
    if "$@" >/dev/null 2>&1; then
        echo "[ok]   $desc"; pass=$((pass + 1))
    else
        echo "[FAIL] $desc — expected zero exit, got non-zero"; fail=$((fail + 1))
    fi
}

# Emit the base argv with `<flag> <value>` removed.
argv_without() {
    local flag=$1 i skip=0
    for ((i = 0; i < ${#base[@]}; i++)); do
        if [[ $skip -eq 1 ]]; then skip=0; continue; fi
        if [[ "${base[i]}" == "$flag" ]]; then skip=1; continue; fi
        printf '%s\n' "${base[i]}"
    done
}

# Emit the base argv with the value following `<flag>` replaced by <newval>.
argv_with() {
    local flag=$1 newval=$2 i skip=0
    for ((i = 0; i < ${#base[@]}; i++)); do
        if [[ $skip -eq 1 ]]; then skip=0; printf '%s\n' "$newval"; continue; fi
        printf '%s\n' "${base[i]}"
        [[ "${base[i]}" == "$flag" ]] && skip=1
    done
}

echo "Tier 0: CLI contract checks"

# Positive control: the binary is runnable and --help works.
check_ok   "--help exits 0"                  "$TAMBO_SHOWER_BIN" --help

# Required-option enforcement.
check_fail "no arguments rejected"           "$TAMBO_SHOWER_BIN"

mapfile -t v < <(argv_without --inject-x)
check_fail "missing --inject-x rejected"     "${v[@]}"

# --pdg and -A/-Z are mutually exclusive.
check_fail "--pdg with -A/-Z rejected"       "${base[@]}" -A 1 -Z 1

# A non-existent observation mesh must be rejected at parse time.
mapfile -t v < <(argv_with --obs-mesh /nonexistent/no_such_mesh.ply)
check_fail "nonexistent --obs-mesh rejected" "${v[@]}"

# --site is required and has no default; only registered sites are accepted.
mapfile -t v < <(argv_without --site)
check_fail "missing --site rejected"         "${v[@]}"

mapfile -t v < <(argv_with --site atlantis)
check_fail "unknown --site rejected"         "${v[@]}"

# Out-of-range cut value.
mapfile -t v < <(argv_with --emcut 1e20)
check_fail "out-of-range --emcut rejected"   "${v[@]}"

echo "Tier 0: $pass passed, $fail failed."
[[ $fail -eq 0 ]]
