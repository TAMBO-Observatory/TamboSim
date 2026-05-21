"""
    _parse_triangles(vertices, faces, cs) -> Vector{Triangle{T}}

Convert raw vertex/face matrices (as loaded from an HDF5 geometry file) into a
vector of `Triangle`s in coordinate system `cs`.

`vertices` is an N×3 matrix of ECEF coordinates in metres; `faces` is an M×3
matrix of 1-based vertex indices. Each row of `faces` becomes one `Triangle`.
"""
function _parse_triangles(
    vertices::Matrix{<:Real},
    faces::Matrix{<:Integer},
    cs::CoordinateSystem{T}
)::Vector{Triangle{T}} where {T}
    triangles = Triangle{T}[]
    for idxs in eachrow(faces)
        vs = []
        for idx in idxs
            v = Coordinate(vertices[idx, :] .* u"m", ecefcoordinates)
            v = convert(cs, v)
            push!(vs, v)
        end
        push!(triangles, Triangle(vs...))
    end
    return triangles
end

CoordinateSystem(g_frame::Frame) = g_frame["cs"]

function _geometry_hash(prem, topography)
    coords = Float64[]
    for s in prem
        push!(coords, ustrip(u"m", s.radius))
    end
    for tri in topography
        for v in (tri.v1, tri.v2, tri.v3)
            append!(coords, ustrip.(u"m", v.point))
        end
    end
    # SHA256 over raw IEEE 754 bytes — stable across Julia versions.
    # Julia's built-in hash() is not stable across minor versions and must not
    # be used for values persisted to disk.
    digest = sha256(reinterpret(UInt8, coords))
    return reinterpret(UInt64, digest[1:8])[1]
end

"""
    build_gcd_bundle(
        vertices, faces, longlat_rad, prem_radii, detector_region
    ) -> TamboFrames

Builds a self-contained GCD bundle from raw mesh data: one G frame (full
terrain), one blank C frame, and one D frame (detector region indices and
pre-built detector BVH).

# Arguments
- `vertices`: (n_verts, 3) matrix of ECEF positions in metres.
- `faces`: (n_faces, 3) matrix of 1-based vertex indices.
- `longlat_rad`: site `(longitude, latitude)` in radians.
- `prem_radii`: PREM layer radii as `Unitful.Length` quantities, outermost last.
- `detector_region`: 1-based face indices selecting the detector sub-region.

Save the result with `save_frames(path, frames, streams=('G','C','D'))` to
produce a JLD2 that downstream runs can load without the original source files.
Use `dump_to_h5` and `dump_to_ply` to export derived HDF5 or binary PLY files.
"""
function build_gcd_bundle(
    vertices        :: Matrix{Float64},
    faces           :: Matrix{<:Integer},
    longlat_rad     :: NTuple{2,Float64},
    prem_radii      :: Vector{<:Unitful.Length},
    detector_region :: Vector{Int}
)
    rearth = prem_radii[end]
    cs     = CoordinateSystem(longlat_rad, rearth)

    center = Coordinate(ecefcoordinates.origin, ecefcoordinates)
    center = convert(cs, center)
    prem   = [Sphere(center, r) for r in prem_radii]

    triangles = _parse_triangles(vertices, faces, cs)
    all(validate_triangle.(triangles, Ref(center))) || throw("Incorrectly oriented triangles")

    bvh = BVHTree(triangles)

    g_frame = Frame('G', Dict{String,Any}(
        "vertices"      => vertices,
        "faces"         => Matrix{Int}(faces),
        "longlat_rad"   => collect(longlat_rad),
        "prem_radii"    => prem_radii,
        "prem"          => prem,
        "topography"    => triangles,
        "bvh"           => bvh,
        "cs"            => cs,
        "geometry_hash" => _geometry_hash(prem, triangles),
    ))

    c_frame = Frame('C', Dict{String,Any}(), Dict{Char,Frame}('G' => g_frame))

    detector_triangles = triangles[detector_region]
    detector_bvh       = BVHTree(detector_triangles)
    d_frame = Frame('D', Dict{String,Any}(
        "detector_region" => detector_region,
        "detector_bvh"    => detector_bvh,
    ), Dict{Char,Frame}('G' => g_frame, 'C' => c_frame))

    return TamboFrames(Frame[g_frame, c_frame, d_frame])
end

"""
    make_watertight(vertices, faces; depth_m=10_000.0) -> (vertices, faces)

Close an open surface mesh by adding a skirt (side walls) and a bottom cap,
inset `depth_m` metres along the radial direction from each boundary vertex.
Returns the inputs unchanged if the mesh is already closed.
"""
function make_watertight(
    vertices :: Matrix{Float64},
    faces    :: Matrix{Int};
    depth_m  :: Real = 10_000.0,
)
    edge_count = Dict{Tuple{Int,Int}, Int}()
    for i in axes(faces, 1)
        for (a, b) in ((faces[i,1], faces[i,2]),
                       (faces[i,2], faces[i,3]),
                       (faces[i,3], faces[i,1]))
            key = minmax(a, b)
            edge_count[key] = get(edge_count, key, 0) + 1
        end
    end
    boundary_edges = [k for (k, v) in edge_count if v == 1]
    isempty(boundary_edges) && return vertices, faces

    adj = Dict{Int, Vector{Int}}()
    for (a, b) in boundary_edges
        push!(get!(adj, a, Int[]), b)
        push!(get!(adj, b, Int[]), a)
    end

    # The walk below assumes a single closed boundary loop with every boundary
    # vertex having exactly 2 boundary-edge neighbors. Fragmented or non-manifold
    # meshes violate this and would walk forever -> OOM. Fail fast instead.
    n_bad = count(nbrs -> length(nbrs) != 2, values(adj))
    if n_bad > 0
        n_boundary_verts = length(adj)
        error("make_watertight: mesh has $n_bad / $n_boundary_verts boundary " *
              "vertices with ≠ 2 boundary-edge neighbors. The mesh is " *
              "fragmented or non-manifold (multiple boundary loops, T-junctions, " *
              "or duplicate/unshared vertices). Boundary-loop walk only supports " *
              "a single closed manifold loop.")
    end

    start = minimum(keys(adj))
    loop  = [start]
    prev  = -1
    cur   = start
    max_iter = length(boundary_edges) + 1
    iter = 0
    while true
        iter += 1
        if iter > max_iter
            error("make_watertight: boundary walk exceeded $max_iter steps " *
                  "without closing. Mesh boundary topology is malformed.")
        end
        nbrs = adj[cur]
        nxt  = nbrs[1] == prev ? nbrs[2] : nbrs[1]
        nxt == start && break
        push!(loop, nxt)
        prev, cur = cur, nxt
    end
    n_loop = length(loop)

    n_old = size(vertices, 1)
    bot_verts = Matrix{Float64}(undef, n_loop, 3)
    for (i, vi) in enumerate(loop)
        v = vertices[vi, :]
        r = norm(v)
        bot_verts[i, :] = v .* ((r - depth_m) / r)
    end
    bot_center = vec(mean(bot_verts, dims=1))

    new_verts      = vcat(vertices, bot_verts, bot_center')
    bot_ring_start = n_old + 1
    bot_center_idx = n_old + n_loop + 1

    side = Matrix{Int}(undef, 2 * n_loop, 3)
    for i in 1:n_loop
        a     = loop[i]
        b     = loop[mod1(i + 1, n_loop)]
        a_bot = bot_ring_start + i - 1
        b_bot = bot_ring_start + mod(i, n_loop)
        side[2i-1, :] = [a, a_bot, b_bot]
        side[2i,   :] = [a, b_bot, b    ]
    end

    bot_cap = Matrix{Int}(undef, n_loop, 3)
    for i in 1:n_loop
        a_bot = bot_ring_start + i - 1
        b_bot = bot_ring_start + mod(i, n_loop)
        bot_cap[i, :] = [a_bot, b_bot, bot_center_idx]
    end

    return new_verts, vcat(faces, side, bot_cap)
end

function _detector_subset_vf(
    vertices        :: Matrix{Float64},
    faces           :: Matrix{<:Integer},
    detector_region :: Vector{Int}
)
    det_faces = faces[detector_region, :]
    used      = sort(unique(vec(det_faces)))
    remap     = Dict(old => new for (new, old) in enumerate(used))
    sub_verts = vertices[used, :]
    sub_faces = [remap[det_faces[i,j]] for i in axes(det_faces,1), j in 1:3]
    return sub_verts, sub_faces
end

function _serialize_corsika_ply(
    vertices :: Matrix{Float64},
    faces    :: Matrix{<:Integer}
)::Vector{UInt8}
    buf = IOBuffer()
    print(buf, "ply\nformat binary_little_endian 1.0\n")
    print(buf, "element vertex $(size(vertices,1))\n")
    print(buf, "property double x\nproperty double y\nproperty double z\n")
    print(buf, "element face $(size(faces,1))\n")
    print(buf, "property list uchar uint vertex_indices\n")
    print(buf, "end_header\n")
    for i in axes(vertices, 1)
        write(buf, htol(vertices[i,1]), htol(vertices[i,2]), htol(vertices[i,3]))
    end
    for i in axes(faces, 1)
        write(buf, UInt8(3),
              htol(UInt32(faces[i,1]-1)),
              htol(UInt32(faces[i,2]-1)),
              htol(UInt32(faces[i,3]-1)))
    end
    return take!(buf)
end

"""
    dump_to_h5(g_frame, d_frame, path, groupname)

Write geometry from a GCD bundle to an HDF5 file under `groupname`. Creates or
overwrites the group; the rest of the file is untouched.
"""
function dump_to_h5(
    g_frame   :: Frame,
    d_frame   :: Frame,
    path      :: String,
    groupname :: String
)
    vertices        = g_frame["vertices"]
    faces           = g_frame["faces"]
    longlat_rad     = g_frame["longlat_rad"]
    prem_radii      = ustrip.(u"m", g_frame["prem_radii"])
    detector_region = d_frame["detector_region"]
    longlat_deg     = rad2deg.(longlat_rad)

    h5open(path, "cw") do f
        haskey(f, groupname) && delete_object(f, groupname)
        grp              = create_group(f, groupname)
        grp["location"]  = Float64[longlat_deg...]
        grp["radii"]     = prem_radii
        grp["vertices"]  = vertices
        grp["faces"]     = faces
        grp["detector1"] = detector_region
    end
end

"""
    dump_to_ply(frame, fname; max_radius_km=nothing, watertight_depth_m=nothing)

Write a binary PLY file for CORSIKA from a G or D frame.

- **G frame**: writes the full terrain mesh. Pass `max_radius_km` to crop faces
  whose centroid exceeds that radius from the site centre. Pass `watertight_depth_m`
  (metres) to close the mesh after cropping.
- **D frame**: writes the detector-region (observation) mesh. Reads vertex/face
  data from the parent G frame. `max_radius_km` and `watertight_depth_m` are unused.
"""
function dump_to_ply(
    frame              :: Frame,
    fname              :: String;
    max_radius_km      :: Union{Real,Nothing} = nothing,
    watertight_depth_m :: Union{Real,Nothing} = nothing
)
    if frame.stream == 'G'
        vertices = frame["vertices"]
        faces    = frame["faces"]

        if !isnothing(max_radius_km)
            longlat = frame["longlat_rad"]
            center  = longlat_to_cart(longlat...) .* ustrip(u"m", frame["prem_radii"][end])
            max_r   = Float64(max_radius_km) * 1_000.0
            kept    = Int[i for i in axes(faces, 1)
                          if norm((vertices[faces[i,1],:] .+
                                   vertices[faces[i,2],:] .+
                                   vertices[faces[i,3],:]) ./ 3 .- center) <= max_r]
            faces    = faces[kept, :]
            used     = sort(unique(vec(faces)))
            remap    = Dict(old => new for (new, old) in enumerate(used))
            vertices = vertices[used, :]
            faces    = [remap[faces[i,j]] for i in axes(faces,1), j in 1:3]
        end

        if !isnothing(watertight_depth_m)
            vertices, faces = make_watertight(vertices, faces; depth_m=watertight_depth_m)
        end

    elseif frame.stream == 'D'
        g               = frame.g_frame
        vertices, faces = _detector_subset_vf(g["vertices"], g["faces"], frame["detector_region"])

    else
        error("dump_to_ply: unsupported frame stream '$(frame.stream)'; expected 'G' or 'D'")
    end

    write(fname, _serialize_corsika_ply(vertices, faces))
end
