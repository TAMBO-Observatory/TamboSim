"""
    triangles_to_mesh(triangles::Vector{Triangle{T}}, forplot::Bool=false) -> Tuple{Vector{Coordinate{T}}, Matrix{Int}}

Converts a vector of `Triangle` objects into a mesh representation (unique vertices and face indices).

This function processes a list of triangles, extracts all unique vertices, assigns an index to each,
and then generates a matrix of face indices where each row defines a triangle using the indices of its vertices.
An optional `forplot` argument can be used to format vertices for plotting.

# Arguments
- `triangles::Vector{Triangle{T}}`: A vector of `Triangle` objects to convert.
- `forplot::Bool`: If `true`, the vertices are converted to `Point3f` for plotting purposes. Defaults to `false`.

# Returns
- `Tuple{Vector{Coordinate{T}}, Matrix{Int}}`: A tuple containing:
    - `unique_vertices`: A vector of unique `Coordinate` objects (or `Point3f` if `forplot` is true).
    - `face_indices`: A `Matrix{Int}` where each row represents a face (triangle) by its vertex indices.
"""
function triangles_to_mesh(
    triangles::Vector{Triangle{T}},
    forplot::Bool=false
) where {T<:Real}
    unique_vertices = Coordinate{T}[]
    vertex_to_index = Dict{Coordinate{T}, Int}()
    face_indices = Vector{Tuple{Int, Int, Int}}()
    
    current_index = 1
    
    for triangle in triangles
        face = Int[]
        for vertex in triangle
            if !haskey(vertex_to_index, vertex)
                vertex_to_index[vertex] = current_index
                push!(unique_vertices, vertex)
                push!(face, current_index)
                current_index += 1
            else
                push!(face, vertex_to_index[vertex])
            end
        end
        
        push!(face_indices, (face[1], face[2], face[3]))
    end
    face_indices = hcat([t[1] for t in face_indices], [t[2] for t in face_indices], [t[3] for t in face_indices])
    if forplot
        unique_vertices = map(verts->Point3f([x.val for x in verts]), unique_vertices)
    end
    return unique_vertices, face_indices
end

"""
    mask_helper(
        intersections::AbstractVector{Intersection{T}},
        detector_region,
        revd::Direction{T}
    ) -> BitVector

Generates a boolean mask for intersections, marking certain intersections as "bad" based on detector region entry/exit.

# Arguments
- `intersections`: A sorted list of `Intersection` objects along a ray.
- `detector_region`: Indices of detector-region triangles.
- `revd::Direction{T}`: The reverse direction of the particle's travel.

# Returns
- `BitVector`: A boolean mask where `false` indicates "bad" intersections to be excluded.
"""
function mask_helper(
    intersections::I,
    detector_region,
    revd::Direction{T}
) where {T<:Real, I<:AbstractVector{Intersection{T}}}
    mask = ones(Bool, length(intersections))
    bad_idxs = Int[]
    for (idx, i) in enumerate(intersections)
        if idx in bad_idxs || isa(i, SphereIntersection)
            continue
        end
        if i.index in detector_region
            entering = dot(i.normal, revd) < 0
            if entering && idx < length(intersections) && !isa(intersections[idx+1], SphereIntersection)
                push!(bad_idxs, idx)
                push!(bad_idxs, idx+1)
            end
        end
    end
    mask[bad_idxs] .= 0
    return mask
end
