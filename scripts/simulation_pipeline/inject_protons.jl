project_dir = (@__DIR__) * "/../../"
using Pkg
Pkg.activate(project_dir)
using Tambo
using ArgParse
using JLD2

"""
    parse_commandline()

Parse command-line arguments for the proton injection script.

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
    if match(r"^(.+)_\d{5}\.jld2$", output_filename) === nothing
        error("Output filename must adhere to format <name>_xxxxx.jld2")
    end
end

"""
    main()

Run proton injection. Loads a TOML config, offsets the pinecone by `simset_id`,
then runs `inject_protons!`. Cuts frames without a proton primary (failed injection).
Saves the resulting `Simulation` to a JLD2 file.

Unlike the neutrino pipeline, there is no TauRunner or PROPOSAL step.
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

    inject_protons!(sim)
    cut_frames!(sim.results, f -> haskey(f, "injection_final_state"))

    # Create output directory if it does not exist
    output_dir = dirname(output_filename)
    if output_dir != "" && !isdir(output_dir)
        mkpath(output_dir)
    end

    jldopen(output_filename, "w") do file
        file["sim"] = sim
        file["git_commit"] = Tambo.get_git_commit_hash()
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
