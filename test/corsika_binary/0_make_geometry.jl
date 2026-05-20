#!/usr/bin/env julia
#
# tambo_shower test suite — Phase 0: canonical geometry builder.
#
# Builds the GCD-bundle JLD2 the suite runs against, from the HDF5 source
# committed at resources/geometry/colca_valley.h5. Generating it here keeps
# the suite self-contained — it does not depend on any external, pre-built
# geometry file. The geometry is deterministic, so submit.slurm builds it
# once and reuses it on subsequent runs.
#
#   julia 0_make_geometry.jl <output.jld2>
#
# Adapted from simulation/0_make_geometry.jl.

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))   # the TamboSim package env

using HDF5
using Unitful
using TamboSim

# colca_valley.h5 carries several mesh resolutions as named groups. The
# 30000-triangle group is the one used for production showers; the coarser
# 3000 group is non-manifold and cannot form a watertight terrain mesh
const GROUPNAME    = "colca_valley_30000"
const DETECTOR_KEY = "detector1"

function main()
    isempty(ARGS) && error("usage: julia 0_make_geometry.jl <output.jld2>")
    out_file = ARGS[1]

    h5_file = joinpath(@__DIR__, "..", "..", "resources", "geometry",
                       "colca_valley.h5")
    isfile(h5_file) || error("geometry source not found: $h5_file")

    frames = h5open(h5_file) do file
        g               = file[GROUPNAME]
        vertices        = read(g["vertices"])
        faces           = read(g["faces"])
        longlat_deg     = read(g["location"])
        longlat_rad     = (deg2rad(longlat_deg[1]), deg2rad(longlat_deg[2]))
        prem_radii      = read(g["radii"]) .* u"m"
        detector_region = read(g[DETECTOR_KEY])
        TamboSim.build_gcd_bundle(vertices, faces, longlat_rad,
                                  prem_radii, detector_region)
    end

    mkpath(dirname(out_file))
    save_frames(out_file, frames; streams = ('G', 'C', 'D'))

    sz_mb = round(filesize(out_file) / 1024 / 1024, digits = 1)
    @info "Canonical geometry written" out_file group = GROUPNAME size_mb = sz_mb
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
