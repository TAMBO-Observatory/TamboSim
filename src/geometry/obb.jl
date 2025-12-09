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

function compute_vertices(center, axes, half_extents)
    x, y, z = half_extents
    [Coordinate(axes * SVector{3}(a*x, b*y, c*z)+center.point, center.coordinate_system) for a in [-1, 1] for b in [-1, 1] for c in [-1,1]]
end
