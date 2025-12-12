struct Frame
    data::Dict{String, Any}
    parent::Union{Nothing, Frame}
    type::Char
    Frame() = new(Dict{String, Any}())
    Frame(data::Dict) = new(data, nothing, 'T')
    Frame(data::Dict, type::Char) = new(data, nothing, type)
    Frame(data::Dict, parent::Frame, type::Char) = new(data, parent, type)
end

function Base.getindex(frame::Frame, key::String)
    if haskey(frame.data, key)
        return frame.data[key]
    elseif isnothing(frame.parent)
        throw(KeyError(key))
    else
        return frame.parent[key]
    end
end

function Base.setindex!(frame::Frame, value, key::String)
    frame.data[key] = value
end

function Base.haskey(frame::Frame, key::String)
    if haskey(frame.data, key)
        return true
    elseif isnothing(frame.parent)
        return false
    else
        return haskey(frame.parent, key)
    end
end

function Base.keys(frame::Frame)
    if isnothing(frame.parent)
        return keys(frame.data)
    else
        return union(keys(frame.data), keys(frame.parent))
    end
end

function Base.getkey(frame::Frame, k::String, default)
    if haskey(frame, k)
        return frame[k]
    else
        return default
    end
end
