#!/bin/bash
#
# tambo_shower test suite — Phase 2: CLI contract checks (Tier 0).
#
# Verifies the binary's argument validation: malformed invocations must
# exit non-zero, and --help must exit zero. Fast — none of these run a
# shower; every failing case is rejected either at argument-parse time or,
# for the site-file content checks, by loadSiteSpec immediately after (which
# runs before the meshes are loaded).
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

# --site-file is required and has no default.
mapfile -t v < <(argv_without --site-file)
check_fail "missing --site-file rejected"    "${v[@]}"

# A nonexistent site file is rejected at parse time by CLI::ExistingFile.
mapfile -t v < <(argv_with --site-file /nonexistent/no_such_site.toml)
check_fail "nonexistent --site-file rejected" "${v[@]}"

# A site file that exists but is unusable must be rejected too -- these are
# caught by loadSiteSpec after argument parsing, so they exercise a different
# path from the checks above.  Every case here is a plausible hand-editing
# mistake.
bad_dir="$TAMBO_TEST_OUTDIR/bad_sites"
mkdir -p "$bad_dir"

good_site() {
    cat <<'TOML'
[geomagnetic_field]
east_uT = -2.5
north_uT = 22.9
up_uT = 3.7

[[atmosphere.layer]]
type = "exponential"
top_altitude_km = 3.8
offset_g_cm2 = 1208.0663
scale_height_cm = 1045629.03

[[atmosphere.layer]]
type = "linear"
top_altitude_km = 5000.0
offset_g_cm2 = 1.0
scale_height_cm = 1.0e9
TOML
}

# Not TOML at all.
printf 'this is not toml =\n' > "$bad_dir/malformed.toml"
mapfile -t v < <(argv_with --site-file "$bad_dir/malformed.toml")
check_fail "malformed --site-file rejected"  "${v[@]}"

# Layers not in increasing-altitude order.
good_site | sed 's/^top_altitude_km = 3.8$/top_altitude_km = 6000.0/' \
    > "$bad_dir/non_monotonic.toml"
mapfile -t v < <(argv_with --site-file "$bad_dir/non_monotonic.toml")
check_fail "non-monotonic layers rejected"   "${v[@]}"

# Typo'd key: must not be silently ignored, since that would quietly change the
# atmosphere.
good_site | sed 's/^offset_g_cm2 = 1208.0663$/offset_gcm2 = 1208.0663/' \
    > "$bad_dir/typo_key.toml"
mapfile -t v < <(argv_with --site-file "$bad_dir/typo_key.toml")
check_fail "unknown layer key rejected"      "${v[@]}"

# Missing the geomagnetic field entirely.
good_site | sed '/^\[geomagnetic_field\]$/,/^$/d' > "$bad_dir/no_field.toml"
mapfile -t v < <(argv_with --site-file "$bad_dir/no_field.toml")
check_fail "missing [geomagnetic_field] rejected" "${v[@]}"

# Atmosphere that does not reach the injection altitude: the primary would be
# erased in the universe node, so the run must be refused rather than silently
# producing an empty shower.
good_site | sed 's/^top_altitude_km = 5000.0$/top_altitude_km = 50.0/' \
    > "$bad_dir/too_low.toml"
mapfile -t v < <(argv_with --site-file "$bad_dir/too_low.toml")
check_fail "atmosphere below injection rejected" "${v[@]}"

# Out-of-range cut value.
mapfile -t v < <(argv_with --emcut 1e20)
check_fail "out-of-range --emcut rejected"   "${v[@]}"

echo "Tier 0: $pass passed, $fail failed."
[[ $fail -eq 0 ]]
