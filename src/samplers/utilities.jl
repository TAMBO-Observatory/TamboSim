"""
    find_trim_idxs(e_slice)::Tuple{Int, Int}

Identifies indices to "trim" a slice of data, typically used for interpolation.

This function iterates inwards from both ends of the `e_slice` and finds the indices
where the absolute difference of the base-10 logarithm of consecutive elements
exceeds 1. This is often used to identify stable regions in data for spline fitting.

# Arguments
- `e_slice`: A slice or vector of numerical data.

# Returns
- `Tuple{Int, Int}`: A tuple `(lidx, ridx)` representing the left and right trim indices.
"""
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
