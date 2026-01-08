"""
    Frame

A hierarchical, dictionary-like container for simulation data.

A `Frame` holds data in a dictionary. It can have a `parent` frame, creating a
chain. When a key is accessed, if it's not in the current frame's data, the
search continues up to the parent. This allows for an efficient way to layer
data from different processing stages.

# Fields
- `data::Dict{String, Any}`: The dictionary holding the data for this frame.
- `parent::Union{Nothing, Frame}`: The parent frame, or `nothing` if it's a root frame.
- `type::Char`: A character indicating the type of the frame (e.g., 'T' for top-level).

# Constructors
- `Frame()`: Creates an empty root frame.
- `Frame(data::Dict)`: Creates a root frame with the given data.
- `Frame(data::Dict, type::Char)`: Creates a root frame with the given data and type.
- `Frame(data::Dict, parent::Frame, type::Char)`: Creates a frame with the given data, parent, and type.
"""
struct Frame
    data::Dict{String, Any}
    parent::Union{Nothing, Frame}
    type::Char
    Frame() = new(Dict{String, Any}())
    Frame(data::Dict) = new(data, nothing, 'T')
    Frame(data::Dict, type::Char) = new(data, nothing, type)
    Frame(data::Dict, parent::Frame, type::Char) = new(data, parent, type)
end

"""
    Base.getindex(frame::Frame, key::String)

Accesses a value in the frame hierarchy.

If the `key` is present in the current `frame`'s data, its value is returned.
Otherwise, the search continues recursively up to the `parent` frame.
Throws a `KeyError` if the key is not found anywhere in the hierarchy.
"""
function Base.getindex(frame::Frame, key::String)
    if haskey(frame.data, key)
        return frame.data[key]
    elseif isnothing(frame.parent)
        throw(KeyError(key))
    else
        return frame.parent[key]
    end
end

"""
    Base.setindex!(frame::Frame, value, key::String)

Sets a value in the frame's data.

The value is always set in the current frame's own `data` dictionary. It does not
affect any parent frames.
"""
function Base.setindex!(frame::Frame, value, key::String)
    frame.data[key] = value
end

"""
    Base.haskey(frame::Frame, key::String) -> Bool

Checks if a key exists in the frame hierarchy.

Recursively checks for the presence of `key` in the current frame's data and
in all its parent frames.

# Returns
- `true` if the key is found, `false` otherwise.
"""
function Base.haskey(frame::Frame, key::String)
    if haskey(frame.data, key)
        return true
    elseif isnothing(frame.parent)
        return false
    else
        return haskey(frame.parent, key)
    end
end

"""
    Base.keys(frame::Frame)

Returns all unique keys in the frame hierarchy.

Collects all keys from the current frame and all its parent frames and returns
their union.
"""
function Base.keys(frame::Frame)
    if isnothing(frame.parent)
        return keys(frame.data)
    else
        return union(keys(frame.data), keys(frame.parent))
    end
end

"""
    Base.getkey(frame::Frame, k::String, default)

Gets a key from the frame hierarchy with a default value.

If the key `k` is found in the frame or its parents, its value is returned.
Otherwise, the `default` value is returned.
"""
function Base.getkey(frame::Frame, k::String, default)
    if haskey(frame, k)
        return frame[k]
    else
        return default
    end
end
