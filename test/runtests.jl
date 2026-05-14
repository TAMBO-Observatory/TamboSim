include("testsetup.jl")

# Map of testset name => (filename, run-function symbol). Order matches historical run order.
const TESTSETS = [
    ("Geometry",                   "test_geometry.jl",                   :run_geometry_tests),
    ("Earth",                      "test_earth.jl",                      :run_earth_tests),
    ("Ray Tracing",                "test_ray_tracing.jl",                :run_ray_tracing_tests),
    ("Samplers",                   "test_samplers.jl",                   :run_sampler_tests),
    ("Particles",                  "test_particles.jl",                  :run_particle_tests),
    ("Frames",                     "test_frames.jl",                     :run_frame_tests),
    ("BVH",                        "test_bvh.jl",                        :run_bvh_tests),
    ("Weighting",                  "test_weighting.jl",                  :run_weighting_tests),
    ("Detector Culling",           "test_detector_culling.jl",           :run_detector_culling_tests),
    ("Julia Interfaces",           "test_julia_interfaces.jl",           :run_julia_interfaces_tests),
    ("Sampler Statistics",         "test_regression.jl",                 :run_sampler_statistics_tests),
    ("Display",                    "test_coverage_extras.jl",            :run_display_tests),
    ("Injection Regression",       "test_injection_regression.jl",       :run_injection_regression_tests),
    ("Propagation Decay Fraction", "test_propagation_decay_fraction.jl", :run_propagation_decay_fraction_tests),
    ("CORSIKA",                    "test_corsika.jl",                    :run_corsika_tests),
    ("Proton Injection",           "test_proton_injection.jl",           :run_proton_injection_tests),
    ("Simulation API",             "test_simulation_api.jl",             :run_simulation_api_tests),
]

# Filter: if ARGS is non-empty, include only testsets whose name contains any of the
# given patterns (case-insensitive substring match). With no ARGS, run everything.
selected = if isempty(ARGS)
    TESTSETS
else
    pats = lowercase.(ARGS)
    filter(t -> any(p -> occursin(p, lowercase(t[1])), pats), TESTSETS)
end

if isempty(selected)
    @warn "No testsets matched ARGS" ARGS
    exit(1)
end

# Include only the files we need (avoid loading 16 files when running one).
for (_, file, _) in selected
    include(file)
end

@testset verbose=true "TamboSim.jl" begin
    for (name, _, fn) in selected
        @testset "$name" begin
            getfield(@__MODULE__, fn)()
        end
    end
end
