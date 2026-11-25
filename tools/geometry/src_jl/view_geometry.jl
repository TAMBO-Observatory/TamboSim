# view_geometry.jl — interactive 3D view of a built bundle with TamboMakie (functions only;
# included by create_geometry_from_kml.jl only for --view, so plain builds never load GLMakie).

using GLMakie
using TamboMakie.Viz3D

"""
    geometry_figure(d_frame; side_km, title="") -> Figure

The scene of TamboMakie's `examples/1_viz3D.jl` without events: a `side_km` square of terrain
around the detector region, coloured by elevation, with the detector region in blue and
detector units (if placed) on top.
"""
function geometry_figure(d; side_km::Real, title::AbstractString="")
    fig = Figure(size = (1100, 850))
    ls = setup_lscene!(fig[1, 1])
    plot_terrain!(ls, d; side_km)
    plot_terrain!(ls, d; region = :detector_region, color = (:royalblue, 0.45),
        transparency = true, fitcam = false,
        depth_shift = -1f-5)                 # draw it just in front of the terrain it lies on
    haskey(d, "detector_units") && plot_detectors!(ls, d)
    isempty(title) || Label(fig[0, 1], title; fontsize = 18, tellwidth = false)
    fig
end

"Open [`geometry_figure`](@ref) in a GLMakie window and block until it is closed."
function view_geometry(d; kwargs...)
    fig = geometry_figure(d; kwargs...)
    println("\n3D view open: drag to rotate, scroll to zoom; W/S A/D R/F move, J/L I/K Q/E turn, " *
            "B/N field of view. Close the window to finish.")
    wait(display(fig))
end
