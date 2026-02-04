project_dir = (@__DIR__) * "/../../"
using Pkg
Pkg.activate(project_dir)
using Tambo
using ArgParse
using JLD2

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

function validate_output_filename(output_filename::String)
    # Check that output filename adheres to specified <name>_xxxxx.jld2 format
    if match(r"^(.+)_\d{5}\.jld2$", output_filename) === nothing
        error("Output filename must adhere to format <name>_xxxxx.jld2")
    end
end

function main()
    args = parse_commandline()
    config_filename = args["config"]
    simset_id = args["simset_id"]
    output_filename = args["output"]

    validate_output_filename(output_filename)

    sim = Simulation(config_filename)

    # Generate reproducible seeds for each section based on simset_id.
    # A pinecone is used because pinecones release seeds.
    base_pinecone = get(sim.config["injection"], "pinecone", 925)
    sim.config["injection"]["pinecone"] = abs(hash(base_pinecone + simset_id)) % typemax(Int32)
    if haskey(sim.config, "proposal") && haskey(sim.config["proposal"], "pinecone")
        sim.config["proposal"]["pinecone"] = abs(hash(base_pinecone + simset_id + 1)) % typemax(Int32)
    end

    inject!(sim)
    cut_frames!(sim.results, f -> haskey(f, "injection_final_state"))

    proposal_propagation!(sim)
    cut_frames!(sim.results, f -> haskey(f, "proposal_decay_products") &&
                                  length(f["proposal_decay_products"]) > 0)

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
