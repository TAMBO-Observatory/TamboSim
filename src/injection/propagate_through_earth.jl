"""
Custom through-Earth propagation loop for neutrino injection.

Replaces the wholesale `taurunner_interface` call with an explicit stack-based
propagation loop that reuses TauRunner's neutrino primitives (column-depth
stepping, interactions) and PROPOSAL's charged-lepton transport, with a
flexible per-particle stopping box near the detector-side END of the track.

Coordinate spine: geometric distance along the actual backward-traced ray,
measured from the true END (`first(intersections)`, the detector-side point).
The neutrino's column depth comes from `compute_density_prem` (PREM density per
Earth shell); the charged lepton's transport comes from `_run_proposal_segments`
(PREM shell density in rock, nominal density in air). END is computed once by the
caller and threaded to every function so all stopping/vertex logic references the
same point.
"""

# Needed at load time: `TR.Particle` appears in a method signature below, and
# this file is included before julia_interfaces/taurunner.jl (which also imports TR).
import TauRunner as TR

# =============================================================================
# Anomaly accounting
#
# Some chains end in a state we cannot turn into a final particle. Raising there
# would not be loud: `_inject_neutrino_event_impl` wraps this whole call in a
# try/catch that drops the event and logs a backtrace, so an exception costs a
# flooded log and buys nothing an ordinary cull does not. Count them instead, so
# the rate is inspectable and a rare corner cannot masquerade as a clean run.
# =============================================================================

const _propagation_anomalies = Dict{Symbol,Int}()

_note_anomaly!(kind::Symbol) =
    (_propagation_anomalies[kind] = get(_propagation_anomalies, kind, 0) + 1; nothing)

"""
    propagation_anomalies() -> Dict{Symbol,Int}

Counts of through-Earth chains dropped for a reason other than ordinary
absorption, by kind, since the last `reset_propagation_anomalies!`. A healthy run
leaves this empty; a nonzero `:segments_exhausted` points at geometry
inconsistency between the injection trace and the per-lepton forward trace.
"""
propagation_anomalies() = copy(_propagation_anomalies)

"""
    reset_propagation_anomalies!()

Zero the [`propagation_anomalies`](@ref) counters.
"""
reset_propagation_anomalies!() = (empty!(_propagation_anomalies); nothing)

# =============================================================================
# Endcap box length
#
# The stopping box is measured back from the detector-side END of the track.
# Its length lives in the axis natural to whatever process ends the particle's
# useful life:
#   - decay-driven (tau)              -> a length          (`endcap_decay_length`)
#   - interaction/loss-driven (mu, nu)-> a column depth    (`endcap_column_depth`)
# =============================================================================

"""
    endcap_decay_length(particle::Particle) -> Quantity{length}

Endcap box length for a decaying charged lepton: the vacuum decay range for
0.1% survival, `particle_vacuum_range(pdg, energy, 1e-3)`. Returns a length.

Defined for tau (PDG 15); errors otherwise.
"""
function endcap_decay_length(particle::Particle)
    abs(Int(particle.pdg)) == 15 ||
        error("endcap_decay_length: expected tau (15), got $(particle.pdg)")
    return particle_vacuum_range(particle.pdg, particle.energy, 1e-3)
end

"""
    endcap_column_depth(particle::Particle) -> Quantity{grammage}

Endcap box length for a charged lepton that ranges out: its range in rock,
`particle_rock_range(energy, pdg)`. Returns a column depth (g/cm²).

Defined for muon (PDG 13); errors otherwise.
"""
function endcap_column_depth(particle::Particle)
    abs(Int(particle.pdg)) == 13 ||
        error("endcap_column_depth: expected muon (13), got $(particle.pdg)")
    return particle_rock_range(particle.energy, particle.pdg) |> u"g/cm^2"
end

"""
    endcap_column_depth(tr_particle::TR.Particle) -> Quantity{grammage}

Endcap box length for a neutrino: 1/1000 of the interaction mean free path,
`get_total_interaction_depth(tr_particle) / 1000`, converted from TauRunner's
natural units to a column depth (g/cm²).
"""
function endcap_column_depth(tr_particle::TR.Particle)
    mfp_over_1000 = TR.get_total_interaction_depth(tr_particle) * 1e-3
    return mfp_over_1000 / (TR.units.gr / TR.units.cm^2) * u"g/cm^2"
end

# =============================================================================
# Column-depth profile along the ray (neutrino attenuation, PREM densities)
# =============================================================================

"""
    compute_density_prem(intersections, earth, prem) -> Vector{density}

Per-segment PREM density (g/cm³) along the intersection list. Segment `k`
(between `intersections[k-1]` and `intersections[k]`, k ≥ 2) gets the PREM
density evaluated at its midpoint radius via TauRunner's `get_density`. Element
1 is a zero placeholder (the detector-point-to-END stub carries no medium).
"""
function compute_density_prem(intersections, earth, prem)
    center = prem[1].center
    R_earth_m = TR.radius(earth) / TR.units.meter   # outer radius, meters (numeric)
    N = length(intersections)
    ρ = Vector{typeof(1.0u"g/cm^3")}(undef, N)
    ρ[1] = 0.0u"g/cm^3"
    for k in 2:N
        mid = 0.5 .* (intersections[k-1].point.point .+ intersections[k].point.point)
        r_phys_m = ustrip(u"m", norm(mid - center.point))
        r_norm = clamp(r_phys_m / R_earth_m, 0.0, 1.0)
        ρ[k] = (TR.get_density(earth, r_norm) / TR.units.DENSITY_CONV) * u"g/cm^3"
    end
    return ρ
end

"""
    _ColumnDepthProfile

Piecewise-linear column-depth vs geometric-distance profile along the ray,
both measured from END (`intersections[1]`). `e_bkpt[k]` is the geometric
distance from END to `intersections[k]`; `Xcd[k]` the column depth from END to
`intersections[k]`; `ρ[k]` the density of the segment ending at `intersections[k]`.
"""
struct _ColumnDepthProfile
    e_bkpt::Vector{typeof(1.0u"m")}
    Xcd::Vector{typeof(1.0u"g/cm^2")}
    ρ::Vector{typeof(1.0u"g/cm^3")}
    L_track::typeof(1.0u"m")
    Xcd_total::typeof(1.0u"g/cm^2")
end

function _build_column_depth_profile(intersections, earth, prem)
    N = length(intersections)
    ρ = compute_density_prem(intersections, earth, prem)
    end_dist = intersections[1].distance
    e_bkpt = [uconvert(u"m", intersections[k].distance - end_dist) for k in 1:N]
    Xcd = Vector{typeof(1.0u"g/cm^2")}(undef, N)
    Xcd[1] = 0.0u"g/cm^2"
    for k in 2:N
        seg = e_bkpt[k] - e_bkpt[k-1]
        Xcd[k] = Xcd[k-1] + uconvert(u"g/cm^2", ρ[k] * seg)
    end
    return _ColumnDepthProfile(e_bkpt, Xcd, ρ, e_bkpt[N], Xcd[N])
end

"Geometric distance from END corresponding to column depth `Xrem` (from END)."
function _e_of_Xcd(prof::_ColumnDepthProfile, Xrem)
    Xrem <= 0.0u"g/cm^2" && return 0.0u"m"
    Xrem >= prof.Xcd_total && return prof.L_track
    k = searchsortedfirst(prof.Xcd, Xrem)          # first k with Xcd[k] >= Xrem
    return prof.e_bkpt[k-1] + uconvert(u"m", (Xrem - prof.Xcd[k-1]) / prof.ρ[k])
end

"Column depth from END corresponding to geometric distance `e` (from END)."
function _Xcd_of_e(prof::_ColumnDepthProfile, e)
    e <= 0.0u"m" && return 0.0u"g/cm^2"
    e >= prof.L_track && return prof.Xcd_total
    k = searchsortedfirst(prof.e_bkpt, e)
    return prof.Xcd[k-1] + uconvert(u"g/cm^2", prof.ρ[k] * (e - prof.e_bkpt[k-1]))
end

"Geometric distance from END to a point on the ray."
_dist_from_end(end_point, pos) = norm((pos - end_point).point)

_is_neutrino(pdg) = abs(Int(pdg)) in (12, 14, 16)

"The regenerated tau neutrino (PDG ±16) among tau-decay products, or `nothing`."
function _regenerated_tau_neutrino(secondaries)
    nus = filter(s -> abs(Int(s.pdg)) == 16, secondaries)
    isempty(nus) && return nothing
    return argmax(s -> ustrip(u"GeV", s.energy), nus)
end

# =============================================================================
# Per-particle macro-steps
# =============================================================================

"""
    _neutrino_macrostep(p, prof, end_point, revd, xs, rng) -> (final, pushes)

Advance a neutrino by one macro-step: exit if already in the
box; else sample the column-depth step to the next interaction and either
advance to the box edge and exit (if it would enter the box first) or advance to
the interaction point and interact once (CC spawns a charged lepton, NC a
degraded neutrino). `final` is the close-state neutrino if it reached the box (or
a null `Particle` if absorbed), else `nothing`; `pushes` are follow-on particles.
"""
function _neutrino_macrostep(p::Particle{T}, prof, end_point, revd, xs, rng) where {T}
    tr_p = TR.Particle(TR.ParticleType(Int(p.pdg)), ustrip(u"eV", p.energy), 0.0, xs)
    e_p = _dist_from_end(end_point, p.position)
    Xrem = _Xcd_of_e(prof, e_p)
    endcap = endcap_column_depth(tr_p)

    # 1. already in box -> exit as neutrino
    Xrem <= endcap && return (final = p, pushes = Particle{T}[])

    # 2. sample column-depth step to next interaction
    dX = TR.get_proposed_depth_step(tr_p; rng = rng) / (TR.units.gr / TR.units.cm^2) * u"g/cm^2"
    if Xrem - dX <= endcap
        # would enter the box before interacting -> advance to box edge and exit
        e_edge = _e_of_Xcd(prof, endcap)
        pos = e_edge * revd + end_point
        return (final = Particle(p.pdg, p.energy, pos, p.direction), pushes = Particle{T}[])
    end

    # 3. interaction at the sampled depth
    e_int = _e_of_Xcd(prof, Xrem - dX)
    pos = e_int * revd + end_point
    p_cc = TR.get_total_interaction_depth(tr_p) / TR.get_interaction_depth(tr_p, :CC)
    if rand(rng) <= p_cc
        TR.interact!(tr_p, :CC; rng = rng)
        # interact!(:CC) sets survived=false only for a ν_e CC: TauRunner marks the
        # electron partner dead (PROPOSAL absorbs electrons with no transport), so the
        # chain ends here with no final state.
        tr_p.survived || return (final = nothing, pushes = Particle{T}[])
        lepton = Particle(ParticleType(Int(tr_p.id)), tr_p.energy / TR.units.GeV * u"GeV", pos, p.direction)
        return (final = nothing, pushes = Particle{T}[lepton])
    else
        TR.interact!(tr_p, :NC; rng = rng)
        nu = Particle(p.pdg, tr_p.energy / TR.units.GeV * u"GeV", pos, p.direction)
        return (final = nothing, pushes = Particle{T}[nu])
    end
end

"""
    _charged_macrostep(p, end_point, prem, bvh) -> (final, pushes)

Advance a charged lepton toward the box via bounded PROPOSAL transport. The box
edge is one endcap length back from END, measured geometrically — a tau's endcap
is its decay length, a muon's is its rock range converted to a length at rock
density. Exit if already in the box (the lepton is a final state); else propagate
to the box edge (`:reached_cap` → the lepton is a final state) or, if it decays en
route, a tau spawns its regenerated ν_τ while a muon is killed (the chain ends
with no final state). `:no_medium` and `:exited` are culls; the latter is counted
in [`propagation_anomalies`](@ref).
"""
function _charged_macrostep(p::Particle{T}, end_point, prem, bvh) where {T}
    abspdg = abs(Int(p.pdg))
    endcap = if abspdg == 15
        endcap_decay_length(p)                                # length (decay range)
    elseif abspdg == 13
        uconvert(u"m", endcap_column_depth(p) / ROCK_DENSITY) # rock-range grammage -> length
    else
        error("propagate_through_the_earth!: charged-lepton propagation for $(p.pdg) not supported")
    end

    e_p = _dist_from_end(end_point, p.position)
    e_p <= endcap && return (final = p, pushes = Particle{T}[])   # already in box

    max_dist = e_p - endcap                      # geometric distance to box edge
    _, _, secondaries, final_state, stop_reason =
        _run_proposal_segments(p, prem, bvh; max_distance = max_dist, deep = true)

    if stop_reason == :decayed
        if abspdg == 15
            nu = _regenerated_tau_neutrino(secondaries)
            if nu === nothing
                # PROPOSAL reported a tau decay with no ν_τ among the products.
                # Nothing survives to continue the chain, so cull and count.
                _note_anomaly!(:tau_decay_without_nu)
                return (final = nothing, pushes = Particle{T}[])
            end
            return (final = nothing, pushes = Particle{T}[nu])
        else
            # A muon that decays before its box is killed; we do not keep its ν_μ.
            return (final = nothing, pushes = Particle{T}[])
        end
    elseif stop_reason == :reached_cap
        # Reached the box edge -> this lepton is a final state.
        return (final = final_state, pushes = Particle{T}[])
    elseif stop_reason == :no_medium
        # The lepton's forward ray crossed no medium (already in air/space): culled.
        return (final = nothing, pushes = Particle{T}[])
    else
        # :exited — the box edge precedes the ray exit by construction, and
        # `_run_proposal_segments` already forgives a sub-metre shortfall, so
        # arriving here means the injection trace and this lepton's forward trace
        # genuinely disagree about the geometry. Cull and count; see the anomaly
        # accounting note at the top of this file for why this is not an error.
        _note_anomaly!(:segments_exhausted)
        return (final = nothing, pushes = Particle{T}[])
    end
end

# =============================================================================
# Driver
# =============================================================================

"""
    propagate_through_the_earth!(particle, intersections, end_point, prem, bvh, seed=nothing) -> Vector{Particle}

Propagate an injected neutrino from the Earth-entry point through the Earth to
the detector-side box near `end_point`, returning the final states that reached
the box: each is a charged lepton if the neutrino converted (and its lepton
reached the box), or a neutrino if it reached the box uninteracted. A killed or
absorbed chain contributes no final state.

For the current leading chain this returns 0 or 1 final state; the caller
(`_inject_neutrino_event_impl`) owns the NeutrinoInjection contract of a single
`injection_final_state` and errors if more than one is returned. Reuses
TauRunner cross-section/interaction primitives for neutrino stepping and PROPOSAL
(via `_run_proposal_segments`) for charged-lepton transport, driven by an
explicit work stack: neutrino CC spawns a lepton, tau decay spawns a ν_τ
(regeneration). The stack supports future multi-product interactions (hadronic
showers, Glashow) that would return multiple final states.
"""
function propagate_through_the_earth!(
    particle::Particle{T},
    intersections,
    end_point,
    prem,
    bvh::BVHTree{T},
    seed = nothing,
) where {T<:Real}

    earth = _tr_earth[]
    xs = _tr_xs[]
    rng = isnothing(seed) ? Random.default_rng() : Random.MersenneTwister(seed)
    # PROPOSAL's RNG is a process-global singleton; seed it here. Injection is
    # single-threaded — if that changes, these charged-lepton calls need a lock.
    PP.set_random_seed(isnothing(seed) ? rand(Int32) : Int32(mod(seed, typemax(Int32))))

    revd = reverse(particle.direction)
    prof = _build_column_depth_profile(intersections, earth, prem)

    stack = Particle{T}[particle]
    finals = Particle{T}[]

    iters = 0
    while !isempty(stack)
        iters += 1
        if iters > 100_000
            p = stack[end]
            error("propagate_through_the_earth!: exceeded iteration limit (non-progressing chain). " *
                  "stack=$(length(stack)), finals=$(length(finals)), last: pdg=$(p.pdg), " *
                  "E=$(p.energy), dist_from_END=$(_dist_from_end(end_point, p.position))")
        end
        p = pop!(stack)
        result = _is_neutrino(p.pdg) ?
            _neutrino_macrostep(p, prof, end_point, revd, xs, rng) :
            _charged_macrostep(p, end_point, prem, bvh)

        result.final !== nothing && push!(finals, result.final)
        append!(stack, result.pushes)
    end

    return finals
end
