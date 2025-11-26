# Coordinate system
struct CoordinateSystem{T<:Real, U}
    origin::SVector{3, Quantity{T,U,typeof(u"m")}}
    rotation::SMatrix{3, 3, T, 9}
end

function CoordinateSystem(longlat::Tuple{Float64, Float64}, rearth::Quantity)
    origin = SVector{3}(longlat_to_cart(longlat...) * rearth)
    rotation = compute_rotation(longlat)
    return CoordinateSystem(origin, rotation)
end

Base.eltype(cs::CoordinateSystem) = eltype(cs.rotation)

const ecefcoordinates = CoordinateSystem(
    SVector{3}([0.0*u"m", 0.0*u"m", 0.0*u"m"]),
    SMatrix{3, 3, Float64, 9}([1.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 1.0])
)
