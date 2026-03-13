"""
Export CORSIKA-compatible binary PLY meshes from resources/basic_geometry.h5.

Two files are produced:
  resources/terrain_corsika.ply          — full terrain mesh
  resources/injection_region_corsika.ply — injection region triangles only

CORSIKA requires binary_little_endian PLY. Vertex coordinates are written as
Float64 (double); face lists use a UInt8 count followed by UInt32 indices
(0-based). Custom properties (is_in_injection, radii) are omitted since
CORSIKA ignores unknown elements and cleanliness is preferred.

Water-tightness note
--------------------
The injection region mesh is an open surface patch extracted from the terrain.
It is suitable as an ObservationMesh (records particle crossings). For use as a
closed volume mesh with TriangularMesh.contains(), additional geometry — side
walls and a floor cap — would be needed to make it watertight. This script does
not add that geometry.
"""

using HDF5

function write_corsika_ply(path::String, vertices::Matrix{Float64}, faces::Matrix{Int})
    n_verts = size(vertices, 1)
    n_faces = size(faces, 1)

    open(path, "w") do io
        # ASCII header
        print(io, "ply\n")
        print(io, "format binary_little_endian 1.0\n")
        print(io, "element vertex $n_verts\n")
        print(io, "property double x\n")
        print(io, "property double y\n")
        print(io, "property double z\n")
        print(io, "element face $n_faces\n")
        print(io, "property list uchar uint vertex_indices\n")
        print(io, "end_header\n")

        # Binary vertex data
        for i in 1:n_verts
            write(io, htol(vertices[i, 1]))
            write(io, htol(vertices[i, 2]))
            write(io, htol(vertices[i, 3]))
        end

        # Binary face data: UInt8 count (always 3) + three UInt32 0-based indices
        for i in 1:n_faces
            write(io, UInt8(3))
            write(io, htol(UInt32(faces[i, 1] - 1)))
            write(io, htol(UInt32(faces[i, 2] - 1)))
            write(io, htol(UInt32(faces[i, 3] - 1)))
        end
    end
end

"""
Extract the subset of vertices and faces for the injection region.
Returns (sub_vertices, sub_faces) where sub_faces uses 1-based indices into
sub_vertices.
"""
function injection_subset(vertices::Matrix{Float64}, faces::Matrix{Int}, injection_indices::Vector{Int})
    inj_faces = faces[injection_indices, :]

    used = sort(unique(vec(inj_faces)))
    remap = Dict(old => new for (new, old) in enumerate(used))

    sub_vertices = vertices[used, :]
    sub_faces = [remap[inj_faces[i, j]] for i in axes(inj_faces, 1), j in 1:3]

    return sub_vertices, sub_faces
end

h5_path = joinpath(@__DIR__, "..", "resources", "basic_geometry.h5")
terrain_path = joinpath(@__DIR__, "..", "resources", "terrain_corsika.ply")
injection_path = joinpath(@__DIR__, "..", "resources", "injection_region_corsika.ply")

vertices, faces, injection_indices = h5open(h5_path, "r") do f
    read(f["colca_valley_30000/vertices"]),
    read(f["colca_valley_30000/faces"]),
    read(f["colca_valley_30000/detector1"])
end

# Full terrain
println("Writing full terrain: $(size(vertices,1)) vertices, $(size(faces,1)) faces")
write_corsika_ply(terrain_path, vertices, faces)
println("Wrote $terrain_path")

# Injection region only
sub_verts, sub_faces = injection_subset(vertices, faces, injection_indices)
println("\nWriting injection region: $(size(sub_verts,1)) vertices, $(size(sub_faces,1)) faces")
write_corsika_ply(injection_path, sub_verts, sub_faces)
println("Wrote $injection_path")
println()
println("Note: injection_region_corsika.ply is an open surface patch.")
println("It is suitable as an ObservationMesh but is not watertight for volume use.")
