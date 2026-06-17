#!/usr/bin/env julia
#
# Compute per-antenna radio energy fluence and render a shower-plane footprint
# from a `tambo_shower --radio` run directory.
#
#   julia --project=src/corsika/tambo_shower/analysis \
#         src/corsika/tambo_shower/analysis/plot_radio_footprint.jl \
#         <run_dir> -o out.png [--title "..."]
#
# First use: instantiate the analysis environment once (pulls CairoMakie +
# Parquet2):
#   julia --project=src/corsika/tambo_shower/analysis -e 'using Pkg; Pkg.instantiate()'
#
# Pipeline:
#   1. load_run                -> antenna positions, shower geometry, waveforms
#   2. energy_fluence          -> per-antenna fluence [eV/m^2]   (radio_fluence.jl)
#   3. project_to_shower_plane -> (v x B, v x (v x B)) coords    (radio_fluence.jl)
#   4. plot_footprint          -> log-color-scale PNG
#
# On-disk format (see ../src/RADIO_NOTES.md section 9 and the writer source
# corsika/detail/modules/radio/RadioProcess.inl), under `<run_dir>/radio/`:
#   * antennas.csv        -- header id,vertex_index,x,y,z (ECEF metres), one row
#                            per observer, id 0-based.
#   * shower_geometry.csv -- one data row: core_*, dir_* (=v), b*_nT (=B).
#   * observers.parquet   -- columns shower, Time(ns), Ex, Ey, Ez (V/m). NO
#                            per-observer id column: rows are observer-insertion
#                            order (== id order == antennas.csv order), each
#                            observer contributing an equal contiguous chunk
#                            (all observers share duration/sampleRate).

import Pkg
Pkg.activate(@__DIR__)

using Parquet2
using Tables
using CairoMakie
using DelimitedFiles
using Printf

include(joinpath(@__DIR__, "radio_fluence.jl"))

# --------------------------------------------------------------------------- #
# CORSIKA IO
# --------------------------------------------------------------------------- #

"Read antennas.csv -> (ids, positions N×3) ordered by ascending id."
function read_antennas_csv(path)
    data, _ = readdlm(path, ',', Float64, '\n'; header = true)
    ids = round.(Int, data[:, 1])
    order = sortperm(ids)
    return ids[order], data[order, 3:5]
end

"Read shower_geometry.csv -> (core, v, B). Column order is fixed by the writer."
function read_shower_geometry_csv(path)
    data, _ = readdlm(path, ',', Float64, '\n'; header = true)
    row = vec(data[1, :])
    return row[1:3], row[4:6], row[7:9]
end

"Locate observers.parquet directly under the radio dir, else search recursively."
function find_parquet(radio_dir)
    direct = joinpath(radio_dir, "observers.parquet")
    isfile(direct) && return direct
    for (root, _, files) in walkdir(radio_dir)
        "observers.parquet" in files && return joinpath(root, "observers.parquet")
    end
    error("observers.parquet not found under $radio_dir")
end

"""
    load_run(run_dir) -> (positions, core, v, B, traces)

`positions` is N×3 (ECEF m, ordered by antenna id); `core,v,B` are length-3;
`traces` is a length-N vector of `(times, ex, ey, ez)` tuples aligned with the
antenna rows (times in ns).
"""
function load_run(run_dir)
    radio_dir = isdir(joinpath(run_dir, "radio")) ? joinpath(run_dir, "radio") : run_dir
    ids, positions = read_antennas_csv(joinpath(radio_dir, "antennas.csv"))
    core, v, B = read_shower_geometry_csv(joinpath(radio_dir, "shower_geometry.csv"))
    n_obs = length(ids)

    tbl = Tables.columntable(Parquet2.Dataset(find_parquet(radio_dir)))
    namemap = Dict(lowercase(String(k)) => k for k in keys(tbl))
    getcol(name) = Float64.(collect(getproperty(tbl, namemap[name])))

    time = getcol("time"); ex = getcol("ex"); ey = getcol("ey"); ez = getcol("ez")

    # Multiple showers: keep only the first event so the equal-chunk row layout
    # is well defined.
    if haskey(namemap, "shower")
        shower = collect(getproperty(tbl, namemap["shower"]))
        first_id = shower[1]
        n_showers = length(unique(shower))
        if n_showers > 1
            @warn "parquet has $n_showers showers; plotting only the first" first_id
        end
        mask = shower .== first_id
        time, ex, ey, ez = time[mask], ex[mask], ey[mask], ez[mask]
    end

    total = length(time)
    traces = Vector{NTuple{4,Vector{Float64}}}(undef, n_obs)
    if n_obs > 0 && total > 0
        total % n_obs == 0 ||
            error("parquet has $total rows, not divisible by $n_obs antennas; " *
                  "cannot split into per-observer contiguous chunks.")
        per = total ÷ n_obs
        for i in 1:n_obs
            sl = ((i - 1) * per + 1):(i * per)
            traces[i] = (time[sl], ex[sl], ey[sl], ez[sl])
        end
    else
        for i in 1:n_obs
            traces[i] = (Float64[], Float64[], Float64[], Float64[])
        end
    end
    return positions, core, v, B, traces
end

# --------------------------------------------------------------------------- #
# Plotting
# --------------------------------------------------------------------------- #

"Render a log-color-scale shower-plane footprint to `out_png`. Returns the path."
function plot_footprint(a, b, fluence_eV_m2, out_png; title = "")
    fl = float.(fluence_eV_m2)
    # log color scale cannot take <= 0: clip to the smallest positive value.
    pos = filter(>(0), fl)
    floorval = isempty(pos) ? 1.0 : minimum(pos)
    clipped = map(x -> x > 0 ? x : floorval, fl)
    vmax = maximum(clipped)
    vmax > floorval || (vmax = floorval * 10)  # keep a non-degenerate colorrange

    mkpath(dirname(abspath(out_png)))
    fig = Figure(size = (700, 600))
    ax = Axis(fig[1, 1]; xlabel = "v×B [m]", ylabel = "v×(v×B) [m]",
              title = title, aspect = DataAspect())
    sc = scatter!(ax, a, b; color = clipped, colormap = :viridis,
                  markersize = 10, colorscale = log10,
                  colorrange = (floorval, vmax))
    Colorbar(fig[1, 2], sc; label = "energy fluence [eV/m²]")
    save(out_png, fig)
    return out_png
end

# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

function _parse_args(args)
    run_dir = nothing
    output = nothing
    title = ""
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg in ("-o", "--output")
            output = args[i + 1]; i += 2
        elseif arg == "--title"
            title = args[i + 1]; i += 2
        elseif startswith(arg, "-")
            error("unknown option: $arg")
        else
            run_dir = arg; i += 1
        end
    end
    (run_dir === nothing || output === nothing) &&
        error("usage: plot_radio_footprint.jl <run_dir> -o out.png [--title ...]")
    return run_dir, output, title
end

function main(args)
    run_dir, output, title = _parse_args(args)
    positions, core, v, B, traces = load_run(run_dir)
    fluence = [energy_fluence(t[1], t[2], t[3], t[4]) for t in traces]
    a, b = project_to_shower_plane(positions, core, v, B)
    out = plot_footprint(a, b, fluence, output; title = title)
    println("wrote $out")
    return out
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
