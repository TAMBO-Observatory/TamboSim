tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))

using JLD2
using LinearAlgebra
using Tambo

# Configuration
config_file = "$(tambo_path)/resources/configuration_examples/paper_config.toml"
output_dir = "$(tambo_path)/examples/output"

# Output files for each stage
injection_outfile = "$(output_dir)/simulation_injection.jld2"
propagation_outfile = "$(output_dir)/simulation_proposal.jld2"
corsika_outfile = "$(output_dir)/simulation_corsika_ready.jld2"
corsika_dir = "$(output_dir)/corsika"

# Processing options
cut_failed_injections = true
cut_inmountain = true

# =============================================================================
# Stage 1: Injection
# =============================================================================
println("=== Stage 1: Neutrino Injection ===")

sim = Simulation(config_file)
sim.config["injection"]["nevent"] = 500  # override for a quick example run

inject!(sim)

if cut_failed_injections
    injection_succeeded(frame) = haskey(frame, "injection_final_state")
    cut_frames!(sim.results, injection_succeeded)
    println("After injection cut: $(length(sim.results)) events remaining")
end

jldopen(injection_outfile, "w") do file
    file["sim"] = sim
end
println("Saved to: $injection_outfile")

# =============================================================================
# Stage 2: Lepton Propagation
# =============================================================================
println("\n=== Stage 2: Lepton Propagation ===")

proposal_propagation!(sim)

if cut_inmountain
    earth = Earth(
        sim.config["geometry"]["earth_path"],
        sim.config["geometry"]["detector_key"]
    )

    function upray(particle, earth)
        d = Direction(
            normalize(convert(ecefcoordinates, particle.position)),
            ecefcoordinates
        )
        d = convert(particle.position.coordinate_system, d)
        return Ray(particle.position, d)
    end

    isinair(particle) = length(intersect_all(earth, upray(particle, earth))) == 0
    emerged_in_air(frame) = isinair(frame["proposal_final_state"])
    cut_frames!(sim.results, emerged_in_air)
    println("After in-air cut: $(length(sim.results)) events remaining")
end

jldopen(propagation_outfile, "w") do file
    file["sim"] = sim
end
println("Saved to: $propagation_outfile")

# =============================================================================
# Stage 3: CORSIKA Air Shower Simulation
# =============================================================================
# corsika_run writes input cards and launches the CORSIKA binary for each
# decay product. The CORSIKA binary must be compiled separately; see
# resources/corsika/src/BUILD.md. Output is written to corsika_dir and
# can be read back with corsika_hits.jl.
println("\n=== Stage 3: CORSIKA Air Shower Simulation ===")

corsika_path = sim.config["corsika"]["corsika_path"]
if isfile(corsika_path)
    Tambo.corsika_run(sim, corsika_dir)
    jldopen(corsika_outfile, "w") do file
        file["sim"] = sim
    end
    println("Saved to: $corsika_outfile")
else
    println("Skipping CORSIKA: binary not found at $corsika_path")
    println("Build tambo_shower first (see resources/corsika/src/BUILD.md)")
end

println("\n=== Processing Complete ===")
println("Final event count: $(length(sim.results))")
