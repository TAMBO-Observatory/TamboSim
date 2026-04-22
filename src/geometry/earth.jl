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
