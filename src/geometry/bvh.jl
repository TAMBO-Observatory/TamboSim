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

"""
    AABB(obbs::Vector{OBB}) -> AABB

Creates an `AABB` that tightly encloses a vector of `OBB`s (Oriented Bounding Boxes).

This constructor calculates the minimum and maximum coordinates across all vertices
of the provided `OBB`s to form a new Axis-Aligned Bounding Box.

# Arguments
- `obbs::Vector{OBB}`: A vector of `OBB` objects.

# Returns
- A new `AABB` object.
"""
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
    surface_area_fast(min_vals, max_vals)

Calculates the surface area of an AABB from its minimum and maximum coordinates.

This is a fast, internal function used in the SAH calculation.

# Arguments
- `min_vals`: A collection of minimum coordinates (x, y, z).
- `max_vals`: A collection of maximum coordinates (x, y, z).

# Returns
- The surface area of the AABB.
"""
function surface_area_fast(
    min_vals, 
    max_vals, 
)
    lx = max_vals[1] - min_vals[1]
    ly = max_vals[2] - min_vals[2] 
    lz = max_vals[3] - min_vals[3]
    return 2 * (lx * ly + ly * lz + lz * lx)
end

"""
    surface_area_fast(
        min_vals::SVector{3, Quantity{T, ldim, typeof(u"m")}}, 
        max_vals::SVector{3, Quantity{T, ldim, typeof(u"m")}}, 
    ) where {T<:Real}

Calculates the surface area of an AABB from `SVector`s with units.

# Arguments
- `min_vals`: An `SVector` of minimum coordinates.
- `max_vals`: An `SVector` of maximum coordinates.

# Returns
- The surface area of the AABB, with units.
"""
function surface_area_fast(
    min_vals::SVector{3, Quantity{T, ldim, typeof(u"m")}}, 
    max_vals::SVector{3, Quantity{T, ldim, typeof(u"m")}}, 
) where {T<:Real}
    lx = max_vals[1] - min_vals[1]
    ly = max_vals[2] - min_vals[2] 
    lz = max_vals[3] - min_vals[3]
    return 2 * (lx * ly + ly * lz + lz * lx)
end

"""
    surface_area_fast(aabb::AABB{T}) where {T<:Real}

Calculates the surface area of an `AABB`.

# Arguments
- `aabb::AABB{T}`: The Axis-Aligned Bounding Box.

# Returns
- The surface area.
"""
function surface_area_fast(
    aabb::AABB{T}
) where {T<:Real}
    return surface_area_fast(aabb.min.point, aabb.max.point)
end

# AABB surface area (for SAH)
"""
    surface_area(bbox::AABB{T}) where {T<:Real}

Calculates the surface area of an `AABB`.

Used for the Surface Area Heuristic (SAH) during BVH construction.

# Arguments
- `bbox::AABB{T}`: The bounding box.

# Returns
- The surface area of the bounding box.
"""
@inline function surface_area(bbox::AABB{T}) where {T<:Real}
    lengths = bbox.max - bbox.min
    return 2 * (lengths[1] * lengths[2] + lengths[2] * lengths[3] + lengths[3] * lengths[1])
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

    # Find the best split using surface area heuristic
    best_axis, best_pos, best_cost = find_best_split(indices, precomputed_aabbs, precomputed_centers)

    # If no good split found, create leaf
    selected_objects = @views objects[indices]
    #if best_cost >= length(indices) * surface_area_fast(AABB(selected_objects))
    #    bbox = AABB(indices, precomputed_aabbs)
    #    return BVHNode(bbox, nothing, nothing, indices, true)
    #end

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

"""
    find_best_split(
        indices::Vector{Int}, 
        precomputed_aabbs::Vector{AABB{T}},
        precomputed_centers::Vector{Coordinate{T}},
        fast=true
    ) where {T<:Real}

Finds the best axis and position to split a set of objects using the Surface Area Heuristic (SAH).

The SAH aims to find a split that minimizes the cost, which is a function of the
surface areas of the resulting bounding boxes and the number of objects in them.

# Arguments
- `indices`: The indices of the objects to consider for the split.
- `precomputed_aabbs`: Pre-computed AABBs for all objects.
- `precomputed_centers`: Pre-computed centers for all AABBs.
- `fast`: If `true`, uses a faster, approximate SAH by sampling a subset of potential splits.

# Returns
- A tuple `(best_axis, best_pos, best_cost)` containing the best splitting axis (1, 2, or 3),
  the position along that axis, and the calculated cost of that split.
"""
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

"""
    split_objects(
        indices,
        precomputed_centers,
        axis,
        split_pos
    )

Partitions a set of object indices into two groups based on a splitting plane.

The split is performed by comparing the center of each object's AABB along the
specified `axis` with the `split_pos`.

# Arguments
- `indices`: The indices of the objects to be split.
- `precomputed_centers`: Pre-computed centers of the AABBs.
- `axis`: The axis to split along (1, 2, or 3).
- `split_pos`: The position on the axis to split at.

# Returns
- A tuple `(left_indices, right_indices)` containing the partitioned indices.
"""
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

"""
    static_extrema_per_dim(
        aabbs::Vector{AABB{T}},
        indices,
        mins::MVector{3, Quantity{T, ldim, typeof(u"m")}},
        maxs::MVector{3, Quantity{T, ldim, typeof(u"m")}},
    ) where {T<:Real}

Computes the minimum and maximum coordinates over a selection of AABBs.

This is a fast, in-place version that updates pre-allocated `MVector`s.

# Arguments
- `aabbs`: A vector of all AABBs.
- `indices`: The indices of the AABBs to consider.
- `mins`: A mutable vector to store the minimum coordinates.
- `maxs`: A mutable vector to store the maximum coordinates.

# Returns
- A tuple `(mins, maxs)` containing the updated mutable vectors.
"""
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

"""
    static_extrema_per_dim(
        aabbs::Vector{AABB{T}},
        indices,
    ) where {T<:Real}

Computes the minimum and maximum coordinates over a selection of AABBs.

This version allocates new `SVector`s for the results.

# Arguments
- `aabbs`: A vector of all AABBs.
- `indices`: The indices of the AABBs to consider.

# Returns
- A tuple `(mins, maxs)` containing new `SVector`s with the min and max coordinates.
"""
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

"""
    static_extrema_per_dim(aabbs, mins, maxs)

Computes the minimum and maximum coordinates over a collection of Axis-Aligned Bounding Boxes (AABBs).

This is an in-place version that updates pre-allocated mutable vectors for `mins` and `maxs`.
It iterates through the provided `aabbs` and updates the `mins` and `maxs` vectors
to encompass the full extent of all AABBs.

# Arguments
- `aabbs`: An iterable collection of `AABB` objects.
- `mins`: A mutable vector (e.g., `MVector{3}`) to store the minimum coordinates.
          It will be initialized to `Inf` and then updated.
- `maxs`: A mutable vector (e.g., `MVector{3}`) to store the maximum coordinates.
          It will be initialized to `-Inf` and then updated.

# Returns
- A tuple containing the updated `mins` and `maxs` mutable vectors.
"""
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
