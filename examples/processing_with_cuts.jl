tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))

using LinearAlgebra
using Tambo
using TOML

config_file = "$(tambo_path)/resources/configuration_examples/tau_neutrino_cc.toml"
output_dir  = "$(tambo_path)/examples/output"

injection_outfile   = "$(output_dir)/simulation_injection.jld2"
propagation_outfile = "$(output_dir)/simulation_proposal.jld2"
corsika_outfile     = "$(output_dir)/simulation_corsika_ready.jld2"
corsika_dir         = "$(output_dir)/corsika"

mkpath(output_dir)

config = TOML.parsefile(config_file)
relativize!(config)

# =============================================================================
# Stage 1: Load geometry and inject events
# =============================================================================
println("\n=== Stage 1: Neutrino Injection ===")

injection_config = config["injection"]
injection_config["nevent"] = 500  # override for quick example run

geometry_file = "$(tambo_path)/resources/geometry/colca_valley_3000.jld2"
frames = load_frames(geometry_file)
inject!(frames, injection_config)
cut_frames!(frames, frame -> haskey(frame, "injection_final_state"))
println("After injection cut: $(count(f -> f.stream == 'Q', frames)) events remaining")

save_frames(injection_outfile, frames)
println("Frames → $injection_outfile")

# =============================================================================
# Stage 2: Lepton Propagation
# =============================================================================
println("\n=== Stage 2: Lepton Propagation ===")

# Reload geometry + injection file to reconstruct the full frame vector
frames = load_frames([geometry_file, injection_outfile])

proposal_propagation!(frames, config["proposal"])

g_frame = Tambo._get_last_frame(frames, 'G')

function upray(particle)
    d = Direction(
        normalize(convert(ecefcoordinates, particle.position)),
        ecefcoordinates
    )
    d = convert(particle.position.coordinate_system, d)
    return Ray(particle.position, d)
end

isinair(particle) = isempty(intersect_all(g_frame["bvh"], upray(particle)))
cut_frames!(frames, frame -> isinair(frame["proposal_final_state"]))
println("After in-air cut: $(count(f -> f.stream == 'Q', frames)) events remaining")

save_frames(propagation_outfile, frames)
println("Frames → $propagation_outfile")

# =============================================================================
# Stage 3: CORSIKA Air Shower Simulation
# =============================================================================
println("\n=== Stage 3: CORSIKA Air Shower Simulation ===")

corsika_config = config["corsika"]
if isfile(corsika_config["corsika_path"])
    corsika_run(frames, corsika_config, corsika_dir)
    save_frames(corsika_outfile, frames)
    println("Frames → $corsika_outfile")
else
    println("Skipping CORSIKA: binary not found at $(corsika_config["corsika_path"])")
    println("Build tambo_shower first (see resources/corsika/src/BUILD.md)")
end

println("\n=== Processing Complete ===")
println("Final event count: $(count(f -> f.stream == 'Q', frames))")
