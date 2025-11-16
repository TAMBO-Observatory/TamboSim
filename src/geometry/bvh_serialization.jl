function serialize_bvh_to_hdf5(
    bvh::BVHTree{T,U},
    location::Union{HDF5.File, HDF5.Group},
    serialize_triangle=true
) where {T,U}
    # Store metadata
    location["metadata/type"] = "BVHTree"
    location["metadata/num_triangles"] = length(bvh.triangles)
    
    # Serialize all triangles first
    if serialize_triangle
        serialize_triangles(location, bvh.triangles)
    end
    
    # Serialize BVH tree structure
    serialize_bvh_node(location, bvh.root, "root")
end

function serialize_bvh_to_hdf5(bvh::BVHTree{T,U}, location::String) where {T,U}
    """
    Serialize a BVHTree to HDF5 format.
    """
    filename, groupname = split(location, ":")
    
    if !isfile(filename)
        h5open(filename, "w") do _
        end
    else
        a, b = dirname(groupname), basename(groupname)
        h5open(filename, "r+") do file
            if length(a) > 0 && ~(a in keys(file))
                create_group(file, a)
            end
            group = length(a) > 0 ? file[a] : file
            if b in keys(group)
                delete_object(group[b])
            end
        end 
    end

    h5open(filename, "r+") do file
        group = create_group(file, groupname)
        serialize_bvh_to_hdf5(bvh, group)
    end
end

function serialize_triangles(group, triangles::Vector{Triangle{T,U}}) where {T,U}
    """
    Serialize all triangles to HDF5.
    """
    num_triangles = length(triangles)
    
    # Create datasets for triangle vertices
    vertices = Matrix{T}(undef, 3, 3 * num_triangles)
    
    for (i, tri) in enumerate(triangles)
        v1 = convert(ecefcoordinates, tri.v1)
        v2 = convert(ecefcoordinates, tri.v2)
        v3 = convert(ecefcoordinates, tri.v3)
        vertices[:, (i-1)*3 + 1] = ustrip.(v1.point)
        vertices[:, (i-1)*3 + 2] = ustrip.(v2.point)
        vertices[:, (i-1)*3 + 3] = ustrip.(v3.point)
    end
    
    group["triangles/vertices"] = vertices
    group["triangles/num_triangles"] = num_triangles
end

function serialize_bvh_node(base_group, node::BVHNode{T,U}, path::String) where {T,U}
    """
    Recursively serialize a BVH node to HDF5.
    """
    group = create_group(base_group, path)
    
    # Store AABB
    mincoord = convert(ecefcoordinates, node.bbox.min)
    maxcoord = convert(ecefcoordinates, node.bbox.max)
    group["bbox/min"] = Vector(ustrip.(mincoord.point))
    group["bbox/max"] = Vector(ustrip.(maxcoord.point))
    
    # Store node properties
    group["is_leaf"] = node.is_leaf
    group["triangles"] = collect(node.triangles)  # Convert to regular array
    
    # Recursively serialize children
    if !node.is_leaf
        if node.left !== nothing
            serialize_bvh_node(base_group, node.left, joinpath(path, "left"))
        end
        if node.right !== nothing
            serialize_bvh_node(base_group, node.right, joinpath(path, "right"))
        end
    end
end

function deserialize_bvh_from_hdf5(location::String, cs::CoordinateSystem)::BVHTree
    """
    Deserialize a BVHTree from HDF5 file.
    """
    filename, groupname = split(location, ":")

    h5open(filename, "r") do file
        group = file[groupname]
        return deserialize_bvh_from_hdf5(group, cs)
    end

end

function deserialize_bvh_from_hdf5(
    location::Union{HDF5.File, HDF5.Group},
    cs::CoordinateSystem{T,U}
)::BVHTree{T,U} where {T,U}
    """
    Deserialize a BVHTree from HDF5 file.
    """
    # Deserialize triangles
    triangles = deserialize_triangles(location, cs)
    @show length(triangles)
    display(first(triangles))

    # Deserialize BVH tree
    root = deserialize_bvh_node(location, "root", triangles, cs)

    return BVHTree(root, triangles)
end

function deserialize_bvh_from_hdf5(
    location::Union{HDF5.File, HDF5.Group},
    triangles::Vector{Triangle{T, U}},
)::BVHTree{T,U} where {T,U}
    """
    Deserialize a BVHTree from HDF5 file.
    """
    cs = CoordinateSystem(first(triangles))

    root = deserialize_bvh_node(location, "root", triangles, cs)

    return BVHTree(root, triangles)
end

function deserialize_triangles(group, cs::CoordinateSystem{T, U})::Vector{Triangle{T, U}} where {T, U}
    """
    Deserialize triangles from HDF5.
    """
    vertices = read(group["triangles/vertices"])
    num_triangles = read(group["triangles/num_triangles"])

    triangles = Vector{Triangle}(undef, num_triangles)

    for i in 1:num_triangles
        v1 = Coordinate(SVector{3}(vertices[:, (i-1)*3 + 1]) * u"m", ecefcoordinates)
        v2 = Coordinate(SVector{3}(vertices[:, (i-1)*3 + 2]) * u"m", ecefcoordinates)
        v3 = Coordinate(SVector{3}(vertices[:, (i-1)*3 + 3]) * u"m", ecefcoordinates)
        v1, v2, v3 = convert(cs, v1), convert(cs, v2), convert(cs, v3)

        triangles[i] = Triangle(v1, v2, v3)
    end

    return triangles
end

function deserialize_bvh_node(
    base_group,
    path::String,
    triangles::Vector{Triangle{T, U}},
    cs::CoordinateSystem{T, U}
)::BVHNode{T, U} where {T, U}
    """
    Recursively deserialize a BVH node from HDF5.
    """
    group = base_group[path]

    # Read AABB
    min_coord = read(group["bbox/min"])
    max_coord = read(group["bbox/max"])

    bbox = AABB(
        convert(cs, Coordinate(SVector{3}(min_coord) * u"m", ecefcoordinates)),
        convert(cs, Coordinate(SVector{3}(max_coord) * u"m", ecefcoordinates)),
    )

    # Read node properties
    is_leaf = read(group["is_leaf"])
    triangle_indices = read(group["triangles"])

    # Handle children
    left_node = nothing
    right_node = nothing

    if !is_leaf
        if haskey(group, "left")
            left_node = deserialize_bvh_node(base_group, joinpath(path, "left"), triangles, cs)
        end
        if haskey(group, "right")
            right_node = deserialize_bvh_node(base_group, joinpath(path, "right"), triangles, cs)
        end
    end

    return BVHNode(bbox, left_node, right_node, triangle_indices, is_leaf)
end
