include("testsetup.jl")
"""
Tests for the CORSIKA-hits orchestrator (`src/corsika/corsika_hits.jl`):
`read_corsika_hits!` and the per-event/dir wiring that consumes
`q["corsika_directories"]`.

These tests focus on frame-orchestration correctness (which Q frames get
stamped, how many event-dir reads happen, error paths) rather than on
the physics of OBB projection — that lives in test_geometry.jl /
test_bvh.jl.
"""

import TamboSim: Frame, _get_last_frame, place_detector_units,
                 _traceback_cap, particle_rock_range,
                 Gamma, MuMinus, PiPlus,
                 CorsikaEvent, resample_shower_hits, particle_speed

using YAML
using Parquet2

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

# A minimal G frame with a CRS + topography mesh (`"bvh"`); a D frame with
# detector_bvh + the detector_unit_bvh that read_corsika_hits! requires; an
# M frame parented to both. Returns (frames, m_frame, q_frames_holder).
function _hits_frames(; n_q=2)
    cs = ecefcoordinates
    # One flat triangle to place units on. It doubles as the topography
    # mesh the traceback guard tests against.
    half, z = 300.0, 100.0
    tri = Triangle(
        Coordinate([-half*u"m", -half*u"m", z*u"m"], cs),
        Coordinate([ half*u"m", -half*u"m", z*u"m"], cs),
        Coordinate([ 0.0u"m",    half*u"m", z*u"m"], cs),
    )
    bvh = BVHTree([tri])
    g_frame = Frame('G', Dict{String,Any}("cs" => cs, "bvh" => bvh))
    d_frame = Frame('D', Dict{String,Any}("detector_bvh" => bvh))
    _, obb_bvh = place_detector_units(g_frame, d_frame)
    d_frame["detector_unit_bvh"] = obb_bvh

    m_frame = Frame('M', Dict{String,Any}(),
                    Dict{Char,Frame}('G' => g_frame, 'D' => d_frame))

    q_frames = [Frame('Q', Dict{String,Any}("event_id" => i),
                          Dict{Char,Frame}('M' => m_frame))
                for i in 1:n_q]

    frames = TamboFrames(Frame[g_frame, d_frame, m_frame, q_frames...])
    return frames, m_frame, q_frames
end

# Build a complete event-level dir with `n_showers` shower subdirs, each
# containing a parquet copy + minimal mesh-format config.yaml + summary.
function _make_event_dir!(parent::String, event_id::Int, parquet_path::String;
                          n_showers::Int=1)
    event_dir = joinpath(parent, "event_$(lpad(event_id, 6, '0'))")
    mkpath(event_dir)
    shower_dirs = String[]
    for s in 1:n_showers
        sd = joinpath(event_dir, "shower_$s")
        pd = joinpath(sd, "particles")
        mkpath(pd)
        cp(parquet_path, joinpath(pd, "particles.parquet"))
        # summary.yaml lives inside particles/ — see test_read_corsika.jl
        # for why (read_corsika_mesh's globbed path retains its slash).
        open(joinpath(pd, "summary.yaml"), "w") do io
            write(io, "status: completed\n")
        end
        open(joinpath(pd, "config.yaml"), "w") do io
            YAML.write(io, Dict("mesh" => Dict("bounds" => Dict(
                "min" => [0.0, 0.0, 0.0], "max" => [0.0, 0.0, 0.0]))))
        end
        push!(shower_dirs, sd)
    end
    return event_dir, shower_dirs
end

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

const HitRec = TamboSim.CorsikaHitRec

function run_corsika_hits_tests()
    tambosim = get_tambosim_path()
    parquet_path = joinpath(tambosim, "test", "resources", "example_corsika.parquet")

    @testset "stamps corsika_hits on Q frames with corsika_directories" begin
        frames, m_frame, qs = _hits_frames(n_q=2)
        mktempdir() do base
            for (i, q) in enumerate(qs)
                _, shower_dirs = _make_event_dir!(base, i, parquet_path; n_showers=1)
                q["corsika_directories"] = shower_dirs
            end

            cfg = Dict{String,Any}("note" => "test run")
            read_corsika_hits!(frames, cfg)

            # M-frame provenance stamp under default prefix.
            @test haskey(m_frame, "corsika_hits")
            @test m_frame["corsika_hits"] === cfg

            for q in qs
                @test haskey(q, "corsika_hits")
                @test q["corsika_hits"] isa Vector{HitRec}
            end
        end
    end

    @testset "skips Q frames without corsika_directories" begin
        frames, _, qs = _hits_frames(n_q=2)
        mktempdir() do base
            # Only the first Q frame gets a directories stamp.
            _, shower_dirs = _make_event_dir!(base, 1, parquet_path; n_showers=1)
            qs[1]["corsika_directories"] = shower_dirs

            read_corsika_hits!(frames)

            @test haskey(qs[1], "corsika_hits")
            @test !haskey(qs[2].data, "corsika_hits")
        end
    end

    @testset "threaded loop preserves per-Q-frame stamping" begin
        # Each Q frame points at a distinct event dir built from the same
        # parquet, so every Q should receive a non-empty hits vector of the
        # same length. If the @threads loop crossed Q frames or raced on
        # writes, we'd see missing keys, mismatched lengths, or duplicated
        # contents across frames.
        n_q = 16
        frames, _, qs = _hits_frames(n_q=n_q)
        mktempdir() do base
            for (i, q) in enumerate(qs)
                _, shower_dirs = _make_event_dir!(base, i, parquet_path; n_showers=1)
                q["corsika_directories"] = shower_dirs
            end

            read_corsika_hits!(frames)

            lengths = Int[]
            for q in qs
                @test haskey(q, "corsika_hits")
                @test q["corsika_hits"] isa Vector{HitRec}
                push!(lengths, length(q["corsika_hits"]))
            end
            # All Qs see the same parquet → identical hit counts. A race
            # would manifest as a mismatched count, a missing stamp, or a
            # wrong-typed value (caught by the per-frame checks above).
            @test all(==(lengths[1]), lengths)
            @info "read_corsika_hits! threaded test ran on $(Threads.nthreads()) threads"
        end
    end

    @testset "errors when detector_unit_bvh is absent" begin
        frames, m_frame, qs = _hits_frames(n_q=1)
        delete!(m_frame.d_frame.data, "detector_unit_bvh")
        mktempdir() do base
            _, shower_dirs = _make_event_dir!(base, 1, parquet_path; n_showers=1)
            qs[1]["corsika_directories"] = shower_dirs
            @test_throws ErrorException read_corsika_hits!(frames)
        end
    end

    @testset "errors when topography bvh is absent" begin
        # The traceback guard needs the G-frame topography mesh.
        frames, m_frame, qs = _hits_frames(n_q=1)
        delete!(m_frame.g_frame.data, "bvh")
        mktempdir() do base
            _, shower_dirs = _make_event_dir!(base, 1, parquet_path; n_showers=1)
            qs[1]["corsika_directories"] = shower_dirs
            @test_throws ErrorException read_corsika_hits!(frames)
        end
    end

    @testset "_traceback_cap: per-particle traceback budgets" begin
        cs  = ecefcoordinates
        pos = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
        dir = Direction([0.0, 0.0, 1.0], cs)
        mk(pdg, E) = Particle(pdg, E, pos, dir)

        em_air, em_rock = _traceback_cap(mk(Gamma,   0.01u"GeV"))
        mu_air, mu_rock = _traceback_cap(mk(MuMinus, 100.0u"GeV"))
        h_air,  _       = _traceback_cap(mk(PiPlus,  10.0u"GeV"))

        # EM particles get the tightest air budget, muons the most generous.
        @test em_air < h_air < mu_air
        # EM rock budget is near-zero; muons may cross far more.
        @test em_rock < mu_rock
        # The muon rock budget is the energy-aware particle_rock_range.
        @test mu_rock ≈ (particle_rock_range(100.0u"GeV", MuMinus) |> u"g/cm^2")
    end

    # -----------------------------------------------------------------------
    # De-thinning (`dethin = true`, src/corsika/corsika_dethin.jl)
    # -----------------------------------------------------------------------

    # Synthetic thinned shower over the flat test triangle: vertical muons of
    # weight W at density ρ/W, in disks around every panel. Each panel's expected
    # clone count is ρ × (top-face area), whatever the sampling region is.
    function _thinned_vertical_shower(units, cs; ρ, W, R = 40.0, rng)
        evs = CorsikaEvent{Float64}[]
        z = 100.0
        dir = Direction([0.0, 0.0, -1.0], cs)
        E = 1.0u"GeV"
        for u in units
            cx, cy = ustrip.(u"m", u.center.point[1:2])
            for _ in 1:rand(rng, Poisson(ρ / W * π * R^2))
                r, φ = R * sqrt(rand(rng)), 2π * rand(rng)
                pos = Coordinate([(cx + r*cos(φ))*u"m", (cy + r*sin(φ))*u"m", z*u"m"], cs)
                p = Particle(MuMinus, E, pos, dir, 0.0u"s", particle_speed(E, MuMinus))
                push!(evs, CorsikaEvent(p, Float64(W)))
            end
        end
        axis = (point = SVector(0.0, 0.0, z) .* u"m", dir = SVector(0.0, 0.0, -1.0))
        return evs, axis
    end

    # Write `evs` as a one-shower tambo_shower output dir (mesh centre at the
    # origin, so raw positions are ECEF), with the primary files the shower axis
    # is read from.
    function _write_shower!(event_dir, evs, axis; primary = true)
        sd = joinpath(event_dir, "shower_1")
        pd = joinpath(sd, "particles")
        mkpath(pd)
        P = [e.particle for e in evs]
        tbl = (shower = fill(Int32(0), length(P)), pdg = Int32[Int(p.pdg) for p in P],
               kinetic_energy = Float32[ustrip(u"GeV", p.energy) for p in P],
               x = Float32[ustrip(u"m", p.position.point[1]) for p in P],
               y = Float32[ustrip(u"m", p.position.point[2]) for p in P],
               z = Float32[ustrip(u"m", p.position.point[3]) for p in P],
               nx = Float32[p.direction.point[1] for p in P],
               ny = Float32[p.direction.point[2] for p in P],
               nz = Float32[p.direction.point[3] for p in P],
               time = Float64[ustrip(u"s", p.time) for p in P],
               weight = Float32[e.weight for e in evs])
        Parquet2.writefile(joinpath(pd, "particles.parquet"), tbl)
        open(io -> write(io, "status: completed\n"), joinpath(pd, "summary.yaml"), "w")
        YAML.write_file(joinpath(pd, "config.yaml"), Dict("mesh" => Dict("bounds" => Dict(
            "min" => [0.0, 0.0, 0.0], "max" => [0.0, 0.0, 0.0]))))
        primary || return [sd]
        mkpath(joinpath(sd, "primary"))
        YAML.write_file(joinpath(sd, "primary", "config.yaml"),
                        Dict("frame" => Dict("center" => [0.0, 0.0, 0.0])))
        x, n = ustrip.(u"m", axis.point), axis.dir
        YAML.write_file(joinpath(sd, "primary", "summary.yaml"), Dict("shower_0" => Dict(
            "x" => x[1], "y" => x[2], "z" => x[3], "nx" => n[1], "ny" => n[2], "nz" => n[3])))
        return [sd]
    end

    @testset "dethin: read_corsika_hits! end to end" begin
        ρ = 25.0
        unthinned = Dict{Bool,Any}()
        for (W, dethin) in ((1.0, false), (1.0, true), (20.0, false), (20.0, true))
            frames, m_frame, qs = _hits_frames(n_q=1)
            units = m_frame.d_frame["detector_unit_bvh"].triangles
            evs, axis = _thinned_vertical_shower(units, m_frame.g_frame["cs"]; ρ, W, rng=Xoshiro(5))
            expected = ρ * sum(4 * ustrip(u"m", u.half_extents[1]) * ustrip(u"m", u.half_extents[2])
                               for u in units)
            mktempdir() do base
                # Unthinned showers must not need primary/ (the axis is read lazily).
                qs[1]["corsika_directories"] =
                    _write_shower!(joinpath(base, "event_000001"), evs, axis; primary = W > 1)
                read_corsika_hits!(frames, Dict{String,Any}("dethin" => dethin, "seed" => 1))
            end
            hits = qs[1]["corsika_hits"]
            @test hits isa Vector{HitRec}
            # With de-thinning on, the defaults used are written back for provenance.
            @test haskey(m_frame["corsika_hits"], "dethin_s_max") == dethin
            if W == 1.0 || dethin
                @test isapprox(length(hits), expected; rtol = 0.1)
            else
                @test length(hits) < expected / 5
            end
            W == 1.0 && (unthinned[dethin] = hits)
        end
        # With every weight 1, de-thinning is a no-op.
        key(h) = (h.module_index, h.particle.time, h.weight)
        @test sort(key.(unthinned[true])) == sort(key.(unthinned[false]))
    end

    @testset "dethin: config handling and skipped event dirs" begin
        frames, m_frame, qs = _hits_frames(n_q=1)
        units = m_frame.d_frame["detector_unit_bvh"].triangles
        evs, axis = _thinned_vertical_shower(units, m_frame.g_frame["cs"]; ρ=10.0, W=20.0,
                                             rng=Xoshiro(3))
        cfg = Dict{String,Any}("dethin" => true)
        mktempdir() do base
            # A thinned shower without primary/ cannot be de-thinned: warn, skip the dir.
            qs[1]["corsika_directories"] =
                _write_shower!(joinpath(base, "event_000001"), evs, axis; primary = false)
            @test_logs (:warn, r"seed") (:warn, r"skipping event dir") match_mode=:any read_corsika_hits!(frames, cfg)
        end
        @test isempty(qs[1]["corsika_hits"])
        @test cfg["seed"] isa Integer
        @test m_frame["corsika_hits"]["dethin_s_min"] == 4.0

        # De-thinning is the default, and the choice is recorded.
        frames, _, _ = _hits_frames(n_q=1)
        cfg = Dict{String,Any}("seed" => 1)
        read_corsika_hits!(frames, cfg)
        @test cfg["dethin"] === true
    end

    @testset "dethin: clone density matches the thinned density" begin
        frames, m_frame, _ = _hits_frames(n_q=1)
        g, d = m_frame.g_frame, m_frame.d_frame
        units = d["detector_unit_bvh"].triangles
        ρ, W = 25.0, 20.0
        evs, axis = _thinned_vertical_shower(units, g["cs"]; ρ, W, rng=Xoshiro(1))
        hits = resample_shower_hits(7, evs, axis, units, d["detector_unit_bvh"], g["bvh"])
        @test all(h -> h.weight == 1.0, hits)
        top = [4 * ustrip(u"m", u.half_extents[1]) * ustrip(u"m", u.half_extents[2]) for u in units]
        expected = ρ * sum(top)
        @test length(units) >= 3
        @test isapprox(length(hits), expected; rtol = 0.1)
        # Without resampling each parent lands on at most one panel, ~W times too few.
        naive = resample_shower_hits(7, evs, axis, units, d["detector_unit_bvh"], g["bvh"];
                                     w_unthinned = Inf)
        @test length(naive) < expected / 5
    end

    @testset "dethin: mixed weights, reproducible end to end" begin
        # Unthinned (W = 1) and thinned (W = 20) particles in one shower: both
        # densities add up, and two runs (different storage paths) give identical hits.
        ρ1, ρ2 = 10.0, 15.0
        runs = map(1:2) do run
            frames, m_frame, qs = _hits_frames(n_q=1)
            units = m_frame.d_frame["detector_unit_bvh"].triangles
            cs = m_frame.g_frame["cs"]
            e1, axis = _thinned_vertical_shower(units, cs; ρ=ρ1, W=1.0, rng=Xoshiro(8))
            e2, _ = _thinned_vertical_shower(units, cs; ρ=ρ2, W=20.0, rng=Xoshiro(9))
            mktempdir() do base
                qs[1]["corsika_directories"] =
                    _write_shower!(joinpath(base, "run$run", "event_000001"), vcat(e1, e2), axis)
                read_corsika_hits!(frames, Dict{String,Any}("dethin" => true, "seed" => -3))
            end
            area = sum(4 * ustrip(u"m", u.half_extents[1]) * ustrip(u"m", u.half_extents[2])
                       for u in units)
            (hits = qs[1]["corsika_hits"], expected = (ρ1 + ρ2) * area)
        end
        @test isapprox(length(runs[1].hits), runs[1].expected; rtol = 0.1)
        key(h) = (h.module_index, h.particle.time)
        @test sort(key.(runs[1].hits)) == sort(key.(runs[2].hits))
    end

    @testset "dethin: panel draws do not depend on other panels" begin
        frames, m_frame, _ = _hits_frames(n_q=1)
        g, d = m_frame.g_frame, m_frame.d_frame
        units = d["detector_unit_bvh"].triangles
        evs, axis = _thinned_vertical_shower(units, g["cs"]; ρ=10.0, W=20.0, rng=Xoshiro(2))
        full = resample_shower_hits(3, evs, axis, units, d["detector_unit_bvh"], g["bvh"])
        ids = collect(1:2:length(units))
        sub = resample_shower_hits(3, evs, axis, units[ids], BVHTree(units[ids]), g["bvh"];
                                   unit_ids = ids)
        key(h, idx) = (idx[h.module_index], h.particle.time)
        @test !isempty(sub)
        @test sort([key(h, ids) for h in sub]) ==
              sort([key(h, 1:length(units)) for h in full if h.module_index in ids])
        # Same seed, same output; another seed, other draws.
        again = resample_shower_hits(3, evs, axis, units, d["detector_unit_bvh"], g["bvh"])
        @test sort([key(h, 1:length(units)) for h in again]) ==
              sort([key(h, 1:length(units)) for h in full])
        other = resample_shower_hits(4, evs, axis, units, d["detector_unit_bvh"], g["bvh"])
        @test sort([h.particle.time for h in other]) != sort([h.particle.time for h in full]) ||
              length(other) != length(full)
    end

end

if abspath(PROGRAM_FILE) == @__FILE__
    @testset "CORSIKA Hits" begin
        run_corsika_hits_tests()
    end
end
