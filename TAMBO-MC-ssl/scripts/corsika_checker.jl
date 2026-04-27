using Pkg 
Pkg.activate("../Tambo")
using Parquet2 
using Glob 

function check_corsika(savepath::String,dirpath::String)
    files = glob("*/*/*final/*.parquet",dirpath)
    empty_files = [] 
    println(length(files))
    for file in files 
        try
            pqf = Parquet2.Dataset(file)
        catch 
            println(file)
            push!(empty_files,file)
            continue 
        end

        pqf = Parquet2.Dataset(file)
        if Parquet2.nvalues(pqf[1][1]) > 0 
            continue 
        else
            println(file)
            push!(empty_files,file) 
        end
    end

    if length(empty_files) > 0
        open("$(savepath)/paths_to_failed_showers.txt", "w") do file
            for line in empty_files
                println(file, line) 
            end
        end
    else
        println(empty_files)
        println("no errors")
    end 
end

#I wanted to find large events at one point 
function large_events(savepath::String,dirpath::String)
    files = glob("*/*/*final/*.parquet",dirpath)
    println(length(files))
    big_files =[]
    for file in files 
        try
            pqf = Parquet2.Dataset(file)
        catch 
            continue 
        end

        pqf = Parquet2.Dataset(file)
        if Parquet2.nvalues(pqf[1][1]) < 1e6
            continue 
        else
            println(file)
            push!(big_files,file) 
        end
    end

    if length(big_files) > 0
        open("$(savepath)/big_showers.txt", "w") do file
            for line in big_files
                println(file, line) 
            end
        end
    else
        println(big_files)
        println("no errors")
    end 
end

function main()
    #the location where you want to save the paths to failed showers
    savepath = "/n/holylfs05/LABS/arguelles_delgado_lab/Lab/common_software/source/TAMBO-MC/scripts/failed_showers"
    
    #the top level directory where all showers live 
    #e.g. dirpath/larger_valley_00000_000XX/shower_*_*/*final/particles.parquet is the path for these showers 
    dirpath = "/n/holylfs05/LABS/arguelles_delgado_lab/Lab/common_software/source/corsika8/corsika-work/Larger_Valley/shower"

    if !isdir(savepath)
        mkdir(savepath)
        println("directory created: $savepath")
    end 

    check_corsika(savepath,dirpath)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end