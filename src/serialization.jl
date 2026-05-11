ArrowTypes.arrowname(::Type{ProposalResult}) = :ProposalResult
ArrowTypes.JuliaType(::Val{:ProposalResult}) = ProposalResult

ArrowTypes.arrowname(::Type{Particle}) = :Particle
ArrowTypes.JuliaType(::Val{:Particle}) = Particle

ArrowTypes.arrowname(::Type{Direction}) = :Direction
ArrowTypes.JuliaType(::Val{:Direction}) = Direction

ArrowTypes.arrowname(::Type{Loss}) = :Loss
ArrowTypes.JuliaType(::Val{:Loss}) = Loss

"""
    rec_flatten_dict(d, prefix_delim=".") -> Dict

Recursively flattens a dictionary.

Nested dictionaries are expanded, with keys concatenated using `prefix_delim`.
Vectors and tuples are also expanded, with their index appended to the key.
All final values are converted to strings.

# Arguments
- `d`: The dictionary to flatten.
- `prefix_delim`: The delimiter to use for concatenating nested keys.

# Returns
- A new, flattened dictionary.
"""
function rec_flatten_dict(d, prefix_delim = ".")
    new_d = empty(d)
    for (key, value) in pairs(d)
        if isa(value, Dict)
             flattened_value = rec_flatten_dict(value, prefix_delim)
             for (ikey, ivalue) in pairs(flattened_value)
                 new_d["$key.$ikey"] = ivalue
             end
        elseif isa(value, AbstractVector) || isa(value, Tuple)
            for (idx, v) in enumerate(value)
                new_d["$(key).$(idx)"] = string(v)
            end
        else
            new_d[key] = string(value)
        end
    end
    return new_d
end