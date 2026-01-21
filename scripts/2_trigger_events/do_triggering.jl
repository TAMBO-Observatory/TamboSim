project_dir = (@__DIR__) * "/../../"
using Pkg
Pkg.activate(project_dir)
using Tambo
using JLD2
using Glob
using ArgParse
using TOML


include("column_depth_functions.jl")

interpolated_effs = load(ENV["TAMBOSIM_PATH"] * "/resources/detector_efficiencies/initial_IceTop_panel_interpolations.jld2")
global interpolated_eff_gamma = interpolated_effs["gamma_interp"]
global interpolated_eff_muon = interpolated_effs["muon_interp"]
global interpolated_eff_electron = interpolated_effs["electron_interp"]

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--simfile"
            help = "Main JLD2 simulation file"
            arg_type = String
            #required = true
            #default = "/n/holylfs05/LABS/arguelles_delgado_lab/Lab/common_software/source/corsika8/corsika-work/Oct16th2023_WhitePaper_300k.jld2"
        "--hitmapdir"
            help = "Directory with all the hitmaps inside"
            arg_type = String
            #default = "/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/will_misc/triggered_events/Jan7th2024_WhitePaper_300k_no_thin/"
            #required = true 
        "--simset_id"
            help = "Simulation set ID"
            arg_type = String
            #required = true
        "--outdir"
            help = "where to store the output"
            arg_type = String
            #default = "./"
            #required = true
        "--trigger_config"
            help = "Config file"
            arg_type = String
            default = nothing
        "--trigger_type"
            help = "Type of trigger to use"
            arg_type = String
        "--module_threshold"
            help = "Module threshold"
            arg_type = Int64
        "--event_threshold"
            help = "Event threshold"
            arg_type = Int64
    end
    return parse_args(s)
end

function load_config(file_path::String)
    if isfile(file_path)
        config_dict = TOML.parsefile(file_path)
        validate_config_file(config_dict)
        return config_dict
    else
        error("Config file not found at: $file_path")
    end
end

function setup_configuration(args)
    expected_arguments = ["simfile", "hitmapdir", "outdir", "trigger_config", "trigger_type", "module_threshold", "event_threshold"]

    config_params = Dict()

    # Check that trigger configuration is provided either via CLI or config file
    if all(isnothing, [args["trigger_config"], any(isnothing, [args["trigger_type"], args["module_threshold"], args["event_threshold"]])])
        error("Missing required arguments. Please define the trigger either via CLI or config file.")
    end

    # Check that trigger settings set by either CLI or config file, not both
    if !isnothing(args["trigger_config"]) && any(!isnothing, [args["trigger_type"], args["module_threshold"], args["event_threshold"]])
        error("Both CLI and config file interface used. Please use only one.")
    end

    # Load from config files if provided
    if !isnothing(args["trigger_config"])
        config_params = load_config(args["trigger_config"])
        for (k, v) in config_params
            if k ∉ expected_arguments
                error("Unexpected key in trigger_config file: $k")
            end
            args[k] = v
        end
    end
    return args
end

function validate_config_file(config::Dict{String, Any})
    # Check that only expected configuration parameters are present
    # so user doesn't think they're setting parameters they aren't
    expected_keys = Set(["trigger_type", "module_threshold", "event_threshold"])
    unexpected_keys = setdiff(Set(keys(config)), expected_keys)
    if !isempty(unexpected_keys)
        error("Unexpected keys found in config file: ", unexpected_keys)
    end
end

function get_injected_event_using_event_id(injected_events::Vector{Tambo.InjectionEvent}, event_id::Int64)
    for event in injected_events
        if event.event_id == event_id
            return event
        end
    end
    error("No injected event found with event_id: $event_id")
end

function main()
    # Parse config file and command line arguments
    args = parse_commandline()
    args = setup_configuration(args)

    sim_file = args["simfile"]
    hitmaps_path = args["hitmapdir"]
    simset_id = args["simset_id"]
    outdir = args["outdir"]
    trigger_type = args["trigger_type"]
    module_thresh = args["module_threshold"]
    event_thresh = args["event_threshold"]

    println("Configuration:")
    println("sim_file: $sim_file")
    println("hitmaps_path: $hitmaps_path")
    println("outdir: $outdir")
    println("trigger_type: $trigger_type")
    println()

    
    hitmaps = Dict{String, Any}()
    hitmaps = load(hitmaps_path * "/hitmaps_$(simset_id)_full.jld2")["hitmap"]

    triggered_event_ids = []
    for (key, value) in hitmaps
        if did_trigger(value, module_thresh, event_thresh, trigger_type)
            push!(triggered_event_ids, parse(Int, split(key, "/")[end]))
        end
    end

    sim_file = load(sim_file)
    triggered_events = [get_injected_event_using_event_id(sim_file["injected_events"], id) for id in triggered_event_ids]

    # Now apply the column depth requirement. This is actually a physics-level cut,
    # but given it's currently the only one, we'll do it here for now
    probability_threshold = 1.00
    required_depth = 4*units.km
    resolution = 0 # TODO: put in natural sim units
    column_depth_probabilities = [compute_column_depth_probability(sim_file, event, resolution, required_depth) for event in triggered_events]
    column_depth_mask = column_depth_probabilities .>= probability_threshold
    passed_events = triggered_events[column_depth_mask]

    jldopen("$(outdir)/triggered_events_$(simset_id).jld2", "w") do f
        f["triggered_events"] = passed_events
        f["trigger_config"] = Dict(
            "module_thresh" => module_thresh,
            "event_thresh" => event_thresh,
            "trigger_type" => trigger_type
        )
    end
end


if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
