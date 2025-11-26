abstract type Intersection{T <: Real} end

# Intersection result with units
struct TriangleIntersection{T <: Real} <: Intersection{T}
    point::Coordinate{T}
    normal::Direction{T}  # Unitless normal
    distance::Quantity{T, ldim, typeof(u"m")}
    u::T  # Barycentric coordinates are unitless
    v::T
    hit::Bool
    index::Int
end

struct SphereIntersection{T <: Real} <: Intersection{T}
    point::Coordinate{T}
    normal::Direction{T}
    distance::Quantity{T, ldim, typeof(u"m")}
    hit::Bool
end

function find_intersect(ray::Ray{T}, triangle::Triangle{T}, tri_index::Int=-1) where {T<:Real}
    # Extract vertices and strip units for the algorithm
    v1 = ustrip.(triangle.v1.point)
    v2 = ustrip.(triangle.v2.point)
    v3 = ustrip.(triangle.v3.point)

    # Convert ray to unitless for computation
    ray_origin = ustrip.(ray.origin.point)
    ray_dir = ray.direction.point

    # Find vectors for two edges sharing v1
    edge1 = v2 - v1
    edge2 = v3 - v1

    # Begin calculating determinant
    pvec = cross(ray_dir, edge2)
    det = dot(edge1, pvec)

    # If determinant is near zero, ray lies in plane of triangle
    if abs(det) < eps(T)
        return 
    end

    inv_det = one(T) / det

    # Calculate distance from v1 to ray origin
    tvec = ray_origin - v1

    # Calculate u parameter and test bound
    u = dot(tvec, pvec) * inv_det
    if u < zero(T) || u > one(T)
        return 
    end

    # Prepare to test v parameter
    qvec = cross(tvec, edge1)

    # Calculate v parameter and test bound
    v = dot(ray_dir, qvec) * inv_det
    if v < zero(T) || (u + v) > one(T)
        return 
    end

    # Calculate t, ray intersects triangle
    t = dot(edge2, qvec) * inv_det

    # Check if intersection is in front of ray origin
    if t < eps(T)
        return 
    end

    # Compute intersection point and normal (with units restored)
    cs = triangle.v1.coordinate_system
    point = Coordinate((ray_origin + t * ray_dir) * u"m", cs)
    normal = Direction(normalize(cross(edge1, edge2)), cs)  # Unitless

    return TriangleIntersection(point, normal, t * u"m", u, v, true, tri_index)
end

# Find all intersections (not just closest)
function intersect_all(bvh::BVHTree{T}, ray::Ray{T})::Vector{TriangleIntersection{T}} where {T<:Real}
    intersections = TriangleIntersection{T}[]
    intersect_node(ray, bvh.root, bvh.triangles, intersections)
    sort!(intersections, by = x -> ustrip(x.distance))
    return intersections
end

function find_intersect(ray::Ray{T}, bbox::AABB{T}) where {T<:Real}
    # Convert to unitless for computation
    ray_origin_u = ustrip.(ray.origin.point)
    ray_dir_u = ray.direction
    bbox_min_u = ustrip.(bbox.min.point)
    bbox_max_u = ustrip.(bbox.max.point)
    
    # Ray-AABB intersection algorithm (unitless)
    tmin = -Inf
    tmax = Inf
    
    for i in 1:3
        if abs(ray_dir_u[i]) < eps(T)
            # Ray is parallel to this slab
            if ray_origin_u[i] < bbox_min_u[i] || ray_origin_u[i] > bbox_max_u[i]
                return false, zero(T), zero(T)
            end
        else
            t1 = (bbox_min_u[i] - ray_origin_u[i]) / ray_dir_u[i]
            t2 = (bbox_max_u[i] - ray_origin_u[i]) / ray_dir_u[i]
            
            if t1 > t2
                t1, t2 = t2, t1
            end
            
            tmin = max(tmin, t1)
            tmax = min(tmax, t2)
            
            if tmin > tmax
                return false, zero(T), zero(T)
            end
        end
    end
    
    return true, tmin, tmax
end
function find_intersect(ray::Ray{T}, bvh::BVHTree{T}) where {T<:Real}
    intersections = TriangleIntersection[]  # (intersection, triangle_index)
    intersect_node(ray, bvh.root, bvh.triangles, intersections)

    # Find the closest intersection
    if isempty(intersections)
        return 
    end

    # Sort by distance and return the closest
    sort!(intersections, by = x -> ustrip(x[1].distance))
    #sort!(intersections, by = x -> ustrip(x[1].distance))
    return first(intersections)
end

function intersect_node(
    ray::Ray{T},
    node::BVHNode{T},
    triangles::Vector{Triangle{T}},
    results::Vector{TriangleIntersection{T}}
) where {T<:Real}
    # Check ray-AABB intersection first
    hits_bbox, tmin, tmax = find_intersect(ray, node.bbox)
    if !hits_bbox || tmax < 0
        return
    end

    if node.is_leaf
        # Check intersection with all triangles in leaf
        for tri_index in node.triangles
            tri = triangles[tri_index]
            intersection = find_intersect(ray, tri, tri_index)
            if isnothing(intersection)
                continue
            end
            push!(results, intersection)
        end
    else
        # Recursively check children
        if node.left !== nothing
            intersect_node(ray, node.left, triangles, results)
        end
        if node.right !== nothing
            intersect_node(ray, node.right, triangles, results)
        end
    end
end

function intersect_all(
    sphere::Sphere{T},
    ray::Ray{T};
    epsilon=1e-10
)::Vector{SphereIntersection{T}} where {T<:Real}
    """
    Detailed sphere-ray intersection with additional information.
    """
    d = ray.direction
    o = ray.origin
    c = sphere.center
    r = sphere.radius
    ϵ = epsilon * u"m"^2

    oc = o - c

    a = dot(d.point, d.point)
    b = 2.0 * dot(oc, d.point)
    c_val = dot(oc.point, oc.point) - r^2

    discriminant = b^2 - 4.0 * a * c_val

    if discriminant < -ϵ
        return SphereIntersection{T}[]
    elseif abs(discriminant) < ϵ
        discriminant = 0.0
    end


    if discriminant == 0.0
        # Tangent intersection
        t = -b / (2.0 * a)
        if t >= 0*u"m"
            point = o + t * d
            normal = Direction(normalize(point.point - c.point), CoordinateSystem(point))
            intersection = SphereIntersection(point, normal, t, true)
            return [intersection]

        end
    else
        # Two intersections
        sqrt_disc = sqrt(discriminant)
        t1 = (-b - sqrt_disc) / (2.0 * a)
        t2 = (-b + sqrt_disc) / (2.0 * a)

        # Sort by t value
        t_candidates = [t1, t2]

        intersections = SphereIntersection{T}[]
        for t in t_candidates
            if t >= 0 * u"m"
                point = o + t * d
                normal = Direction(normalize(point.point - c.point), CoordinateSystem(point))

                intersection = SphereIntersection(point, normal, t, true)
                push!(intersections, intersection)
            end
        end
        return intersections
    end

    return SphereIntersection{T}[]
end

function intersect_all(
    earth::Earth{T},
    ray::Ray{T}
)::Vector{<:Intersection{T}} where {T}
    mesh_intersections = intersect_all(earth.bvh, ray)
    sphere_intersections = vcat([intersect_all(sphere, ray) for sphere in earth.prem]...)
    intersections = vcat(mesh_intersections, sphere_intersections)
    intersections = sort(intersections; by=x->x.distance)
    return intersections
end
