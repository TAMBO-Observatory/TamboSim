struct Earth{T <: Real, U}
    sphere::Sphere{T, U}
    topography::Vector{Triangle{T, U}}
    bvh::BVHTree{T, U}
    detector_region::Union{Vector{Int}, Nothing}
end

function Base.show(io::IO, earth::Earth)
    print(io, "Earth:\n\t$(earth.sphere.radius)\n\t$(length(earth.topography)) triangles")
end

function Earth(location::String, detectorname::String="")
    filename, groupname = split(location, ":")
    earth = h5open(filename) do file
        group = file[groupname]

        longlat = deg2rad.(Tuple(read(group["location"])))
        rearth = read(group["rearth"]) * u"m"
        # Construct coordinate system
        enu_coordinates = CoordinateSystem(longlat, rearth)

        # Make sphere that defines limits of PREM
        center = Coordinate(ecefcoordinates.origin, ecefcoordinates)
        center = convert(enu_coordinates, center)
        sphere = Sphere(center, rearth)

        # Load indices corresponding to detector region if applicable
        detector_region = nothing
        if length(detectorname) > 0
            detector_region = read(group[detectorname])
        end

        # Load mesh
        triangles = parse_triangles(group, enu_coordinates)
        all(validate_triangle.(triangles, Ref(center))) || throw("Incorrectly oriented trinagles")

        # Construct or load BVH
        bvh = parse_bvh(group, enu_coordinates, triangles)

        return Earth(sphere, triangles, bvh, detector_region)
    end
end

function parse_bvh(
    group::Union{HDF5.File, HDF5.Group},
    cs::CoordinateSystem{T,U},
    triangles::Vector{Triangle{T,U}}
)::BVHTree{T,U} where {T,U}
    if "bvh" in keys(group)
        return deserialize_bvh_from_hdf5(group["bvh"], triangles)
         
    else
        println("Computing BVH from scratch.")
        bvh = build_bvh(triangles)
        println("Saving BVH to `$(realpath(filename)):$(groupname)/bvh`")
        group = create_group(group, "bvh")
        serialize_bvh_to_hdf5(bvh, group, false)
        return bvh
    end
end

function parse_triangles(
    group::Union{HDF5.File, HDF5.Group},
    cs::CoordinateSystem{T,U}
)::Vector{Triangle{T,U}} where {T,U}
    vertices = read(group["vertices"])
    faces = read(group["faces"])
    vertices, faces

    triangles = Triangle{T, U}[]
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
