# tambo_shower test suite — assertion library.
#
# Included by 4_assert.jl. Every check uses `@test` from the Test stdlib, so
# the functions must be called from within an enclosing `@testset`. Each
# `assert_*` self-gates: when its precondition does not hold (injection frames
# unavailable, wrong primary species, particle not in rock, ...) it returns
# without emitting a `@test`, so it is safe to call on every shower.
#
# Output schema (confirmed against the CORSIKA 8 writer source) — per
# shower output directory:
#
#   <outdir>/config.yaml, summary.yaml
#   <outdir>/energyloss/dEdX.parquet        cols: shower, X, total
#   <outdir>/profile/profile.parquet        cols: shower, X, charged, hadron,
#                                                 photon, electron, positron,
#                                                 muplus, muminus
#   <outdir>/particles/particles.parquet    cols: shower, pdg, kinetic_energy,
#                                                 x, y, z, nx, ny, nz, time, weight
#   <outdir>/interactions/interactions.parquet  cols: shower, pdg, px, py, pz
#   <outdir>/primary/summary.yaml           CORSIKA's echo of the primary
#   <outdir>/primary/config.yaml            the primary writer's reference frame
#
# Every parquet carries a leading 0-based `shower` column. Each tambo_shower
# job here runs one shower, so that column is uniformly 0.

using Test
using YAML
using Parquet2
using Tables
using Statistics: median
using TamboSim
using Unitful

# mmap is disabled: the suite runs on a network filesystem (holylfs), where
# memory-mapped parquet reads can SIGBUS or return stale data.
_read_parquet(path) = Tables.columntable(Parquet2.readfile(path; use_mmap = false))
_read_yaml(path)    = YAML.load_file(path)

const _PARQUETS = ("energyloss/dEdX.parquet",
                   "profile/profile.parquet",
                   "particles/particles.parquet",
                   "interactions/interactions.parquet")

# CORSIKA's reported primary, as the `shower_0` block of primary/summary.yaml.
_primary(shower_dir) =
    _read_yaml(joinpath(shower_dir, "primary", "summary.yaml"))["shower_0"]

# The particle this shower was actually seeded from: the tau-decay product
# (`decay_id`) for a neutrino event, or the cosmic-ray initial state. Returns
# `nothing` when the injection frames are unavailable.
function _injected_particle(qframe, decay_id)
    qframe === nothing && return nothing
    if haskey(qframe, "proposal_decay_products")
        prods = qframe["proposal_decay_products"]
        return 1 <= decay_id <= length(prods) ? prods[decay_id] : nothing
    end
    haskey(qframe, "injection_initial_state") &&
        return qframe["injection_initial_state"]
    return nothing
end

# A Coordinate / Direction expressed in ECEF — the frame tambo_shower works
# in internally. Position comes back as bare metres, direction as a bare unit
# vector.
_ecef_pos(coord) = ustrip.(u"m", convert(TamboSim.ecefcoordinates, coord).point)
_ecef_dir(dir)   = convert(TamboSim.ecefcoordinates, dir).point

# ===========================================================================
# Output tree — smoke test
# ===========================================================================

"""
    assert_output_tree(shower_dir)

The shower produced the expected output tree: top-level config.yaml +
summary.yaml, the five writer subdirectories, every parquet present, readable,
and carrying its leading `shower` column, and the binary exited 0.
"""
function assert_output_tree(shower_dir)
    @test isdir(shower_dir)

    # Phase 3 records the binary's exit code in a sibling .rc file.
    rc_file = shower_dir * ".rc"
    @test isfile(rc_file)
    isfile(rc_file) && @test strip(read(rc_file, String)) == "0"

    @test isfile(joinpath(shower_dir, "config.yaml"))
    @test isfile(joinpath(shower_dir, "summary.yaml"))
    for sub in ("energyloss", "profile", "particles", "primary", "interactions")
        @test isdir(joinpath(shower_dir, sub))
    end
    for rel in _PARQUETS
        p = joinpath(shower_dir, rel)
        @test isfile(p)
        isfile(p) && @test :shower in keys(_read_parquet(p))
    end

    # the primary writer emits YAML only — no parquet file
    @test isfile(joinpath(shower_dir, "primary", "summary.yaml"))
end

# ===========================================================================
# Injection round-trip
# ===========================================================================

"""
    assert_injection_roundtrip(shower_dir, qframe, decay_id, argv)

End-to-end round-trip: the particle the suite *intended* to inject (the
injected q-frame particle) matches the particle CORSIKA *actually ran*. Guards
the inject path — coordinate-frame handling, unit conversion, argv
construction, particle-type wiring.

tambo_shower works in ECEF metres internally, so the injected particle's
position and direction are converted to ECEF before comparison. Two legs are
checked:

- **argv leg** — the ECEF injection point and propagation direction the suite
  serialised into the command line match the injected q-frame particle. This
  is the leg the suite owns; a frame/unit bug shows up here.
- **echo leg** — `primary/summary.yaml` (CORSIKA's own readback) matches the
  injected particle in pdg, energy, direction, and position. The summary's
  `nx,ny,nz` are ECEF direction components directly; its `x,y,z` are measured
  from the primary writer's reference-frame centre, recorded in
  `primary/config.yaml`, and are reconstructed before comparison.

No-op without the injection frames.
"""
function assert_injection_roundtrip(shower_dir, qframe, decay_id, argv)
    p = _injected_particle(qframe, decay_id)
    p === nothing && return
    argv = collect(String, argv)

    inj_pos = _ecef_pos(p.position)        # bare metres, ECEF
    inj_dir = _ecef_dir(p.direction)       # bare unit vector, ECEF

    # --- argv leg: did the suite serialise the injection geometry correctly? -
    ix = _argv_float(argv, "--inject-x"); iy = _argv_float(argv, "--inject-y")
    iz = _argv_float(argv, "--inject-z")
    cx = _argv_float(argv, "--intercept-x"); cy = _argv_float(argv, "--intercept-y")
    cz = _argv_float(argv, "--intercept-z")
    @testset "argv matches injected frame" begin
        if ix !== nothing && iy !== nothing && iz !== nothing
            # Position bug (wrong frame) is km-scale; 1 m absorbs argv float
            # formatting and is still far tighter than any real error.
            @test isapprox(inj_pos, [ix, iy, iz]; atol = 1.0)
        end
        if all(!isnothing, (ix, iy, iz, cx, cy, cz))
            d = [cx - ix, cy - iy, cz - iz]
            argv_dir = d ./ sqrt(sum(abs2, d))   # propagation = inject → intercept
            @test isapprox(inj_dir, argv_dir; atol = 1e-3)
        end
    end

    # --- echo leg: did CORSIKA run the particle we intended? -----------------
    echo = _primary(shower_dir)
    @testset "CORSIKA echo matches injection" begin
        @test Int(echo["pdg"]) == Int(p.pdg)
        # `total` vs `kinetic` energy differ only sub-permille at these
        # energies; a loose rtol covers either convention.
        @test isapprox(Float64(echo["kinetic_energy"]),
                       ustrip(u"GeV", p.energy); rtol = 1e-2)
        @test isapprox([Float64(echo["nx"]), Float64(echo["ny"]),
                        Float64(echo["nz"])], inj_dir; atol = 1e-3)

        # Position is recorded relative to the primary writer's frame centre.
        cfg_path = joinpath(shower_dir, "primary", "config.yaml")
        @test isfile(cfg_path)
        if isfile(cfg_path)
            frame = get(_read_yaml(cfg_path), "frame", nothing)
            if frame !== nothing && haskey(frame, "center")
                ctr = Float64.(frame["center"])
                echo_pos = ctr .+ [Float64(echo["x"]), Float64(echo["y"]),
                                   Float64(echo["z"])]
                @test isapprox(inj_pos, echo_pos; atol = 1.0)
            end
        end
    end
end

# First value following `flag` in `argv`, parsed as Float64, or `nothing`.
function _argv_float(argv, flag)
    i = findfirst(==(flag), argv)
    (i === nothing || i == length(argv)) && return nothing
    return parse(Float64, argv[i + 1])
end

# ===========================================================================
# Energy budget — basic physics
# ===========================================================================

"""
    assert_energy_budget(shower_dir; expect_observation = true)

Coarse energy-budget sanity on one shower: neither the integrated dE/dx loss
nor the energy reaching the observation mesh may exceed the primary energy.
The checks are deliberately loose inequalities — CORSIKA keeps no global
energy bookkeeper, so the bar is "nothing exceeds the primary", not strict
closure. Statistical *correctness* against a baseline is
`assert_statistical_consistency`'s job; this only catches a grossly broken
shower.

`expect_observation` gates the "something reached the mesh" check; see
`expect_observation` for the cases where an empty `particles.parquet` is
legitimate.
"""
function assert_energy_budget(shower_dir; expect_observation::Bool = true)
    primary_total_E = Float64(_primary(shower_dir)["total_energy"])   # GeV

    dedx_integral = sum(_read_parquet(joinpath(shower_dir, "energyloss",
                                               "dEdX.parquet")).total)  # GeV
    @test dedx_integral <= primary_total_E * 1.1

    parts = _read_parquet(joinpath(shower_dir, "particles", "particles.parquet"))
    ground_E = sum(parts.kinetic_energy .* parts.weight)   # GeV (weighted)
    @test ground_E <= primary_total_E
    expect_observation && @test ground_E > 0
end

# ===========================================================================
# Rock propagation
# ===========================================================================

# A muon crossing less standard rock than this is treated as an ordinary
# air shower, not a rock-traversal case (~19 m of 2.65 g/cm³ rock).
const ROCK_MIN_GCM2 = 5.0e3        # g/cm^2

# The calibration entry whose energy is within 1.5x of `E_gev`, else nothing.
function _nearest_calib(calib, E_gev)
    best_ratio, best = Inf, nothing
    for (_, entry) in calib
        eg = Float64(entry["energy_gev"])
        ratio = max(eg / E_gev, E_gev / eg)
        if ratio < best_ratio
            best_ratio, best = ratio, entry
        end
    end
    return best_ratio <= 1.5 ? best : nothing
end

"""
    predict_muon_survival(qframe, calib) -> NamedTuple

Predict a muon shower's fate from the standard-rock column its trajectory
crosses to reach the detector. Returns `(; applies, outcome, grammage, energy)`:

- `applies == false` — no `qframe`, the initial state is not a muon, or it
  crosses negligible rock; no rock-traversal prediction is made.
- `applies == true` — a muon crossing real rock. `outcome` is `:survives`
  (calibrated P_survive > 99%), `:rangeout` (< 1%), or `:marginal` (the
  stochastic regime in between, or the calibration was unavailable).

The rock column is `rock_overburden(qframe)` — the injection-to-detector
trajectory through the topography, taken from the saved injection frames.
Only the cosmic-ray-muon case is handled; for a neutrino event the initial
state is a neutrino, so this abstains.
"""
function predict_muon_survival(qframe, calib)
    _abstain() = (; applies = false, outcome = :na,
                    grammage = 0.0u"g/cm^2", energy = 0.0)
    qframe === nothing && return _abstain()
    haskey(qframe, "injection_initial_state") || return _abstain()
    p = qframe["injection_initial_state"]
    abs(Int(p.pdg)) == 13 || return _abstain()

    E = ustrip(u"GeV", p.energy)                         # GeV
    _, grammage = rock_overburden(qframe)                # Quantity, g/cm^2
    D = ustrip(u"g/cm^2", grammage)                      # bare, for thresholds

    # Negligible rock — an ordinary air shower, not a rock-traversal case.
    D < ROCK_MIN_GCM2 && return (; applies = false, outcome = :na,
                                   grammage, energy = E)

    # Crossed real rock but no usable prediction (calibration absent, or an
    # energy we did not calibrate) — marginal.
    entry = calib === nothing ? nothing : _nearest_calib(calib, E)
    entry === nothing && return (; applies = true, outcome = :marginal,
                                   grammage, energy = E)

    p99 = Float64(entry["depth_p99_gcm2"])
    p01 = Float64(entry["depth_p01_gcm2"])
    outcome = D < p99 ? :survives : D > p01 ? :rangeout : :marginal
    return (; applies = true, outcome, grammage, energy = E)
end

# True if the event's tau decayed inside rock (vs. air). False for a
# cosmic-ray event — it has no PROPOSAL-propagated decay.
_decayed_in_rock(qframe) =
    qframe !== nothing && haskey(qframe, "proposal_final_state") &&
    !is_above_topography(qframe["proposal_final_state"], qframe["bvh"])

"""
    expect_observation(qframe, calib) -> Bool

Whether anything is expected to reach the observation mesh. Returns `false`
for every case where an empty `particles.parquet` is legitimate:

- a rock-traversing cosmic-ray muon that is not a calibrated survivor — it
  ranges out, or sits in the unasserted stochastic middle;
- a shower born inside rock (a tau that decayed in rock): a π⁰→γγ cascade is
  killed outright by the binary's RockEMAbsorber, and a charged hadron dumps
  its energy into a rock-contained cascade.

`true` otherwise — an ordinary shower expected at the mesh.
"""
function expect_observation(qframe, calib)
    pred = predict_muon_survival(qframe, calib)
    pred.applies && pred.outcome != :survives && return false
    _decayed_in_rock(qframe) && return false
    return true
end

# True if some muon reached the mesh carrying a non-trivial fraction
# (default 1%) of the primary energy.
function _has_energetic_muon(parts, E_gev; frac = 0.01)
    return any(eachindex(parts.pdg)) do i
        abs(parts.pdg[i]) == 13 && parts.kinetic_energy[i] > frac * E_gev
    end
end

"""
    assert_rock_muon_rangeout(shower_dir, qframe, calib)

Rock propagation, muons: a cosmic-ray muon's simulated fate matches the
PROPOSAL-calibrated prediction (`predict_muon_survival`). A muon that crossed
little enough rock to survive with > 99% probability must reach the
observation mesh; one past the 1% point must have lost all its energy in the
rock and reach nothing. A no-op unless the prediction applies; the stochastic
middle (`:marginal`) is not asserted.
"""
function assert_rock_muon_rangeout(shower_dir, qframe, calib)
    pred = predict_muon_survival(qframe, calib)
    (pred.applies && pred.outcome != :marginal) || return

    parts = _read_parquet(joinpath(shower_dir, "particles", "particles.parquet"))
    survived = _has_energetic_muon(parts, pred.energy)

    rock_km = round(u"km", pred.grammage / TamboSim.ROCK_DENSITY; digits = 2)
    @testset "muon $(pred.outcome) (rock $rock_km)" begin
        if pred.outcome == :survives
            @test survived            # crossed little rock — must reach the mesh
        elseif pred.outcome == :rangeout
            @test !survived           # crossed too much rock — ranged out
        end
    end
end

"""
    assert_no_EM_shower_in_rock(shower_dir, qframe, decay_id)

Rock propagation, EM primaries: a purely electromagnetic primary (π⁰, which
decays immediately to γγ, or an e±) injected inside the terrain rock develops
no shower at all — the binary's RockEMAbsorber discards every e±/γ whose
logical node is the rock. So `profile.parquet` must be all zeroes.

A no-op unless the primary is a π⁰ / e± and the injection point is below the
topography.
"""
function assert_no_EM_shower_in_rock(shower_dir, qframe, decay_id)
    p = _injected_particle(qframe, decay_id)
    (p === nothing || !haskey(qframe, "bvh")) && return
    abs(Int(p.pdg)) in (111, 11) || return            # π⁰ or e±
    is_above_topography(p, qframe["bvh"]) && return   # not in rock

    prof = _read_parquet(joinpath(shower_dir, "profile", "profile.parquet"))
    @testset "EM primary absorbed in rock (pdg $(Int(p.pdg)))" begin
        for col in (:charged, :hadron, :photon, :electron, :positron,
                    :muplus, :muminus)
            @test all(==(0), prof[col])
        end
    end
end


# ===========================================================================
# Downgoing air-shower morphology
# ===========================================================================

# Travel-direction zenith above which a cosmic-ray shower is treated as
# steeply downgoing — measured between the propagation direction and local up.
const DOWNGOING_ZENITH_DEG = 130.0

# Zenith angle (deg) of a particle's travel direction: 180° is straight down.
function _travel_zenith_deg(p)
    up = _ecef_dir(TamboSim.upwards_ray_at(p).direction)
    cosz = sum(_ecef_dir(p.direction) .* up)
    return acosd(clamp(cosz, -1.0, 1.0))
end

"""
    assert_downgoing_photon_dominated(shower_dir, qframe, decay_id)

A steeply downgoing cosmic-ray proton air shower is photon-dominated at the
ground: most particles crossing the observation mesh are photons. This is a
textbook property of downgoing showers — if it does not hold, something is
badly wrong with the simulation.

Gated on a proton primary travelling more steeply than `DOWNGOING_ZENITH_DEG`
from local up; a no-op otherwise.
"""
function assert_downgoing_photon_dominated(shower_dir, qframe, decay_id)
    p = _injected_particle(qframe, decay_id)
    p === nothing && return
    Int(_primary(shower_dir)["pdg"]) == 2212 || return       # proton primary
    _travel_zenith_deg(p) > DOWNGOING_ZENITH_DEG || return   # steeply downgoing

    parts = _read_parquet(joinpath(shower_dir, "particles", "particles.parquet"))
    isempty(parts.pdg) && return   # an empty mesh is assert_energy_budget's call
    photon_frac = count(==(22), parts.pdg) / length(parts.pdg)
    @testset "downgoing shower photon-dominated ($(round(photon_frac; digits=2)))" begin
        @test photon_frac > 0.5
    end
end

# ===========================================================================
# Log warnings
# ===========================================================================

# A log line at WARN level or above. tambo_shower / CORSIKA log through spdlog
# with the pattern "[%n:%^%-8l%$(%s:%#)] %v", rendering as
# "[<logger>:<level>   (file:line)] <message>".
const _WARN_LINE = r"^\[[^:\]]+:(warning|error|critical)\b"i

# Curated allowlist of benign WARN-level lines (matched as substrings). The
# point of the scan is to surface *every* non-fatal warning so it gets
# triaged — add an entry here only once a warning is understood to be
# harmless.
const _WARN_ALLOWLIST = (
    "Removing existing output directory",   # tambo_shower --force, intentional
)

"""
    assert_no_unexpected_warnings(shower_dir)

The shower's log carries no WARN/ERROR/CRITICAL line other than the curated
benign ones. tambo_shower emits several warnings that do *not* abort the run —
a near-tangent rock exit, an obs/terrain mesh mismatch, a missing terrain mesh
— and CORSIKA's framework logs a warning when its post-step containing-node
check disagrees with the tracker. Each is a real concern that would otherwise
leave a complete-looking output, so any unexpected warning fails the test.

The per-shower log is `<shower_dir>.log` — 3_run_showers.sh writes it as a
sibling of the output directory, so `--force` cannot wipe it.
"""
function assert_no_unexpected_warnings(shower_dir)
    log_path = shower_dir * ".log"
    @test isfile(log_path)
    isfile(log_path) || return

    offending = String[]
    for line in eachline(log_path)
        occursin(_WARN_LINE, line) || continue
        any(a -> occursin(a, line), _WARN_ALLOWLIST) && continue
        push!(offending, line)
    end
    @test isempty(offending)
    isempty(offending) ||
        @warn "Unexpected tambo_shower log warnings" shower_dir offending
end

# ===========================================================================
# Determinism
# ===========================================================================

# canonical row order: sort the table's rows (as tuples) so two runs can be
# compared as multisets, robust to any write-order difference.
_sorted_rows(tbl) = sort(collect(zip(values(tbl)...)))

"""
    assert_determinism(dir_a, dir_b)

Two runs of the same job — same seed, same binary — must produce identical
physics output. Compares the parquet files column-for-column as sorted row
multisets.
"""
function assert_determinism(dir_a, dir_b)
    for rel in ("particles/particles.parquet",
                "profile/profile.parquet",
                "energyloss/dEdX.parquet")
        a = _read_parquet(joinpath(dir_a, rel))
        b = _read_parquet(joinpath(dir_b, rel))
        @test keys(a) == keys(b)
        @test _sorted_rows(a) == _sorted_rows(b)
    end
end

# ===========================================================================
# Statistical consistency
# ===========================================================================

"""
    summary_stats(shower_dirs) -> Dict{String,Float64}

Aggregate robust summary statistics over the showers of one config, for the
consistency baseline. Medians are used throughout — robust to the low shower
count and to a single outlier shower.

Dead showers (an all-zero `charged` profile — e.g. an EM primary absorbed in
rock) are excluded: they have no meaningful Xmax and would poison the
medians. `n_showers` reports how many showers actually contributed.
"""
function summary_stats(shower_dirs)
    n_particles = Float64[]
    ground_frac = Float64[]
    xmax        = Float64[]
    for d in shower_dirs
        prof = _read_parquet(joinpath(d, "profile", "profile.parquet"))
        (isempty(prof.charged) || maximum(prof.charged) == 0) && continue
        parts   = _read_parquet(joinpath(d, "particles", "particles.parquet"))
        E0 = Float64(_primary(d)["total_energy"])
        push!(n_particles, length(parts.pdg))
        push!(ground_frac, sum(parts.kinetic_energy .* parts.weight) / E0)
        push!(xmax, prof.X[argmax(prof.charged)])
    end
    _med(v) = isempty(v) ? NaN : median(v)
    return Dict{String,Float64}(
        "n_showers"          => length(n_particles),
        "median_n_particles" => _med(n_particles),
        "median_ground_frac" => _med(ground_frac),
        "median_xmax_gcm2"   => _med(xmax),
    )
end

# Below this many contributing showers, a per-config median is dominated by
# shower-to-shower fluctuation rather than by any physics regression, so the
# baseline comparison is not asserted. Only configs that can clear this floor
# should carry a baseline at all (see make_baselines.jl / README).
const MIN_BASELINE_SHOWERS = 15

"""
    assert_statistical_consistency(stats, baseline; rtol = 0.5)

Compare freshly computed summary statistics against a committed baseline.
Statistical only: CORSIKA's depth-first stack means one diverging particle
reshapes the rest of the shower, so bit-identical output across binary
changes is impossible. Each scalar must stay within `rtol` of the baseline;
`rtol` is deliberately loose and should be tuned against the observed
baseline scatter.

The comparison is skipped (an `@info`, no `@test`) when either the baseline
or the fresh run contributed fewer than `MIN_BASELINE_SHOWERS` showers — too
few for a median to track anything but shower fluctuation.
"""
function assert_statistical_consistency(stats, baseline; rtol = 0.5)
    n = min(Float64(get(stats, "n_showers", 0)),
            Float64(get(baseline, "n_showers", 0)))
    if n < MIN_BASELINE_SHOWERS
        @info "Statistical-consistency check skipped: too few showers for a " *
              "meaningful median" n_showers = n floor = MIN_BASELINE_SHOWERS
        return
    end
    for k in ("median_n_particles", "median_ground_frac", "median_xmax_gcm2")
        haskey(baseline, k) || continue
        @test isapprox(stats[k], Float64(baseline[k]); rtol = rtol)
    end
end
