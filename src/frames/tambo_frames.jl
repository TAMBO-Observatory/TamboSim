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

const _STREAM_PROPERTY = Dict(
    :g_frames => 'G',
    :c_frames => 'C',
    :d_frames => 'D',
    :m_frames => 'M',
    :q_frames => 'Q',
    :p_frames => 'P',
)

"""
    tf.g_frames, tf.c_frames, tf.d_frames, tf.m_frames, tf.q_frames, tf.p_frames

Property accessors that return all frames of the given stream from `tf`. One
per stream tag in the `G → C → D → M → Q → P` hierarchy.

These mirror the singular `f.g_frame` / `f.c_frame` / etc. parent-property idiom
on individual frames: dotted access, computed on each call. For a plain
`Vector{Frame}` (or when the stream tag is dynamic) use `frames_of_stream`.
"""
function Base.getproperty(tf::TamboFrames, sym::Symbol)
    stream = get(_STREAM_PROPERTY, sym, nothing)
    stream === nothing && return getfield(tf, sym)
    return frames_of_stream(getfield(tf, :frames), stream)
end

Base.propertynames(::TamboFrames, private::Bool=false) =
    (:frames, keys(_STREAM_PROPERTY)...)

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

# Pretty-printing -------------------------------------------------------------

const _CHILDREN_CAP = 3
const _COLLAPSE_STREAMS = ('Q', 'P')

function Base.show(io::IO, ::MIME"text/plain", tf::TamboFrames)
    # Header: counts per stream in hierarchy order.
    counts = Dict{Char, Int}()
    for f in tf
        counts[f.stream] = get(counts, f.stream, 0) + 1
    end
    parts = String[]
    for s in STREAM_HIERARCHY
        haskey(counts, s) && push!(parts, "$(counts[s]) $s")
    end
    println(io, "TamboFrames (", join(parts, ", "), ")")
    isempty(tf) && return

    children_of = _immediate_children_map(tf.frames)
    rs = filter(f -> isempty(f.parents), tf.frames)
    _render_children(io, rs, children_of, "")
end

function _immediate_children_map(frames::AbstractVector{Frame})
    children_of = IdDict{Frame, Vector{Frame}}()
    for f in frames
        isempty(f.parents) && continue
        # Immediate parent: highest STREAM_HIERARCHY index among the frame's parents.
        best_idx = -1
        best_parent = nothing
        for parent in values(f.parents)
            idx = findfirst(==(parent.stream), STREAM_HIERARCHY)
            if !isnothing(idx) && idx > best_idx
                best_idx = idx
                best_parent = parent
            end
        end
        best_parent === nothing && continue
        push!(get!(children_of, best_parent, Frame[]), f)
    end
    children_of
end

function _stream_runs(children::AbstractVector{Frame})
    runs = Tuple{Char, Vector{Frame}}[]
    isempty(children) && return runs
    cur_stream = children[1].stream
    cur_group = Frame[children[1]]
    for c in @view children[2:end]
        if c.stream == cur_stream
            push!(cur_group, c)
        else
            push!(runs, (cur_stream, cur_group))
            cur_stream = c.stream
            cur_group = Frame[c]
        end
    end
    push!(runs, (cur_stream, cur_group))
    runs
end

function _render_children(io, children, children_of, prefix)
    isempty(children) && return
    runs = _stream_runs(children)
    for (gi, (stream, group)) in enumerate(runs)
        is_last_run = (gi == length(runs))
        if stream in _COLLAPSE_STREAMS
            g_branch = is_last_run ? "└─ " : "├─ "
            label = length(group) == 1 ? "$stream" : "$stream × $(length(group))"
            println(io, prefix, g_branch, label)
        else
            n = length(group)
            n_show = n > _CHILDREN_CAP ? _CHILDREN_CAP : n
            for i in 1:n_show
                child_is_last = is_last_run && i == n_show && n_show == n
                _render_subtree(io, group[i], children_of, prefix, child_is_last)
            end
            if n > n_show
                t_branch = is_last_run ? "└─ " : "├─ "
                println(io, prefix, t_branch, "… (", n - n_show, " more ", stream, ")")
            end
        end
    end
end

function _render_subtree(io, frame, children_of, prefix, is_last)
    branch = is_last ? "└─ " : "├─ "

    # Collapse runs of single-child frames into a horizontal `A → B → C` chain.
    # Box-drawing resumes at the first branch point or terminal `× N` collapse.
    chain_labels = String[string(frame.stream)]
    cur = frame
    branched_children = Frame[]
    while true
        children = get(children_of, cur, Frame[])
        isempty(children) && break
        runs = _stream_runs(children)
        if length(runs) != 1
            branched_children = children
            break
        end
        (run_stream, run_group) = runs[1]
        if run_stream in _COLLAPSE_STREAMS
            label = length(run_group) == 1 ? "$run_stream" : "$run_stream × $(length(run_group))"
            push!(chain_labels, label)
            break
        end
        if length(run_group) != 1
            branched_children = children
            break
        end
        cur = run_group[1]
        push!(chain_labels, string(cur.stream))
    end

    chain_text = join(chain_labels, " → ")
    println(io, prefix, branch, chain_text)

    isempty(branched_children) && return
    chain_indent = length(chain_text) - length(chain_labels[end])
    new_prefix = prefix * (is_last ? "   " : "│  ") * (" " ^ chain_indent)
    _render_children(io, branched_children, children_of, new_prefix)
end
