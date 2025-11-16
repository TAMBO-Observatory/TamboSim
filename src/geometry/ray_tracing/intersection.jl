abstract type Intersection end

# Intersection result with units
struct TriangleIntersection{T <: Real, U}
    point::Coordinate{T, U}
    normal::Direction{T}  # Unitless normal
    distance::Quantity{T, U, typeof(u"m")}
    u::T  # Barycentric coordinates are unitless
    v::T
    hit::Bool
end

struct SphereIntersection{T <: Real, U}
    point::Coordinate{T, U}
    normal::Direction{T}
    distance::Quantity{T, U, typeof(u"m")}
    hit::Bool
end

# No-intersection result with units
function no_intersection_triangle(::Type{T} = Float64) where {T}
    zero_quant = zero(T) * u"m"
    vec = Coordinate(
        SVector{3}(zero_quant, zero_quant, zero_quant),
        ecefcoordinates
    )
    dir = Direction(SVector{3, T}(0, 0, 0), ecefcoordinates)
    TriangleIntersection(vec, dir, T(Inf) * u"m", zero(T), zero(T), false)
end

function no_intersection_sphere(::Type{T} = Float64) where {T}
    zero_quant = zero(T) * u"m"
    vec = Coordinate(
        SVector{3}(zero_quant, zero_quant, zero_quant),
        ecefcoordinates
    )
    dir = Direction(SVector{3, T}(0, 0, 0), ecefcoordinates)
    return SphereIntersection(vec, dir, T(Inf) * u"m", false)
end

function find_intersect(ray::Ray{T, U}, triangle::Triangle{T,U}) where {T, U}
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
        return no_intersection_triangle(T)
    end

    inv_det = one(T) / det

    # Calculate distance from v1 to ray origin
    tvec = ray_origin - v1

    # Calculate u parameter and test bound
    u = dot(tvec, pvec) * inv_det
    if u < zero(T) || u > one(T)
        return no_intersection_triangle(T)
    end

    # Prepare to test v parameter
    qvec = cross(tvec, edge1)

    # Calculate v parameter and test bound
    v = dot(ray_dir, qvec) * inv_det
    if v < zero(T) || (u + v) > one(T)
        return no_intersection_triangle(T)
    end

    # Calculate t, ray intersects triangle
    t = dot(edge2, qvec) * inv_det

    # Check if intersection is in front of ray origin
    if t < eps(T)
        return no_intersection_triangle(T)
    end

    # Compute intersection point and normal (with units restored)
    point_unit = unit(ray.origin[1])
    cs = triangle.v1.coordinate_system
    point = ray.origin + t * point_unit * ray.direction
    normal = Direction(normalize(cross(edge1, edge2)), cs)  # Unitless

    return TriangleIntersection(point, normal, t * point_unit, u, v, true)
end

# Find all intersections (not just closest)
function intersect_all(ray::Ray, bvh::BVHTree)
    intersections = Tuple{TriangleIntersection, Int}[]
    intersect_node(ray, bvh.root, bvh.triangles, intersections)
    sort!(intersections, by = x -> ustrip(x[1].distance))
    return intersections
end

function find_intersect(ray::Ray, bbox::AABB{T, U}) where {T, U}
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
function find_intersect(ray::Ray, bvh::BVHTree)
    intersections = Tuple{TriangleIntersection, Int}[]  # (intersection, triangle_index)
    intersect_node(ray, bvh.root, bvh.triangles, intersections)

    # Find the closest intersection
    if isempty(intersections)
        return no_intersection_triangle(), -1
    end

    # Sort by distance and return the closest
    sort!(intersections, by = x -> ustrip(x[1].distance))
    #sort!(intersections, by = x -> ustrip(x[1].distance))
    return intersections[1]
end

function intersect_node(
    ray::Ray{T, U},
    node::BVHNode{T, U},
    triangles::Vector{Triangle{T, U}},
    results::Vector{Tuple{TriangleIntersection, Int}}
) where {T, U}
    # Check ray-AABB intersection first
    hits_bbox, tmin, tmax = find_intersect(ray, node.bbox)
    if !hits_bbox || tmax < 0
        return
    end

    if node.is_leaf
        # Check intersection with all triangles in leaf
        for tri_index in node.triangles
            tri = triangles[tri_index]
            intersection = find_intersect(ray, tri)
            if intersection.hit
                push!(results, (intersection, tri_index))
            end
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

function detailed_sphere_intersection(sphere::Sphere, ray::Ray; epsilon=1e-10)
    """
    Detailed sphere-ray intersection with additional information.
    """
    d = ray.direction
    o = ray.origin
    c = sphere.center
    r = sphere.radius

    oc = o - c

    a = dot(d, d)
    b = 2.0 * dot(oc, d)
    c_val = dot(oc, oc) - r^2

    discriminant = b^2 - 4.0 * a * c_val

    if discriminant < -epsilon
        return nothing
    end

    # Handle near-zero discriminant
    if abs(discriminant) < epsilon
        discriminant = 0.0
    end

    points = Vector{Vector{Float64}}()
    t_values = Vector{Float64}()
    distances = Vector{Float64}()
    normals = Vector{Vector{Float64}}()

    if discriminant == 0.0
        # Tangent intersection
        t = -b / (2.0 * a)
        if t >= 0
            point = o + t * d
            normal = normalize(point - c)

            push!(points, point)
            push!(t_values, t)
            push!(distances, norm(point - o))
            push!(normals, normal)
        end
    else
        # Two intersections
        sqrt_disc = sqrt(discriminant)
        t1 = (-b - sqrt_disc) / (2.0 * a)
        t2 = (-b + sqrt_disc) / (2.0 * a)

        # Sort by t value
        t_candidates = sort([t1, t2])

        for t in t_candidates
            if t >= 0
                point = o + t * d
                normal = normalize(point - c)

                push!(points, point)
                push!(t_values, t)
                push!(distances, norm(point - o))
                push!(normals, normal)
            end
        end
    end

    return IntersectionResult(points, t_values, distances, normals, discriminant == 0.0)
end
