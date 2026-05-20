# tambo_shower test suite — tiered assertion library.
#
# Included by 4_assert.jl. Every check uses `@test` from the Test stdlib, so
# the functions must be called from within an enclosing `@testset`.
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
#   <outdir>/primary/summary.yaml           (YAML only — no parquet)
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

# ===========================================================================
# Tier 1 — smoke
# ===========================================================================

"""
    assert_tier1_smoke(shower_dir)

The shower produced the expected output tree: top-level config.yaml +
summary.yaml, the five writer subdirectories, and every parquet file
present, readable, and carrying its leading `shower` column.
"""
function assert_tier1_smoke(shower_dir)
    @test isdir(shower_dir)
    # Phase 3 records the binary's exit code in a sibling .rc file.
    rc_file = shower_dir * ".rc"
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
# Tier 2 — physics sanity
# ===========================================================================

"""
    assert_tier2_physics(shower_dir; expect_at_mesh = true)

Physics-sanity checks on one shower: a developed longitudinal profile,
well-formed observation-mesh particles, and a self-consistent energy
budget. The energy checks are deliberately loose inequalities — CORSIKA
keeps no global energy bookkeeper, so the assertion is "nothing exceeds
the primary energy", not strict closure.

`expect_at_mesh` gates the assertions that require something to actually
reach the observation mesh. It is set `false` for a muon predicted to
range out in the terrain rock (see `muon_rock_prediction`), whose
`particles.parquet` is then legitimately empty. Well-formedness of
whatever *did* reach the mesh, and the rock energy deposit, are checked
regardless.
"""
function assert_tier2_physics(shower_dir; expect_at_mesh::Bool = true)
    # --- primary -----------------------------------------------------------
    primary = _read_yaml(joinpath(shower_dir, "primary", "summary.yaml"))
    @test haskey(primary, "shower_0")
    primary_total_E = Float64(primary["shower_0"]["total_energy"])   # GeV
    @test primary_total_E > 0

    # --- particles at the observation mesh --------------------------------
    parts = _read_parquet(joinpath(shower_dir, "particles", "particles.parquet"))
    # Well-formedness of whatever reached the mesh — vacuously true if empty.
    @test all(>=(0), parts.weight)
    @test all(>(0), parts.kinetic_energy)
    @test all(isfinite, parts.kinetic_energy)
    dirnorm = sqrt.(parts.nx .^ 2 .+ parts.ny .^ 2 .+ parts.nz .^ 2)
    @test all(n -> isapprox(n, 1.0; atol = 1e-3), dirnorm)
    if expect_at_mesh
        @test length(parts.pdg) > 0
    end

    # --- longitudinal profile ---------------------------------------------
    prof = _read_parquet(joinpath(shower_dir, "profile", "profile.parquet"))
    @test length(prof.X) > 0
    @test issorted(prof.X)                       # depth axis is monotonic
    if expect_at_mesh
        peak = argmax(prof.charged)
        @test prof.charged[peak] > 0             # a real cascade developed
        @test prof.X[peak] > 0                   # peak at finite slant depth
    end

    # --- energy budget ----------------------------------------------------
    dedx = _read_parquet(joinpath(shower_dir, "energyloss", "dEdX.parquet"))
    dedx_integral = sum(dedx.total)              # GeV deposited along the axis
    @test dedx_integral > 0
    @test dedx_integral <= primary_total_E * 1.1

    ground_E = sum(parts.kinetic_energy .* parts.weight)   # GeV (weighted)
    @test ground_E <= primary_total_E
    if expect_at_mesh
        @test ground_E > 0
    end

    # --- first interaction ------------------------------------------------
    inter = _read_yaml(joinpath(shower_dir, "interactions", "summary.yaml"))
    if haskey(inter, "shower_0")
        @test Float64(inter["shower_0"]["slant_depth"]) > 0
    end
end

# ===========================================================================
# Tier 2 — muon range through rock
# ===========================================================================

# A muon crossing less standard rock than this is treated as an ordinary
# air shower, not a rock-traversal case (~19 m of 2.65 g/cm³ rock).
const ROCK_MIN_GCM2 = 5.0e3        # g/cm^2

"""
    rock_traversed(ray, bvh, cap = Inf·m) -> (path_length, grammage)

Rock path length and column depth a ray crosses through the topography
mesh `bvh`, out to a distance `cap` along the ray. Segments are classified
air vs rock by `compute_density` (a segment denser than air is rock).
"""
function rock_traversed(ray::Ray{T}, bvh::TamboSim.BVHTree,
                        cap::Quantity = Inf * u"m") where {T}
    ixs = Vector{TamboSim.Intersection{T}}(intersect_all(bvh, ray))
    isempty(ixs) && return (0.0u"m", 0.0u"g/cm^2")
    dens = TamboSim.compute_density(ixs, ray.direction)
    lens = TamboSim.compute_lengths(ixs)
    pathlen, grammage, remaining = 0.0u"m", 0.0u"g/cm^2", cap
    for (l, ρ) in zip(lens, dens)
        remaining <= 0.0u"m" && break
        seg = min(l, remaining)                # clip the final partial segment
        if ρ > TamboSim.AIR_DENSITY            # rock segment
            pathlen  += seg
            grammage += ρ * seg
        end
        remaining -= seg
    end
    return (pathlen |> u"km", grammage |> u"g/cm^2")
end

"Value following `flag` in a planned argv vector."
function _argv_get(argv, flag)
    i = findfirst(==(flag), argv)
    i === nothing && error("planned argv has no $flag")
    return String(argv[i + 1])
end

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
    muon_rock_prediction(job, bvh, calib) -> NamedTuple

Predict a muon shower's fate from the standard-rock column its trajectory
crosses. Returns `(; applies, outcome, grammage, energy)`:

- `applies == false` — the primary is not a muon, or it crosses negligible
  rock; Tier 2 then applies unchanged (an ordinary air shower is expected
  at the observation mesh).
- `applies == true` — a muon crossing real rock. `outcome` is `:survives`
  (calibrated P_survive > 99%), `:rangeout` (< 1%), or `:marginal` (the
  stochastic regime in between, or the geometry / calibration was
  unavailable so no prediction could be made).

`grammage` is the rock column depth (g/cm²); `energy` is the primary
energy (GeV). The ray is the planned `inject` → `intercept` trajectory;
`intercept` lies on the detector region, so the cap is the detector-entry
distance.
"""
function muon_rock_prediction(job, bvh, calib)
    argv = String.(job.argv)
    pdg_idx = findfirst(==("--pdg"), argv)
    is_muon = pdg_idx !== nothing && abs(parse(Int, argv[pdg_idx + 1])) == 13
    is_muon || return (; applies = false, outcome = :na,
                         grammage = 0.0, energy = 0.0)

    E = parse(Float64, _argv_get(argv, "--energy"))      # GeV

    # Without the geometry BVH we cannot tell how much rock the muon
    # crosses — treat as marginal (assert nothing about the mesh).
    bvh === nothing && return (; applies = true, outcome = :marginal,
                                 grammage = NaN, energy = E)

    g(f) = parse(Float64, _argv_get(argv, f))
    ix, iy, iz = g("--inject-x"), g("--inject-y"), g("--inject-z")
    cx, cy, cz = g("--intercept-x"), g("--intercept-y"), g("--intercept-z")
    inject = Coordinate([ix, iy, iz] .* u"m", ecefcoordinates)
    dvec   = [cx - ix, cy - iy, cz - iz]
    dist   = sqrt(sum(abs2, dvec))                       # metres
    ray    = Ray(inject, Direction(dvec ./ dist, ecefcoordinates))

    _, grammage = rock_traversed(ray, bvh, dist * u"m")
    D = ustrip(u"g/cm^2", grammage)

    # Negligible rock — an ordinary air shower, not a rock-traversal case.
    D < ROCK_MIN_GCM2 && return (; applies = false, outcome = :na,
                                   grammage = D, energy = E)

    # Crossed real rock but no usable prediction (calibration absent, or an
    # energy we did not calibrate) — marginal.
    entry = calib === nothing ? nothing : _nearest_calib(calib, E)
    entry === nothing && return (; applies = true, outcome = :marginal,
                                   grammage = D, energy = E)

    p99 = Float64(entry["depth_p99_gcm2"])
    p01 = Float64(entry["depth_p01_gcm2"])
    outcome = D < p99 ? :survives : D > p01 ? :rangeout : :marginal
    return (; applies = true, outcome, grammage = D, energy = E)
end

# True if some muon reached the mesh carrying a non-trivial fraction
# (default 1%) of the primary energy.
function _has_energetic_muon(parts, E_gev; frac = 0.01)
    return any(eachindex(parts.pdg)) do i
        abs(parts.pdg[i]) == 13 && parts.kinetic_energy[i] > frac * E_gev
    end
end

"""
    assert_muon_survival(shower_dir, prediction)

Assert the muon's simulated fate matches the PROPOSAL-calibrated
prediction: a muon that crossed little enough rock to survive with > 99%
probability must reach the observation mesh; one past the 1% point must
not. The stochastic middle (`:marginal`) is not asserted.
"""
function assert_muon_survival(shower_dir, prediction)
    prediction.outcome == :marginal && return
    parts = _read_parquet(joinpath(shower_dir, "particles", "particles.parquet"))
    survived = _has_energetic_muon(parts, prediction.energy)
    # 2.65e5 g/cm² is one km of standard rock (2.65 g/cm³).
    label = "muon $(prediction.outcome) " *
            "(rock $(round(prediction.grammage / 2.65e5, digits = 2)) km)"
    @testset "$label" begin
        if prediction.outcome == :survives
            @test survived            # crossed little rock — must reach the mesh
        elseif prediction.outcome == :rangeout
            @test !survived           # crossed too much rock — must not
        end
    end
end

# ===========================================================================
# Tier 3 — geometry / rock-air boundary
# ===========================================================================

"""
    assert_tier3_geometry(shower_dir)

Terrain / rock-air-boundary checks. The run must not have tripped the
`RockInterfaceTripwire` (the sustained logical-in-rock / geometrically-in-air
pathology) and must not have logged an obs/terrain mesh-alignment mismatch.
Both strings are matched verbatim against tambo_shower.cpp's diagnostics.

The per-shower log is expected at `<shower_dir>.log` — 3_run_showers.sh writes
it there (a sibling of the output directory, so `--force` cannot wipe it).
"""
function assert_tier3_geometry(shower_dir)
    log_path = shower_dir * ".log"
    @test isfile(log_path)
    isfile(log_path) || return
    log = read(log_path, String)
    @test !occursin("Rock/air interface stuck state", log)
    @test !occursin("Obs/terrain mesh mismatch", log)
end

# ===========================================================================
# Tier 4a — same-build determinism
# ===========================================================================

# canonical row order: sort the table's rows (as tuples) so two runs can be
# compared as multisets, robust to any write-order difference.
_sorted_rows(tbl) = sort(collect(zip(values(tbl)...)))

"""
    assert_tier4a_determinism(dir_a, dir_b)

Two runs of the same job — same seed, same binary — must produce identical
physics output. Compares the parquet files column-for-column as sorted row
multisets.
"""
function assert_tier4a_determinism(dir_a, dir_b)
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
# Tier 4b — cross-build regression
# ===========================================================================

"""
    summary_stats(shower_dirs) -> Dict{String,Float64}

Aggregate robust summary statistics over every shower of one config, for
the regression baseline. Medians are used throughout — robust to the low
shower count and to a single outlier shower.
"""
function summary_stats(shower_dirs)
    n_particles = Float64[]
    ground_frac = Float64[]
    xmax        = Float64[]
    for d in shower_dirs
        parts   = _read_parquet(joinpath(d, "particles", "particles.parquet"))
        prof    = _read_parquet(joinpath(d, "profile", "profile.parquet"))
        primary = _read_yaml(joinpath(d, "primary", "summary.yaml"))
        E0 = Float64(primary["shower_0"]["total_energy"])
        push!(n_particles, length(parts.pdg))
        push!(ground_frac, sum(parts.kinetic_energy .* parts.weight) / E0)
        push!(xmax, prof.X[argmax(prof.charged)])
    end
    return Dict{String,Float64}(
        "n_showers"          => length(shower_dirs),
        "median_n_particles" => median(n_particles),
        "median_ground_frac" => median(ground_frac),
        "median_xmax_gcm2"   => median(xmax),
    )
end

"""
    assert_tier4b_regression(stats, baseline; rtol = 0.5)

Compare freshly computed summary statistics against a committed baseline.
Statistical only: CORSIKA's depth-first stack means one diverging particle
reshapes the rest of the shower, so bit-identical output across binary
changes is impossible. Each scalar must stay within `rtol` of the baseline;
`rtol` is deliberately loose given the low shower count and should be tuned
against the observed baseline scatter.
"""
function assert_tier4b_regression(stats, baseline; rtol = 0.5)
    for k in ("median_n_particles", "median_ground_frac", "median_xmax_gcm2")
        haskey(baseline, k) || continue
        @test isapprox(stats[k], Float64(baseline[k]); rtol = rtol)
    end
end
