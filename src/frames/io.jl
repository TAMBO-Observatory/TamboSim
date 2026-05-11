"""
    save_frames(path::String, frames::AbstractVector{Frame}; streams=('M', 'Q'))

Writes frames whose stream type is in `streams` to a JLD2 file. Defaults to
M and Q frames so that simulation meta/config rides along with the event frames.
Accepts either a `Vector{Frame}` or a `TamboFrames`.

Parent references are not stored; they are reconstructed from stream order on
load. G frames are written as-is, including earth geometry keys, so a saved G
frame is fully self-contained and does not require the original h5 file on
reload. To save a standalone geometry file, use `streams=('G',)`.
"""
function save_frames(path::String, frames::AbstractVector{Frame}; streams::Tuple{Vararg{Char}}=('M', 'Q'))
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
        if stream == 'G'
            _ensure_geometry_hash!(frame)
        end
        parent_cache[stream] = frame
        push!(frames, frame)
    end
    return frames
end

"""
    _validate_geometry_hash!(tf::TamboFrames; prefixes=("injection",))

For every M frame that snapshotted a `geometry_hash` under one of `prefixes`
(set at injection time by `_setup_injection`), verify it matches the live
`geometry_hash` of its parent G frame. Mismatches mean the user paired a
saved injection campaign with the wrong geometry — `oneweights` would
silently produce wrong values without this guard.

Skips M frames that have no G parent (M-only files loaded standalone), no
config under any of `prefixes`, or no snapshotted hash within that config
(campaigns predating the snapshot).
"""
function _validate_geometry_hash!(tf::TamboFrames; prefixes=("injection",))
    for (m_idx, m) in enumerate(tf.m_frames)
        haskey(m.parents, 'G') || continue
        g = m.parents['G']
        haskey(g.data, "geometry_hash") || continue
        for prefix in prefixes
            haskey(m.data, prefix) || continue
            cfg = m.data[prefix]
            cfg isa AbstractDict && haskey(cfg, "geometry_hash") || continue
            snap = UInt(cfg["geometry_hash"])
            live = UInt(g["geometry_hash"])
            snap == live || error(
                "_validate_geometry_hash!: M frame #$m_idx (prefix=\"$prefix\") " *
                "was injected against geometry_hash=$snap, but its loaded G frame " *
                "has geometry_hash=$live. Loading the wrong G with this M+Q file " *
                "would silently produce incorrect oneweights — refusing to proceed."
            )
        end
    end
end

"""
    load_frames(paths::Vector{String}) -> TamboFrames

Loads frames from one or more JLD2 files and concatenates them into a single
`TamboFrames`. Parent references are reconstructed from stream order, with
the parent cache (G/C frames) carrying over across file boundaries.

    load_frames(path::String) -> TamboFrames

Loads frames from a single JLD2 file.
"""
function load_frames(paths::Vector{String}; prefixes=("injection",))
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
    tf = TamboFrames(_reconstruct_frames(raw))
    _validate_geometry_hash!(tf; prefixes)
    return tf
end

load_frames(path::String; prefixes=("injection",)) = load_frames([path]; prefixes)
