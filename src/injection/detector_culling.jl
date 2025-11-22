function geometric_triangle_weight(
    triangles::Vector{Triangle{T,U}},
    d::Direction{T,U},
    normals::Union{Nothing,Vector{Direction{T,U}}}=nothing,
    bvh::Union{Nothing,BVHTree{T,U}}=nothing
) where {T,U}
    if isnothing(normals)
        normals = normal.(triangles)
    end
    if isnothing(bvh)
        bvh = build_bvh(triangles)
    end
    backwards_mask = faces_backwards.(Ref(d), normals)
    vxs, faces = triangles_to_mesh(triangles)
    occlusion_mask_vxs = compute_occlusion(vxs, faces, d, bvh)
    occlusion_mask = occlusion_mask_to_faces(occlusion_mask_vxs, faces)
    return backwards_mask .* occlusion_mask
end

function faces_backwards(
    d::Direction{T,U},
    normal::Direction{T,U}
) where {T,U}
    return dot(normal.point, d.point) < 0
end 

function compute_occlusion(
    vertices::Vector{Coordinate{T,U}},
    faces::Matrix{Int},
    d::Direction{T,U},
    bvh::BVHTree{T,U},
) where {T,U}
    cs = d.coordinate_system
    occlusion_mask = BitVector(undef, length(vertices))
    revd = reverse(d)
    for (idx, vx) in enumerate(vertices)
        occlusion_mask[idx] = 1
        p = Coordinate(vx.point + 1e-6u"m" * revd.point, cs)
        ray = Ray(p, revd)
        a = intersect_all(bvh, ray)
        if length(a)>0
            occlusion_mask[idx] = 0
        else
            occlusion_mask[idx] = 1
        end
    end
    return occlusion_mask
end

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
