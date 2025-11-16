struct AABB{T, U}
    min::Coordinate{T, U}
    max::Coordinate{T, U}
end

function CoordinateSystem(aabb::AABB)
    return CoordinateSystem(aabb.min)
end

function AABB(
    indices::Vector{Int},
    precomputed_aabbs::Vector{AABB{T,U}}
) where {T,U}

    # Merge precomputed AABBs
    aabb = precomputed_aabbs[indices[1]]
    min_point = aabb.min.point
    max_point = aabb.max.point

    @inbounds for i in indices[2:end]
        aabb = precomputed_aabbs[i]
        min_point = min.(min_point, aabb.min.point)
        max_point = max.(max_point, aabb.max.point)
    end

    cs = CoordinateSystem(aabb)
    return AABB(Coordinate(min_point, cs), Coordinate(max_point, cs))
end

function AABB(
    triangles::Vector{Triangle{T,U}},
    indices::Vector{Int},
    precomputed_aabbs::Vector{AABB{T,U}}
) where {T,U}

    # Merge precomputed AABBs
    aabb = precomputed_aabbs[indices[1]]
    min_point = aabb.min.point
    max_point = aabb.max.point

    @inbounds for i in indices[2:end]
        aabb = precomputed_aabbs[i]
        min_point = min.(min_point, aabb.min.point)
        max_point = max.(max_point, aabb.max.point)
    end

    cs = CoordinateSystem(aabb)
    return AABB(Coordinate(min_point, cs), Coordinate(max_point, cs))
end

function AABB(triangle::Triangle{T, U}) where {T, U}
    v1 = triangle.v1
    v2 = triangle.v2
    v3 = triangle.v3
    cs = CoordinateSystem(triangle)

    min_corner = min.(v1, v2, v3)
    max_corner = max.(v1, v2, v3)

    return AABB(min_corner, max_corner)
end

# Create an AABB that contains multiple triangles
function AABB(
    triangles::Vector{Triangle{T, U}},
    indices::Vector{Int}
) where {T, U}
    if isempty(indices)
        error("Cannot create AABB for empty triangle set")
    end

    # Initialize with first triangle
    first_tri = triangles[indices[1]]
    v1 = first_tri.v1
    min_corner, max_corner = v1, v1

    # Expand to include all triangles
    @inbounds for i in indices
        tri = triangles[i]
        v1 = tri.v1
        v2 = tri.v2
        v3 = tri.v3

        min_corner = min.(min_corner, v1, v2, v3)
        max_corner = max.(max_corner, v1, v2, v3)
    end

    return AABB(min_corner, max_corner)
end

# BVH Node
mutable struct BVHNode{T <: Real, U}
    bbox::AABB{T, U}
    left::Union{BVHNode{T, U}, Nothing}
    right::Union{BVHNode{T, U}, Nothing}
    triangles::Vector{Int}  # Indices into the triangles array
    is_leaf::Bool
end

# BVH Tree
struct BVHTree{T <: Real, U}
    root::BVHNode{T, U}
    triangles::Vector{Triangle{T, U}}
end

# Merge two AABBs
function merge(a::AABB{T, U}, b::AABB{T, U}) where {T, U}
    min_corner = min.(a.min.point, b.min.point)
    max_corner = max.(a.max.point, b.max.point)
    cs = CoordinateSystem(a)
    return AABB(Coordinate(min_corner, cs), Coordinate(max_corner, cs))
end

function surface_area_fast(bbox::AABB)
    min_vals = bbox.min.point
    max_vals = bbox.max.point
    lx = max_vals[1] - min_vals[1]
    ly = max_vals[2] - min_vals[2] 
    lz = max_vals[3] - min_vals[3]
    return 2.0 * (lx * ly + ly * lz + lz * lx)
end

# AABB surface area (for SAH)
@inline function surface_area(bbox::AABB)
    lengths = bbox.max - bbox.min
    return 2.0 * (lengths[1] * lengths[2] + lengths[2] * lengths[3] + lengths[3] * lengths[1])
end

# AABB center
@inline function center(bbox::AABB)
    return (bbox.min + bbox.max) / 2.0
end

function build_bvh(triangles::Vector{Triangle{T, U}}; max_triangles_per_leaf = 4) where {T, U}
#function build_bvh(triangles::Vector{Triangle{<:Quantity}}; max_triangles_per_leaf = 4)
    if isempty(triangles)
        error("Cannot build BVH from empty triangle list")
    end

    indices = collect(1:length(triangles))
    precomputed_aabbs = AABB{T, U}[AABB(triangle) for triangle in triangles]
    precomputed_centers = [center(aabb) for aabb in precomputed_aabbs]
    #display(precomputed_centers)
    root = build_bvh_node(triangles, indices, max_triangles_per_leaf, precomputed_aabbs, precomputed_centers)
    return BVHTree(root, triangles)
end

function build_bvh_node(
    triangles::Vector{Triangle{T, U}},
    indices::Vector{Int},
    max_triangles_per_leaf::Int,
    precomputed_aabbs::Vector{AABB{T, U}},
    precomputed_centers::Vector{Coordinate{T, U}}
) where {T <: Real, U}

    # Create leaf if few triangles remain
    if length(indices) <= max_triangles_per_leaf
        bbox = AABB(triangles, indices, precomputed_aabbs)
        return BVHNode(bbox, nothing, nothing, indices, true)
    end

    # Find the best split using SAH (Surface Area Heuristic)
    best_axis, best_pos, best_cost = find_best_split(triangles, indices, precomputed_aabbs, precomputed_centers)

    # If no good split found, create leaf
    if best_cost >= length(indices) * surface_area_fast(AABB(triangles, indices))
    #if best_cost >= length(indices) * surface_area(AABB(triangles, indices))
        bbox = AABB(triangles, indices, precomputed_aabbs)
        return BVHNode(bbox, nothing, nothing, indices, true)
    end

    # Split triangles along the best axis
    left_indices, right_indices = split_triangles_optimized(triangles, indices, precomputed_aabbs, best_axis, best_pos)
    #left_indices, right_indices = split_triangles(triangles, indices, best_axis, best_pos)

    # Recursively build children
    left_node = build_bvh_node(triangles, left_indices, max_triangles_per_leaf, precomputed_aabbs, precomputed_centers)
    right_node = build_bvh_node(triangles, right_indices, max_triangles_per_leaf, precomputed_aabbs, precomputed_centers)

    # Merge bounding boxes
    bbox = merge(left_node.bbox, right_node.bbox)

    return BVHNode(bbox, left_node, right_node, Int[], false)
end

function find_best_split(
    triangles::Vector{Triangle{T,U}},
    indices::Vector{Int}, 
    precomputed_aabbs::Vector{AABB{T,U}},
    precomputed_centers::Vector{Coordinate{T, U}},
    fast=true
) where {T,U}
    best_axis = 1
    best_pos = 0.0
    best_cost = Inf * u"m"^2

    # Use precomputed AABBs
    bbox = AABB(triangles, indices, precomputed_aabbs)
    bbox_center_val = center(bbox)

    for axis in 1:3
        # Use precomputed centers
        centers = [precomputed_centers[i][axis] for i in indices]
        #centers = [center(precomputed_aabbs[i])[axis] for i in indices]
        sorted_indices = sortperm(centers)

        skipper = 1
        if fast
            skipper = Int(floor(sqrt(length(centers))))
        end
        #skipper = Int(ceil(1 / sqrt(length(centers))))
        for i in 1:skipper:length(sorted_indices)-1
            split_pos = (centers[sorted_indices[i]] + centers[sorted_indices[i+1]]) / 2.0
            left_indices = indices[sorted_indices[1:i]]
            right_indices = indices[sorted_indices[i+1:end]]

            # Use precomputed AABBs for cost calculation
            left_bbox = AABB(triangles, left_indices, precomputed_aabbs)
            right_bbox = AABB(triangles, right_indices, precomputed_aabbs)

            #cost = length(left_indices) * surface_area(left_bbox) +
            #       length(right_indices) * surface_area(right_bbox)
            cost = length(left_indices) * surface_area_fast(left_bbox) +
                   length(right_indices) * surface_area_fast(right_bbox)

            if cost < best_cost
                best_cost = cost
                best_axis = axis
                best_pos = split_pos
            end
        end
    end

    return best_axis, best_pos, best_cost
end

function find_best_split(triangles, indices)
    best_axis = 1
    best_pos = 0.0
    best_cost = Inf * u"m"^2

    bbox = AABB(triangles, indices)
    bbox_center = center(bbox)

    # Try all three axes
    for axis in 1:3
        # Sort triangle centers along this axis
        centers = [center(AABB(triangles[i]))[axis] for i in indices]
        sorted_indices = sortperm(centers)

        # Try different split positions
        for i in 1:length(sorted_indices)-1
            split_pos = (centers[sorted_indices[i]] + centers[sorted_indices[i+1]]) / 2.0

            left_indices = indices[sorted_indices[1:i]]
            right_indices = indices[sorted_indices[i+1:end]]

            left_bbox = AABB(triangles, left_indices)
            right_bbox = AABB(triangles, right_indices)

            #cost = length(left_indices) * surface_area(left_bbox) +
            #       length(right_indices) * surface_area(right_bbox)
            cost = length(left_indices) * surface_area_fast(left_bbox) +
                   length(right_indices) * surface_area_fast(right_bbox)

            if cost < best_cost
                best_cost = cost
                best_axis = axis
                best_pos = split_pos
            end
        end
    end

    return best_axis, best_pos, best_cost
end

function split_triangles_optimized(triangles, indices, precomputed_aabbs, axis, split_pos)
    left_indices = Int[]
    right_indices = Int[]
    sizehint!(left_indices, length(indices) ÷ 2)
    sizehint!(right_indices, length(indices) ÷ 2)

    @inbounds for i in indices
        tri_center = center(precomputed_aabbs[i])[axis]
        if tri_center < split_pos
            push!(left_indices, i)
        else
            push!(right_indices, i)
        end
    end

    # Handle bad splits more efficiently
    if isempty(left_indices) || isempty(right_indices)
        mid = length(indices) ÷ 2
        return indices[1:mid], indices[mid+1:end]
    end

    return left_indices, right_indices
end

function split_triangles(triangles, indices, axis, split_pos)
    left_indices = Int[]
    right_indices = Int[]

    for i in indices
        tri_center = center(AABB(triangles[i]))[axis]
        if tri_center < split_pos
            push!(left_indices, i)
        else
            push!(right_indices, i)
        end
    end

    # If split failed (all triangles on one side), do median split
    if isempty(left_indices) || isempty(right_indices)
        mid = length(indices) ÷ 2
        left_indices = indices[1:mid]
        right_indices = indices[mid+1:end]
    end

    return left_indices, right_indices
end
