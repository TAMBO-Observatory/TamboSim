#!/usr/bin/env julia
#
# Dump the observation-mesh PLY from the committed GCD geometry, for a
# run-by-hand radio gun test of `tambo_shower --radio`.
#
# `tambo_shower --radio` places one antenna on every (strided) vertex of the
# `--obs-mesh` PLY, so a radio run needs that PLY. No PLY is checked in: it is
# generated from `resources/geometry/colca_valley_3000.jld2` (which already
# carries the G/C/D streams) via `dump_to_ply` of the detector D-frame. This is
# a one-time, self-contained step -- NOT the full simulation chain.
#
#   julia make_obs_ply.jl [out.ply]
#
# Default output: obs_surface.ply in the current directory.

using Pkg
# analysis/ -> tambo_shower/ -> corsika/ -> src/ -> TamboSim (package root)
Pkg.activate(joinpath(@__DIR__, "..", "..", "..", ".."))

using TamboSim

function main()
    out = isempty(ARGS) ? "obs_surface.ply" : ARGS[1]
    geo = joinpath(@__DIR__, "..", "..", "..", "..",
                   "resources", "geometry", "colca_valley_3000.jld2")
    isfile(geo) || error("geometry not found: $geo")

    frames = load_frames(geo)
    # The detector D-frame carries the observation-region surface; dump_to_ply
    # extracts the detector subset of vertices/faces for stream 'D'.
    dframe = frames.d_frames[1]
    TamboSim.dump_to_ply(dframe, out)
    @info "wrote observation-mesh PLY" out
end

main()
