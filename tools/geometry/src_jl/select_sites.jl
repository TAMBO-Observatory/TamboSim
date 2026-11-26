# select_sites.jl — interactive picker for the candidate sites of an oroscope search (functions only; included by
# create_geometry.jl for --point without --sites, so GLMakie loads only when the window is needed).

using GLMakie

const KM_PER_DEG = 6371.0 * π / 180

"Shaded relief (RGB, [x, y]) of the DEM within `half_km` of (lon0, lat0), at most `maxpx` cells a side."
function shaded_relief(g::GridInterp, lon0, lat0, half_km; maxpx=1000)
    kx = KM_PER_DEG * cosd(lat0)
    i0 = max(1, floor(Int, (lon0 - half_km / kx - g.lon0) / g.dlon)); i1 = min(size(g.z, 1), ceil(Int, (lon0 + half_km / kx - g.lon0) / g.dlon) + 2)
    j0 = max(1, floor(Int, (lat0 - half_km / KM_PER_DEG - g.lat0) / g.dlat)); j1 = min(size(g.z, 2), ceil(Int, (lat0 + half_km / KM_PER_DEG - g.lat0) / g.dlat) + 2)
    s = max(1, ceil(Int, max(i1 - i0, j1 - j0) / maxpx))
    I = i0:s:i1; J = j0:s:j1
    z = g.z[I, J]
    dx = s * g.dlon * kx * 1000; dy = s * g.dlat * KM_PER_DEG * 1000          # cell size (m)
    light = (-sind(45) * cosd(45), cosd(45) * cosd(45), sind(45))           # from the NW, 45° up
    lo, hi = extrema(z); cmap = Makie.to_colormap(:lightterrain)
    img = map(CartesianIndices(z)) do ci
        a, b = Tuple(ci)
        zx = (z[min(a + 1, end), b] - z[max(a - 1, 1), b]) / ((min(a + 1, size(z, 1)) - max(a - 1, 1)) * dx)
        zy = (z[a, min(b + 1, end)] - z[a, max(b - 1, 1)]) / ((min(b + 1, size(z, 2)) - max(b - 1, 1)) * dy)
        shade = max(0.0, (-zx * light[1] - zy * light[2] + light[3]) / sqrt(zx^2 + zy^2 + 1))
        c = Makie.interpolated_getindex(cmap, Float32((z[a, b] - lo) / max(hi - lo, 1))); f = Float32(0.35 + 0.65 * shade)
        RGBf(f * c.r, f * c.g, f * c.b)
    end
    xs = ((g.lon0 + (first(I) - 1) * g.dlon - lon0) * kx, (g.lon0 + (last(I) - 1) * g.dlon - lon0) * kx)
    ys = ((g.lat0 + (first(J) - 1) * g.dlat - lat0) * KM_PER_DEG, (g.lat0 + (last(J) - 1) * g.dlat - lat0) * KM_PER_DEG)
    xs, ys, img, (lo, hi)
end

"""
    site_picker(search, centre, radius_km, extents_km, r_cap_km; preselect=Int[], combine=false)
        -> (fig, ax, checkboxes, combine_checkbox, buttons)

The picker figure: shaded relief of the search area, the search circle, each candidate site coloured and lettered,
a list of the sites with a checkbox each, and a "one bundle" checkbox. Sites reaching beyond the fine-mesh zone
(`extents_km[k] > r_cap_km`) are flagged in the list; with "one bundle" on, so is the combined selection.
"""
function site_picker(search, centre, radius_km, extents_km, r_cap_km; preselect=Int[], combine=false,
                     limit_desc="fine mesh < $(round(r_cap_km, digits=2)) km", mesh_desc="")
    lon0, lat0 = centre; kx = KM_PER_DEG * cosd(lat0)
    km(p) = Point2f((p[1] - lon0) * kx, (p[2] - lat0) * KM_PER_DEG)
    n = length(search.outlines)
    palette = Makie.to_colormap(n <= 10 ? :tab10 : :tab20)
    colors = [RGBAf(palette[mod1(k, length(palette))]) for k in 1:n]

    fig = Figure(size=(1400, 900))
    half = 1.08 * radius_km
    xs, ys, img, (zlo, zhi) = shaded_relief(search.dem, lon0, lat0, half)
    ax = Axis(fig[1, 1]; aspect=DataAspect(), xlabel="east of the point (km)", ylabel="north of the point (km)",
              title="oroscope sites within $(radius_km) km of ($(round(lat0, digits=5)), $(round(lon0, digits=5)))",
              subtitle="Copernicus GLO-30, $(round(Int, zlo))–$(round(Int, zhi)) m")
    image!(ax, xs[1] .. xs[2], ys[1] .. ys[2], img; interpolate=true)
    θ = range(0, 2π; length=361)
    lines!(ax, radius_km .* cos.(θ), radius_km .* sin.(θ); color=:black, linestyle=:dash, linewidth=1.5)
    scatter!(ax, [0.0], [0.0]; marker=:xcross, color=:red, markersize=14, strokecolor=:white, strokewidth=1)
    limits!(ax, -half, half, -half, half)

    # One column, each part in its own row: a part spanning several columns would not count towards the
    # panel's width, and could run off the window.
    panel = GridLayout(fig[1, 2]; valign=:top, tellheight=false)
    Label(panel[1, 1], "Candidate sites (best first)"; font=:bold, fontsize=17, halign=:left)
    list = GridLayout(panel[2, 1]; halign=:left)
    cbs = Checkbox[]
    for (k, o) in enumerate(search.outlines)
        s = search.sites[k]; col = colors[k]
        cb = Checkbox(list[k, 1]; checked=k in preselect, size=18, checkboxcolor_checked=col,
                      checkboxstrokecolor_checked=:black, checkboxstrokecolor_unchecked=col)
        push!(cbs, cb)
        far = extents_km[k] > r_cap_km
        Label(list[k, 2], "$(o.label)   $(s.area_km2) km²  ·  $(s.capacity_exact) units  ·  faces $(s.facing_direction)" *
              (far ? "   ⚠ reaches $(round(extents_km[k], digits=2)) km; $limit_desc" : "");
              halign=:left, fontsize=14, color=far ? :darkorange3 : :black)
        sel = cb.checked
        polys = [Makie.GeometryBasics.Polygon([km(q) for q in p[1]], [[km(q) for q in h] for h in p[2:end]]) for p in o.polygons]
        for P in polys
            poly!(ax, P; color=@lift(RGBAf(col.r, col.g, col.b, $sel ? 0.75 : 0.3)), strokecolor=@lift($sel ? RGBAf(0, 0, 0, 1) : col),
                  strokewidth=@lift($sel ? 2.0 : 1.0))
        end
    end
    # Letters on round badges in the site's colour, lifted above the outlines (GLMakie does not draw later
    # plots on top of earlier ones at the same depth).
    anchors = [km(a) for a in search.anchors]
    badges = scatter!(ax, anchors; marker=:circle, markersize=30, color=:white, strokecolor=colors, strokewidth=2.5)
    letters = text!(ax, anchors; text=[o.label for o in search.outlines], align=(:center, :center), fontsize=17,
                    font=:bold, color=:black)
    translate!(badges, 0, 0, 10); translate!(letters, 0, 0, 11)
    rowgap!(list, 4)
    selected = lift((c...) -> findall(collect(c)), (cb.checked for cb in cbs)...)

    # One bundle for all selected sites: show how far they reach from their combined centre.
    one = GridLayout(panel[3, 1]; halign=:left)
    cb_one = Checkbox(one[1, 1]; checked=combine, size=18)
    Label(one[1, 2], "Build the selected sites as one bundle (combined detector region)"; halign=:left, fontsize=14)
    reach = lift(selected, cb_one.checked) do sel, on
        (on && length(sel) > 1) || return ("", false)
        o = combine_outlines(search.outlines[sel]); e = outline_extent_km(o, area_centroid(o))
        ("$(o.label) reaches $(round(e, digits=2)) km from its centre" *
         (e > r_cap_km ? "  ⚠ $limit_desc" : "  ($limit_desc)"),
         e > r_cap_km)
    end
    Label(one[2, 2], @lift($reach[1]); halign=:left, fontsize=13, color=@lift($reach[2] ? :darkorange3 : :gray30))

    buttons = GridLayout(panel[4, 1]; halign=:left)
    b_build = Button(buttons[1, 1]; buttoncolor=RGBf(0.75, 0.9, 0.75),
                     label=@lift($(cb_one.checked) && length($selected) > 1 ? "Build as one bundle ($(length($selected)))" :
                                 "Build selected ($(length($selected)))"))
    b_all = Button(buttons[1, 2]; label="All"); b_none = Button(buttons[1, 3]; label="None")
    b_cancel = Button(buttons[1, 4]; label="Cancel")
    Label(panel[5, 1], "Click a site or press its letter to select it.\nEnter builds the selection; Esc or closing " *
          "the window cancels.\n\nEach selected site becomes its own bundle, centred on it,\nunless they are built " *
          "as one bundle, centred on all of them." * (isempty(mesh_desc) ? "" : "\nFine mesh (~60 m triangles): $mesh_desc.");
          halign=:left, fontsize=13, color=:gray30, justification=:left)
    fig, ax, cbs, cb_one, (; build=b_build, all=b_all, none=b_none, cancel=b_cancel)
end

"""
    pick_sites(search, centre, radius_km, extents_km, r_cap_km; combine=false) -> (indices, combine)

Open the picker and wait. Returns the indices of the sites selected when "Build selected" (or Enter) is pressed,
or an empty vector if the window is cancelled or closed, and whether to build them as one bundle (the checkbox,
which starts at `combine`).
"""
function pick_sites(search, centre, radius_km, extents_km, r_cap_km; combine=false,
                    limit_desc="fine mesh < $(round(r_cap_km, digits=2)) km", mesh_desc="")
    GLMakie.activate!(; title="Pick TAMBO sites")
    fig, ax, cbs, cb_one, b = site_picker(search, centre, radius_km, extents_km, r_cap_km; combine=combine,
                                          limit_desc=limit_desc, mesh_desc=mesh_desc)
    lon0, lat0 = centre; kx = KM_PER_DEG * cosd(lat0)
    toggle!(k) = (cbs[k].checked[] = !cbs[k].checked[])
    chosen = Ref{Union{Nothing,Vector{Int}}}(nothing)
    build!() = (chosen[] = findall(cb -> cb.checked[], cbs))
    cancel!() = (chosen[] = Int[])

    on(_ -> build!(), b.build.clicks); on(_ -> cancel!(), b.cancel.clicks)
    on(_ -> foreach(cb -> cb.checked[] = true, cbs), b.all.clicks)
    on(_ -> foreach(cb -> cb.checked[] = false, cbs), b.none.clicks)
    on(events(fig).mousebutton; priority=2) do ev
        (ev.button == Mouse.left && ev.action == Mouse.press && is_mouseinside(ax.scene)) || return Consume(false)
        x, y = mouseposition(ax.scene)
        k = findfirst(o -> inside(o, lon0 + x / kx, lat0 + y / KM_PER_DEG), search.outlines)
        k === nothing && return Consume(false)
        toggle!(k)
        Consume(true)
    end
    on(events(fig).keyboardbutton) do ev
        ev.action == Keyboard.press || return
        if ev.key in (Keyboard.enter, Keyboard.kp_enter)
            build!()
        elseif ev.key == Keyboard.escape
            cancel!()
        elseif Int(Keyboard.a) <= Int(ev.key) <= Int(Keyboard.z)
            k = Int(ev.key) - Int(Keyboard.a) + 1
            k <= length(cbs) && toggle!(k)
        end
    end

    screen = display(fig)
    while isopen(screen) && chosen[] === nothing
        sleep(0.05)
    end
    isopen(screen) && close(screen)
    something(chosen[], Int[]), cb_one.checked[]
end
