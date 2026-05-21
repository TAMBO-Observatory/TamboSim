# rebuild_geometry_jld2.jl
#
# Rebuild a tracked GCD-bundle JLD2 fixture from its HDF5 source, e.g.
# `resources/geometry/colca_valley.h5` → `resources/geometry/colca_valley_3000.jld2`.
#
# Run when the on-disk type schema changes — JLD2 stores fully-qualified
# type names, so anything that renames a module (`Tambo` → `TamboSim`),
# moves a type, or changes a struct's fields will leave existing fixtures
# loading as `JLD2.ReconstructedStatic` and failing to dispatch.
#
# The HDF5 source carries multiple resolutions as named groups (e.g.
# `colca_valley_3000`, `colca_valley_30000`); GROUPNAME picks one. The
# output filename is `<groupname>.jld2` next to the source.

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using HDF5
using Unitful
using TamboSim

const GROUPNAME    = "colca_valley_3000"
const DETECTOR_KEY = "detector1"

h5_file  = joinpath(tambo_path, "resources", "geometry", "colca_valley.h5")
out_file = joinpath(tambo_path, "resources", "geometry", "$(GROUPNAME).jld2")

frames = h5open(h5_file) do file
    g               = file[GROUPNAME]
    vertices        = read(g["vertices"])
    faces           = read(g["faces"])
    longlat_deg     = read(g["location"])
    longlat_rad     = (deg2rad(longlat_deg[1]), deg2rad(longlat_deg[2]))
    prem_radii      = read(g["radii"]) .* u"m"
    detector_region = read(g[DETECTOR_KEY])
    TamboSim.build_gcd_bundle(vertices, faces, longlat_rad, prem_radii, detector_region)
end
save_frames(out_file, frames; streams=('G', 'C', 'D'))

sz_mb = round(filesize(out_file) / 1024 / 1024, digits=1)
println("Wrote $out_file")
println("  group:     $GROUPNAME")
println("  file size: $sz_mb MB")
