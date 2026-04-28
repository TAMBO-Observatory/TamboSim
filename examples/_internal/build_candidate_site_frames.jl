"""
build_candidate_site_frames.jl

Read every site group from resources/candidate_sites.h5 and write a
self-contained G-frame JLD2 to resources/geometry/ for each one.

Output files are named candidate_<groupname>.jld2, e.g.:
  resources/geometry/candidate_site_1.jld2
  resources/geometry/candidate_site_2.jld2
  ...

Each JLD2 can be loaded directly with load_frames("candidate_site_N.jld2")
without needing the source HDF5 file.
"""

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))

using HDF5
using Tambo

h5_path  = "$(tambo_path)/resources/candidate_sites.h5"
out_dir  = "$(tambo_path)/resources/geometry"
mkpath(out_dir)

site_keys = sort(h5open(f -> collect(keys(f)), h5_path))

println("Found $(length(site_keys)) sites in $h5_path\n")

for site in site_keys
    earth_path = "$(h5_path):$(site)"
    jld2_path  = "$(out_dir)/candidate_$(site).jld2"

    frames = Tambo.build_gcd_bundle(earth_path, "detector1")
    save_frames(jld2_path, frames, streams=('G', 'C', 'D'))

    g_frame  = Tambo._get_last_frame(frames, 'G')
    d_frame  = Tambo._get_last_frame(frames, 'D')
    n_tris  = length(g_frame["topography"])
    n_det   = length(d_frame["detector_region"])
    sz_mb   = round(filesize(jld2_path) / 1024^2, digits=1)
    println("  $site → candidate_$(site).jld2  ($n_tris triangles, $n_det detector faces, $(sz_mb) MB)")
end

println("\nDone — $(length(site_keys)) geometry files written to $out_dir")
