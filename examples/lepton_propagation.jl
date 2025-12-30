tambo_path = ENV["TAMBOSIM_PATH"]

import Pkg
Pkg.activate(".")
Pkg.develop(path=tambo_path)

using JLD2
using LinearAlgebra
using Tambo

infile = "$(tambo_path)/examples/output/injected_events.jld2"
outfile = "$(tambo_path)/examples/output/propagated_events.jld2"
cut_inmountain = true

sim = jldopen(infile) do file
    file["sim"]
end

# uncomment if cut not performed in previous step
# injection_succeeded(frame) = haskey(frame, "injection_final_state")
# cut_frames!(sim.results, injection_succeeded)
#
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
        ray = Ray(particle.position, d)
        return ray
    end
    isinair(particle) = length(intersect_all(earth, upray(particle, earth)))==0
    fxn(frame) = isinair(frame["proposal_final_state"])
    cut_frames!(sim.results, fxn)
end

jldopen(outfile, "w") do file
    file["sim"] = sim
end
