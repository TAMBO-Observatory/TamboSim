struct Earth{T <: Real}
    prem::Vector{Sphere{T}}
    topography::Vector{Triangle{T}}
    bvh::BVHTree{T}
    detector_region::Union{Vector{Int}, Nothing}
    function Earth(prem::Vector{Sphere{T}}, topography::Vector{Triangle{T}}, bvh::BVHTree{T}, detector_region::Union{Vector{Int},Nothing}) where {T<:Real}
        cs_prem = CoordinateSystem(prem[1])
        @assert all([CoordinateSystem(sphere)==cs_prem for sphere in prem]) "Incompatible coordinate systems"
        cs_topo = CoordinateSystem(topography[1])
        @assert all([CoordinateSystem(tri)==cs_topo for tri in topography]) "Incompatible coordinate systems"
        @assert cs_prem==cs_topo==CoordinateSystem(bvh) "Incompatible coordinate systems"
        return new{T}(prem, topography, bvh, detector_region)
    end
end

function CoordinateSystem(earth::Earth)
    return CoordinateSystem(earth.prem[1])
end

function Base.show(io::IO, earth::Earth)
    print(io, "Earth:\n\t$(length(earth.prem)) layers\n\t$(length(earth.topography)) triangles")
end

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
        bvh = build_bvh(triangles)

        return Earth(prem, triangles, bvh, detector_region)
    end
end

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
