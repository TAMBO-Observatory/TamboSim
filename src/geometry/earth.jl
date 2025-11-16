struct Earth{T <: Real, U}
    sphere::Sphere{T, U}
    topography::Vector{Triangle{T, U}}
    bvh::BVHTree{T, U}
end

function Base.show(io::IO, earth::Earth)
    print(io, "Earth:\n\t$(earth.sphere.radius)\n\t$(length(earth.topography)) triangles")
end

function Earth(location::String, longlat::Tuple{Float64, Float64}, rearth=6_378_000.0*u"m")
    enu_coordinates = CoordinateSystem(longlat, rearth)
    vertices, faces = parse_triangles(location)

    center = convert(
        enu_coordinates,
        Coordinate(
            ecefcoordinates.origin,
            ecefcoordinates
        )
    )
    sphere = Sphere(center, rearth)
    
    T = typeof(one(rearth))
    U = typeof(u"m").parameters[2]
    triangles = Triangle{T, U}[]
    for idxs in eachrow(faces)
        vs = []
        for idx in idxs
            v = Coordinate(
                SVector{3}(vertices[idx, :] * u"m"),
                ecefcoordinates
            )

            v = convert(enu_coordinates, v)
            push!(vs, v)
        end
            
        push!(triangles, Triangle(vs...))
    end
    bvh = parse_bvh(location, enu_coordinates, triangles)

    earth = Earth(sphere, triangles, bvh)
    return earth
end

function parse_bvh(
    location::String,
    cs::CoordinateSystem{T,U},
    triangles::Vector{Triangle{T,U}}
) where {T,U}
    filename, groupname = split(location, ":")
    bvh = h5open(filename, "r+") do file
        group = file[groupname]
        bhv = nothing
        if "bvh" in keys(group)
            bvh = deserialize_bvh_from_hdf5(group["bvh"], triangles)
        else
            println("Computing BVH from scratch.")
            bvh = build_bvh(triangles)
            println("Saving BVH to `$(realpath(filename)):$(groupname)/bvh`")
            group = create_group(group, "bvh")
            serialize_bvh_to_hdf5(bvh, group, false)
        end
        bvh
    end
    return bvh
end

function parse_triangles(location::String)
    filename, groupname = split(location, ":")
    vertices, faces= h5open(filename) do file
       group = file[groupname]
       vertices = group["vertices"][:, :]
       faces = group["faces"][:, :]
       vertices, faces
    end
    return vertices, faces
end
