function triangles_to_mesh(
    triangles::Vector{Triangle{T,U}},
    forplot::Bool=false
) where {T,U}
    unique_vertices = Coordinate{T,U}[]
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
    intersections::Vector{T},
    earth::Tambo.Earth{U,V}
) where {T<:Tambo.Intersection,U,V}
    mask = ones(Bool, length(intersections))
    bad_idxs = Int[]
    for (idx, i) in enumerate(intersections)
        if idx in bad_idxs || typeof(i)==SphereIntersection{U,V}
            continue
        end
        if i.index in earth.detector_region
            show_this = true
            push!(bad_idxs, idx)
            push!(bad_idxs, idx+1)
        end
    end
    mask[bad_idxs] .= 0
    return mask
end
