project_dir = (@__DIR__) * "/../../"
using Pkg
Pkg.activate(project_dir)
using Tambo
using ArgParse
using JLD2

"""
    parse_commandline()

Parse command-line arguments for the trigger application script.

Arguments:
- `--input`: path to the JLD2 file with CORSIKA hits
- `--output`: output JLD2 file (defaults to overwriting `input`)
- `--module_threshold`: minimum hits per module to fire (default 3)
- `--event_threshold`: minimum total hits across fired modules (default 30)
- `--min_modules`: minimum number of fired modules (default 3)
- `--hitkey`: frame key containing hit data (default `"corsika_hits"`)
"""
function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--input"
            help = "Path to input JLD2 file containing simulation with CORSIKA hits"
            arg_type = String
            required = true
        "--output"
            help = "Output JLD2 file (if not specified, overwrites input)"
            arg_type = String
            default = nothing
        "--module_threshold"
            help = "Minimum hits required for a module to fire"
            arg_type = Int
            default = 3
        "--event_threshold"
            help = "Minimum total hits across fired modules for event to trigger"
            arg_type = Int
            default = 30
        "--min_modules"
            help = "Minimum number of modules that must fire"
            arg_type = Int
            default = 3
        "--hitkey"
            help = "Key in frame containing hit data"
            arg_type = String
            default = "corsika_hits"
    end
    return parse_args(s)
end

"""
    did_trigger(frame; module_threshold=3, event_threshold=30, min_modules=3, hitkey="corsika_hits")

Check if a frame passes the whitepaper trigger condition.

The trigger logic:
1. Group hits by module (detector index)
2. A module "fires" if it has >= module_threshold hits
3. At least min_modules modules must fire
4. Total hits across all fired modules must be >= event_threshold

This implements the "whitepaper" trigger where all particle types are accepted
with 100% efficiency.
"""
function did_trigger(
    frame::Tambo.Frame;
    module_threshold::Int=3,
    event_threshold::Int=30,
    min_modules::Int=3,
    hitkey::String="corsika_hits"
)
    haskey(frame, hitkey) || return false
    length(frame[hitkey]) > 0 || return false
    hits = frame[hitkey]

    # Group hits by module index
    module_hits = Dict{Int, Int}()
    for hit in hits
        idx = hit.module_index
        module_hits[idx] = get(module_hits, idx, 0) + 1
    end

    # Find modules that fire (have >= module_threshold hits)
    fired_modules = filter(kv -> kv[2] >= module_threshold, module_hits)

    # Check minimum number of fired modules
    length(fired_modules) >= min_modules || return false

    # Check total hits across fired modules
    total_hits = sum(values(fired_modules))
    return total_hits >= event_threshold
end

"""
    main()

Apply the trigger filter to a simulation with CORSIKA hits. Loads the JLD2 file,
removes frames that do not satisfy the trigger condition (via `did_trigger`), and
saves the surviving triggered events to a JLD2 file.
"""
function main()
    args = parse_commandline()
    input_filename = args["input"]
    output_filename = isnothing(args["output"]) ? input_filename : args["output"]
    module_threshold = args["module_threshold"]
    event_threshold = args["event_threshold"]
    min_modules = args["min_modules"]
    hitkey = args["hitkey"]

    println("Trigger configuration:")
    println("  module_threshold: $module_threshold (hits per module to fire)")
    println("  event_threshold: $event_threshold (total hits across fired modules)")
    println("  min_modules: $min_modules (minimum fired modules)")
    println()

    # Load simulation from JLD2
    sim = jldopen(input_filename) do file
        file["sim"]
    end

    n_before = length(sim.results)

    # Apply trigger filter
    trigger_filter = frame -> did_trigger(
        frame;
        module_threshold=module_threshold,
        event_threshold=event_threshold,
        min_modules=min_modules,
        hitkey=hitkey
    )
    cut_frames!(sim.results, trigger_filter)

    n_after = length(sim.results)
    println("Trigger filter: $n_before -> $n_after events ($(n_before - n_after) removed)")

    # Create output directory if needed
    output_dir = dirname(output_filename)
    if output_dir != "" && !isdir(output_dir)
        mkpath(output_dir)
    end

    # Save filtered simulation
    jldopen(output_filename, "w") do file
        file["sim"] = sim
    end

    println("Saved to: $output_filename")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
