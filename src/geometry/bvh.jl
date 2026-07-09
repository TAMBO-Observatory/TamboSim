"""
    AABB{T}

Represents an Axis-Aligned Bounding Box.

An AABB is defined by two points, `min` and `max`, which represent the minimum and
maximum coordinates of the box in each dimension.

# Fields
- `min::Coordinate{T}`: The minimum corner of the bounding box.
- `max::Coordinate{T}`: The maximum corner of the bounding box.
"""
struct AABB{T}
    min::Coordinate{T}
    max::Coordinate{T}
end

"""
    CoordinateSystem(aabb::AABB) -> CoordinateSystem

Constructs a `CoordinateSystem` based on the minimum corner of an `AABB`.

This is a convenience function that extracts the coordinate system from the `min`
field of the Axis-Aligned Bounding Box.

# Arguments
- `aabb::AABB`: The Axis-Aligned Bounding Box.

# Returns
- A `CoordinateSystem` object.
"""
function CoordinateSystem(aabb::AABB)
    return CoordinateSystem(aabb.min)
end

"""
    AABB(indices, precomputed_aabbs::Vector{AABB{T}}) where T

Creates a new `AABB` that encloses a selection of pre-computed AABBs.

This constructor is used during the BVH build process to merge the bounding boxes
of a set of objects.

# Arguments
- `indices`: The indices of the AABBs to merge from `precomputed_aabbs`.
- `precomputed_aabbs::Vector{AABB{T}}`: A vector of all pre-computed AABBs.

# Returns
- A new `AABB` that tightly bounds the selected AABBs.
"""
function AABB(
    indices,
    precomputed_aabbs::Vector{AABB{T}}
) where T

    # Merge precomputed AABBs
    aabb = precomputed_aabbs[first(indices)]
    min_point = aabb.min.point
    max_point = aabb.max.point

    for i in Iterators.drop(indices, 1)
        aabb = precomputed_aabbs[i]
        min_point = min.(min_point, aabb.min.point)
        max_point = max.(max_point, aabb.max.point)
    end

    cs = CoordinateSystem(aabb)
    return AABB(Coordinate(min_point, cs), Coordinate(max_point, cs))
end

"""
    AABB(obb::OBB) -> AABB

Creates an `AABB` that tightly encloses an `OBB` (Oriented Bounding Box).

It does this by finding the minimum and maximum coordinates among all the vertices
of the `OBB`.

# Arguments
- `obb::OBB`: The Oriented Bounding Box.

# Returns
- The enclosing `AABB`.
"""
function AABB(obb::OBB{T}) where T
    min_corner = fill(T(Inf)*u"m", 3)
    max_corner = fill(T(-Inf)*u"m", 3)
    
    for i in 1:8
        vertex = obb.vertices[i]
        min_corner = min.(min_corner, vertex.point)
        max_corner = max.(max_corner, vertex.point)
    end
        
    cs = CoordinateSystem(obb.vertices[1])
    return AABB(Coordinate(min_corner, cs), Coordinate(max_corner, cs))
end

"""
    AABB(obbs::AbstractVector{OBB{T}}) where {T<:Real} -> AABB

Creates an `AABB` that encloses a vector of `OBB`s (Oriented Bounding Boxes).

# Arguments
- `obbs::AbstractVector{OBB{T}}`: A vector of Oriented Bounding Boxes.

# Returns
- A single `AABB` that tightly bounds all the `OBB`s.
"""
function AABB(
    obbs::AbstractVector{OBB{T}}
) where {T<:Real}
    min_corner = fill(T(Inf)*u"m", 3)
    max_corner = fill(T(-Inf)*u"m", 3)
    
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

"""
    AABB(triangle::Triangle{T}) where {T <: Real} -> AABB

Creates an `AABB` that tightly encloses a single `Triangle`.

# Arguments
- `triangle::Triangle{T}`: The triangle to be enclosed.

# Returns
- The enclosing `AABB`.
"""
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
"""
    AABB(triangles::AbstractVector{Triangle{T}}) where {T<:Real} -> AABB

Creates an `AABB` that encloses a vector of `Triangle`s.

# Arguments
- `triangles::AbstractVector{Triangle{T}}`: A vector of triangles.

# Returns
- A single `AABB` that tightly bounds all the triangles.
"""
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


# BVH Node
"""
    BVHNode{T <: Real}

Represents a node in the `BVHTree`.

Each node contains a bounding box (`bbox`) that encloses all objects in its subtree.
If it's an internal node, it has `left` and `right` children. If it's a leaf node,
it contains a list of `indices` into the main objects array of the `BVHTree`.

# Fields
- `bbox::AABB{T}`: The Axis-Aligned Bounding Box for this node.
- `left::Union{BVHNode{T}, Nothing}`: The left child node.
- `right::Union{BVHNode{T}, Nothing}`: The right child node.
- `indices::Vector{Int}`: Indices of the objects contained in this leaf node.
- `is_leaf::Bool`: A flag indicating whether this is a leaf node.
"""
mutable struct BVHNode{T <: Real}
    bbox::AABB{T}
    left::Union{BVHNode{T}, Nothing}
    right::Union{BVHNode{T}, Nothing}
    indices::Vector{Int}  # Indices into the triangles array
    is_leaf::Bool
end

# BVH Tree
"""
    BVHTree{T <: Real, S<:Union{Triangle{T}, OBB{T}}}

Represents a Bounding Volume Hierarchy (BVH) tree.

The `BVHTree` is a spatial acceleration structure that allows for efficient
intersection tests (e.g., for ray tracing) with a large number of geometric objects.

# Fields
- `root::BVHNode{T}`: The root node of the tree.
- `triangles::Vector{S}`: The vector of all geometric objects (e.g., `Triangle` or `OBB`) stored in the tree.
"""
struct BVHTree{T <: Real, S<:Union{Triangle{T}, OBB{T}}}
    root::BVHNode{T}
    triangles::Vector{S}
end

"""
    CoordinateSystem(bvh::BVHTree) -> CoordinateSystem

Extracts the `CoordinateSystem` from the first object (e.g., Triangle or OBB) within a `BVHTree`.

This function assumes that all objects within the `BVHTree` share the same coordinate system.

# Arguments
- `bvh::BVHTree`: The Bounding Volume Hierarchy tree.

# Returns
- A `CoordinateSystem` object.
"""
function CoordinateSystem(bvh::U) where {T<:Real, U<:BVHTree{T}}
    return CoordinateSystem(first(bvh.triangles))
end

# Merge two AABBs
"""
    Base.merge(a::AABB{T}, b::AABB{T}) where {T<:Real} -> AABB

Merges two `AABB`s into a single `AABB` that encloses both.

# Arguments
- `a::AABB{T}`: The first AABB.
- `b::AABB{T}`: The second AABB.

# Returns
- A new `AABB` that is the union of `a` and `b`.
"""
function Base.merge(a::AABB{T}, b::AABB{T}) where {T<:Real}
    min_corner = min.(a.min.point, b.min.point)
    max_corner = max.(a.max.point, b.max.point)
    cs = CoordinateSystem(a)
    return AABB(Coordinate(min_corner, cs), Coordinate(max_corner, cs))
end

"""
    _aabb_surface_area(mins, maxs) -> Float64

Surface area of an AABB from unitless min/max corner components (metres).
Internal helper for the SAH sweeps in [`find_best_split`](@ref).
"""
@inline function _aabb_surface_area(mins, maxs)
    lx = maxs[1] - mins[1]
    ly = maxs[2] - mins[2]
    lz = maxs[3] - mins[3]
    return 2 * (lx * ly + ly * lz + lz * lx)
end

# AABB center
"""
    center(bbox::AABB{T})::Coordinate{T} where {T<:Real}

Calculates the geometric center of an `AABB`.

# Arguments
- `bbox::AABB{T}`: The bounding box.

# Returns
- A `Coordinate` representing the center of the bounding box.
"""
@inline function center(bbox::AABB{T})::Coordinate{T} where {T<:Real}
    return (bbox.min + bbox.max) / 2
end

"""
    BVHTree(
        objects::Vector{S};
        max_triangles_per_leaf = 4
    )::BVHTree{T, S} where {T<:Real, S<:Union{Triangle{T}, OBB{T}}}

Constructs a `BVHTree` from a vector of geometric objects.

This function builds the BVH by recursively partitioning the objects. It pre-computes
AABBs and centers for all objects to speed up the build process.

# Arguments
- `objects`: A vector of `Triangle` or `OBB` objects.
- `max_triangles_per_leaf`: The maximum number of objects allowed in a leaf node.

# Returns
- A new `BVHTree` object.
"""
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

"""
    build_bvh_node(
        objects::Vector{S},
        indices::Vector{Int},
        max_objects_per_leaf::Int,
        precomputed_aabbs::Vector{AABB{T}},
        precomputed_centers::Vector{Coordinate{T}},
    ) where {T <: Real, S<:Union{Triangle{T}, OBB{T}}} -> BVHNode

Recursively constructs a single node in the `BVHTree`.

This function decides whether to create a leaf node or an internal node. If the
number of objects is below the threshold, it creates a leaf. Otherwise, it finds
the best split, partitions the objects, and recursively calls itself to build
the child nodes.

# Arguments
- `objects`: The full list of geometric objects.
- `indices`: The indices of the objects belonging to this node.
- `max_objects_per_leaf`: The threshold for creating a leaf node.
- `precomputed_aabbs`: Pre-computed AABBs for all objects.
- `precomputed_centers`: Pre-computed centers for all AABBs.

# Returns
- The constructed `BVHNode`.
"""
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

    # Find the best split using the surface area heuristic
    sorted_indices, best_split = find_best_split(indices, precomputed_aabbs, precomputed_centers)
    left_indices = sorted_indices[1:best_split]
    right_indices = sorted_indices[best_split+1:end]

    # Recursively build children
    left_node = build_bvh_node(objects, left_indices, max_objects_per_leaf, precomputed_aabbs, precomputed_centers)
    right_node = build_bvh_node(objects, right_indices, max_objects_per_leaf, precomputed_aabbs, precomputed_centers)

    # Merge bounding boxes
    bbox = merge(left_node.bbox, right_node.bbox)

    return BVHNode(bbox, left_node, right_node, Int[], false)
end

"""
    find_best_split(
        indices::Vector{Int},
        precomputed_aabbs::Vector{AABB{T}},
        precomputed_centers::Vector{Coordinate{T}},
    ) where {T<:Real} -> (sorted_indices, best_split)

Finds the best way to split a set of objects into two groups using the
Surface Area Heuristic (SAH).

For each axis, the object indices are sorted by AABB center and every split
position is scored with prefix/suffix surface-area sweeps (O(n) per axis
after the sort). The SAH cost of a candidate split is

    cost = C_trav + (SA_left/SA_parent)*N_left + (SA_right/SA_parent)*N_right

with `C_trav = 1`. When the parent box is degenerate (zero surface area),
the cost falls back to the plain object counts.

# Arguments
- `indices`: The indices of the objects to consider for the split.
- `precomputed_aabbs`: Pre-computed AABBs for all objects.
- `precomputed_centers`: Pre-computed centers of the AABBs.

# Returns
- `(sorted_indices, best_split)`: object indices sorted along the winning
  axis, and the split position such that `sorted_indices[1:best_split]` /
  `sorted_indices[best_split+1:end]` are the left/right children. Both
  halves are guaranteed non-empty (`1 <= best_split <= length(indices)-1`).
"""
function find_best_split(
    indices::Vector{Int},
    precomputed_aabbs::Vector{AABB{T}},
    precomputed_centers::Vector{Coordinate{T}},
) where {T<:Real}
    n = length(indices)
    @assert n >= 2 "find_best_split requires at least 2 objects"

    # Parent surface area for SAH normalization
    parent_mins = MVector{3,Float64}(Inf, Inf, Inf)
    parent_maxs = MVector{3,Float64}(-Inf, -Inf, -Inf)
    _extend_extrema!(parent_mins, parent_maxs, precomputed_aabbs, indices)
    parent_area = _aabb_surface_area(parent_mins, parent_maxs)

    best_cost = Inf
    best_split = n ÷ 2
    best_sorted = indices

    left_areas = Vector{Float64}(undef, n)
    right_areas = Vector{Float64}(undef, n)
    mins = MVector{3,Float64}(undef)
    maxs = MVector{3,Float64}(undef)

    for axis in 1:3
        sorted = sort(indices; by = i -> ustrip(u"m", precomputed_centers[i].point[axis]))

        # Prefix sweep: left_areas[k] = surface area of the box over sorted[1:k]
        mins .= Inf; maxs .= -Inf
        for k in 1:n
            _extend_extrema!(mins, maxs, precomputed_aabbs, (sorted[k],))
            left_areas[k] = _aabb_surface_area(mins, maxs)
        end

        # Suffix sweep: right_areas[k] = surface area of the box over sorted[k:n]
        mins .= Inf; maxs .= -Inf
        for k in n:-1:1
            _extend_extrema!(mins, maxs, precomputed_aabbs, (sorted[k],))
            right_areas[k] = _aabb_surface_area(mins, maxs)
        end

        for split in 1:n-1
            cost = if parent_area > 0
                1.0 + (left_areas[split] / parent_area) * split +
                      (right_areas[split+1] / parent_area) * (n - split)
            else
                1.0 + n
            end
            if cost < best_cost
                best_cost = cost
                best_split = split
                best_sorted = sorted
            end
        end
    end

    return best_sorted, best_split
end

"""
    _extend_extrema!(mins, maxs, aabbs, indices)

Extend the running component-wise extrema `mins`/`maxs` (unitless metres)
by the AABBs of the given object `indices`. Internal helper for the SAH
sweeps in [`find_best_split`](@ref).
"""
@inline function _extend_extrema!(
    mins::MVector{3,Float64},
    maxs::MVector{3,Float64},
    aabbs::Vector{AABB{T}},
    indices,
) where {T<:Real}
    for idx in indices
        p1 = aabbs[idx].min.point
        p2 = aabbs[idx].max.point
        @inbounds for c in 1:3
            mins[c] = min(mins[c], ustrip(u"m", p1[c]))
            maxs[c] = max(maxs[c], ustrip(u"m", p2[c]))
        end
    end
    return mins, maxs
end
