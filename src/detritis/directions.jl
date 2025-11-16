struct Direction
    theta::Float64
    phi::Float64
    proj::SVector{3,Float64}
end

"""
    Direction(θ::T, ϕ::U) where {T,U<:Number}

TBW
"""
function Direction(θ::T, ϕ::U) where {T,U<:Number}
    θ, ϕ = Float64(θ), mod(Float64(ϕ), 2π)
    proj = SVector{3}([cos(ϕ) * sin(θ), sin(ϕ) * sin(θ), cos(θ)])
    return Direction(θ, ϕ, proj)
end

"""
    Direction(x::T, y::U, z::V) where {T,U,V<:Number}

TBW
"""
function Direction(x::T, y::U, z::V) where {T,U,V<:Number}
    x, y, z = promote(x, y, z)
    proj = SVector{3}([x, y, z]) ./ norm((x, y, z))
    θ = acos(proj.z)
    ϕ = mod(atan(proj.y, proj.x), 2π) 
    return Direction(θ, ϕ, proj)
end

function Direction(sv::SVector{3})
    return Direction(sv.x, sv.y, sv.z)
end

function Direction(ip::SVector{3}, fp::SVector{3})
    return Direction(ip .- fp)
end

function Direction(pp_vector::PyObject)
    return Direction(pp_vector.x, pp_vector.y, pp_vector.z)
end

function Base.getproperty(d::Direction, field::Symbol)
    if field==:θ
        return d.theta
    elseif field==:ϕ
        return d.phi
    else
        return getfield(d, field)
    end
end

function Base.show(io::IO, d::Direction)
    print(
        io,
        """
        ($(round(rad2deg(d.θ), sigdigits=3))°, $(round(rad2deg(d.ϕ), sigdigits=3))°)"""
    )
end

Base.reverse(d::Direction) = Direction(-d.proj...)

Base.:/(sv::SVector{3}, d::Direction) = sv ./ d.proj
Base.:*(m, d::Direction) = m .* d.proj
