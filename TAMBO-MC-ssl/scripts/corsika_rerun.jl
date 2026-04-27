using Pkg
Pkg.activate("../Tambo")
using Tambo 
using JLD2
using Glob
using ProgressBars

#function to check if corsika event information matches whats found in sim file 
function read_corsika(simdir,filepath)
    open(filepath, "r") do file
        for line in eachline(file)
            println(line)
            event_number = parse(Int64,split(split(line,"/")[end-2],"_")[2])
            decay_number = parse(Int64,split(split(line,"/")[end-2],"_")[3])
            
            sim_file_name = split(line,"/")[13]
            sim_file_path = joinpath(simdir,sim_file_name*".jld2")

            simfile = jldopen(sim_file_path)
            event = simfile["proposal_events"]["decay_products"][event_number][decay_number]
            break
        end
    end
end 

function corsika_loader(s)
   
    corsika_config = Tambo.CORSIKAConfig(s)
    geo = Tambo.Geometry(
        s.geo_spline_path,
        s.tambo_coordinates
    )
    corsika_propagator = Tambo.CORSIKAPropagator(corsika_config,geo)

    return corsika_propagator
end 

function corsika_rerun(simdir,showerdir,filepath)
    #println(joinpath(showerdir,"*/"))
    files = glob("*jld2",simdir)

    open(filepath, "r") do file
        for (idx,line) in tqdm(enumerate(eachline(file)))

            rm_path = join(split(line, "/")[1:14], "/")
            
            #THIS DELETES THE SHOWER DIR BE CAREFUL!!!!
            #check that the rm_path points to where you want to point
            #CORSIKA can't overwrite the empty parquet file 
            #comment this out when you know you have the right path
            println("This directory will be deleted: $(rm_path)")
            break 

            #uncomment this when ready 
            # try
            #     rm(rm_path, recursive=true)
            # catch 
            #     continue 
            # end 

            event_number = parse(Int64,split(split(line,"/")[end-2],"_")[2])
            decay_number = parse(Int64,split(split(line,"/")[end-2],"_")[3])
            
            sim_file_name = split(line,"/")[13]
            sim_file_path = joinpath(simdir,sim_file_name*".jld2")

            simfile = SimulationConfig(sim_file_path)

            #comment this out if the sim files you produced point to your personal sbatch script 
            simfile.corsika_sbatch_path="/n/holylfs05/LABS/arguelles_delgado_lab/Everyone/pzhelnin/TAMBO-MC/scripts/corsika_parallel.sbatch"
            cp = corsika_loader(simfile)
            Tambo.corsika_parallel(simfile["proposal_events"],cp,[[event_number,decay_number]])
          
        end
    end
end 

function main() 
    #path to failed showers txt file 
    filepath="./00000_paths_to_failed_showers.txt"

    #top level where showers live 
    showerdir="/n/holylfs05/LABS/arguelles_delgado_lab/Lab/common_software/source/corsika8/corsika-work/Larger_Valley/shower"
    
    #where sim files live 
    simdir="/n/holylfs05/LABS/arguelles_delgado_lab/Lab/common_software/source/corsika8/corsika-work/Larger_Valley/sim_files"
    corsika_rerun(simdir,showerdir,filepath)
    #read_corsika(simdir,filepath)
end 

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
