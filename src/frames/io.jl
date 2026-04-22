const TRANSIENT_EARTH_KEYS = ("prem", "topography", "bvh", "detector_region", "cs")

"""
    save_frames(path::String, frames::Vector{Frame}; streams=('Q',))

Writes frames whose stream type is in `streams` to a JLD2 file. Defaults to
Q frames only, matching the recommended GC-split workflow where geometry and
config are saved once to a separate file. Use `streams=('G','C','Q')` for a
self-contained file.

Parent references are not stored; they are reconstructed from stream order on
load. Transient earth geometry keys (prem, topography, bvh, detector_region, cs)
are stripped before write and rebuilt via `load_earth!` on reload.
"""
function save_frames(path::String, frames::Vector{Frame}; streams::Tuple{Vararg{Char}}=('Q',))
    to_save = filter(f -> f.stream in streams, frames)
    jldopen(path, "w") do file
        file["nframes"] = length(to_save)
        for (i, frame) in enumerate(to_save)
            file["frames/$i/stream"] = string(frame.stream)
            data = Dict{String,Any}(k => v for (k, v) in frame.data if k ∉ TRANSIENT_EARTH_KEYS)
            file["frames/$i/data"] = data
        end
    end
end

function _reconstruct_frames(raw::Vector{Tuple{Char,Dict{String,Any}}})
    parent_cache = Dict{Char,Frame}()
    frames = Frame[]
    for (stream, data) in raw
        frame = Frame(stream, data)
        for s in STREAM_HIERARCHY
            s == stream && break
            haskey(parent_cache, s) && (frame.parents[s] = parent_cache[s])
        end
        if stream == 'G' && haskey(data, "earth_path")
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
