"""
frame_usage.jl

Demonstrates the Frame hierarchy, the I/O patterns, and common frame
operations. Intended as a quick reference for the core data model.

Topics covered:
  1. Stream types and the hierarchy (G → C → Q)
  2. Key lookup and inheritance
  3. Saving and loading frames
  4. Loading multiple files with load_frames
  5. Earth access via G frame keys
  6. Filtering and cutting event frames
"""

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))
output_dir = "$(tambo_path)/examples/output"
mkpath(output_dir)

using Tambo
using TOML

config_file = "$(tambo_path)/resources/configuration_examples/tau_neutrino_cc.toml"

config = TOML.parsefile(config_file)
relativize!(config)

# =============================================================================
# 1. Stream types and the hierarchy
# =============================================================================
# load_frames on a geometry JLD2 returns [G frame]. inject! creates a C frame
# and nevent Q frames, all linked by parent references (G → C → Q).

injection_config = config["injection"]
injection_config["nevent"] = 20

geometry_file = "$(tambo_path)/resources/geometry/colca_valley_3000.jld2"
frames = load_frames(geometry_file)
inject!(frames, injection_config)

gframe = get_frame(frames, 'G')
mframe = get_frame(frames, 'M')

println("G frame keys: ", sort(collect(String, keys(gframe.data))))
println("M frame keys: ", sort(collect(String, keys(mframe.data))))

# =============================================================================
# 2. Key lookup and inheritance
# =============================================================================
# Keys are resolved by checking own data first, then parents in G → M order.

qframe = first(filter(f -> f.stream == 'Q', frames))
println("\nearth_path via Q frame:  ", qframe["earth_path"])          # from G parent
println("injection nevent via Q:  ", qframe["injection"]["nevent"])  # from M parent
println("event_id (own data):     ", qframe["event_id"])             # own Q data

println("has earth_path:          ", haskey(qframe, "earth_path"))
println("has event_id:            ", haskey(qframe, "event_id"))
println("has nonexistent:         ", haskey(qframe, "nonexistent_key"))

# =============================================================================
# 3. Saving and loading frames
# =============================================================================
# save_frames writes the requested streams to JLD2. Parent references are not
# stored — they are reconstructed from stream order on load. G frames are
# written as-is (including bvh and topography) when explicitly included in
# streams; see create_geometry.jl for the one-time geometry file workflow.

sim_file = "$(output_dir)/frame_usage_sim.jld2"

save_frames(sim_file, frames)  # saves C and Q frames (default)
println("\nSaved frames → $sim_file  ($(count(f -> f.stream == 'Q', frames)) Q frames)")

# =============================================================================
# 4. Loading frames
# =============================================================================
# load_frames reconstructs parent references from stream order.

frames2 = load_frames(sim_file)
q_frames = filter(f -> f.stream == 'Q', frames2)
println("\nLoaded $(length(q_frames)) Q frames from $sim_file")

# Multiple event files can be combined by passing a list of paths.
# The parent cache (G/C frames) carries over across file boundaries so the
# first file's G frame becomes the parent of Q frames in subsequent files.
sim_file2 = "$(output_dir)/frame_usage_sim2.jld2"

frames3 = load_frames(geometry_file)
inject!(frames3, merge(config["injection"], Dict("nevent" => 10)))
save_frames(sim_file2, frames3)

frames_combined = load_frames([sim_file, sim_file2])
println("Combined load: $(count(f -> f.stream == 'Q', frames_combined)) Q frames")

# =============================================================================
# 5. Earth access
# =============================================================================
# G frames are not saved by default (save_frames writes C+Q only). To access
# geometry, load the geometry JLD2 directly. The G frame is self-contained —
# bvh, topography, and coordinate system are all stored inside it.

gframe2 = get_frame(load_frames(geometry_file), 'G')
bvh = gframe2["bvh"]
println("\nBVH type:          ", typeof(bvh))
println("Triangles in BVH:  ", length(bvh.triangles))

# =============================================================================
# 6. Filtering and cutting event frames
# =============================================================================
# cut_frames! removes Q frames for which the predicate returns false.
# G and C frames are always preserved regardless of the predicate.

n_before = count(f -> f.stream == 'Q', frames2)
cut_frames!(frames2, f -> haskey(f, "injection_final_state"))
n_after = count(f -> f.stream == 'Q', frames2)

println("\nQ frames before cut: $n_before")
println("Q frames after cut:  $n_after")
println("G/M frames present:  ", count(f -> f.stream in ('G','M'), frames2))
