"""
Export the terrain mesh from resources/basic_geometry.h5 to PLY format.

Face indices in the HDF5 file are 1-based; PLY requires 0-based indices.

Custom elements:
  - Per-face property `is_in_injection` (uchar): 1 if the face is in the injection region.
  - Element `radii`: array of detector radii values.
"""

using HDF5

function write_ply(path, vertices, faces, injection_mask, radii)
    n_verts = size(vertices, 1)
    n_faces = size(faces, 1)
    n_radii = length(radii)

    open(path, "w") do io
        write(io, "ply\n")
        write(io, "format ascii 1.0\n")
        write(io, "element vertex $n_verts\n")
        write(io, "property double x\n")
        write(io, "property double y\n")
        write(io, "property double z\n")
        write(io, "element face $n_faces\n")
        write(io, "property list uchar int vertex_indices\n")
        write(io, "property uchar is_in_injection\n")
        write(io, "element radii $n_radii\n")
        write(io, "property double value\n")
        write(io, "end_header\n")

        for i in 1:n_verts
            write(io, "$(vertices[i,1]) $(vertices[i,2]) $(vertices[i,3])\n")
        end

        for i in 1:n_faces
            # Convert from 1-based (HDF5) to 0-based (PLY)
            a, b, c = faces[i, 1] - 1, faces[i, 2] - 1, faces[i, 3] - 1
            flag = injection_mask[i] ? 1 : 0
            write(io, "3 $a $b $c $flag\n")
        end

        for r in radii
            write(io, "$r\n")
        end
    end
end

h5_path = joinpath(@__DIR__, "..", "resources", "basic_geometry.h5")
ply_path = joinpath(@__DIR__, "..", "resources", "basic_geometry.ply")

vertices, faces, injection_indices, radii = h5open(h5_path, "r") do f
    read(f["colca_valley_30000/vertices"]),
    read(f["colca_valley_30000/faces"]),
    read(f["colca_valley_30000/detector1"]),
    read(f["colca_valley_30000/radii"])
end

injection_mask = falses(size(faces, 1))
injection_mask[injection_indices] .= true

println("Vertices: $(size(vertices, 1)), Faces: $(size(faces, 1)), Injection faces: $(sum(injection_mask))")
write_ply(ply_path, vertices, faces, injection_mask, radii)
println("Wrote $ply_path")
