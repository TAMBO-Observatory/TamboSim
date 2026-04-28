# 1_frame_usage.jl
#
# Load and explore an existing TamboSim simulation output. Designed to be
# pasted into the REPL section by section — values display themselves
# rather than being wrapped in println.
#
# Topics covered:
#   1. Loading frames from one or more JLD2 files
#   2. Exploring the TamboFrames container
#   3. Key lookup and parent inheritance
#   4. Inspecting the TOML config that produced the output

using Tambo
using TOML

tambo_path = get(ENV, "TAMBOSIM_PATH", dirname(dirname(@__DIR__)))

geometry_file = joinpath(tambo_path, "resources", "geometry", "colca_valley_3000.jld2")
example_file  = joinpath(tambo_path, "examples", "resources", "example_output.jld2")
config_file   = joinpath(tambo_path, "resources", "configuration_examples", "tau_neutrino_cc.toml")

# =============================================================================
# 1. Loading frames
# =============================================================================
# load_frames returns a TamboFrames container. Pass a vector of paths to
# combine multiple files — the geometry (G frame) lives separately from the
# simulation output (M+Q frames), and parent references are reconstructed
# from stream order at load time.

frames = load_frames([geometry_file, example_file])

# =============================================================================
# 2. Exploring the TamboFrames container
# =============================================================================
# The tree-style Base.show summarizes the hierarchy at a glance.

frames                            # tree view: counts per stream + parent links

length(frames)                    # total frame count
length(frames.q_frames)           # event frames only
length(frames.g_frames)           # geometry frames

# Per-stream property accessors return Vector{Frame}. 
frames.g_frames                   # vector containing the one G frame
frames.m_frames                   # one M frame per inject! call (one here)
frames.q_frames[1]                # first event frame

# `frames_of_stream` is the equivalent function call — useful when the stream 
# tag is dynamic, or when you have a plain Vector{Frame} rather than a TamboFrames.
frames.q_frames
frames_of_stream( frames, 'Q' )

# =============================================================================
# 3. Key lookup and parent inheritance
# =============================================================================
# Each Frame is a dictionary-like container. getindex resolves keys against
# own data first, then walks parents in G → C → D → M → Q → P order. The
# .gframe / .mframe shortcuts give direct access to the immediate parent of
# the corresponding stream.

qframe = frames.q_frames[1]
gframe = qframe.gframe
mframe = qframe.mframe

# What's stored on each frame directly:
sort(collect(keys(qframe.data)))  # injection_*, proposal_*, weight_params, event_id
sort(collect(keys(mframe.data)))  # injection / proposal config snapshots
sort(collect(keys(gframe.data)))  # bvh, topography, prem, cs, earth_path, ...

# What's reachable from a Q frame via getindex (own + inherited):
sort(collect(keys(qframe)))

qframe["event_id"]                # own data
qframe["earth_path"]              # inherited from G parent
qframe["injection"]["nevent"]     # inherited from M parent (the inject! config snapshot)

haskey(qframe, "nonexistent_key") # false — getindex on this would throw KeyError

# =============================================================================
# 4. The config that produced this output
# =============================================================================
# Tambo simulation configs are TOML files. inject! and proposal_propagation!
# each take a sub-table from the parsed config and snapshot it onto the M
# frame, so the example_output's M frame mirrors what's in the TOML.

config = TOML.parsefile(config_file)
relativize!(config)

keys(config) |> collect |> sort   # top-level: "injection", "proposal", "corsika", "geometry"

config["injection"]               # injection knobs: energy spectrum, region, PDG, ...
config["proposal"]                # PROPOSAL settings

# The M frame carries a snapshot. For this artifact, nevent and pinecone
# were overridden by make_example_output.jl — see
# _internal/make_example_output.jl for the producer details.
mframe["injection"]["nevent"]     # 50 (overridden by the producer)
mframe["injection"]["pdg"]        # 16 = nu_tau (taken from the TOML)