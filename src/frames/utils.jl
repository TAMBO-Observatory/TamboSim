"""
    _get_last_frame(frames::AbstractVector{Frame}, stream::Char) -> Frame

Returns the last frame in `frames` with the given stream type. Internal
bootstrap utility — prefer navigating via parent references (e.g. `qframe.gframe`)
wherever a parent chain already exists. Accepts either a `Vector{Frame}` or a
`TamboFrames`.
"""
function _get_last_frame(frames::AbstractVector{Frame}, stream::Char; required::Bool=true)
    idx = findlast(f -> f.stream == stream, frames)
    if isnothing(idx)
        required && error("No '$stream' frame found in frame vector")
        return nothing
    end
    return frames[idx]
end

"""
    cut_frames!(frames::TamboFrames, fxn::Function)

Removes Q-stream frames for which `fxn` returns `false`, plus any descendants
of those Q frames (typically P). Frames of other stream types (G, C, D, M) are
left in place — `fxn` is only consulted for Q frames.

Cascade is delegated to `deleteat!(tf, inds; remove_children=true)`, which
walks the parent map to find every frame whose ancestry references a deleted Q.
"""
function cut_frames!(frames::TamboFrames, fxn::Function)
    indices = Int[]
    for (i, f) in enumerate(frames)
        if f.stream == 'Q' && !fxn(f)
            push!(indices, i)
        end
    end
    deleteat!(frames, indices; remove_children=true)
    return frames
end
