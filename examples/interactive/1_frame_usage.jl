
# 1_frame_usage.jl
# Demonstrates the Frame hierarchy, the I/O patterns, and common frame
# operations. Designed to be run interactively in the Julia REPL.
#
# Topics covered:
#   1. Stream types and the hierarchy (G → M → Q)
#   2. Key lookup and inheritance
#   3. Saving and loading frames
#   4. Loading multiple files with load_frames
#   5. Earth access via the G frame
#   6. Filtering and cutting event frames

using Tambo
using TOML

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(@__DIR__))
output_dir = mkpath(joinpath(tambo_path, "examples", "output"))

config_file = joinpath(tambo_path, "resources", "configuration_examples", "tau_neutrino_cc.toml")
config = TOML.parsefile(config_file);
relativize!(config);

# =============================================================================
# 1. Stream types and the hierarchy
# =============================================================================
# load_frames on a geometry JLD2 returns a TamboFrames containing one G frame.
# inject! adds an M (metadata) frame plus nevent Q (event) frames, all linked
# by parent references: G → M → Q.

config["injection"]["nevent"] = 20

geometry_file = joinpath(tambo_path, "resources", "geometry", "colca_valley_3000.jld2")
frames = load_frames(geometry_file)
inject!(frames, config["injection"])
frames                                # tree view via Base.show

qframe = frames.q_frames[1]

gframe = qframe.gframe
sort(collect(keys(gframe)))       # G frame keys (own data only)

mframe = qframe.mframe
sort(collect(keys(mframe)))       # M frame keys (inherits G frame keys)

# =============================================================================
# 2. Key lookup and inheritance
# =============================================================================
# Keys resolve from own data first, then walk parents in G → C → D → M order.

qframe["earth_path"]              # inherited from G parent
qframe["injection"]["nevent"]     # inherited from M parent
qframe["event_id"]                # own Q data
qframe["nonexistent_key"]         # throws a KeyError

# =============================================================================
# 3. Saving + loading frames
# =============================================================================
# save_frames writes the requested streams to JLD2; default is ('M','Q'), so
# the geometry is omitted (G frames are large). Parent references are not
# stored — they are reconstructed from stream order on load. To include the G
# frame, pass `streams=('G','M','Q')`.

sim_file_1 = joinpath(output_dir, "1_frame_usage_sim1.jld2")
save_frames(sim_file_1, frames);

frames_1 = load_frames(sim_file_1)
length(frames_1.q_frames)

# Multiple files combine cleanly. The G frame loaded from `geometry_file`
# becomes the parent of every Q frame, including those from later files in
# the list.
sim_file_2 = joinpath(output_dir, "1_frame_usage_sim2.jld2")
frames_2 = load_frames(geometry_file);
inject!(frames_2, merge(config["injection"], Dict("nevent" => 10)));
save_frames(sim_file_2, frames_2);

frames_combined = load_frames([geometry_file, sim_file_1, sim_file_2])
length(frames_combined.q_frames)

# =============================================================================
# 4. Earth access
# =============================================================================
# G frames are not saved by default, so to work with geometry, load the
# geometry JLD2 directly. The G frame is self-contained — bvh, topography,
# and coordinate system all live in it.

geo_only = load_frames(geometry_file)
bvh = geo_only.g_frames[end]["bvh"]
typeof(bvh)
length(bvh.triangles)

# =============================================================================
# 6. Filtering and cutting event frames
# =============================================================================
# cut_frames! removes Q frames for which the predicate returns false. G/C/D/M
# frames are preserved, and any P descendants of a cut Q frame cascade out
# alongside it.

n_before = length(frames_2.q_frames)
cut_frames!(frames_2, qf -> haskey(qf, "injection_final_state"));
n_after  = length(frames_2.q_frames)

@show n_before n_after;
@show length(frames_2.g_frames) length(frames_2.m_frames);
