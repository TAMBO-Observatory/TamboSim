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

Constructs an `Earth` object by loading data from an HDF5 file.

This constructor reads geographical and geological data, including PREM layers and
surface topography (as a mesh of triangles), from a specified HDF5 file.
It then constructs a `BVHTree` for efficient spatial querying.

# Arguments
- `location::String`: A string indicating the path to the HDF5 file and the group name
  within it (e.g., "data.h5:earth_model").
- `detectorname::String`: An optional name for a detector region within the HDF5 group.
  If provided, indices corresponding to this region in the topography will be loaded.

# Returns
- A new `Earth` object.
"""
function Earth(location::String, detectorname::String="")
    filename, groupname = split(location, ":")
    earth = h5open(filename) do file
        group = file[groupname]

        longlat = deg2rad.(Tuple(read(group["location"])))
        radii = read(group["radii"]) .* u"m"
        rearth = radii[end]
        # Construct coordinate system
        enu_coordinates = CoordinateSystem(longlat, rearth)

        # Make sphere that defines limits of PREM
        center = Coordinate(ecefcoordinates.origin, ecefcoordinates)
        center = convert(enu_coordinates, center)
        prem = [Sphere(center, r) for r in radii]

        # Load indices corresponding to detector region if applicable
        detector_region = nothing
        if length(detectorname) > 0
            detector_region = read(group[detectorname])
        end

        # Load mesh
        triangles = parse_triangles(group, enu_coordinates)
        all(validate_triangle.(triangles, Ref(center))) || throw("Incorrectly oriented trinagles")

        # Construct or load BVH
        bvh = BVHTree(triangles)

        return Earth(prem, triangles, bvh, detector_region)
    end
end

"""
    parse_triangles(group::Union{HDF5.File, HDF5.Group}, cs::CoordinateSystem{T}) -> Vector{Triangle{T}}

Parses triangle data (vertices and faces) from an HDF5 group and constructs `Triangle` objects.

The vertices are read, converted to the specified `CoordinateSystem`, and then assembled
into `Triangle` objects based on the face indices.

# Arguments
- `group`: An HDF5 file or group object containing "vertices" and "faces" datasets.
- `cs::CoordinateSystem{T}`: The target coordinate system for the constructed triangles.

# Returns
- A `Vector{Triangle{T}}` representing the parsed mesh.
"""
function parse_triangles(
    group::Union{HDF5.File, HDF5.Group},
    cs::CoordinateSystem{T}
)::Vector{Triangle{T}} where {T}
    vertices = read(group["vertices"])
    faces = read(group["faces"])
    vertices, faces

    triangles = Triangle{T}[]
    for idxs in eachrow(faces)
        vs = []
        for idx in idxs
            v = Coordinate(
                vertices[idx, :] .* u"m",
                ecefcoordinates
            )
            v = convert(cs, v)
            push!(vs, v)
        end
            
        push!(triangles, Triangle(vs...))
    end
    return triangles
end
