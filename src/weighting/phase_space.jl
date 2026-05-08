abstract type PhaseSpace end
abstract type PhaseSpacePoint end

# --- Neutrino injection (propagation through Earth; events may be forced CC or upstream-converted) ---

struct NeutrinoInjectionPS <: PhaseSpace
    g_frame  :: Frame
    pdg      :: Int
    emin     :: Float64   # GeV
    emax     :: Float64   # GeV
    gamma    :: Float64
    thetamin :: Float64   # rad
    thetamax :: Float64   # rad
    phimin   :: Float64   # rad
    phimax   :: Float64   # rad
    nevent   :: Int
end

struct ForcedNeutrinoInteractionPoint <: PhaseSpacePoint
    g_frame  :: Frame
    pdg      :: Int
    E        :: Float64   # GeV, injected neutrino energy
    theta    :: Float64   # rad
    phi      :: Float64   # rad
    area     :: Float64   # m²  (sum of visible detector face areas for this event)
    cd       :: Float64   # g/cm² (column depth to forced-CC vertex)
    rho      :: Float64   # g/cm³ (density at vertex)
    sigma    :: Float64   # cm² (total cross section)
    dsigma   :: Float64   # cm² (differential cross section evaluated at final-state energy)
end

struct UpstreamNeutrinoInteractionPoint <: PhaseSpacePoint
    g_frame  :: Frame
    pdg      :: Int
    E        :: Float64   # GeV, injected neutrino energy
    theta    :: Float64   # rad
    phi      :: Float64   # rad
    area     :: Float64   # m²
end

# --- Cosmic-ray injection (surface sampling) ---

struct CosmicRayInjectionPS <: PhaseSpace
    g_frame  :: Frame
    pdg      :: Int
    emin     :: Float64   # GeV
    emax     :: Float64   # GeV
    gamma    :: Float64
    thetamin :: Float64   # rad
    thetamax :: Float64   # rad
    phimin   :: Float64   # rad
    phimax   :: Float64   # rad
    nevent   :: Int
end

struct SurfaceCRPoint <: PhaseSpacePoint
    g_frame  :: Frame
    pdg      :: Int
    E        :: Float64   # GeV, injected CR energy
    theta    :: Float64   # rad
    phi      :: Float64   # rad
    area     :: Float64   # m²
end

# =============================================================================
# Compatibility guard — shared by all functor methods
# =============================================================================

function _compatible(ps::PhaseSpace, pt::PhaseSpacePoint)
    if !haskey(ps.g_frame, "geometry_hash") || !haskey(pt.g_frame, "geometry_hash")
        error("_compatible: G frame is missing `geometry_hash`. Old JLD2 files predating the geometry-hash plumbing must be re-saved through `build_gcd_bundle` / `load_earth!` before they can be weighted.")
    end
    ps.g_frame["geometry_hash"] != pt.g_frame["geometry_hash"] && return false
    ps.pdg != pt.pdg         && return false
    # Half-open intervals on the upper bound: adjacent campaigns sharing
    # a boundary value are disjoint, not double-counted.
    !(ps.emin     <= pt.E     < ps.emax)     && return false
    !(ps.thetamin <= pt.theta < ps.thetamax) && return false
    !(ps.phimin   <= pt.phi   < ps.phimax)   && return false
    return true
end

const _zero_iow = 0.0u"GeV^-1 * m^-2 * sr^-1"

# =============================================================================
# Surface pdf helper (shared by upstream-converted neutrino and CR cases)
# =============================================================================

function _surface_pdf(ps::PhaseSpace, pt::PhaseSpacePoint)
    norm = pl_norm(ps.gamma, ps.emin * u"GeV", ps.emax * u"GeV")
    p    = norm * (pt.E / ps.emin)^(-ps.gamma)
    Ω    = (cos(ps.thetamin) - cos(ps.thetamax)) * (ps.phimax - ps.phimin) * u"sr"
    p   /= Ω
    p   /= pt.area * u"m^2"
    return uconvert(u"GeV^-1 * m^-2 * sr^-1", p)
end

# =============================================================================
# Functor methods
# =============================================================================

function (ps::NeutrinoInjectionPS)(pt::ForcedNeutrinoInteractionPoint)
    _compatible(ps, pt) || return _zero_iow
    mc   = p_mc(
        pt.area   * u"m^2",
        ps.emin   * u"GeV", ps.emax * u"GeV", ps.gamma,
        ps.thetamin, ps.thetamax, ps.phimin, ps.phimax,
        pt.E      * u"GeV",
        pt.cd     * u"g/cm^2",
        pt.rho    * u"g/cm^3",
        pt.sigma  * u"cm^2",
        pt.dsigma * u"cm^2",
    )
    phys = p_phys(pt.cd * u"g/cm^2", pt.rho * u"g/cm^3", pt.dsigma * u"cm^2")
    return uconvert(u"GeV^-1 * m^-2 * sr^-1", mc / phys)
end

function (ps::NeutrinoInjectionPS)(pt::UpstreamNeutrinoInteractionPoint)
    _compatible(ps, pt) || return _zero_iow
    return _surface_pdf(ps, pt)
end

function (ps::CosmicRayInjectionPS)(pt::SurfaceCRPoint)
    _compatible(ps, pt) || return _zero_iow
    return _surface_pdf(ps, pt)
end

function (ps::PhaseSpace)(pt::PhaseSpacePoint)
    @warn "No functor method defined for ($(typeof(ps)))($(typeof(pt))). Returning zero weight. This is likely a bug — check that PhaseSpace and PhaseSpacePoint types are consistent."
    return _zero_iow
end

# =============================================================================
# oneweight public API
# =============================================================================

const _one_weight_units = u"GeV*m^2*sr"
const _zero_ow = 0.0u"GeV*m^2*sr"

function _oneweight_from_ps(q::Frame, phase_spaces::Vector{<:PhaseSpace})
    if !haskey(q.data, "phase_space_point")
        eid = get(q.data, "event_id", "unknown")
        @warn "Q frame (event_id=$eid) has no phase_space_point key — returning zero weight."
        return _zero_ow
    end
    pt    = q["phase_space_point"]
    total = sum(ps -> ps(pt) * ps.nevent, phase_spaces)
    iszero(ustrip(total)) && return _zero_ow
    return uconvert(_one_weight_units, inv(total))
end

"""
    oneweight(tf::TamboFrames, q::Frame) -> Quantity

Per-event one-weight in units of `GeV·m²·sr`. Returns zero if `q` has no
`"phase_space_point"` key (failed injection) with a warning, or if no M frame
contributes a non-zero phase-space density.
"""
function oneweight(tf::TamboFrames, q::Frame)
    phase_spaces = [build_phase_space(m) for m in tf.m_frames]
    return _oneweight_from_ps(q, phase_spaces)
end

"""
    oneweights(tf::TamboFrames) -> Vector{<:Quantity}

Compute one-weights for all Q frames in `tf`. Phase-space functors are
constructed once per M frame and reused across all Q frames.
"""
function oneweights(tf::TamboFrames)
    phase_spaces = [build_phase_space(m) for m in tf.m_frames]
    return map(tf.q_frames) do q
        _oneweight_from_ps(q, phase_spaces)
    end
end

"""
    oneweights!(tf::TamboFrames)

Compute one-weights for all Q frames in `tf` and store the result in each Q
frame under the key `"oneweight"`. Phase-space functors are constructed once
per M frame and reused across all Q frames.
"""
function oneweights!(tf::TamboFrames; key::String="oneweight")
    phase_spaces = [build_phase_space(m) for m in tf.m_frames]
    for q in tf.q_frames
        q[key] = _oneweight_from_ps(q, phase_spaces)
    end
end

# =============================================================================
# PhaseSpace factory
# =============================================================================

"""
    build_phase_space(m::Frame) -> PhaseSpace

Construct the appropriate `PhaseSpace` subtype from an M frame's injection
config. Neutrino campaigns (those with an `"xs_location"` key) produce a
`NeutrinoInjectionPS`; cosmic-ray campaigns produce a `CosmicRayInjectionPS`.
"""
function build_phase_space(m::Frame, prefix::String="injection")
    cfg = m[prefix]
    g      = m.g_frame
    args = (
        g,
        Int(cfg["pdg"]),
        Float64(cfg["emin"]),
        Float64(cfg["emax"]),
        Float64(cfg["gamma"]),
        deg2rad(Float64(cfg["thetamin"])),
        deg2rad(Float64(cfg["thetamax"])),
        deg2rad(Float64(cfg["phimin"])),
        deg2rad(Float64(cfg["phimax"])),
        Int(cfg["nevent"]),
    )
    if haskey(cfg, "xs_location")
        return NeutrinoInjectionPS(args...)
    else
        return CosmicRayInjectionPS(args...)
    end
end
