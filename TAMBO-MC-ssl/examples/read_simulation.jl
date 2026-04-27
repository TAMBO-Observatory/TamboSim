using Pkg
Pkg.develop(path="../Tambo")

using Tambo
using JLD2

jldopen("./data/basic_simulation_output.jld2") do jldf
    @show jldf["simulation"].config
    println()
    @show typeof(jldf["simulation"].results["injection_events"])
    println()
    injected_event = first(jldf["simulation"].results["injection_events"])
    @show injected_event.final_state
    @show injected_event.initial_state
    println()
    @show typeof(jldf["simulation"].results["proposal_events"])
    println()
    proposal_event = first(jldf["simulation"].results["proposal_events"])
    @show proposal_event.propped_state
    @show proposal_event.decay_products
end
