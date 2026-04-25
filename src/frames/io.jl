"""
    save_frames(path::String, frames::Vector{Frame}; streams=('C', 'Q'))

Writes frames whose stream type is in `streams` to a JLD2 file. Defaults to
C and Q frames so that simulation config rides along with the event frames.

Parent references are not stored; they are reconstructed from stream order on
load. G frames are written as-is, including earth geometry keys, so a saved G
frame is fully self-contained and does not require the original h5 file on
reload. To save a standalone geometry file, use `streams=('G',)`.
"""
function save_frames(path::String, frames::Vector{Frame}; streams::Tuple{Vararg{Char}}=('C', 'Q'))
    to_save = filter(f -> f.stream in streams, frames)
    jldopen(path, "w") do file
        file["nframes"] = length(to_save)
        for (i, frame) in enumerate(to_save)
            file["frames/$i/stream"] = string(frame.stream)
            file["frames/$i/data"] = frame.data
        end
    end
end

function _reconstruct_frames(raw::Vector{Tuple{Char,Dict{String,Any}}})
    parent_cache = Dict{Char,Frame}()
    frames = Frame[]
    for (stream, data) in raw
        # A new frame invalidates all lower-hierarchy context: e.g. a new G
        # frame means any cached C or Q frames belong to the previous run.
        found = false
        for s in STREAM_HIERARCHY
            found && delete!(parent_cache, s)
            s == stream && (found = true)
        end
        parents = Dict{Char,Frame}()
        for s in STREAM_HIERARCHY
            s == stream && break
            haskey(parent_cache, s) && (parents[s] = parent_cache[s])
        end
        frame = Frame(stream, data, parents)
        if stream == 'G' && haskey(data, "earth_path") && !haskey(data, "bvh")
            load_earth!(frame)
        end
        parent_cache[stream] = frame
        push!(frames, frame)
    end
    return frames
end

"""
    load_frames(paths::Vector{String}) -> Vector{Frame}

Loads frames from one or more JLD2 files and concatenates them into a single
vector. Parent references are reconstructed from stream order, with the parent
cache (G/C frames) carrying over across file boundaries.

    load_frames(path::String) -> Vector{Frame}

Loads frames from a single JLD2 file.
"""
function load_frames(paths::Vector{String})
    raw = Tuple{Char,Dict{String,Any}}[]
    for path in paths
        jldopen(path, "r") do file
            n = file["nframes"]
            for i in 1:n
                stream = only(file["frames/$i/stream"])
                data = file["frames/$i/data"]
                push!(raw, (stream, data))
            end
        end
    end
    return _reconstruct_frames(raw)
end

load_frames(path::String) = load_frames([path])
