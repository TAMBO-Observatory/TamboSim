"""
    serialize_bvh_to_hdf5(
        bvh::BVHTree{T,U},
        location::Union{HDF5.File, HDF5.Group},
        serialize_triangle=true
    ) where {T,U}

Serializes a `BVHTree` object to an HDF5 file or group.

This function stores the metadata, triangles (optional), and the tree structure
of the `BVHTree` into the specified HDF5 location.

# Arguments
- `bvh::BVHTree`: The `BVHTree` object to serialize.
- `location`: An HDF5 file or group object where the data will be stored.
- `serialize_triangle`: If `true`, the triangles themselves are also serialized.
  Set to `false` if the triangles are already stored elsewhere.
"""
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

"""
    serialize_bvh_to_hdf5(bvh::BVHTree{T,U}, location::String) where {T,U}

Serializes a `BVHTree` to a specified path in an HDF5 file.

This is a convenience method that handles opening the HDF5 file and creating the
necessary groups. The `location` string should be in the format "filename:groupname".

# Arguments
- `bvh::BVHTree`: The `BVHTree` to serialize.
- `location::String`: A string specifying the file and group path (e.g., "mydata.h5:geometry/bvh").
"""
function serialize_bvh_to_hdf5(bvh::BVHTree{T,U}, location::String) where {T,U}
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

"""
    serialize_triangles(group, triangles::Vector{Triangle{T,U}}) where {T,U}

Serializes a vector of `Triangle` objects to an HDF5 group.

The vertices of all triangles are stored in a single large matrix for efficiency.

# Arguments
- `group`: The HDF5 group to store the triangle data in.
- `triangles`: A vector of `Triangle` objects.
"""
function serialize_triangles(group, triangles::Vector{Triangle{T,U}}) where {T,U}
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

"""
    serialize_bvh_node(base_group, node::BVHNode{T,U}, path::String) where {T,U}

Recursively serializes a `BVHNode` and its children to an HDF5 group.

# Arguments
- `base_group`: The parent HDF5 group.
- `node::BVHNode`: The node to serialize.
- `path::String`: The path within the `base_group` where this node will be stored.
"""
function serialize_bvh_node(base_group, node::BVHNode{T,U}, path::String) where {T,U}
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

"""
    deserialize_bvh_from_hdf5(location::String, cs::CoordinateSystem) -> BVHTree

Deserializes a `BVHTree` from a specified path in an HDF5 file.

This is a convenience method that handles opening the HDF5 file. The `location`
string should be in the format "filename:groupname".

# Arguments
- `location::String`: The path to the HDF5 file and group (e.g., "mydata.h5:geometry/bvh").
- `cs::CoordinateSystem`: The coordinate system to which the `BVHTree` should be transformed.

# Returns
- A `BVHTree` object.
"""
function deserialize_bvh_from_hdf5(location::String, cs::CoordinateSystem)::BVHTree
    filename, groupname = split(location, ":")

    h5open(filename, "r") do file
        group = file[groupname]
        return deserialize_bvh_from_hdf5(group, cs)
    end

end

"""
    deserialize_bvh_from_hdf5(
        location::Union{HDF5.File, HDF5.Group},
        cs::CoordinateSystem{T,U}
    )::BVHTree{T,U} where {T,U}

Deserializes a `BVHTree` from an HDF5 file or group.

This function reads the `BVHTree` data, including triangles and the node structure,
from the specified HDF5 location and reconstructs the `BVHTree` object.

# Arguments
- `location`: An HDF5 file or group object.
- `cs::CoordinateSystem`: The coordinate system for the reconstructed `BVHTree`.

# Returns
- A `BVHTree` object.
"""
function deserialize_bvh_from_hdf5(
    location::Union{HDF5.File, HDF5.Group},
    cs::CoordinateSystem{T,U}
)::BVHTree{T,U} where {T,U}
    # Deserialize triangles
    triangles = deserialize_triangles(location, cs)
    @show length(triangles)
    display(first(triangles))

    # Deserialize BVH tree
    root = deserialize_bvh_node(location, "root", triangles, cs)

    return BVHTree(root, triangles)
end

"""
    deserialize_bvh_from_hdf5(
        location::Union{HDF5.File, HDF5.Group},
        triangles::Vector{Triangle{T, U}},
    )::BVHTree{T,U} where {T,U}

Deserializes a `BVHTree` from HDF5, using a pre-existing vector of triangles.

This version is used when the triangles are not serialized with the `BVHTree` itself.
It deserializes the node structure and links it to the provided triangle vector.

# Arguments
- `location`: An HDF5 file or group object containing the `BVHNode` data.
- `triangles`: The vector of `Triangle` objects to be used by the `BVHTree`.

# Returns
- A `BVHTree` object.
"""
function deserialize_bvh_from_hdf5(
    location::Union{HDF5.File, HDF5.Group},
    triangles::Vector{Triangle{T, U}},
)::BVHTree{T,U} where {T,U}
    cs = CoordinateSystem(first(triangles))

    root = deserialize_bvh_node(location, "root", triangles, cs)

    return BVHTree(root, triangles)
end

"""
    deserialize_triangles(group, cs::CoordinateSystem{T, U})::Vector{Triangle{T, U}} where {T, U}

Deserializes a vector of `Triangle` objects from an HDF5 group.

# Arguments
- `group`: The HDF5 group containing the triangle data.
- `cs::CoordinateSystem`: The coordinate system to apply to the triangles.

# Returns
- A vector of `Triangle` objects.
"""
function deserialize_triangles(group, cs::CoordinateSystem{T, U})::Vector{Triangle{T, U}} where {T, U}
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

"""
    deserialize_bvh_node(
        base_group,
        path::String,
        triangles::Vector{Triangle{T, U}},
        cs::CoordinateSystem{T, U}
    )::BVHNode{T, U} where {T, U}

Recursively deserializes a `BVHNode` and its children from an HDF5 group.

# Arguments
- `base_group`: The parent HDF5 group.
- `path::String`: The path to the node's data within the `base_group`.
- `triangles`: The vector of all triangles in the `BVHTree`.
- `cs::CoordinateSystem`: The target coordinate system.

# Returns
- A reconstructed `BVHNode` object.
"""
function deserialize_bvh_node(
    base_group,
    path::String,
    triangles::Vector{Triangle{T, U}},
    cs::CoordinateSystem{T, U}
)::BVHNode{T, U} where {T, U}
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
