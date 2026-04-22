"""
    _check_parent_conflicts(frame::Frame)

Warns if any key is defined in more than one parent frame. The first parent
in stream hierarchy order wins silently; this function makes that visible.
"""
function _check_parent_conflicts(frame::Frame)
    seen = Dict{String,Char}()
    for s in STREAM_HIERARCHY
        haskey(frame.parents, s) || continue
        for k in keys(frame.parents[s].data)
            if haskey(seen, k)
                @warn "Key \"$k\" defined in both '$(seen[k])' and '$s' parent frames; '$(seen[k])' takes precedence"
            else
                seen[k] = s
            end
        end
    end
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
