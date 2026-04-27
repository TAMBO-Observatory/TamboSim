using Glob

using FileWatching: watch_file
using Base.Filesystem

function write_to_shared_file(sharedfilename, key, contenttowrite)
    lockacquired = false
    lockfilename = sharedfilename * ".lock"
    #lockfilename = lockfile_location * basename(sharedfilename) * ".lock"
    local lockfilehandle
    while !lockacquired
        while isfile(lockfilename)
            # watch_file will notify if the file status changes, waiting until then
            # here we want to wait for the file to get deleted
            watch_file(lockfilename)
        end
        try
            # try to acquire the lock by creating lock file with JL_O_EXCL (exclusive)
            lockfilehandle = Filesystem.open(lockfilename, JL_O_CREAT | JL_O_EXCL, 0o600)
            lockacquired = true
        catch err
            # in case the file was created between our `isfile` check above and the
            # `Filesystem.open` call, we'll get an IOError with error code `UV_EEXIST`.
            # In that case, we loop and try again.
            if err isa IOError && err.code == Base.UV_EEXIST
                continue
            else
                rethrow()
            end
        end
    end
    # now that the lock is acquired, we can safely write to
    # the actual shared file we want to write to
    jldopen(sharedfilename, "r+") do jldf
    #open(sharedfilename, append = true) do sharedfile
        # write to the sharedfile here just as usual
        jldf[key] = contenttowrite
    end

    # free up the lock so that the other process can acquire it if it needs
    close(lockfilehandle)
    Filesystem.unlink(lockfilename)
end

function get_event_numbers(basedir::String, simset_id::String)
    sims = glob("showers/$(simset_id)/shower_*_?", basedir)
    event_numbers = []
    for sim in sims
        event_number = parse(Int, split(sim, "_")[end-1])
        if event_number in event_numbers
            continue
        end
        push!(event_numbers, event_number)
    end
    return sort(event_numbers)
end

function find_extant_files(simset_id::String, event_number::Int, basedir::String) Vector{String}
    files = glob("showers/$(simset_id)/shower_$(event_number)_?/*/particles.parquet", basedir)
    if isempty(files) 
        println("No files matched the pattern. The array is empty.")
    end 
    return files
end

function loadcorsika(df,xyzcorsika)
    ids = df.pdg
    es = df.kinetic_energy .* units.GeV
    pos = (Matrix(df[:,["x","y","z"]]) * xyzcorsika') * RotZ(-π/2)
    #pos = Matrix(df[:,["x","y","z"]]) * xyzcorsika'
    df.x = pos[:,1] .* units.m # x coord
    df.y = pos[:,2] .* units.m # y coord
    df.z = pos[:,3] .* units.m # z coord
    ts = df.time .* units.second # time
    ws = df.weight
    return df
end 
