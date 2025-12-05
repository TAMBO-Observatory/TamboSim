function world_to_local(obb::OBB, point::Coordinate)
    # Relative to center, then project onto OBB axes
    rel_point = point.point - obb.center.point
    return obb.axes' * rel_point  # Transpose of rotation matrix = inverse
end

function world_to_local(obb::OBB, direction::Direction)
    return obb.axes' * direction.point
end


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
