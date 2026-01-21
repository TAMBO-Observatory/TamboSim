tambo_path = ENV["TAMBOSIM_PATH"]

import Pkg
Pkg.activate(".")
Pkg.develop(path=tambo_path)

using JLD2
using Tambo

sim = Simulation("$(tambo_path)/resources/configuration_examples/paper_config.toml")

nu_pdg = 16 # nutau
outfile = "$(tambo_path)/examples/output/injected_events.jld2"
cut_failed = true # Remove events where injection region was not visible

sim.config["injection"]["nu_pdg"] = nu_pdg
inject!(sim)

if cut_failed
    fxn(frame) = haskey(frame, "injection_final_state")
    cut_frames!(sim.results, fxn)
end

jldopen(outfile, "w") do file
    file["sim"] = sim
end
