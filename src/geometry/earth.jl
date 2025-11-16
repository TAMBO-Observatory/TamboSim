struct Earth{T <: Real, U}
    sphere::Sphere{T, U}
    topography::Vector{Triangle{T, U}}
end

function Base.show(io::IO, earth::Earth)
    print(io, "Earth:\n\t$(earth.sphere.radius)\n\t$(length(earth.topography)) triangles")
end

#function Earth(location::String)
#
#    sphere, triangles = parse_earth_file(location)
#    triangles = [
#        Triangle([Coordinate(x...) for x in y]...) for y in triangles
#    ]
#    
#    earth = Earth(sphere, triangles)
#    return earth
#end

function Earth(location::String, longlat::Tuple{Float64, Float64})
    rearth, vertices, faces = parse_earth_file(location)
    rearth = rearth * units.m
    enu_coordinates = CoordinateSystem(longlat, rearth)

    center = convert(
        enu_coordinates,
        Coordinate(
            ecefcoordinates.origin,
            ecefcoordinates
        )
    )
    sphere = Sphere(center, rearth)

    #x = Coordinate(enu_coordinates.origin, ecefcoordinates)
    
    T = typeof(one(rearth))
    U = typeof(u"m").parameters[2]
    triangles = Triangle{T, U}[]
    for idxs in eachrow(faces)
        vs = []
        for idx in idxs
            v = Coordinate(
                SVector{3}(vertices[idx, :] * units.m),
                ecefcoordinates
            )

            v = convert(enu_coordinates, v)
            push!(vs, v)
        end
            
        push!(triangles, Triangle(vs...))
    end
    earth = Earth(sphere, triangles)
    return earth
end

function parse_earth_file(location::String)
    filename, groupname = split(location, ":")
    rearth, vertices, faces= h5open(filename) do h5f
       group = h5f[groupname]
       rearth = Float64(attrs(group)["rearth"])
       vertices = group["vertices"][:, :]
       faces = group["faces"][:, :]
       rearth, vertices, faces
    end
    return rearth, vertices, faces
end
