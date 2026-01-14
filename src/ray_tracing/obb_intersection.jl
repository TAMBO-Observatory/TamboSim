"""
    world_to_local(obb::OBB, point::Coordinate) -> SVector{3}

Transforms a `Coordinate` from world space to the local coordinate system of an `OBB`.

This involves translating the point relative to the OBB's center and then
rotating it by the inverse of the OBB's orientation.

# Arguments
- `obb::OBB`: The Oriented Bounding Box.
- `point::Coordinate`: The `Coordinate` in world space.

# Returns
- `SVector{3}`: The transformed point in the OBB's local coordinate system.
"""
function world_to_local(obb::OBB, point::Coordinate)
    # Relative to center, then project onto OBB axes
    rel_point = point.point - obb.center.point
    return obb.axes' * rel_point  # Transpose of rotation matrix = inverse
end

"""
    world_to_local(obb::OBB, direction::Direction) -> SVector{3}

Transforms a `Direction` vector from world space to the local coordinate system of an `OBB`.

This involves rotating the direction by the inverse of the OBB's orientation.

# Arguments
- `obb::OBB`: The Oriented Bounding Box.
- `direction::Direction`: The `Direction` in world space.

# Returns
- `SVector{3}`: The transformed direction in the OBB's local coordinate system.
"""
function world_to_local(obb::OBB, direction::Direction)
    return obb.axes' * direction.point
end


"""
    find_intersect(ray::Ray, obb::OBB, idx::Int) -> Union{TriangleIntersection, Nothing}

Calculates the intersection between a `Ray` and an Oriented Bounding Box (`OBB`).

This function transforms the ray into the OBB's local coordinate system and then
performs a ray-AABB intersection test. If an intersection is found, it returns
a `TriangleIntersection` object (used generically for OBB intersections),
otherwise `nothing`.

# Arguments
- `ray::Ray`: The ray to test.
- `obb::OBB`: The Oriented Bounding Box to test against.
- `idx::Int`: The index of the OBB in its original collection.

# Returns
- `Union{TriangleIntersection, Nothing}`: A `TriangleIntersection` object (containing details about the hit point, normal, and distance), or `nothing` if no intersection occurs.
"""
function find_intersect(ray::Ray, obb::OBB, idx::Int)
    EPSILON = 1e-7
    
    # Transform ray to OBB local space
    local_origin = world_to_local(obb, ray.origin)
    local_dir = world_to_local(obb, ray.direction)
    
    t_min = -Inf * u"m"
    t_max = Inf * u"m"
    
    # Track which face we hit (for normal calculation)
    hit_face = 0
    hit_face_sign = 0
    
    # Test against all 3 slabs
    for i in 1:3
        if abs(local_dir[i]) < EPSILON
            # Ray parallel to slab
            if local_origin[i] < -obb.half_extents[i] || local_origin[i] > obb.half_extents[i]
                return 
            end
        else
            # Calculate intersection distances
            t1 = (-obb.half_extents[i] - local_origin[i]) / local_dir[i]
            t2 = (obb.half_extents[i] - local_origin[i]) / local_dir[i]
            
            # Ensure t1 is the near intersection
            if t1 > t2
                t1, t2 = t2, t1
            end
            
            # Update global t_min/t_max
            if t1 > t_min
                t_min = t1
                hit_face = i
                hit_face_sign = local_dir[i] > 0 ? -1 : 1
            end
            t_max = min(t_max, t2)
            
            if t_min > t_max
                return
            end
        end
    end
    
    # Check if intersection is valid
    if t_max < 0u"m"
        return
    end
    
    t = t_min >= 0u"m" ? t_min : t_max
    if t < 0u"m"
        return 
    end
    
    # Compute intersection point in world space
    point = Coordinate(ray.origin.point + ray.direction.point * t, ray.origin.coordinate_system)
    
    # Compute normal in world space
    normal = zeros(3)
    if hit_face > 0
        normal = Direction(obb.axes[:, hit_face] * hit_face_sign, ray.origin.coordinate_system)
    else
        # Fallback: compute from closest face
        local_point = world_to_local(obb, point)
        # Find which face is closest
        min_dist = Inf
        for i in 1:3
            for sign in [-1, 1]
                face_pos = sign * obb.half_extents[i]
                dist = abs(local_point[i] - face_pos)
                if dist < min_dist
                    min_dist = dist
                    normal = Direction(obb.axes[:, i] * sign, ray.origin.coordinate_system)
                end
            end
        end
    end
    
    return TriangleIntersection(point, normal, t, 0.5, 0.5, true, idx)
end
