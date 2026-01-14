"""
    cut_frames!(frames::Vector{Frame}, fxn::Function)

Filters a vector of `Frame` objects in-place.

This function iterates through a vector of `frames` and removes any frame
for which the predicate function `fxn` returns `false`. The modification
is done in-place.

# Arguments
- `frames::Vector{Frame}`: The vector of frames to be filtered.
- `fxn::Function`: A function that takes a `Frame` and returns `true` if it should be kept, `false` otherwise.
"""
function cut_frames!(frames::Vector{Frame}, fxn::Function)
    idx = 1
    while idx <= length(frames)
        frame = frames[idx]
        if ~fxn(frame)
            deleteat!(frames, idx)
            continue
        end
        idx += 1
    end
end
