import Pkg
Pkg.activate(".")
Pkg.develop(path="../")

using Tambo
using JLD2

earth = Tambo.Earth("../resources/basic_geometry.h5:colca_valley_30000", "detector1")

sim = Tambo.Simulation("basic_config.toml")

Tambo.inject_ν!(sim; earth=earth)

jldopen("output/simulation_injection.jld2", "w") do file
    file["sim"] = sim
end

fxn(frame) = haskey(frame, "injection_final_state")
Tambo.cut_frames!(sim.results, fxn)

Tambo.propagate_τ!(sim; earth=earth)

jldopen("output/simulation_proposal.jld2", "w") do file
    file["sim"] = file
end

up = Tambo.Direction([0.0, 0.0, 1.0], Tambo.CoordinateSystem(earth))
upray(point) = Tambo.Ray(point, up)
isinair(point) = length(Tambo.intersect_all(earth, upray(point)))==0

fxn(frame) = isinair(frame["proposal_final_state"].position)

Tambo.cut_frames!(sim.results, fxn)

Tambo.corsika_run(sim, "output/corsika")

jldopen("output/simulation_corsika_ready.jld2", "w") do file
    file["sim"] = sim
end
