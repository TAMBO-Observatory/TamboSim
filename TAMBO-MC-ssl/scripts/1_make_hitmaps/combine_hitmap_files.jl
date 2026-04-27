project_dir = (@__DIR__) * "/../../"
using Pkg
Pkg.activate(project_dir)
using Tambo
using JLD2
using Glob
using ArgParse

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--hitmap_directory"
            help = "Directory containing hitmap files"
            arg_type = String
            required = true
        "--simset_id"
            help = "Simulation set ID"
            arg_type = String
            required = true
    end
    return parse_args(s)
end

function get_filename_list(directory::String, simset_id::String)
    if !isdir(directory)
        error("Directory does not exist: $directory")
    end

    filelist = glob("hitmaps_$(simset_id)_*_*.jld2", directory)

    if isempty(filelist)
        error("No files with this simset ID found in directory: $directory")
    end

    # Check only one division of files exists and that we have all files expected
    num_expected_files = parse(Int64, split(split(filelist[1], ".")[end-1], "_")[end])
    for i in eachindex(filelist[begin+1:end])
        if parse(Int64, split(split(filelist[i], ".")[end-1], "_")[end]) != num_expected_files
            error("Unexpected file: $directory/hitmaps_$(simset_id)_$num_expected_files.jld2\nMultiple hitmap file divisions in same directory is not supported.")
        end
    end

    if length(filelist) != num_expected_files
        error("Missing files in directory: $directory\nExpected $num_expected_files files, found $(length(filelist))")
    end

    # Check that array config is same across all files
    jldopen(filelist[begin]) do ref_file
        for file in filelist[begin+1:end]
            jldopen(file) do f
                if f["array_config"] != ref_file["array_config"]
                    error("Array configuration does not match between files: $filelist[begin] and $file")
                end
            end
        end
    end
    return filelist
end

function main()
    args = parse_commandline()
    hitmap_directory = args["hitmap_directory"]
    simset_id = args["simset_id"]

    # Get list of files to merge and perform some checks
    filename_list = get_filename_list(hitmap_directory, simset_id)

    # Combine hitmaps into one file and save
    array_config = Dict()
    full_hitmap = Dict()

    jldopen(filename_list[begin]) do ref_file
        array_config = ref_file["array_config"]
    end

    for file in filename_list
        jldopen(file) do f
            merge!(full_hitmap, f["hitmap"]) do key, val1, val2
                error("Key conflict when merging hitmaps: $key. This means this event is present in multiple files!")
            end
        end
    end

    outfile = hitmap_directory * "/hitmaps_$(simset_id)_full.jld2"
    jldopen(outfile, "w") do file
        file["array_config"] = array_config
        file["hitmap"] = full_hitmap
    end

    println("Hit maps combined and saved to: $outfile. You may now delete the individual files.")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
