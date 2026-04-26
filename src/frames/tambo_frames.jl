"""
    TamboFrames <: AbstractVector{Frame}

A thin wrapper around `Vector{Frame}` providing hierarchy-aware accessors and
tree-navigation methods. Implements the full `AbstractVector{Frame}` interface,
so any function written against `AbstractVector{Frame}` accepts a `TamboFrames`
without modification.

The underlying `Vector{Frame}` is a depth-first linearization of the frame
tree: walking a `TamboFrames` in order traverses the tree DFS. A higher-rank
frame appearing after a lower-rank frame marks a branch point.

Iteration, indexing, broadcasting, and standard mutation (`push!`, `append!`,
`deleteat!`, `empty!`, `vcat`, `copy`) all delegate to the wrapped vector.

# Fields
- `frames::Vector{Frame}`: wrapped storage.

# Constructors
- `TamboFrames()`: empty.
- `TamboFrames(frames::Vector{Frame})`: wrap an existing vector.
- `TamboFrames(fs::Frame...)`: vararg.
"""
struct TamboFrames <: AbstractVector{Frame}
    frames::Vector{Frame}
end

TamboFrames() = TamboFrames(Frame[])
TamboFrames(fs::Frame...) = TamboFrames(collect(fs))

# AbstractVector interface
Base.size(tf::TamboFrames) = size(tf.frames)
Base.getindex(tf::TamboFrames, i::Int) = tf.frames[i]
Base.setindex!(tf::TamboFrames, v, i::Int) = (tf.frames[i] = v; tf)
Base.IndexStyle(::Type{TamboFrames}) = IndexLinear()

# Mutation
Base.push!(tf::TamboFrames, f::Frame) = (push!(tf.frames, f); tf)
Base.append!(tf::TamboFrames, fs) = (append!(tf.frames, fs); tf)
Base.deleteat!(tf::TamboFrames, inds) = (deleteat!(tf.frames, inds); tf)
Base.empty!(tf::TamboFrames) = (empty!(tf.frames); tf)
Base.vcat(a::TamboFrames, b::TamboFrames) = TamboFrames(vcat(a.frames, b.frames))
Base.copy(tf::TamboFrames) = TamboFrames(copy(tf.frames))
