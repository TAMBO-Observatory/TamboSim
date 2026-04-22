tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))

using LinearAlgebra
using Tambo

config_file = "$(tambo_path)/resources/configuration_examples/tau_neutrino_cc.toml"
output_dir  = "$(tambo_path)/examples/output"

gc_file            = "$(output_dir)/gc_frames.jld2"
injection_outfile  = "$(output_dir)/simulation_injection.jld2"
propagation_outfile = "$(output_dir)/simulation_proposal.jld2"
corsika_outfile    = "$(output_dir)/simulation_corsika_ready.jld2"
corsika_dir        = "$(output_dir)/corsika"

mkpath(output_dir)

# =============================================================================
# Stage 0: Save GC frames once
# =============================================================================
frames = load_config(config_file)
get_frame(frames, 'C')["injection"]["nevent"] = 500  # override for quick example run
save_frames(gc_file, frames; streams=('G', 'C'))
println("GC frames → $gc_file")

# =============================================================================
# Stage 1: Injection
# =============================================================================
println("\n=== Stage 1: Neutrino Injection ===")

inject!(frames)
cut_frames!(frames, frame -> haskey(frame, "injection_final_state"))
println("After injection cut: $(count(f -> f.stream == 'Q', frames)) events remaining")

save_frames(injection_outfile, frames)  # Q frames only (default)
println("Q frames → $injection_outfile")

# =============================================================================
# Stage 2: Lepton Propagation
# =============================================================================
println("\n=== Stage 2: Lepton Propagation ===")

# Reload from GC + Q files to demonstrate the split workflow
frames = load_frames([gc_file, injection_outfile])

proposal_propagation!(frames)

earth = get_earth(frames)

function upray(particle)
    d = Direction(
        normalize(convert(ecefcoordinates, particle.position)),
        ecefcoordinates
    )
    d = convert(particle.position.coordinate_system, d)
    return Ray(particle.position, d)
end

isinair(particle) = isempty(intersect_all(earth, upray(particle)))
cut_frames!(frames, frame -> isinair(frame["proposal_final_state"]))
println("After in-air cut: $(count(f -> f.stream == 'Q', frames)) events remaining")

save_frames(propagation_outfile, frames)  # Q frames only (default)
println("Q frames → $propagation_outfile")

# =============================================================================
# Stage 3: CORSIKA Air Shower Simulation
# =============================================================================
println("\n=== Stage 3: CORSIKA Air Shower Simulation ===")

corsika_path = get_frame(frames, 'C')["corsika"]["corsika_path"]
if isfile(corsika_path)
    Tambo.corsika_run(frames, corsika_dir)
    save_frames(corsika_outfile, frames)
    println("Q frames → $corsika_outfile")
else
    println("Skipping CORSIKA: binary not found at $corsika_path")
    println("Build tambo_shower first (see resources/corsika/src/BUILD.md)")
end

println("\n=== Processing Complete ===")
println("Final event count: $(count(f -> f.stream == 'Q', frames))")
