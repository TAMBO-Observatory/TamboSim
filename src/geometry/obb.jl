"""
    OBB{T<:Real}

Represents an Oriented Bounding Box (OBB) in 3D space.

An OBB is defined by its center, a rotation (axes), and its half-extents along
each of its local axes. It also pre-computes and stores its 8 corner vertices.

# Fields
- `center::Coordinate{T}`: The center `Coordinate` of the OBB.
- `axes::AngleAxis{T}`: An `AngleAxis` object defining the orientation of the OBB's local axes relative to its coordinate system.
- `half_extents::SVector{3, Quantity{T, ldim, typeof(u"m")}}`: A static vector containing the half-lengths of the OBB along its local x, y, and z axes.
- `vertices::Vector{Coordinate{T}}`: A pre-computed vector of the 8 corner `Coordinate`s of the OBB.

# Constructors
- `OBB(center, axes, half_extents)`: Primary constructor that computes vertices and validates `half_extents` length.
"""
struct OBB{T<:Real}
    center::Coordinate{T}
    axes::AngleAxis{T}
    half_extents::SVector{3, Quantity{T, ldim, typeof(u"m")}}
    vertices::Vector{Coordinate{T}}

    function OBB(
        center::Coordinate{T},
        axes::AngleAxis{T},
        half_extents::AbstractVector{<:Quantity{T,ldim}}
    ) where {T<:Real}
        length(half_extents) == 3 || throw(ArgumentError("half_extents must have length 3"))
        half_extents_sv = SVector{3}(uconvert.(u"m", half_extents)...)
        vertices = compute_vertices(center, axes, half_extents_sv)
        return new{T}(center, axes, half_extents_sv, vertices)
    end
end

"""
    compute_vertices(center::Coordinate, axes::AngleAxis, half_extents::SVector{3}) -> Vector{Coordinate}

Computes the 8 corner vertices of an Oriented Bounding Box (OBB).

This helper function calculates the coordinates of all vertices given the OBB's
center, rotation (`axes`), and half-extents.

# Arguments
- `center::Coordinate`: The center `Coordinate` of the OBB.
- `axes::AngleAxis`: An `AngleAxis` object defining the orientation.
- `half_extents::SVector{3}`: A static vector containing the half-lengths along the local axes.

# Returns
- `Vector{Coordinate}`: A vector containing the 8 corner `Coordinate`s of the OBB.
"""
function compute_vertices(center, axes, half_extents)
    x, y, z = half_extents
    [Coordinate(axes * SVector{3}(a*x, b*y, c*z)+center.point, center.coordinate_system) for a in [-1, 1] for b in [-1, 1] for c in [-1,1]]
end
