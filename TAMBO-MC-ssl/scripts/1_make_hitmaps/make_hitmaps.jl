project_dir = (@__DIR__) * "/../../"
using Pkg
Pkg.activate(project_dir)

using Tambo
using JLD2
using StaticArrays
using ArgParse
using Glob
using LinearAlgebra
using Parquet2
using DataFrames 
using ProgressBars
using TOML
using Rotations

include("utils.jl")

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--basedir"
            help = "Directory with all the simulation directories inside"
            arg_type = String
            required = true
            #default = "/Users/pavelzhelnin/Documents/physics/TAMBO/resources/airshowers/GraphNet_00000_00001"
        "--injection_config"
            help = "Injection config file"
            arg_type = String
            required = true
        "--simfile"
            help = "Simulation file, if no simulation file produced you need to specify plane coord, vector and spline path"
            arg_type = String
            required = true 
            #default = "/Users/pavelzhelnin/Documents/physics/TAMBO/resources/example_sim_file.jld2"
        "--outfile"
            help = "where to store the output"
            arg_type = String
            required = true
        "--deltas"
            help = "Distance between modules on hexagonal array"
            arg_type = Float64
            required = false
        "--length"
            help = "Length of the full array"
            arg_type = Float64
            required = false
        "--nparallel"
            help = "Number of parallel jobs happening"
            arg_type = Int
            required = true
            #default=1
        "--njob"
            help = "Which parallel job"
            arg_type = Int
            required = true
            #default=1
        "--altmin"
            help = "Minimum altitude in m"
            arg_type = Float64
            required = false
        "--altmax"
            help = "Maximum altitude in m"
            arg_type = Float64
            required = false
        "--simset_id"
            help = "Simset ID"
            arg_type = String
            required = true
        "--size"
            help = "size of modules"
            arg_type = String 
        "--array_config"
            help = "Path to a TOML config file"
            arg_type = String
            default = nothing       
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
    expected_arguments = ["basedir", "array_config", "injection_config", "simfile", "outfile", "deltas", "length", "size", "nparallel", "njob", "altmin", "altmax", "simset_id", "config"]

    # First check that either config file of CL arguments are provided, not both
    if !isnothing(args["array_config"]) && any(!isnothing, [args["deltas"], args["length"], args["size"], args["altmin"], args["altmax"]])
        error("If providing a config file, cannot provide any of deltas, length, size, altmin, altmax")
    end

    # If using CLI, check that all required arguments are provided
    if isnothing(args["array_config"]) && any(isnothing, [args["deltas"], args["length"], args["size"], args["altmin"], args["altmax"]])
        error("If not providing a config file, must provide all of deltas, length, size, altmin, altmax")
    end
    
    config_params = Dict()

    # Load from config files if provided
    if !isnothing(args["array_config"])
        println(args)
        config_params = load_config(args["array_config"])
        for (k, v) in config_params
            if k ∉ expected_arguments
                error("Unexpected key in config file: $k")
            end
            args[k] = v
        end
    else
        for (k, v) in args
            if k ∉ expected_arguments
                error("Unexpected key in command line arguments: $k")
            end
            if k != "array_config"
                config_params[k] = v
            end
        end
    end

    if args["size"] ∉ ["normal", "small", "medium"]
        error("Invalid size: $(args["size"])")
    end
    
    @assert args["njob"] <= args["nparallel"]

    println("Configuration:")
    for (k, v) in args
        println("$k: $v")
    end
    return args
end

function validate_config_file(config::Dict{String, Any})
    # Check that only expected configuration parameters are present
    # so user doesn't think they're setting parameters they aren't

    expected_keys = Set(["length", "deltas", "altmin", "altmax", "size"])
    unexpected_keys = setdiff(Set(keys(config)), expected_keys)
    if !isempty(unexpected_keys)
        error("Unexpected keys found in config file: ", unexpected_keys)
    end
end

function add_hits!(d::Dict, og_df::DataFrame, modules)
    rmax = maximum([norm(m.extent) for m in modules])
    for m in modules
        df = copy(og_df)
       
        df.x .-= m.pos[1]
        df.y .-= m.pos[2]
        df.z .-= m.pos[3]

        filter!([:x,:y,:z] => (x,y,z) -> abs(x) <= rmax && abs(y) <= rmax && abs(z) <=rmax, df)
        
        if isempty(df)
            continue 
        end

        for particle in eachrow(df)
            particle[[:x,:y,:z]] = m.rot * Vector(particle[[:x,:y,:z]])
        end 

        filter!([:x,:y,:z] => (x,y,z) -> all(abs.([x,y,z]) .< m.extent / 2), df)

        if isempty(df)
            continue 
        end

        if !(m.idx in keys(d))
            d[m.idx] = Tambo.CorsikaEvent[]
        end
        for particle in eachrow(df)
            position = SVector{3}([particle.x,particle.y,particle.z])
            push!(
                d[m.idx],
                Tambo.CorsikaEvent(
                    particle.pdg,
                    particle.kinetic_energy * units.GeV,
                    position,
                    particle.time * units.second,
                    particle.weight
                )
            )
        end 
    end 
end 


function make_hitmap(
    simset_id,
    event_number,
    modules,
    basedir,
    xyzcorsika;
    xmax=nothing,
    xmin=nothing,
    ymin=nothing,
    ymax=nothing
)
   
    if isnothing(xmin)
        xmin = minimum([m.pos.x for m in modules])
    end
    if isnothing(xmax)
        xmax = maximum([m.pos.x for m in modules])
    end
    if isnothing(ymin)
        ymin = minimum([m.pos.y for m in modules])
    end
    if isnothing(ymax)
        ymax = maximum([m.pos.y for m in modules])
    end

    d = Dict{Int, Vector{Tambo.CorsikaEvent}}()
    files = find_extant_files(simset_id, event_number, basedir)
    for file in files
        #CORSIKA8 sometimes doesn't finish b/c job times out 
        df = DataFrame()
        try
            df = DataFrame(Parquet2.Dataset(file))
        catch
            println("This file can't be read (maybe job timed out): $file")
            continue
        end

        df = loadcorsika(select(df,Not("shower","nx","ny","nz")),xyzcorsika)
        df = filter(
            e -> xmin < e.x && e.x < xmax && ymin < e.y && e.y < ymax,
            df
        )
        add_hits!(d, df, modules)

        #if necessary to avoid runaway RAM usage
        #GC.gc()
        #close(pqf)
    end 
    
    return d
end

function main()
    # Parse config file and command line arguments
    # Providing the configuration via a config file vs command line arguments
    # is enforced to be mutually exclusive
    args = parse_commandline()
    args = setup_configuration(args)
    

    config = nothing
    try 
        # TODO: seems like this should load from the injection file rather than the config in case config is changed
        config = Simulation(get_tambosim_path() * "/resources/configuration_examples/$(args["injection_config"]).toml")
    catch
        error("Config file not found. Currently only supports running config files in the resources/configuration_examples directory")
    end
    geo = Geometry(config.config["geometry"])
    #tambo_coord_degrees = Tambo.Coord((deg2rad.(config.config["geometry"]["tambo_coordinates"]))...)
    
    zcorsika = config.config["geometry"]["plane_orientation"]
    display("original zcorsika = $zcorsika")
    #possibly a hack but (this is because everything has to be rotated to corsika x_hat = N;y_hat=W)
    #previous convention was x_hat = E; y_hat =N 
    #xyzcorsika rotates into 3d from 2d but to where x_hat is N!!!!
    #need extra rotation to get it back to TAMBO coordinate system 
    
    zcorsika = RotZ(-π/2) * zcorsika 
    xcorsika = SVector{3}([0, -zcorsika[3]/sqrt(zcorsika[2]^2+zcorsika[3]^2), zcorsika[2]/sqrt(zcorsika[2]^2+zcorsika[3]^2)])
    ycorsika = cross(zcorsika, xcorsika)
    xyzcorsika = inv([
        xcorsika.x xcorsika.y xcorsika.z;
        ycorsika.x ycorsika.y ycorsika.z;
        zcorsika.x zcorsika.y zcorsika.z;
    ])

    display("xyzcorsika = $xyzcorsika")

    if args["size"] == "normal"
        size = SVector{3}([1.875, 0.8, 0.03])units.m
    elseif args["size"] == "small"
        size = SVector{3}([2,2, 0.03])units.m
    elseif args["size"] == "medium"
        size = SVector{3}([4,4,0.03])units.m
    end 

    modules = make_detector_array(
        args["length"]units.m,
        args["deltas"]units.m,
        args["altmin"]units.m,
        args["altmax"]units.m,
        geo,
        size
    )

    outfile = args["outfile"]

    event_numbers = get_event_numbers(args["basedir"], args["simset_id"])[args["njob"]:args["nparallel"]:end]
    hitmap = Dict()
    println("Processing events: ", event_numbers)
    for event_number in ProgressBar(event_numbers)
        hitmap["$(event_number)"] = make_hitmap(args["simset_id"], event_number, modules, args["basedir"], xyzcorsika)
    end

    jldopen(outfile, "w") do jldf
        jldf["hitmap"] = hitmap
        jldf["array_config"] = Dict(
            "length" => args["length"] * units.m,
            "deltas" => args["deltas"] * units.m,
            "detector_size" => args["size"],
            "altmin" => args["altmin"] * units.m,
            "altmax" => args["altmax"] * units.m
        )
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
