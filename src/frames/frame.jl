const STREAM_HIERARCHY = ('G', 'C', 'D', 'M', 'Q', 'R')

"""
    Frame

A hierarchical, dictionary-like container for simulation data.

A `Frame` holds data in a dictionary and carries references to parent frames
from higher-level streams. When a key is accessed, the current frame's data is
checked first; if the key is absent, parent frames are searched in stream
hierarchy order (G → C → D → M → Q → R).

Q frames require an M parent (simulation meta/config always travels with events)
but not G, C, or D parents — analysis workflows that do not need earth/detector
geometry can load M+Q frames without a GCD bundle. Accessing `.g_frame`,
`.c_frame`, or `.d_frame` on a Q frame without the corresponding parent raises an
error at that point.

# Fields
- `stream::Char`: Stream type ('G' geometry, 'C' calibration, 'D' detector, 'M' meta/config, 'Q' event, 'R' reconstructed).
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
            haskey(parents, 'M') || error("Q frame requires an M parent")
        end
        new(stream, data, parents)
    end
end

"""
    f.g_frame, f.c_frame, f.d_frame, f.m_frame

Convenience property accessors that look up the named parent frame by stream
letter (`G`, `C`, `D`, `M`) and return it, erroring descriptively if the parent
is absent. Accessing any other symbol delegates to `getfield`.
"""
function Base.getproperty(f::Frame, sym::Symbol)
    if sym === :g_frame
        haskey(f.parents, 'G') || error("Frame (stream='$(f.stream)') has no G parent")
        return f.parents['G']
    elseif sym === :c_frame
        haskey(f.parents, 'C') || error("Frame (stream='$(f.stream)') has no C parent")
        return f.parents['C']
    elseif sym === :d_frame
        haskey(f.parents, 'D') || error("Frame (stream='$(f.stream)') has no D parent")
        return f.parents['D']
    elseif sym === :m_frame
        haskey(f.parents, 'M') || error("Frame (stream='$(f.stream)') has no M parent")
        return f.parents['M']
    end
    return getfield(f, sym)
end

"""
    frame[key::String]

Look up `key` in this frame's own data dict; if absent, walk up the parent
chain in `STREAM_HIERARCHY` order and return the first match. Throws `KeyError`
if the key is not found in the frame or any ancestor.
"""
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

"""
    frame[key::String] = value

Write `value` into this frame's own data dict under `key`. Never writes to a
parent frame.
"""
function Base.setindex!(frame::Frame, value, key::String)
    frame.data[key] = value
end

"""
    haskey(frame::Frame, key::String) -> Bool

Return `true` if `key` is present in this frame's own data or in any ancestor
frame reachable via the parent chain.
"""
function Base.haskey(frame::Frame, key::String)
    haskey(frame.data, key) && return true
    for s in STREAM_HIERARCHY
        if haskey(frame.parents, s)
            haskey(frame.parents[s].data, key) && return true
        end
    end
    return false
end

"""
    keys(frame::Frame) -> Set{String}

Return the union of all keys visible from this frame — its own data plus all
keys reachable through the parent chain.
"""
function Base.keys(frame::Frame)
    ks = Set(keys(frame.data))
    for s in STREAM_HIERARCHY
        haskey(frame.parents, s) && union!(ks, keys(frame.parents[s].data))
    end
    return ks
end

"""
    getkey(frame::Frame, key::String, default)

Return `frame[key]` if the key is visible (own data or any ancestor), otherwise
return `default`. Equivalent to `get(frame, key, default)`.
"""
function Base.getkey(frame::Frame, k::String, default)
    haskey(frame, k) ? frame[k] : default
end
