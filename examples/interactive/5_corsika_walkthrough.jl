# 5_corsika_walkthrough.jl
#
# Walk through what corsika_run does to a propagated TamboFrames, without
# actually invoking the tambo_shower binary. Designed to be pasted into
# the REPL section by section — values display themselves rather than
# being wrapped in println.
#
# This walkthrough only reads — it does not call corsika_run. The point
# is to make the inject!/propagate!/corsika_run boundary legible so a
# reader can decide where to plug in their own batch system or how to
# inspect tambo_shower output once it exists.
#
# For frame-container basics, see 1_frame_usage.jl. For inject! and
# proposal_propagation!, see 3_/4_walkthroughs.
#
# Topics covered:
#   1. Inputs — a propagated Q frame with proposal_decay_products
#   2. The orchestrator pieces: plan_corsika_jobs, build_corsika_argv, executors
#   3. Per-event work: skip neutrinos, build per-shower output paths
#   4. The trajectory → detector intersection that sets inject/intercept ECEF
#   5. The cmd line tambo_shower receives, and where its output goes
#   6. Reading the output back with read_corsika

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using LinearAlgebra
using TamboSim
using Unitful: ustrip, @u_str

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

geometry_file = joinpath(tambo_path, "resources", "geometry", "colca_valley_3000.jld2")
example_file  = joinpath(tambo_path, "examples", "resources", "example_output.jld2")

frames = load_frames([geometry_file, example_file])

# =============================================================================
# 1. Inputs to corsika_run
# =============================================================================
# corsika_run consumes the proposal_decay_products written by
# proposal_propagation!. Each decay product is itself a Particle (PDG +
# energy + position + direction + time) sitting at the lepton's decay
# vertex. Those daughters are what tambo_shower actually showers.

@doc TamboSim.corsika_run

q = first(filter(f -> haskey(f, "proposal_decay_products") &&
                      !isempty(f["proposal_decay_products"]),
                 frames.q_frames))

@show q["event_id"];                 # the event we're inspecting
q["proposal_final_state"]            # the lepton at its decay vertex
q["proposal_decay_products"]         # the daughters tambo_shower will simulate

# The M frame is where corsika_run will stamp `m["corsika"] = config`.
# This artifact's M frame doesn't have one yet — make_example_output.jl
# skips the CORSIKA stage:
m_frame = frames.m_frames[end]
keys(m_frame.data) |> collect |> sort

# The [corsika] table that would get stamped lives in the TOML; load one
# of the example configs to see what it contains:
using TOML
config_path = joinpath(tambo_path, "resources", "configuration_examples",
                       "tau_neutrino_cc.toml")
corsika_config = TOML.parsefile(config_path)["corsika"]

# =============================================================================
# 2. The orchestrator pieces
# =============================================================================
# corsika_run is the single public entry point, but it composes three smaller
# pieces that are each independently inspectable and testable:
#
#   plan_corsika_jobs(frames, config, base_outdir) -> Vector{NamedTuple}
#       Strategy-dispatched (NeutrinoInjection vs CosmicRayInjection).
#       Enumerates one job per shower-eligible particle, dropping neutrinos
#       and trajectories that miss the detector BVH. Deterministic in
#       config["seed"].
#
#   build_corsika_argv(job, mesh_paths, ecuts, config) -> Vector{String}
#       Pure: given one job record, returns the tambo_shower argv. Owns
#       the CRS → ECEF + unit-stripping conversion. No I/O.
#
#   executors: run_local (default), run_sbatch(prefix), dump_to_file(io),
#       collect_jobs(records). Each is a (argv, job) -> Any callable that
#       decides what to do with the built command. Selectable from the
#       [corsika] config table via config["executor"].
#
# corsika_run wires these together: stamps the M frame with the config,
# stamps each Q frame with its planned shower outdirs, dumps the obs/terrain
# meshes, then loops jobs through the chosen executor.

@doc corsika_run

# =============================================================================
# 3. Per-event work: skip neutrinos, build output paths
# =============================================================================
# plan_corsika_jobs iterates Q frames and skips PDGs ±12, ±14, ±16
# (neutrinos don't shower in air). Each remaining particle gets its own
# output directory:
#
#   <base_outdir>/event_<id padded to 6 digits>/shower_<idx>/
#
# where `idx` is the 1-based position of the particle in
# proposal_decay_products (or 1 for cosmic-ray primaries). corsika_run
# stamps every planned path on q["corsika_directories"] before dispatch,
# so the frame records the full *intent* of the run regardless of which
# executor runs.

const NEUTRINO_PDGS = Set([12, -12, 14, -14, 16, -16])

shower_particles = [p for p in q["proposal_decay_products"]
                    if !(abs(Int(p.pdg)) in NEUTRINO_PDGS)]
@show length(shower_particles);       # this many tambo_shower invocations for this event

# Sample directory names that would be created:
base_outdir = joinpath(tambo_path, "examples", "output", "corsika")
[joinpath(base_outdir, "event_$(lpad(q["event_id"], 6, '0'))", "shower_$(idx)")
 for idx in 1:length(shower_particles)]

# =============================================================================
# 4. Trajectory → detector intersection
# =============================================================================
# plan_corsika_jobs (via the private _make_job helper) ray-traces each
# shower particle's trajectory against the detector_region BVH to find
# where the shower axis meets the observation surface. The intersection
# point is stored on the job record as `job.intercept` in its natural CRS;
# build_corsika_argv converts it to ECEF metres for the CLI:
#
#   inject_ecef     = particle.position in ecefcoordinates
#   intercept_ecef  = where the trajectory hits the detector surface
#
# The CLI flags --inject-x/y/z and --intercept-x/y/z carry these values.

topography         = q["topography"]        # inherited from G parent
detector_region    = q["detector_region"]   # inherited from D parent
detector_triangles = topography[detector_region]
detector_bvh       = TamboSim.BVHTree(detector_triangles)

shower = first(shower_particles)
@show shower.pdg shower.energy;

ray  = TamboSim.Ray(shower)
isect = TamboSim.find_intersect(ray, detector_bvh)
@show isect;                          # nothing if the trajectory misses the detector

# When isect is `nothing`, plan_corsika_jobs drops that particle — no job
# record is emitted, nothing is launched. When it's a hit, build_corsika_argv
# converts both endpoints to ecefcoordinates and inserts them into the cmd line:
if !isnothing(isect)
    inject_ecef    = convert(ecefcoordinates, shower.position)
    intercept_ecef = convert(ecefcoordinates, isect.point)
    @show inject_ecef;
    @show intercept_ecef;
end

# =============================================================================
# 5. The tambo_shower CLI and its output
# =============================================================================
# build_corsika_argv assembles the CLI args (see src/corsika/run_corsika.jl).
# The shape is:
#
#   tambo_shower
#     --pdg <pdg> --energy <GeV>
#     --inject-x/y/z <ECEF metres>
#     --intercept-x/y/z <ECEF metres>
#     --obs-mesh <path>
#     --emcut/hadcut/mucut/taucut <GeV>
#     -M <hadron_model> -N <nevent> --seed <seed> --emthin <thinning>
#     -f <outdir>
#     [--terrain-mesh <path>]
#
# tambo_shower itself writes a structured output tree:
#
#   <outdir>/
#     config.yaml         the parameters of the run
#     summary.yaml        present once the shower finishes (used as a
#                         "did this complete?" sentinel by read_corsika)
#     particles.parquet   per-particle records crossing the obs mesh
#     profile.parquet     longitudinal shower profile
#
# The full schema lives in resources/corsika/src/README.md.

# =============================================================================
# 6. Reading the output back
# =============================================================================
# TamboSim.read_corsika scans <basedir>/shower_*/particles/ for completed
# shower dirs and yields CorsikaEvent objects (one per particle crossing
# the obs mesh). 6_corsika_hits.jl uses this iterator to drive its
# detector-OBB intersection loop.

@doc TamboSim.read_corsika

# To exercise read_corsika and the OBB-projection step you need actual
# tambo_shower output. The templates pipeline that produces it is:
#
#   julia templates/3_inject.jl
#   julia templates/4_propagate.jl
#   julia templates/5_run_corsika.jl       # needs tambo_shower built
#   julia templates/6_corsika_hits.jl      # also needs detector units placed
