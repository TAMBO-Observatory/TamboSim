"""
    geometric_triangle_weight(
        triangles::Vector{Triangle{T}},
        d::Direction{T},
        normals::Union{Nothing,Vector{Direction{T}}}=nothing,
        bvh::Union{Nothing,BVHTree{T}}=nothing
    ) where {T<:Real}

Calculates a weight for each triangle based on its orientation and whether it is occluded.

The weight is a product of two masks: one for triangles facing forward (towards the direction `d`),
and another for triangles that are not occluded by other triangles.

# Arguments
- `triangles`: A vector of `Triangle` objects.
- `d`: The direction of interest (e.g., of an incoming particle).
- `normals`: Optional pre-computed normals for the triangles.
- `bvh`: Optional pre-computed `BVHTree` for the triangles.

# Returns
- A vector of weights (0.0 or 1.0) for each triangle.
"""
function geometric_triangle_weight(
    triangles::Vector{Triangle{T}},
    d::Direction{T},
    normals::Union{Nothing,Vector{Direction{T}}}=nothing,
    bvh::Union{Nothing,BVHTree{T}}=nothing
) where {T<:Real}
    if isnothing(normals)
        normals = normal.(triangles)
    end
    if isnothing(bvh)
        bvh = BVHTree(triangles)
    end
    forewards_mask = faces_forward.(Ref(d), normals)
    vxs, faces = triangles_to_mesh(triangles)
    occlusion_mask_vxs = compute_occlusion(vxs, faces, d, bvh)
    occlusion_mask = occlusion_mask_to_faces(occlusion_mask_vxs, faces)
    return forewards_mask .* occlusion_mask
end

"""
    faces_forward(
        d::Direction{T},
        normal::Direction{T}
    ) where {T<:Real}

Checks if a face is oriented towards a given direction.

A face is considered to be facing forward if the dot product of its normal
and the direction `d` is negative.

# Arguments
- `d`: The direction of interest.
- `normal`: The normal vector of the face.

# Returns
- `true` if the face is facing forward, `false` otherwise.
"""
function faces_forward(
    d::Direction{T},
    normal::Direction{T}
) where {T<:Real}
    return dot(normal, d) < 0
end 

"""
    compute_occlusion(
        vertices::Vector{Coordinate{T}},
        faces::Matrix{Int},
        d::Direction{T},
        bvh::BVHTree{T},
    ) where {T<:Real}

Determines which vertices of a mesh are occluded by other parts of the mesh from a certain direction.

For each vertex, a ray is cast in the reverse direction of `d`. If the ray intersects
with any other part of the mesh (using a `BVHTree` for acceleration), the vertex
is considered occluded.

# Arguments
- `vertices`: A vector of vertex coordinates.
- `faces`: A matrix defining the faces of the mesh.
- `d`: The direction of view.
- `bvh`: A `BVHTree` of the mesh for accelerating intersection tests.

# Returns
- A `BitVector` where `1` indicates an unoccluded vertex and `0` indicates an occluded one.
"""
function compute_occlusion(
    vertices::Vector{Coordinate{T}},
    faces::Matrix{Int},
    d::Direction{T},
    bvh::BVHTree{T},
) where {T<:Real}
    cs = d.coordinate_system
    occlusion_mask = BitVector(undef, length(vertices))
    revd = reverse(d)
    for (idx, vx) in enumerate(vertices)
        p = Coordinate(vx.point + 1e-6u"m" * revd.point, cs)
        ray = Ray(p, revd)
        a = intersect_all(bvh, ray)
        if length(a)==0
            occlusion_mask[idx] = 1
        else
            occlusion_mask[idx] = 0
        end
    end
    return occlusion_mask
end

"""
    occlusion_mask_to_faces(
        occlusion_mask::BitVector,
        faces::Matrix{Int}
    )

Converts a vertex-based occlusion mask to a face-based occlusion mask.

The occlusion value for a face is the average of the occlusion values of its vertices.

# Arguments
- `occlusion_mask`: A `BitVector` indicating vertex occlusion (1 for unoccluded, 0 for occluded).
- `faces`: A matrix defining the faces of the mesh.

# Returns
- A vector of occlusion values for each face, ranging from 0.0 to 1.0.
"""
function occlusion_mask_to_faces(
    occlusion_mask::BitVector,
    faces::Matrix{Int}
)
    out = zeros(size(faces, 1))
    for (idx, face) in enumerate(eachrow(faces))
        out[idx] = sum(occlusion_mask[face]) / 3
    end
    return out
end
