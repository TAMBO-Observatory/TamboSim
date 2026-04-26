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
    cut_frames!(frames::AbstractVector{Frame}, fxn::Function)

Removes Q-stream frames for which `fxn` returns `false`. Frames with other
stream types (G, C, P) are always preserved. Accepts either a `Vector{Frame}`
or a `TamboFrames`.
"""
function cut_frames!(frames::AbstractVector{Frame}, fxn::Function)
    idx = 1
    while idx <= length(frames)
        frame = frames[idx]
        if frame.stream == 'Q' && !fxn(frame)
            deleteat!(frames, idx)
            continue
        end
        idx += 1
    end
end
