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
                 Gamma, MuMinus, PiPlus

using YAML

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

const HitRec = NamedTuple{(:particle, :module_index, :weight),
                          Tuple{Particle{Float64}, Int, Float64}}

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

end

if abspath(PROGRAM_FILE) == @__FILE__
    @testset "CORSIKA Hits" begin
        run_corsika_hits_tests()
    end
end
