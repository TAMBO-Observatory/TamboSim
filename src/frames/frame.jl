const STREAM_HIERARCHY = ('G', 'C', 'Q', 'P')

"""
    Frame

A hierarchical, dictionary-like container for simulation data.

A `Frame` holds data in a dictionary and carries references to parent frames
from higher-level streams. When a key is accessed, the current frame's data is
checked first; if the key is absent, parent frames are searched in stream
hierarchy order (G → C → Q → P).

# Fields
- `stream::Char`: Stream type ('G' geometry, 'C' config, 'Q' event, 'P' physics).
- `data::Dict{String, Any}`: Data stored in this frame.
- `parents::Dict{Char, Frame}`: Parent frames indexed by their stream type.

# Constructors
- `Frame(stream)`: Empty frame with the given stream type.
- `Frame(stream, data)`: Frame with pre-populated data.
- `Frame(stream, data, parents)`: Frame with data and explicit parent map.
"""
mutable struct Frame
    stream::Char
    data::Dict{String, Any}
    parents::Dict{Char, Frame}
    Frame(stream::Char) = Frame(stream, Dict{String,Any}(), Dict{Char,Frame}())
    Frame(stream::Char, data::Dict) = Frame(stream, data, Dict{Char,Frame}())
    function Frame(stream::Char, data::Dict, parents::Dict{Char,Frame})
        if stream == 'Q'
            haskey(parents, 'G') || error("Q frame requires a G parent")
            haskey(parents, 'C') || error("Q frame requires a C parent")
        end
        new(stream, data, parents)
    end
end

function Base.getproperty(f::Frame, sym::Symbol)
    if sym === :gframe
        haskey(f.parents, 'G') || error("Frame (stream='$(f.stream)') has no G parent")
        return f.parents['G']
    elseif sym === :cframe
        haskey(f.parents, 'C') || error("Frame (stream='$(f.stream)') has no C parent")
        return f.parents['C']
    end
    return getfield(f, sym)
end

function Base.getindex(frame::Frame, key::String)
    haskey(frame.data, key) && return frame.data[key]
    for s in STREAM_HIERARCHY
        if haskey(frame.parents, s)
            parent = frame.parents[s]
            haskey(parent.data, key) && return parent.data[key]
        end
    end
    throw(KeyError(key))
end

function Base.setindex!(frame::Frame, value, key::String)
    frame.data[key] = value
end

function Base.haskey(frame::Frame, key::String)
    haskey(frame.data, key) && return true
    for s in STREAM_HIERARCHY
        if haskey(frame.parents, s)
            haskey(frame.parents[s].data, key) && return true
        end
    end
    return false
end

function Base.keys(frame::Frame)
    ks = Set(keys(frame.data))
    for s in STREAM_HIERARCHY
        haskey(frame.parents, s) && union!(ks, keys(frame.parents[s].data))
    end
    return ks
end

function Base.getkey(frame::Frame, k::String, default)
    haskey(frame, k) ? frame[k] : default
end
