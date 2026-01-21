"""
    position_from_pp_vector(pp_vector, cs::CoordinateSystem)

Converts a position vector from the PROPOSAL coordinate system to the simulation's coordinate system.

# Arguments
- `pp_vector`: The position vector from PROPOSAL (a PROPOSAL Cartesian3D object).
- `cs::CoordinateSystem`: The target coordinate system.

# Returns
- `Coordinate{T}`: The converted coordinate in the target coordinate system.
"""
function position_from_pp_vector(pp_vector, cs::CoordinateSystem{T}) where {T<:Real}
    x = PP.get_x(pp_vector) * u"cm"
    y = PP.get_y(pp_vector) * u"cm"
    z = PP.get_z(pp_vector) * u"cm"
    return Coordinate([x, y, z], cs)
end

"""
    direction_from_pp_vector(pp_vector, cs::CoordinateSystem)

Converts a direction vector from the PROPOSAL coordinate system to the simulation's coordinate system.

# Arguments
- `pp_vector`: The direction vector from PROPOSAL (a PROPOSAL Cartesian3D object).
- `cs::CoordinateSystem`: The target coordinate system.

# Returns
- `Direction{T}`: The converted direction in the target coordinate system.
"""
function direction_from_pp_vector(pp_vector, cs::CoordinateSystem{T}) where {T<:Real}
    x = PP.get_x(pp_vector)
    y = PP.get_y(pp_vector)
    z = PP.get_z(pp_vector)
    return Direction([x, y, z], cs)
end
