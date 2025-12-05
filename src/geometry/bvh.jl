struct AABB{T}
    min::Coordinate{T}
    max::Coordinate{T}
end

function CoordinateSystem(aabb::AABB)
    return CoordinateSystem(aabb.min)
end

function AABB(
    indices,
    precomputed_aabbs::Vector{AABB{T}}
) where T

    # Merge precomputed AABBs
    aabb = precomputed_aabbs[first(indices)]
    min_point = aabb.min.point
    max_point = aabb.max.point

    for i in indices
        if i==1
            continue
        end
        aabb = precomputed_aabbs[i]
        min_point = min.(min_point, aabb.min.point)
        max_point = max.(max_point, aabb.max.point)
    end

    cs = CoordinateSystem(aabb)
    return AABB(Coordinate(min_point, cs), Coordinate(max_point, cs))
end

function AABB(obb::OBB)
    min_corner = fill(Inf*u"m", 3)
    max_corner = fill(-Inf*u"m", 3)
    
    for i in 1:8
        vertex = obb.vertices[i]
        min_corner = min.(min_corner, vertex.point)
        max_corner = max.(max_corner, vertex.point)
    end
        
    cs = CoordinateSystem(obb.vertices[1])
    return AABB(Coordinate(min_corner, cs), Coordinate(max_corner, cs))
end

function AABB(
    obbs::AbstractVector{OBB{T}}
) where {T<:Real}
    min_corner = fill(Inf*u"m", 3)
    max_corner = fill(-Inf*u"m", 3)
    
    for obb in obbs
        for i in 1:8
            vertex = obb.vertices[i]
            min_corner = min.(min_corner, vertex.point)
            max_corner = max.(max_corner, vertex.point)
        end
    end
    
    cs = CoordinateSystem(obbs[1].vertices[1])
    return AABB(Coordinate(min_corner, cs), Coordinate(max_corner, cs))
end

function AABB(triangle::Triangle{T}) where {T <: Real}
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
    triangles::AbstractVector{Triangle{T}},
) where {T<:Real}
    if length(triangles)==0
        error("Cannot create AABB for empty triangle set")
    end

    # Initialize with first triangle
    first_tri = triangles[1]
    v1 = first_tri.v1
    min_corner, max_corner = v1, v1

    # Expand to include all triangles
    for tri in triangles
        v1 = tri.v1
        v2 = tri.v2
        v3 = tri.v3

        min_corner = min.(min_corner, v1, v2, v3)
        max_corner = max.(max_corner, v1, v2, v3)
    end

    return AABB(min_corner, max_corner)
end

function AABB(obbs::Vector{OBB})
    min_corner = fill(Inf, 3)
    max_corner = fill(-Inf, 3)

    for obb in obbs
        for i in 1:8
            vertex = obb.vertices[:, i]
            min_corner = min.(min_corner, vertex)
            max_corner = max.(max_corner, vertex)
        end
    end

    new(SVector{3}(min_corner), SVector{3}(max_corner))
end

# BVH Node
mutable struct BVHNode{T <: Real}
    bbox::AABB{T}
    left::Union{BVHNode{T}, Nothing}
    right::Union{BVHNode{T}, Nothing}
    indices::Vector{Int}  # Indices into the triangles array
    is_leaf::Bool
end

# BVH Tree
struct BVHTree{T <: Real, S<:Union{Triangle{T}, OBB{T}}}
    root::BVHNode{T}
    triangles::Vector{S}
end

function CoordinateSystem(bvh::U) where {T<:Real, U<:BVHTree{T}}
    return CoordinateSystem(first(bvh.triangles))
end

# Merge two AABBs
function merge(a::AABB{T}, b::AABB{T}) where {T<:Real}
    min_corner = min.(a.min.point, b.min.point)
    max_corner = max.(a.max.point, b.max.point)
    cs = CoordinateSystem(a)
    return AABB(Coordinate(min_corner, cs), Coordinate(max_corner, cs))
end

function surface_area_fast(
    min_vals, 
    max_vals, 
)
    lx = max_vals[1] - min_vals[1]
    ly = max_vals[2] - min_vals[2] 
    lz = max_vals[3] - min_vals[3]
    return 2.0 * (lx * ly + ly * lz + lz * lx)
end

function surface_area_fast(
    min_vals::SVector{3, Quantity{T, ldim, typeof(u"m")}}, 
    max_vals::SVector{3, Quantity{T, ldim, typeof(u"m")}}, 
) where {T<:Real}
    lx = max_vals[1] - min_vals[1]
    ly = max_vals[2] - min_vals[2] 
    lz = max_vals[3] - min_vals[3]
    return 2.0 * (lx * ly + ly * lz + lz * lx)
end

function surface_area_fast(
    aabb::AABB{T}
) where {T<:Real}
    return surface_area_fast(aabb.min.point, aabb.max.point)
end

# AABB surface area (for SAH)
@inline function surface_area(bbox::AABB{T}) where {T<:Real}
    lengths = bbox.max - bbox.min
    return 2.0 * (lengths[1] * lengths[2] + lengths[2] * lengths[3] + lengths[3] * lengths[1])
end

# AABB center
@inline function center(bbox::AABB{T})::Coordinate{T} where {T<:Real}
    return (bbox.min + bbox.max) / 2.0
end

function BVHTree(
    objects::Vector{S};
    max_triangles_per_leaf = 4
)::BVHTree{T, S} where {T<:Real, S<:Union{Triangle{T}, OBB{T}}}
#function build_bvh(triangles::Vector{Triangle{<:Quantity}}; max_triangles_per_leaf = 4)
    if isempty(objects)
        error("Cannot build BVH from empty triangle list")
    end

    indices = collect(1:length(objects))
    precomputed_aabbs = AABB.(objects)
    precomputed_centers = center.(precomputed_aabbs)
    root = build_bvh_node(objects, indices, max_triangles_per_leaf, precomputed_aabbs, precomputed_centers)
    return BVHTree(root, objects)
end

function build_bvh_node(
    objects::Vector{S},
    indices::Vector{Int},
    max_objects_per_leaf::Int,
    precomputed_aabbs::Vector{AABB{T}},
    precomputed_centers::Vector{Coordinate{T}},
) where {T <: Real, S<:Union{Triangle{T}, OBB{T}}}

    if length(indices) <= max_objects_per_leaf
        bbox = AABB(indices, precomputed_aabbs)
        return BVHNode(bbox, nothing, nothing, indices, true)
    end

    # Find the best split using surface area heuristic
    best_axis, best_pos, best_cost = find_best_split(indices, precomputed_aabbs, precomputed_centers)

    # If no good split found, create leaf
    selected_objects = @views objects[indices]
    if best_cost >= length(indices) * surface_area_fast(AABB(selected_objects))
        bbox = AABB(indices, precomputed_aabbs)
        return BVHNode(bbox, nothing, nothing, indices, true)
    end

    # Split triangles along the best axis
    left_indices, right_indices = split_objects(
        indices,
        precomputed_centers,
        best_axis,
        best_pos
    )

    # Recursively build children
    left_node = build_bvh_node(objects, left_indices, max_objects_per_leaf, precomputed_aabbs, precomputed_centers)
    right_node = build_bvh_node(objects, right_indices, max_objects_per_leaf, precomputed_aabbs, precomputed_centers)

    # Merge bounding boxes
    bbox = merge(left_node.bbox, right_node.bbox)

    return BVHNode(bbox, left_node, right_node, Int[], false)
end

function find_best_split(
    indices::Vector{Int}, 
    precomputed_aabbs::Vector{AABB{T}},
    precomputed_centers::Vector{Coordinate{T}},
    fast=true
) where {T<:Real}
    best_axis = 1
    best_pos = 0.0
    best_cost = Inf * u"m"^2

    n = length(indices)
    skipper = 1
    if fast
        skipper = Int(floor(sqrt(n)))
    end
    for axis in 1:3
        # Use precomputed centers
        centers = [precomputed_centers[i][axis] for i in indices]
        sorted_indices = sortperm(centers)

        for i in 1:skipper:n-1
            left_indices = Iterators.take(sorted_indices, i)
            right_indices = Iterators.rest(sorted_indices, i+1)
            
            left_min, left_max = static_extrema_per_dim(precomputed_aabbs, left_indices)
            a1 = surface_area_fast(left_min, left_max)
            right_min, right_max = static_extrema_per_dim(precomputed_aabbs, right_indices)
            a2 = surface_area_fast(right_min, right_max)

            cost = length(left_indices) * a1 + (n-length(left_indices)) * a2

            if cost < best_cost
                split_pos = (centers[sorted_indices[i]] + centers[sorted_indices[i+1]]) / 2.0
                best_cost = cost
                best_axis = axis
                best_pos = split_pos
            end
        end
    end
    return best_axis, best_pos, best_cost
end

function split_objects(
    indices,
    precomputed_centers,
    axis,
    split_pos
)
    left_indices = Int[]
    right_indices = Int[]
    sizehint!(left_indices, length(indices) ÷ 2)
    sizehint!(right_indices, length(indices) ÷ 2)

    @inbounds for i in indices
        tri_center = precomputed_centers[i][axis]
        if tri_center < split_pos
            push!(left_indices, i)
        else
            push!(right_indices, i)
        end
    end

    if isempty(left_indices) || isempty(right_indices)
        mid = length(indices) ÷ 2
        return indices[1:mid], indices[mid+1:end]
    end

    return left_indices, right_indices
end

function static_extrema_per_dim(
    aabbs::Vector{AABB{T}},
    indices,
    mins::MVector{3, Quantity{T, ldim, typeof(u"m")}},
    maxs::MVector{3, Quantity{T, ldim, typeof(u"m")}},
) where {T<:Real}
    ndims = 3
    mins .= Inf * u"m"
    maxs .= -Inf * u"m"
    for idx in indices
        p1 = aabbs[idx].min.point
        p2 = aabbs[idx].max.point
        @inbounds for i in 1:ndims
            mins[i] = min(mins[i], p1[i])
            maxs[i] = max(maxs[i], p2[i])
        end
    end

    return mins, maxs
end

function static_extrema_per_dim(
    aabbs::Vector{AABB{T}},
    indices,
) where {T<:Real}
    ndims = 3
    mins = MVector{3}(fill(Inf, 3))
    maxs = MVector{3}(fill(-Inf, 3))
    for idx in indices
        p1 = ustrip.(aabbs[idx].min.point)
        p2 = ustrip.(aabbs[idx].max.point)
        @inbounds for i in 1:ndims

            mins[i] = min(mins[i], p1[i])
            maxs[i] = max(maxs[i], p2[i])
        end
    end

    return SVector{3}(mins)*u"m", SVector{3}(maxs)*u"m"
end

function static_extrema_per_dim(
    aabbs,
    mins,
    maxs
)
    ndims = 3
    mins = MVector{ndims}(fill(Inf*u"m", ndims))
    maxs = MVector{ndims}(fill(-Inf*u"m", ndims))

    for aabb in aabbs
        p1 = ustrip.(aabb.min.point)
        p2 = ustrip.(aabb.max.point)
        @inbounds for i in 1:ndims
            mins[i] = min(mins[i], p1[i])
            maxs[i] = max(maxs[i], p2[i])
        end
    end

    return mins, maxs
end
