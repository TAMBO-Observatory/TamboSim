function _load_earth_h5(location::String, detectorname::String="")
    filename, groupname = split(location, ":")
    h5open(filename) do file
        group = file[groupname]

        longlat = deg2rad.(Tuple(read(group["location"])))
        radii = read(group["radii"]) .* u"m"
        rearth = radii[end]
        cs = CoordinateSystem(longlat, rearth)

        center = Coordinate(ecefcoordinates.origin, ecefcoordinates)
        center = convert(cs, center)
        prem = [Sphere(center, r) for r in radii]

        detector_region = nothing
        if length(detectorname) > 0
            detector_region = read(group[detectorname])
        end

        triangles = parse_triangles(group, cs)
        all(validate_triangle.(triangles, Ref(center))) || throw("Incorrectly oriented triangles")

        bvh = BVHTree(triangles)

        return prem, triangles, bvh, detector_region, cs
    end
end

function _load_earth_ply(path::String)
    vertices, faces, is_in_injection, radii = parse_ply(path)

    radii_m = radii .* u"m"
    rearth = radii_m[end]

    longlat = Tuple(injection_longlat(vertices, faces, is_in_injection))
    cs = CoordinateSystem(longlat, rearth)

    center = Coordinate(ecefcoordinates.origin, ecefcoordinates)
    center = convert(cs, center)
    prem = [Sphere(center, r) for r in radii_m]

    triangles = parse_triangles(vertices, faces, cs)
    all(validate_triangle.(triangles, Ref(center))) || throw("Incorrectly oriented triangles")

    bvh = BVHTree(triangles)
    detector_region = findall(is_in_injection)

    return prem, triangles, bvh, detector_region, cs
end

"""
    injection_longlat(vertices, faces, is_in_injection) -> Vector{Float64}

Computes the area-weighted mean longitude and latitude of the injection region.
"""
function injection_longlat(
    vertices::Matrix{Float64},
    faces::Matrix{Int},
    is_in_injection::BitVector
)
    weighted_sum = zeros(3)
    total_weight = 0.0

    for i in axes(faces, 1)
        is_in_injection[i] || continue
        v1 = vertices[faces[i, 1], :]
        v2 = vertices[faces[i, 2], :]
        v3 = vertices[faces[i, 3], :]
        c = (v1 + v2 + v3) / 3
        a = 0.5 * norm(cross(v2 - v1, v3 - v1))
        weighted_sum .+= a .* c
        total_weight += a
    end

    return cart_to_longlat((weighted_sum ./ total_weight)...)
end

function parse_ply_header(io::IO)
    n_verts = n_faces = n_radii = 0
    while true
        line = readline(io)
        line == "end_header" && break
        parts = split(line)
        if length(parts) == 3 && parts[1] == "element"
            count = parse(Int, parts[3])
            if parts[2] == "vertex"
                n_verts = count
            elseif parts[2] == "face"
                n_faces = count
            elseif parts[2] == "radii"
                n_radii = count
            end
        end
    end
    return n_verts, n_faces, n_radii
end

function parse_ply(path::String)
    open(path, "r") do io
        n_verts, n_faces, n_radii = parse_ply_header(io)

        vertices = Matrix{Float64}(undef, n_verts, 3)
        for i in 1:n_verts
            parts = split(readline(io))
            vertices[i, 1] = parse(Float64, parts[1])
            vertices[i, 2] = parse(Float64, parts[2])
            vertices[i, 3] = parse(Float64, parts[3])
        end

        faces = Matrix{Int}(undef, n_faces, 3)
        is_in_injection = falses(n_faces)
        for i in 1:n_faces
            parts = split(readline(io))
            faces[i, 1] = parse(Int, parts[2]) + 1
            faces[i, 2] = parse(Int, parts[3]) + 1
            faces[i, 3] = parse(Int, parts[4]) + 1
            is_in_injection[i] = parse(Int, parts[5]) != 0
        end

        radii = Vector{Float64}(undef, n_radii)
        for i in 1:n_radii
            radii[i] = parse(Float64, readline(io))
        end

        return vertices, faces, is_in_injection, radii
    end
end

function parse_triangles(
    group::Union{HDF5.File, HDF5.Group},
    cs::CoordinateSystem{T}
)::Vector{Triangle{T}} where {T}
    return parse_triangles(read(group["vertices"]), read(group["faces"]), cs)
end

function parse_triangles(
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

"""
    load_earth!(g_frame::Frame)

Reads geometry from `g_frame["earth_path"]` and populates the G frame with:

- `"prem"`: `Vector{Sphere}` — concentric PREM layers for ray tracing
- `"topography"`: `Vector{Triangle}` — surface mesh
- `"bvh"`: `BVHTree` — acceleration structure over the full topography
- `"cs"`: `CoordinateSystem` — local ENU coordinate system at the site

Detector region data is NOT stored here; it belongs in the D frame.
Dispatches to HDF5 or PLY loading based on the file extension of `earth_path`.
For HDF5 files, also reads `g_frame["detector_key"]` if present (legacy path).
"""
function load_earth!(g_frame::Frame)
    location = g_frame["earth_path"]
    prem, topography, bvh, _, cs = if endswith(location, ".ply")
        _load_earth_ply(location)
    else
        detectorname = haskey(g_frame.data, "detector_key") ? g_frame.data["detector_key"] : ""
        _load_earth_h5(location, detectorname)
    end
    new_hash = _geometry_hash(prem, topography)
    if haskey(g_frame.data, "geometry_hash") && g_frame["geometry_hash"] != new_hash
        @warn "geometry_hash mismatch for $(location): stored hash does not match reloaded geometry. The file may have changed since the JLD2 was written."
    end
    g_frame["prem"]          = prem
    g_frame["topography"]    = topography
    g_frame["bvh"]           = bvh
    g_frame["cs"]            = cs
    g_frame["geometry_hash"] = new_hash
    return g_frame
end

CoordinateSystem(g_frame::Frame) = g_frame["cs"]

"""
    _ensure_geometry_hash!(g_frame::Frame)

If `g_frame` has prem and topography but no `geometry_hash`, derive and store
it. Defensive fallback for legacy fixtures saved before `build_gcd_bundle`
started baking the hash in.
"""
function _ensure_geometry_hash!(g_frame::Frame)
    haskey(g_frame.data, "geometry_hash") && return
    haskey(g_frame.data, "prem") && haskey(g_frame.data, "topography") || return
    g_frame["geometry_hash"] = _geometry_hash(g_frame["prem"], g_frame["topography"])
end

"""
    _ensure_earth_loaded!(frames::TamboFrames)

Ensures the G frame has earth geometry loaded. Calls `load_earth!` if prem is missing.
"""
function _ensure_earth_loaded!(frames::TamboFrames)
    g_frame = _get_last_frame(frames, 'G')
    if !haskey(g_frame.data, "prem")
        load_earth!(g_frame)
    end
    _ensure_geometry_hash!(g_frame)
end

"""
    build_gcd_bundle(earth_path, detector_key) -> TamboFrames

Builds a self-contained GCD bundle: one G frame (full terrain), one blank C
frame (placeholder for future calibration data), and one D frame (detector
region indices and pre-built detector BVH).

Save the result with `save_frames(path, frames, streams=('G','C','D'))` to
produce a JLD2 that downstream runs can load without the original HDF5 file.
"""
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

function build_gcd_bundle(earth_path::String, detector_key::String)
    prem, topography, bvh, detector_region, cs = if endswith(earth_path, ".ply")
        _load_earth_ply(earth_path)
    else
        _load_earth_h5(earth_path, detector_key)
    end

    g_frame = Frame('G', Dict{String,Any}(
        "earth_path"    => earth_path,
        "prem"          => prem,
        "topography"    => topography,
        "bvh"           => bvh,
        "cs"            => cs,
        "geometry_hash" => _geometry_hash(prem, topography),
    ))

    c_frame = Frame('C', Dict{String,Any}(), Dict{Char,Frame}('G' => g_frame))

    detector_triangles = topography[detector_region]
    detector_bvh       = BVHTree(detector_triangles)
    d_frame = Frame('D', Dict{String,Any}(
        "detector_region" => detector_region,
        "detector_bvh"    => detector_bvh,
    ), Dict{Char,Frame}('G' => g_frame, 'C' => c_frame))

    return TamboFrames(Frame[g_frame, c_frame, d_frame])
end
