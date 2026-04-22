"""
frame_usage.jl

Demonstrates the Frame hierarchy, the GC-split I/O pattern, and common
frame operations. Intended as a quick reference for the core data model.

Topics covered:
  1. Stream types and the hierarchy (G → C → Q)
  2. Key lookup and inheritance
  3. GC-split workflow: save geometry/config once, event files separately
  4. Loading multiple files with load_frames
  5. Earth caching via get_earth
  6. Filtering and cutting event frames
"""

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))
output_dir = "$(tambo_path)/examples/output"
mkpath(output_dir)

using Tambo

config_file = "$(tambo_path)/resources/configuration_examples/tau_neutrino_cc.toml"

# =============================================================================
# 1. Stream types and the hierarchy
# =============================================================================
# load_config returns [G frame, C frame].
# G holds geometry paths; C holds configuration sections; both are referenced
# as parents by every Q (event) frame that inject! creates.

frames = load_config(config_file)

gframe = get_frame(frames, 'G')
cframe = get_frame(frames, 'C')

println("G frame keys: ", sort(collect(String, keys(gframe.data))))
println("C frame keys: ", sort(collect(String, keys(cframe.data))))

# =============================================================================
# 2. Key lookup and inheritance
# =============================================================================
# Keys are resolved by checking own data first, then parents in G → C order.

# C inherits earth_path from its G parent
println("\nearth_path via C frame:  ", cframe["earth_path"])

# Override injection event count before running
cframe["injection"]["nevent"] = 20

# After inject!, each Q frame inherits all G and C keys
inject!(frames)

qframe = first(filter(f -> f.stream == 'Q', frames))
println("earth_path via Q frame:  ", qframe["earth_path"])         # from G parent
println("injection nevent via Q:  ", qframe["injection"]["nevent"]) # from C parent
println("event_id (own data):     ", qframe["event_id"])            # own Q data

# haskey and keys work across the full hierarchy
println("has earth_path:          ", haskey(qframe, "earth_path"))
println("has event_id:            ", haskey(qframe, "event_id"))
println("has nonexistent:         ", haskey(qframe, "nonexistent_key"))

# =============================================================================
# 3. GC-split workflow
# =============================================================================
# Save geometry and config once; save only event frames per run.
# This avoids duplicating large objects across output files.

gc_file  = "$(output_dir)/gc_frames.jld2"
sim_file = "$(output_dir)/frame_usage_sim.jld2"

save_frames(gc_file, frames; streams=('G', 'C'))  # GC file: written once per geometry/config
save_frames(sim_file, frames)                      # event file: Q frames only (default)

println("\nSaved GC frames → $gc_file")
println("Saved Q frames  → $sim_file  ($(count(f -> f.stream == 'Q', frames)) events)")

# =============================================================================
# 4. Loading multiple files
# =============================================================================
# load_frames reconstructs parent references from stream order.
# GC file must come first so G/C are in the parent cache when Q frames are read.

frames2 = load_frames([gc_file, sim_file])
q_frames = filter(f -> f.stream == 'Q', frames2)

println("\nLoaded $(length(q_frames)) Q frames from [gc_file, sim_file]")

# Multiple event files can be combined the same way
sim_file2 = "$(output_dir)/frame_usage_sim2.jld2"

frames3 = load_config(config_file)
get_frame(frames3, 'C')["injection"]["nevent"] = 10
inject!(frames3)
save_frames(sim_file2, frames3)

frames_combined = load_frames([gc_file, sim_file, sim_file2])
println("Combined load: $(count(f -> f.stream == 'Q', frames_combined)) Q frames")

# =============================================================================
# 5. Earth caching
# =============================================================================
# get_earth builds Earth from gframe["earth_path"] + gframe["detector_key"]
# on first call and stores it back in the G frame. Subsequent calls return
# the same object with no file I/O.

earth1 = get_earth(frames2)
earth2 = get_earth(frames2)
println("\nEarth type:        ", typeof(earth1))
println("Cached (===):      ", earth1 === earth2)

# Earth is stripped from G frame data on save, so output files stay small
save_frames("$(output_dir)/after_earth.jld2", frames2; streams=('G', 'C'))
frames4 = load_frames(["$(output_dir)/after_earth.jld2"])
gframe4 = get_frame(frames4, 'G')
println("Earth in saved GC: ", haskey(gframe4.data, "earth"))  # false — stripped on save

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
println("G/C frames present:  ", count(f -> f.stream in ('G','C'), frames2))
