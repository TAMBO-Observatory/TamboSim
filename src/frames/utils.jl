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
