"""
    Earth{T<:Real}

Represents the Earth model, including its layered structure (PREM), surface topography,
and an associated Bounding Volume Hierarchy (BVH) for efficient ray tracing.

# Fields
- `prem::Vector{Sphere{T}}`: A vector of `Sphere` objects representing the concentric layers of the Earth (PREM model).
- `topography::Vector{Triangle{T}}`: A vector of `Triangle` objects representing the Earth's surface topography.
- `bvh::BVHTree{T, Triangle{T}}`: A Bounding Volume Hierarchy built from the `topography` for accelerated intersection tests.
- `detector_region::Union{Vector{Int}, Nothing}`: Optional indices into the `topography` vector, marking triangles that belong to a detector region.

# Constructors
- `Earth(prem, topography, bvh, detector_region)`: Primary constructor that validates coordinate system consistency.
"""
struct Earth{T<:Real}
    prem::Vector{Sphere{T}}
    topography::Vector{Triangle{T}}
    bvh::BVHTree{T, Triangle{T}}
    detector_region::Union{Vector{Int}, Nothing}
    function Earth(
        prem::Vector{Sphere{T}},
        topography::Vector{Triangle{T}},
        bvh::BVHTree{T, Triangle{T}},
        detector_region::Union{Vector{Int},Nothing}
    ) where {T<:Real}
        cs_prem = CoordinateSystem(prem[1])
        @assert all([CoordinateSystem(sphere)==cs_prem for sphere in prem]) "Incompatible coordinate systems"
        cs_topo = CoordinateSystem(topography[1])
        @assert all([CoordinateSystem(tri)==cs_topo for tri in topography]) "Incompatible coordinate systems"
        @assert cs_prem==cs_topo==CoordinateSystem(bvh) "Incompatible coordinate systems"
        return new{T}(prem, topography, bvh, detector_region)
    end
end

"""
    CoordinateSystem(earth::Earth) -> CoordinateSystem

Retrieves the `CoordinateSystem` of the `Earth` model.

This function extracts the coordinate system from the first PREM layer, assuming
all components of the `Earth` model share the same coordinate system.

# Arguments
- `earth::Earth`: The `Earth` object.

# Returns
- The `CoordinateSystem` of the Earth model.
"""
function CoordinateSystem(earth::Earth)
    return CoordinateSystem(earth.prem[1])
end

"""
    Base.show(io::IO, earth::Earth)

Prints a concise summary of the `Earth` object to the given I/O stream.

The summary includes the number of PREM layers and the number of topography triangles.

# Arguments
- `io::IO`: The I/O stream to write to.
- `earth::Earth`: The `Earth` object to display.
"""
function Base.show(io::IO, earth::Earth)
    print(io, "Earth:\n\t$(length(earth.prem)) layers\n\t$(length(earth.topography)) triangles")
end

"""
    Earth(location::String, detectorname::String="") -> Earth

Constructs an `Earth` object from either an HDF5 file or a PLY file, dispatching
based on the file extension.

For HDF5, `location` must be of the form `"file.h5:groupname"`. The optional
`detectorname` names a dataset within the group whose integer indices mark the
detector region in the topography.

For PLY, `location` is a plain path to a `.ply` file. The injection region and
radii are read from custom PLY elements embedded in the file, and `detectorname`
is ignored.

# Arguments
- `location::String`: Path to the data file.
- `detectorname::String`: HDF5 only — name of the detector-region dataset within the group.

# Returns
- A new `Earth` object.
"""
function Earth(location::String, detectorname::String="")
    if endswith(location, ".ply")
        return earth_from_ply(location)
    else
        return earth_from_h5(location, detectorname)
    end
end

"""
    earth_from_h5(location::String, detectorname::String="") -> Earth

Constructs an `Earth` object by loading data from an HDF5 file.

# Arguments
- `location::String`: Path and group name in the form `"file.h5:groupname"`.
- `detectorname::String`: Optional name of a detector-region dataset within the group.

# Returns
- A new `Earth` object.
"""
function earth_from_h5(location::String, detectorname::String="")
    filename, groupname = split(location, ":")
    h5open(filename) do file
        group = file[groupname]

        longlat = deg2rad.(Tuple(read(group["location"])))
        radii = read(group["radii"]) .* u"m"
        rearth = radii[end]
        enu_coordinates = CoordinateSystem(longlat, rearth)

        center = Coordinate(ecefcoordinates.origin, ecefcoordinates)
        center = convert(enu_coordinates, center)
        prem = [Sphere(center, r) for r in radii]

        detector_region = nothing
        if length(detectorname) > 0
            detector_region = read(group[detectorname])
        end

        triangles = parse_triangles(group, enu_coordinates)
        all(validate_triangle.(triangles, Ref(center))) || throw("Incorrectly oriented triangles")

        bvh = BVHTree(triangles)

        return Earth(prem, triangles, bvh, detector_region)
    end
end

"""
    earth_from_ply(path::String) -> Earth

Constructs an `Earth` object by loading a mesh from a PLY file.

The PLY file is expected to contain:
- `vertex` elements with `x`, `y`, `z` properties (ECEF coordinates in metres).
- `face` elements with `vertex_indices` and an `is_in_injection` (uchar) property.
- A custom `radii` element with a `value` property (metres).

The location (longitude/latitude) of the coordinate system origin is derived as the
area-weighted mean of the centroids of all triangles flagged as `is_in_injection`.

# Arguments
- `path::String`: Path to the `.ply` file.

# Returns
- A new `Earth` object.
"""
function earth_from_ply(path::String)
    vertices, faces, is_in_injection, radii = parse_ply(path)

    radii_m = radii .* u"m"
    rearth = radii_m[end]

    longlat = Tuple(injection_longlat(vertices, faces, is_in_injection))
    enu_coordinates = CoordinateSystem(longlat, rearth)

    center = Coordinate(ecefcoordinates.origin, ecefcoordinates)
    center = convert(enu_coordinates, center)
    prem = [Sphere(center, r) for r in radii_m]

    triangles = parse_triangles(vertices, faces, enu_coordinates)
    all(validate_triangle.(triangles, Ref(center))) || throw("Incorrectly oriented triangles")

    bvh = BVHTree(triangles)

    detector_region = findall(is_in_injection)

    return Earth(prem, triangles, bvh, detector_region)
end

"""
    injection_longlat(vertices, faces, is_in_injection) -> Vector{Float64}

Computes the area-weighted mean longitude and latitude of the injection region.

For each face flagged in `is_in_injection`, the centroid and area are computed in
raw ECEF space (metres). The weighted mean ECEF position is then converted to
`[longitude, latitude]` in radians.

# Arguments
- `vertices::Matrix{Float64}`: `(n_verts, 3)` ECEF vertex positions in metres.
- `faces::Matrix{Int}`: `(n_faces, 3)` 1-based vertex indices.
- `is_in_injection::BitVector`: Mask over faces.

# Returns
- `Vector{Float64}` of length 2: `[longitude, latitude]` in radians.
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

"""
    parse_ply_header(io::IO) -> (n_verts, n_faces, n_radii)

Reads lines from `io` up to and including `end_header`, returning the element counts
for `vertex`, `face`, and `radii` elements.
"""
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

"""
    parse_ply(path::String) -> (vertices, faces, is_in_injection, radii)

Parses an ASCII PLY file written by the TAMBO-MC exporter.

Face vertex indices are converted from 0-based (PLY) to 1-based (Julia).

# Returns
- `vertices::Matrix{Float64}`: `(n_verts, 3)`
- `faces::Matrix{Int}`: `(n_faces, 3)`, 1-based
- `is_in_injection::BitVector`: `(n_faces,)`
- `radii::Vector{Float64}`: `(n_radii,)`
"""
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
            # PLY face line: "3 a b c flag" (0-based indices)
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

"""
    parse_triangles(group::Union{HDF5.File, HDF5.Group}, cs::CoordinateSystem{T}) -> Vector{Triangle{T}}

Parses triangle data from an HDF5 group and constructs `Triangle` objects.

# Arguments
- `group`: HDF5 file or group containing `"vertices"` and `"faces"` datasets.
- `cs::CoordinateSystem{T}`: Target coordinate system for the triangles.
"""
function parse_triangles(
    group::Union{HDF5.File, HDF5.Group},
    cs::CoordinateSystem{T}
)::Vector{Triangle{T}} where {T}
    return parse_triangles(read(group["vertices"]), read(group["faces"]), cs)
end

"""
    parse_triangles(vertices, faces, cs::CoordinateSystem{T}) -> Vector{Triangle{T}}

Constructs `Triangle` objects from raw vertex and face arrays.

Vertices are assumed to be ECEF coordinates in metres. Face indices are 1-based.

# Arguments
- `vertices::Matrix{<:Real}`: `(n_verts, 3)` ECEF positions in metres.
- `faces::Matrix{<:Integer}`: `(n_faces, 3)` 1-based vertex indices.
- `cs::CoordinateSystem{T}`: Target coordinate system.
"""
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
