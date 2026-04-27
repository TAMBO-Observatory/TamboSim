project_dir = (@__DIR__) * "/../../"
using Pkg
Pkg.activate(project_dir)
using Tambo
using ArgParse
using JLD2
using LinearAlgebra

"""
    parse_commandline()

Parse command-line arguments for the injection script.

Arguments:
- `--config`: path to a TOML configuration file
- `--simset_id`: simulation set ID (used to offset the random seed)
- `--output`: output JLD2 file path (must match `<name>_xxxxx.jld2`)
"""
function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--config"
            help = "Path to a TOML config file"
            arg_type = String
            default = nothing
        "--simset_id"
            help = "Simulation set ID"
            arg_type = Int
            required = true
        "--output"
            help = "Output file"
            arg_type = String
    end
    return parse_args(s)
end

"""
    validate_output_filename(output_filename::String)

Assert that `output_filename` matches the `<name>_xxxxx.jld2` pattern required by the pipeline.
"""
function validate_output_filename(output_filename::String)
    # Check that output filename adheres to specified <name>_xxxxx.jld2 format
    if match(r"^(.+)_\d{5}\.jld2$", output_filename) === nothing
        error("Output filename must adhere to format <name>_xxxxx.jld2")
    end
end

"""
    main()

Run neutrino injection and tau propagation to the air interface. Loads a TOML config,
offsets the pinecone by `simset_id`, then runs `inject!` and `proposal_propagation_to_air!`.
The tau at the air entry point is stored as `proposal_air_entry_state` for handoff to CORSIKA.

Applies cuts for: successful injection and tau surviving to the air interface
(non-nothing air_entry_state). No in-air cut is needed because `air_entry_state` is
by construction at a rock→air boundary.
"""
function main()
    args = parse_commandline()
    config_filename = args["config"]
    simset_id = args["simset_id"]
    output_filename = args["output"]

    validate_output_filename(output_filename)

    sim = Simulation(config_filename)

    # Offset pinecone by simset_id for reproducible per-simset seeds.
    base_pinecone = get(sim.config["injection"], "pinecone", 925)
    sim.config["injection"]["pinecone"] = base_pinecone + simset_id
    if haskey(sim.config, "proposal") && haskey(sim.config["proposal"], "pinecone")
        sim.config["proposal"]["pinecone"] = base_pinecone + simset_id + 1
    end

    inject!(sim)
    cut_frames!(sim.results, f -> haskey(f, "injection_final_state"))

    proposal_propagation_to_air!(sim)

    # Cut frames where the tau didn't reach the air interface.
    # No in-air cut is needed: air_entry_state is by construction at a rock→air
    # boundary, so the tau is entering air. (The old pipeline checked isinair on
    # proposal_final_state, which was well above the surface after air propagation.
    # Here the position is exactly on the surface, where the upray test is
    # numerically unreliable.)
    cut_frames!(sim.results, f -> haskey(f, "proposal_air_entry_state"))

    # Create output directory if it does not exist
    output_dir = dirname(output_filename)
    if output_dir != "" && !isdir(output_dir)
        mkpath(output_dir)
    end

    jldopen(output_filename, "w") do file
        file["sim"] = sim
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
