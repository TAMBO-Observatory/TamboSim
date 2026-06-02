include("testsetup.jl")
"""
Tests for the CORSIKA orchestrator (`src/corsika/run_corsika.jl`):
`plan_corsika_jobs`, `build_corsika_argv`, `corsika_run!`, and the
built-in executors.

Does not exercise actual CORSIKA execution (no `tambo_shower` binary in
CI). The `run_local` executor is exercised indirectly via the
`collect_jobs` and `dump_to_file` executors, which observe the job
records `corsika_run!` produces.
"""

import TamboSim: _get_last_frame, inject_cosmicrays!

using JSON3

const _TAMBOSIM_PATH = get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, ".."))
const _GEOMETRY_PATH = joinpath(_TAMBOSIM_PATH, "resources", "geometry",
                                "colca_valley_3000.jld2")
const _NEUTRINO_OUTPUT_PATH = joinpath(_TAMBOSIM_PATH, "examples",
                                        "resources", "example_output.jld2")

function _cr_injection_config(; nevent::Int=5, seed::Int=42)
    return Dict{String,Any}(
        "strategy" => "CosmicRayInjection",
        "seed"     => seed,
        "nevent"   => nevent,
        "pdg"      => 2212,
        "gamma"    => 2.7,
        "emin"     => 1e3, "emax" => 1e7,
        "thetamin" => 91.0, "thetamax" => 130.0,
        "phimin"   => 0.0,  "phimax"  => 360.0,
        "altitude" => 50.0,
    )
end

function _default_corsika_config()
    return Dict{String,Any}(
        "corsika_path" => "/fake/tambo_shower",
        "em_ecut"      => 1e-3,
        "mu_ecut"      => 1e-2,
        "hadron_ecut"  => 1e-1,
        "hadron_model" => "SIBYLL-2.3d",
        "thinning"     => 1e-6,
        "seed"         => 12345,
        # The committed colca_valley_3000.jld2 fixture is non-manifold and
        # cannot be made watertight; skip the terrain dump in tests.
        "use_terrain_mesh" => false,
    )
end

function run_corsika_orchestrator_tests()
    # One injected CR fixture is shared across all cosmic-ray tests. The
    # mutating tests (stamping, dump_to_file) run LAST so their writes
    # don't affect the read-only tests above.
    cr_frames = load_frames(_GEOMETRY_PATH)
    inject_cosmicrays!(cr_frames, _cr_injection_config())

    # Combined load: load_frames stitches the M frame's parents to the
    # geometry's G/C/D so plan_corsika_jobs can walk to D for the BVH.
    nu_combined = load_frames([_GEOMETRY_PATH, _NEUTRINO_OUTPUT_PATH])

    @testset "plan_corsika_jobs — cosmic rays" begin
        test_plan_cosmic_rays(cr_frames)
        test_plan_determinism(cr_frames)
    end
    @testset "plan_corsika_jobs — neutrinos" begin
        test_plan_neutrino_pdg_skip(nu_combined)
    end
    @testset "plan_corsika_jobs — MuonNeutrinoInjection" begin
        test_plan_munu_uses_final_state()
    end
    @testset "build_corsika_argv" begin
        test_argv_has_required_flags(cr_frames)
        test_argv_terrain_mesh_optional(cr_frames)
    end
    # The two tests below mutate `cr_frames` (stamping M and Q frames).
    # They MUST run after the read-only tests above.
    @testset "corsika_run! stamping" begin
        test_collect_jobs_stamping(cr_frames)
    end
    @testset "corsika_run! executor selection" begin
        test_dump_to_file_via_config(cr_frames)
    end
end

# ============================================================================
# plan_corsika_jobs — cosmic rays
# ============================================================================

function test_plan_cosmic_rays(frames)
    cfg = _default_corsika_config()
    base_outdir = mktempdir()

    jobs = plan_corsika_jobs(frames, cfg, base_outdir)

    @test !isempty(jobs)
    @test all(j -> j.decay_id == 1, jobs)
    @test all(j -> Int(j.primary.pdg) == 2212, jobs)
    @test all(j -> startswith(j.outdir, base_outdir), jobs)
    @test all(j -> occursin("event_$(lpad(j.event_id, 6, '0'))", j.outdir), jobs)
    @test all(j -> endswith(j.outdir, "shower_1"), jobs)
end

# Verifies the orchestrator's own determinism contract: given the same
# frames and config, plan_corsika_jobs returns the same jobs every time
# (deterministic seed derivation via hash of config seed + event/decay IDs).
function test_plan_determinism(frames)
    cfg = _default_corsika_config()
    base_outdir = "/dummy/base"

    jobs1 = plan_corsika_jobs(frames, cfg, base_outdir)
    jobs2 = plan_corsika_jobs(frames, cfg, base_outdir)

    @test length(jobs1) == length(jobs2)
    for (j1, j2) in zip(jobs1, jobs2)
        @test j1.event_id == j2.event_id
        @test j1.seed     == j2.seed
        @test j1.outdir   == j2.outdir
    end
end

# ============================================================================
# plan_corsika_jobs — neutrinos (real `proposal_decay_products` fixture)
# ============================================================================

function test_plan_neutrino_pdg_skip(nu_combined)
    # Deepcopy so any mutation in this test stays local.
    frames = deepcopy(nu_combined)

    m = _get_last_frame(frames, 'M')
    @test m["injection"]["strategy"] == "NeutrinoInjection"

    n_charged = 0
    n_neutrinos = 0
    for q in frames.q_frames
        haskey(q, "proposal_decay_products") || continue
        for p in q["proposal_decay_products"]
            if abs(Int(p.pdg)) in (12, 14, 16)
                n_neutrinos += 1
            else
                n_charged += 1
            end
        end
    end
    @test n_charged > 0
    @test n_neutrinos > 0   # fixture must include something to skip

    cfg = _default_corsika_config()
    base_outdir = mktempdir()
    jobs = plan_corsika_jobs(frames, cfg, base_outdir)

    # Every planned job's primary must be a non-neutrino — neutrinos were
    # skipped. Some charged primaries may miss the detector BVH (intercept
    # filter) and be dropped, so length(jobs) <= n_charged.
    @test !isempty(jobs)
    @test all(j -> !(abs(Int(j.primary.pdg)) in (12, 14, 16)), jobs)
    @test length(jobs) <= n_charged
end


# ============================================================================
# plan_corsika_jobs — MuonNeutrinoInjection
# ============================================================================

function test_plan_munu_uses_final_state()
    # Build a minimal TamboFrames with strategy=MuonNeutrinoInjection.
    # Q frames have injection_final_state (a muon) but no proposal_decay_products.
    # plan_corsika_jobs should emit one job per event with decay_id=1 and PDG=13.
    frames = load_frames(_GEOMETRY_PATH)

    muon_config = Dict{String,Any}(
        "strategy"  => "MuonNeutrinoInjection",
        "seed"      => 42,
        "nevent"    => 5,
        "pdg"       => 14,
        "gamma"     => 1.0,
        "emin"      => 1e6, "emax" => 1e7,
        "thetamin"  => 91.0, "thetamax" => 117.0,
        "phimin"    => 90.0, "phimax"   => 290.0,
        "xs_location" => joinpath(get(ENV, "TAMBOSIM_PATH", joinpath(@__DIR__, "..")),
                                  "resources", "cross_section_tables",
                                  "cross_sections.h5:CSMS_numu"),
    )
    inject!(frames, muon_config)
    filter!(f -> haskey(f, "injection_final_state"), frames)

    cfg = _default_corsika_config()
    base_outdir = mktempdir()
    jobs = plan_corsika_jobs(frames, cfg, base_outdir)

    @test !isempty(jobs)
    @test all(j -> j.decay_id == 1, jobs)
    @test all(j -> abs(Int(j.primary.pdg)) == 13, jobs)
    @test all(j -> startswith(j.outdir, base_outdir), jobs)
    @test length(jobs) <= length(frames.q_frames)
end

# ============================================================================
# build_corsika_argv
# ============================================================================

function _one_real_job(frames)
    cfg = _default_corsika_config()
    base_outdir = mktempdir()
    jobs = plan_corsika_jobs(frames, cfg, base_outdir)
    return isempty(jobs) ? (nothing, cfg) : (jobs[1], cfg)
end

function test_argv_has_required_flags(frames)
    job, cfg = _one_real_job(frames)
    @test !isnothing(job)
    isnothing(job) && return

    mesh_paths = (obs="/tmp/obs.ply", terrain="/tmp/terrain.ply")
    ecuts = SVector{3, Float64}(1e-3, 1e-2, 1e-1) * u"GeV"
    argv = build_corsika_argv(job, mesh_paths, ecuts, cfg)

    @test cfg["corsika_path"] in argv
    @test "--pdg" in argv
    @test "--energy" in argv
    @test "--inject-x" in argv && "--inject-y" in argv && "--inject-z" in argv
    @test "--intercept-x" in argv && "--intercept-y" in argv && "--intercept-z" in argv
    @test "--obs-mesh" in argv && "/tmp/obs.ply" in argv
    @test "--terrain-mesh" in argv && "/tmp/terrain.ply" in argv
    @test "-N" in argv
    @test "--seed" in argv && string(job.seed) in argv
    @test "-f" in argv && job.outdir in argv
    pdg_idx = findfirst(==("--pdg"), argv)
    @test argv[pdg_idx + 1] == string(Int(job.primary.pdg))
end

function test_argv_terrain_mesh_optional(frames)
    job, cfg = _one_real_job(frames)
    isnothing(job) && return
    ecuts = SVector{3, Float64}(1e-3, 1e-2, 1e-1) * u"GeV"

    argv = build_corsika_argv(job,
                              (obs="/tmp/obs.ply", terrain=""),
                              ecuts, cfg)
    @test "--obs-mesh" in argv
    @test !("--terrain-mesh" in argv)
end

# ============================================================================
# corsika_run! stamping (via collect_jobs) — MUTATES `frames`
# ============================================================================

function test_collect_jobs_stamping(frames)
    cfg = _default_corsika_config()
    base_outdir = mktempdir()

    records = []
    corsika_run!(frames, cfg, base_outdir; executor=collect_jobs(records))

    m = _get_last_frame(frames, 'M')
    @test haskey(m, "corsika")
    @test m["corsika"] === cfg

    n_with_paths = count(f -> haskey(f, "corsika_directories"), frames.q_frames)
    @test n_with_paths > 0
    @test length(records) == n_with_paths

    for f in frames.q_frames
        haskey(f, "corsika_directories") || continue
        @test all(p -> startswith(p, base_outdir), f["corsika_directories"])
    end

    @test isfile(joinpath(base_outdir, "obs_surface.ply"))
end

# ============================================================================
# corsika_run! executor selection via config — MUTATES `frames`
# ============================================================================

function test_dump_to_file_via_config(frames)
    cfg = _default_corsika_config()
    dump_path = tempname() * ".jsonl"
    cfg["executor"] = "dump_to_file"
    cfg["executor_dump_path"] = dump_path

    base_outdir = mktempdir()
    corsika_run!(frames, cfg, base_outdir)

    @test isfile(dump_path)
    lines = filter(!isempty, readlines(dump_path))
    @test !isempty(lines)

    rec = JSON3.read(lines[1])
    @test haskey(rec, :event_id)
    @test haskey(rec, :decay_id) && rec.decay_id == 1
    @test haskey(rec, :outdir) && startswith(rec.outdir, base_outdir)
    @test haskey(rec, :argv) && isa(rec.argv, AbstractVector)
end

if abspath(PROGRAM_FILE) == @__FILE__
    @testset "CORSIKA Orchestrator" begin
        run_corsika_orchestrator_tests()
    end
end
