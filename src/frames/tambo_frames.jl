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
"""
    _descendants_closure(frames, targets) -> IdDict{Frame, Nothing}

Return the downward closure of `targets` under the parent-child relation: an
identity-keyed set containing every target plus every frame in `frames` whose
`parents` map (transitively) references any target.

Internal helper. Currently used by `deleteat!` with `remove_children=true`.
Can be promoted to public API if a second consumer appears.
"""
function _descendants_closure(frames::AbstractVector{Frame}, targets)
    # Inverse parents map: frame → its children in the container.
    children_of = IdDict{Frame, Vector{Frame}}()
    for f in frames
        for p in values(f.parents)
            push!(get!(children_of, p, Frame[]), f)
        end
    end

    # BFS from targets, including the targets themselves.
    closure = IdDict{Frame, Nothing}()
    queue = Frame[]
    for t in targets
        if !haskey(closure, t)
            closure[t] = nothing
            push!(queue, t)
        end
    end
    while !isempty(queue)
        f = popfirst!(queue)
        for child in get(children_of, f, Frame[])
            if !haskey(closure, child)
                closure[child] = nothing
                push!(queue, child)
            end
        end
    end
    closure
end

"""
    deleteat!(tf::TamboFrames, inds; remove_children=false)

Delete frames at the given indices. If `remove_children=true`, also remove all
frames whose `parents` map (transitively) references any deleted frame —
useful for cleanly excising a whole subtree from an ensemble.
"""
function Base.deleteat!(tf::TamboFrames, inds; remove_children::Bool=false)
    if !remove_children
        deleteat!(tf.frames, inds)
        return tf
    end

    initial_indices = if inds isa Integer
        Int[inds]
    elseif inds isa AbstractVector{Bool}
        findall(inds)
    else
        collect(Int, inds)
    end

    targets = (tf.frames[i] for i in initial_indices)
    to_remove = _descendants_closure(tf.frames, targets)

    indices_to_remove = Int[]
    for (i, f) in enumerate(tf.frames)
        haskey(to_remove, f) && push!(indices_to_remove, i)
    end
    deleteat!(tf.frames, indices_to_remove)
    return tf
end
Base.empty!(tf::TamboFrames) = (empty!(tf.frames); tf)
Base.vcat(a::TamboFrames, b::TamboFrames) = TamboFrames(vcat(a.frames, b.frames))
Base.copy(tf::TamboFrames) = TamboFrames(copy(tf.frames))

# Stream filters --------------------------------------------------------------

"""
    frames_of_stream(frames, stream::Char) -> Vector{Frame}

Return the subset of `frames` whose stream tag matches `stream`. Defined on
`AbstractVector{Frame}`, so it works on both `TamboFrames` and plain
`Vector{Frame}`.
"""
frames_of_stream(frames::AbstractVector{Frame}, s::Char) =
    filter(f -> f.stream == s, frames)

"""
    g_frames(frames), c_frames(frames), d_frames(frames),
    m_frames(frames), q_frames(frames), r_frames(frames)

Short aliases for `frames_of_stream(frames, 'G')` etc., one per stream tag in
the `G → C → D → M → Q → R` hierarchy. Return `Vector{Frame}`.
"""
g_frames(frames::AbstractVector{Frame}) = frames_of_stream(frames, 'G')
c_frames(frames::AbstractVector{Frame}) = frames_of_stream(frames, 'C')
d_frames(frames::AbstractVector{Frame}) = frames_of_stream(frames, 'D')
m_frames(frames::AbstractVector{Frame}) = frames_of_stream(frames, 'M')
q_frames(frames::AbstractVector{Frame}) = frames_of_stream(frames, 'Q')
r_frames(frames::AbstractVector{Frame}) = frames_of_stream(frames, 'R')

# Validation ------------------------------------------------------------------

"""
    hierarchy_violations(frames::AbstractVector{Frame}) -> Vector{NamedTuple}

Return a list of structural violations in the frame hierarchy. Each violation
is a `NamedTuple` `(idx, kind, msg)`:

- `idx`: position of the offending frame in `frames`
- `kind`: symbol classifying the violation
    - `:unknown_stream` — frame's stream char is not in `STREAM_HIERARCHY`
    - `:parent_key_mismatch` — `parents[c]` references a frame whose `stream != c`
    - `:parent_rank` — parent has equal-or-lower rank than child
    - `:parent_not_in_container` — parent pointer references a frame not in `frames`
    - `:parent_appears_later` — parent appears at index ≥ child's (violates DFS ordering)
- `msg`: human-readable description

An empty list means the container is well-formed. Within-a-frame invariants
(e.g. Q frames must have a C parent) are enforced at `Frame` construction and
are not re-checked here.

Validation is opt-in. Construction of a `TamboFrames` does not call this; nor
do the standard accessors. Methods that genuinely depend on the linearization
invariant (e.g. `subtrees`) assert validity at their entry points.
"""
function hierarchy_violations(frames::AbstractVector{Frame})
    violations = NamedTuple{(:idx, :kind, :msg), Tuple{Int, Symbol, String}}[]
    rank(c::Char) = findfirst(==(c), STREAM_HIERARCHY)

    positions = IdDict{Frame, Int}()
    for (i, f) in enumerate(frames)
        positions[f] = i
    end

    for (i, f) in enumerate(frames)
        r_self = rank(f.stream)
        if isnothing(r_self)
            push!(violations, (idx=i, kind=:unknown_stream,
                msg="frame at $i has stream '$(f.stream)' not in STREAM_HIERARCHY"))
            continue
        end

        for (key, parent) in f.parents
            if key != parent.stream
                push!(violations, (idx=i, kind=:parent_key_mismatch,
                    msg="frame at $i has parents['$key'] but parent.stream='$(parent.stream)'"))
            end

            r_par = rank(parent.stream)
            if isnothing(r_par) || r_par >= r_self
                push!(violations, (idx=i, kind=:parent_rank,
                    msg="frame at $i (stream '$(f.stream)') has parent of equal/lower rank '$(parent.stream)'"))
            end

            if !haskey(positions, parent)
                push!(violations, (idx=i, kind=:parent_not_in_container,
                    msg="frame at $i has parent (stream '$(parent.stream)') not present in container"))
            elseif positions[parent] >= i
                push!(violations, (idx=i, kind=:parent_appears_later,
                    msg="frame at $i has parent at position $(positions[parent])"))
            end
        end
    end
    violations
end

"""
    is_valid_hierarchy(frames::AbstractVector{Frame}) -> Bool

Return `true` iff `hierarchy_violations(frames)` is empty.
"""
is_valid_hierarchy(frames::AbstractVector{Frame}) = isempty(hierarchy_violations(frames))
