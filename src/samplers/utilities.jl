function find_trim_idxs(e_slice)::Tuple{Int, Int}
    d = diff(log.(10, e_slice))
    l, r,lidx, ridx = 1, length(d), 0, length(e_slice)
    while l < r
        if abs(d[l]) > 1
            lidx = l
        end
        if abs(d[r]) > 1
            ridx = r
        end
        l+=1
        r-=1
    end
    lidx += 1
    return lidx, ridx
end
