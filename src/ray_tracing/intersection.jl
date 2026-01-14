"""
    Intersection{T<:Real}

Abstract type representing a ray-shape intersection event.

Concrete subtypes (e.g., `TriangleIntersection`, `SphereIntersection`) provide
details about the intersection point, normal, distance, and the type of shape hit.
"""
abstract type Intersection{T <: Real} end

# Tolerance constants for intersection calculations
"""Tolerance for detecting parallel rays in plane intersection tests."""
const PLANE_PARALLELISM_TOLERANCE = 1e-10

# Intersection result with units
"""
    TriangleIntersection{T<:Real} <: Intersection{T}

Represents an intersection between a ray and a `Triangle`.

# Fields
- `point::Coordinate{T}`: The `Coordinate` of the intersection point.
- `normal::Direction{T}`: The `Direction` of the triangle's normal at the intersection point.
- `distance::Quantity{T, ldim, typeof(u"m")}`: The distance from the ray origin to the intersection point.
- `u::T`: The barycentric coordinate `u` of the intersection point.
- `v::T`: The barycentric coordinate `v` of the intersection point.
- `hit::Bool`: A boolean indicating if a valid hit occurred (always `true` for a returned intersection).
- `index::Int`: The index of the triangle in the original collection.
"""
struct TriangleIntersection{T <: Real} <: Intersection{T}
    point::Coordinate{T}
    normal::Direction{T}  # Unitless normal
    distance::Quantity{T, ldim, typeof(u"m")}
    u::T  # Barycentric coordinates are unitless
    v::T
    hit::Bool
    index::Int
end

"""
    SphereIntersection{T<:Real} <: Intersection{T}

Represents an intersection between a ray and a `Sphere`.

# Fields
- `point::Coordinate{T}`: The `Coordinate` of the intersection point.
- `normal::Direction{T}`: The `Direction` of the sphere's normal at the intersection point.
- `distance::Quantity{T, ldim, typeof(u"m")}`: The distance from the ray origin to the intersection point.
- `hit::Bool`: A boolean indicating if a valid hit occurred (always `true` for a returned intersection).
"""
struct SphereIntersection{T <: Real} <: Intersection{T}
    point::Coordinate{T}
    normal::Direction{T}
    distance::Quantity{T, ldim, typeof(u"m")}
    hit::Bool
end

"""
    find_intersect(ray::Ray{T}, triangle::Triangle{T}, tri_index::Int=-1) -> Union{TriangleIntersection{T}, Nothing}

Calculates the intersection between a `Ray` and a `Triangle` using the Möller-Trumbore algorithm.

This function determines if and where a ray intersects a triangle. It handles back-face culling implicitly
(by returning `nothing` if the ray hits the back face or is parallel to the plane).
The coordinates are stripped of units for computation and then restored.

# Arguments
- `ray::Ray{T}`: The ray to test for intersection.
- `triangle::Triangle{T}`: The triangle to test against.
- `tri_index::Int`: The index of the triangle in the original collection (for the `TriangleIntersection` object). Defaults to -1.

# Returns
- `Union{TriangleIntersection{T}, Nothing}`: A `TriangleIntersection` object if an intersection is found, otherwise `nothing`.
"""
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
function intersect_all(
    bvh::BVHTree{T},
    ray::Ray{T}
)::Vector{TriangleIntersection{T}} where {T<:Real}
    intersections = TriangleIntersection{T}[]
    intersect_node!(intersections, ray, bvh.root, bvh.triangles)
    sort!(intersections, by = x -> ustrip(x.distance))
    return intersections
end

"""
    find_intersect(ray::Ray{T}, bbox::AABB{T}) -> Tuple{Bool, T, T}

Calculates the intersection of a `Ray` with an Axis-Aligned Bounding Box (`AABB`).

This function determines if a ray intersects an AABB and, if so, returns the entry (`tmin`)
and exit (`tmax`) parameters along the ray. The computation is done in a unitless fashion
for numerical stability and then units are implicitly handled by the context.

# Arguments
- `ray::Ray{T}`: The ray to test.
- `bbox::AABB{T}`: The Axis-Aligned Bounding Box to test against.

# Returns
- `Tuple{Bool, T, T}`: A tuple containing:
    - `Bool`: `true` if an intersection occurs, `false` otherwise.
    - `T`: The `t` parameter for the ray's entry point into the AABB (if hit).
    - `T`: The `t` parameter for the ray's exit point from the AABB (if hit).
"""
function find_intersect(ray::Ray{T}, bbox::AABB{T}) where {T<:Real}
    # Convert to unitless for computation
    ray_origin_u = ustrip.(ray.origin.point)
    ray_dir_u = ray.direction.point
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
"""
    find_intersect(ray::Ray{T}, bvh::BVHTree{T}) -> Union{TriangleIntersection{T}, Nothing}

Finds the closest intersection between a `Ray` and any triangle within a `BVHTree`.

This function traverses the BVH to efficiently find the first (closest) intersection.

# Arguments
- `ray::Ray{T}`: The ray to test.
- `bvh::BVHTree{T}`: The Bounding Volume Hierarchy containing the triangles.

# Returns
- `Union{TriangleIntersection{T}, Nothing}`: The closest `TriangleIntersection` object if found, otherwise `nothing`.
"""
function find_intersect(ray::Ray{T}, bvh::BVHTree{T}) where {T<:Real}
    intersections = TriangleIntersection[]  # (intersection, triangle_index)
    intersect_node!(intersections, ray, bvh.root, bvh.triangles)

    # Find the closest intersection
    if isempty(intersections)
        return 
    end

    # Sort by distance and return the closest
    sort!(intersections, by = x -> ustrip(x.distance))
    return first(intersections)
end

"""
    intersect_node!(
        results::Vector{TriangleIntersection{T}},
        ray::Ray{T},
        node::BVHNode{T},
        objects::Vector{S},
    ) where {T<:Real, S<:Union{Triangle{T}, OBB{T}}}

Recursively traverses the `BVHNode` to find all ray-object intersections within its subtree.

This is an internal helper function for BVH-accelerated ray tracing. It performs
ray-AABB intersection tests for the node's bounding box and, if hit, recursively
calls itself for child nodes or checks individual objects if it's a leaf node.

# Arguments
- `results::Vector{TriangleIntersection{T}}`: A mutable vector to store all found intersections.
- `ray::Ray{T}`: The ray to test.
- `node::BVHNode{T}`: The current BVH node being traversed.
- `objects::Vector{S}`: The collection of all geometric objects (triangles or OBBs) referenced by the BVH.
"""
function intersect_node!(
    results::Vector{TriangleIntersection{T}},
    ray::Ray{T},
    node::BVHNode{T},
    triangles::Vector{S},
) where {T<:Real, S<:Union{Triangle{T}, OBB{T}}}
    # Check ray-AABB intersection first
    hits_bbox, tmin, tmax = find_intersect(ray, node.bbox)
    if !hits_bbox || tmax < 0
        return
    end

    if node.is_leaf
        # Check intersection with all triangles in leaf
        #ixs = map(i->find_intersect(ray, triangles[i], i), node.triangles)
        for idx in node.indices
            tri = triangles[idx]
            intersection = find_intersect(ray, tri, idx)
            if isnothing(intersection)
                continue
            end
            push!(results, intersection)
        end
    else
        # Recursively check children
        if node.left !== nothing
            intersect_node!(results, ray, node.left, triangles)
        end
        if node.right !== nothing
            intersect_node!(results, ray, node.right, triangles)
        end
    end
end

"""
    intersect_all(sphere::Sphere{T}, ray::Ray{T}; epsilon=1e-10) -> Vector{SphereIntersection{T}}

Calculates all intersections between a `Ray` and a `Sphere`.

This function solves the quadratic equation for ray-sphere intersection, finding up to
two intersection points. It handles cases of no intersection, tangent intersection,
and two distinct intersections.

# Arguments
- `sphere::Sphere{T}`: The sphere to test against.
- `ray::Ray{T}`: The ray to test.
- `epsilon`: A small numerical tolerance for floating-point comparisons.

# Returns
- `Vector{SphereIntersection{T}}`: A vector of `SphereIntersection` objects, which can be empty if no intersections occur.
"""
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

"""
    intersect_all(earth::Earth{T}, ray::Ray{T}) -> Vector{<:Intersection{T}}

Calculates all intersections between a `Ray` and the `Earth` model.

This function finds intersections with both the Earth's topography (accelerated by a BVH)
and its layered structure (PREM spheres). All found intersections are then combined and
sorted by distance from the ray origin.

# Arguments
- `earth::Earth{T}`: The `Earth` model to test against.
- `ray::Ray{T}`: The ray to test.

# Returns
- `Vector{<:Intersection{T}}`: A sorted vector containing all `TriangleIntersection` and `SphereIntersection` objects.
"""
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

"""
    find_intersection(ray::Ray{T}, plane::Plane{T}) -> Tuple{Union{Coordinate{T}, Nothing}, Union{Quantity{T, ldim, typeof(u"m")}, Nothing}}

Calculates the intersection between a `Ray` and a `Plane`.

This function determines the point where a ray intersects an infinite plane.
It returns `nothing` for both the point and the distance if the ray is parallel
to the plane or if the intersection occurs behind the ray's origin.

# Arguments
- `ray::Ray{T}`: The ray to test.
- `plane::Plane{T}`: The plane to test against.

# Returns
- `Tuple{Union{Coordinate{T}, Nothing}, Union{Quantity{T, ldim, typeof(u"m")}, Nothing}}`: A tuple containing:
    - The `Coordinate` of the intersection point, or `nothing`.
    - The distance (`t` parameter) along the ray to the intersection, or `nothing`.
"""
function find_intersection(
    ray::Ray{T},
    plane::Plane{T}
) where {T<:Real}

    plane_normal = plane.normal.point

    # Calculate denominator
    denominator = dot(ray.direction.point, plane.normal.point)

    # Check if ray is parallel to plane
    if abs(denominator) < PLANE_PARALLELISM_TOLERANCE
        return nothing, nothing  # No intersection or ray lies in plane
    end

    # Calculate parameter t
    t = dot(plane.point.point - ray.origin.point, plane.normal.point) / denominator

    # Check if intersection is in front of ray origin
    if t < 0u"m"
        return nothing, nothing  # Intersection behind ray origin
    end

    # Calculate intersection point
    intersection_point = ray.origin + t * ray.direction

    return intersection_point, t
end
