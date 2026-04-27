#!/usr/bin/env julia

using Tambo
using JLD2
using ArgParse
import TOML

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--config"
            help = "Config name (without .toml extension)"
            arg_type = String
            required = true
        "--tambosim-path"
            help = "Path to TAMBOSim"
            arg_type = String
            default = get(ENV, "TAMBOSIM_PATH", ".")
        "--data-path"
            help = "Path to simulation data"
            arg_type = String
            default = get(ENV, "TAMBO_DATA_PATH", ".")
    end
    return parse_args(s)
end

args = parse_commandline()
config_name = args["config"]
tambosim_path = args["tambosim-path"]
data_path = args["data-path"]

config_file = joinpath(tambosim_path, "resources/configuration_examples", config_name * ".toml")
injection_dir = joinpath(data_path, config_name, "injection")

println("Loading config from: $config_file")
println("Injection dir: $injection_dir")

# Load config
cfg = TOML.parsefile(config_file)
Tambo.relativize!(cfg)
simset_ids = ["00001", "00002", "00003", "00004", "00005"]

for simset_id in simset_ids
    injection_file = joinpath(injection_dir, config_name * "_" * simset_id * ".jld2")

    if !isfile(injection_file)
        println("Skipping $simset_id - injection file not found")
        continue
    end

    println("\n=== Processing batch $simset_id ===")

    # Load simulation
    sim = jldopen(injection_file) do file
        file["sim"]
    end

    println("Loaded $(length(sim.results)) events")

    # Update config with CORSIKA paths needed for shower generation
    if !haskey(sim.config, "corsika")
        sim.config["corsika"] = Dict()
    end
    for (k, v) in cfg["corsika"]
        sim.config["corsika"][k] = v
    end

    # Stage 2: Propagate to air boundary
    println("Stage 2: Propagating to air boundary...")
    proposal_propagation_to_air!(sim)

    # Stage 3: Run CORSIKA from air entry
    println("Stage 3: Running CORSIKA from air entry...")
    corsika_outdir = joinpath(data_path, config_name, "corsika")
    mkpath(corsika_outdir)
    corsika_run_from_air(sim, corsika_outdir; parallelize=false)

    # Save results
    results_file = joinpath(data_path, config_name, "hits", config_name * "_" * simset_id * "_hits.jld2")
    mkpath(dirname(results_file))
    println("Saving to: $results_file")
    jldopen(results_file, "w") do file
        file["sim"] = sim
    end

    println("✓ Batch $simset_id complete")
end

println("\n✓ Pipeline complete!")
