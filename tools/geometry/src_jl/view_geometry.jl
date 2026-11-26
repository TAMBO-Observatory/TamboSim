# view_geometry.jl — interactive 3D view of a built bundle with TamboMakie (functions only;
# included by create_geometry.jl only for --view, so plain builds never load GLMakie).

using GLMakie
using TamboMakie.Viz3D
using TamboMakie.Adapters: terrain_mesh
using Unitful

const FINE_COLOR = :gold

"""
Faces of `faces` whose centre lies in the `side_km` square around the detector region that `plot_terrain!` shows
(the same window and elevation bounds as TamboMakie's `:local` patch), so an overlay does not reach past it.
"""
function faces_in_view(d, faces, side_km)
    topo = d["topography"]; det = d["detector_region"]
    km(x) = ustrip(u"km", x)
    cx = sum(km(t.v1.x + t.v2.x + t.v3.x) for t in topo[det]) / 3length(det)
    cy = sum(km(t.v1.y + t.v2.y + t.v3.y) for t in topo[det]) / 3length(det)
    zs = [km(z) for t in topo[det] for z in (t.v1.z, t.v2.z, t.v3.z)]
    zlo, zhi = minimum(zs) - side_km, maximum(zs) + side_km
    filter(faces) do i
        t = topo[i]
        abs(km(t.v1.x + t.v2.x + t.v3.x) / 3 - cx) <= side_km / 2 && abs(km(t.v1.y + t.v2.y + t.v3.y) / 3 - cy) <= side_km / 2 &&
            zlo <= km(t.v1.z + t.v2.z + t.v3.z) / 3 <= zhi
    end
end

"Line segments (km, lifted `lift_km`) along the edge of the region made of `region_faces`, where `shown` faces are."
function region_edge(d, region_faces, shown; lift_km=0.004)
    F = d["faces"]; topo = d["topography"]
    uses = Dict{Tuple{Int,Int},Int}()
    for i in region_faces, (a, b) in ((1, 2), (2, 3), (3, 1))
        e = minmax(F[i, a], F[i, b]); uses[e] = get(uses, e, 0) + 1
    end
    pos = Dict{Int,Point3f}()
    for i in shown, (k, v) in enumerate((topo[i].v1, topo[i].v2, topo[i].v3))
        pos[F[i, k]] = Point3f(ustrip(u"km", v.x), ustrip(u"km", v.y), ustrip(u"km", v.z) + lift_km)
    end
    [pos[v] for (e, n) in uses if n == 1 && haskey(pos, e[1]) && haskey(pos, e[2]) for v in e]
end

"""
    geometry_figure(d_frame; side_km, title="", fine_faces=nothing, fine_desc="") -> Figure

The scene of TamboMakie's `examples/1_viz3D.jl` without events: a `side_km` square of terrain around the detector
region, coloured by elevation, with the detector region in blue and detector units (if placed) on top. With
`fine_faces` (indices of the fine-mesh triangles), the fine-mesh region is tinted gold with its edge in orange.
Toggles under the scene switch that and the triangle edges on and off.
"""
function geometry_figure(d; side_km::Real, title::AbstractString="", fine_faces=nothing, fine_desc::AbstractString="")
    fig = Figure(size = (1100, 900))
    ls = setup_lscene!(fig[1, 1])
    plot_terrain!(ls, d; side_km)

    # Triangle edges of the shown terrain (off by default): fine and coarse triangles side by side.
    show_edges = Observable(false); show_fine = Observable(fine_faces !== nothing)
    tm = terrain_mesh(d; region=:local, side_km)                     # (points, faces) in km
    edges = [tm.points[f[k]] for f in tm.faces for (a, b) in ((1, 2), (2, 3), (3, 1)) for k in (a, b)]
    linesegments!(ls, edges; color=(:black, 0.35), linewidth=0.6, visible=show_edges, depth_shift=-2f-5)

    if fine_faces !== nothing
        shown = faces_in_view(d, fine_faces, side_km)
        if !isempty(shown)
            # terrain_mesh reads a face list by key (in memory only). Drawn with mesh! rather than plot_terrain!,
            # whose recipe turns a `keys` override into an Observable that its region lookup cannot use.
            d["fine_faces_in_view"] = shown
            fm = terrain_mesh(d; region=:detector_region, keys=(; detector_region="fine_faces_in_view"))
            mesh!(ls, fm.points, fm.faces; color=(FINE_COLOR, 0.3), transparency=true, depth_shift=-5f-6,
                  visible=show_fine)
            edge = region_edge(d, fine_faces, shown)
            isempty(edge) || linesegments!(ls, edge; color=:darkorange, linewidth=2.5, visible=show_fine)
        end
    end
    plot_terrain!(ls, d; region = :detector_region, color = (:royalblue, fine_faces === nothing ? 0.45 : 0.7),
        transparency = true, fitcam = false,
        depth_shift = -1f-5)                 # draw it just in front of the terrain it lies on
    haskey(d, "detector_units") && plot_detectors!(ls, d)
    isempty(title) || Label(fig[0, 1], title; fontsize = 18, tellwidth = false)

    controls = GridLayout(fig[2, 1]; tellwidth=false, halign=:center)
    col = 1
    if fine_faces !== nothing
        t_fine = Toggle(controls[1, col]; active=true); connect!(show_fine, t_fine.active)
        Label(controls[1, col + 1], "fine mesh" * (isempty(fine_desc) ? "" : " ($fine_desc)") * ": gold, edge in orange";
              halign=:left)
        col += 2
    end
    t_edges = Toggle(controls[1, col]; active=false); connect!(show_edges, t_edges.active)
    Label(controls[1, col + 1], "triangle edges"; halign=:left)
    Label(controls[1, col + 2], "     detector region: blue"; halign=:left, color=:royalblue)
    colgap!(controls, 8)
    fig
end

"Open [`geometry_figure`](@ref) in a GLMakie window and block until it is closed."
function view_geometry(d; kwargs...)
    fig = geometry_figure(d; kwargs...)
    println("\n3D view open: drag to rotate, scroll to zoom; W/S A/D R/F move, J/L I/K Q/E turn, " *
            "B/N field of view; the toggles under the scene switch the fine-mesh region and the triangle edges. " *
            "Close the window to finish.")
    wait(display(fig))
end
