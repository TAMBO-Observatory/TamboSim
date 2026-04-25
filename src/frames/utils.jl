"""
    get_frame(frames::Vector{Frame}, stream::Char) -> Frame

Returns the last frame in `frames` with the given stream type. Errors if none
is found.
"""
function get_frame(frames::Vector{Frame}, stream::Char)
    idx = findlast(f -> f.stream == stream, frames)
    isnothing(idx) && error("No '$stream' frame found in frame vector")
    return frames[idx]
end

"""
    cut_frames!(frames::Vector{Frame}, fxn::Function)

Removes Q-stream frames for which `fxn` returns `false`. Frames with other
stream types (G, C, P) are always preserved.
"""
function cut_frames!(frames::Vector{Frame}, fxn::Function)
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
