function triangles_to_mesh(
    triangles::Vector{Triangle{T}},
    forplot::Bool=false
) where {T<:Real}
    unique_vertices = Coordinate{T}[]
    vertex_to_index = Dict{Any, Int}()
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

function mask_helper(
    intersections::I,
    earth::Earth{T},
    revd::Direction{T}
) where {T<:Real, I<:AbstractVector{Intersection{T}}}
    mask = ones(Bool, length(intersections))
    bad_idxs = Int[]
    for (idx, i) in enumerate(intersections)
        if idx in bad_idxs || typeof(i)==SphereIntersection{T}
            continue
        end
        if i.index in earth.detector_region
            tri = earth.topography[idx]
            entering = dot(normal(tri), revd) < 0
            if entering && typeof(intersections[idx+1])!=SphereIntersection{T}
                push!(bad_idxs, idx)
                push!(bad_idxs, idx+1)
            end
        end
    end
    mask[bad_idxs] .= 0
    return mask
end
