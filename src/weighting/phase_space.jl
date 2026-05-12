abstract type PhaseSpace end
abstract type PhaseSpacePoint end

# --- Neutrino injection (propagation through Earth; events may be forced CC or upstream-converted) ---

struct NeutrinoInjectionPS <: PhaseSpace
    geometry_hash :: UInt
    pdg           :: Int
    emin     :: Quantity{Float64, edim, typeof(u"GeV")}
    emax     :: Quantity{Float64, edim, typeof(u"GeV")}
    gamma    :: Float64
    thetamin :: Float64   # rad
    thetamax :: Float64   # rad
    phimin   :: Float64   # rad
    phimax   :: Float64   # rad
    nevent   :: Int
end

struct ForcedNeutrinoInteractionPoint <: PhaseSpacePoint
    E        :: Quantity{Float64, edim, typeof(u"GeV")}
    theta    :: Float64   # rad
    phi      :: Float64   # rad
    area     :: Quantity{Float64, ldim^2, typeof(u"m^2")}
    cd       :: Quantity{Float64, mdim/ldim^2, typeof(u"g/cm^2")}
    rho      :: Quantity{Float64, mdim/ldim^3, typeof(u"g/cm^3")}
    sigma    :: Quantity{Float64, ldim^2, typeof(u"cm^2")}
    dsigma   :: Quantity{Float64, ldim^2, typeof(u"cm^2")}
end

struct UpstreamNeutrinoInteractionPoint <: PhaseSpacePoint
    E        :: Quantity{Float64, edim, typeof(u"GeV")}
    theta    :: Float64   # rad
    phi      :: Float64   # rad
    area     :: Quantity{Float64, ldim^2, typeof(u"m^2")}
end

# --- Glashow-resonance ν̄_e → τ⁻ injection ---

struct GlashowPS <: PhaseSpace
    geometry_hash :: UInt
    pdg           :: Int
    emin     :: Quantity{Float64, edim, typeof(u"GeV")}
    emax     :: Quantity{Float64, edim, typeof(u"GeV")}
    gamma    :: Float64
    thetamin :: Float64   # rad
    thetamax :: Float64   # rad
    phimin   :: Float64   # rad
    phimax   :: Float64   # rad
    nevent   :: Int
end

struct GlashowInteractionPoint <: PhaseSpacePoint
    E                  :: Quantity{Float64, edim, typeof(u"GeV")}            # E_ν
    E_tau              :: Quantity{Float64, edim, typeof(u"GeV")}
    theta              :: Float64   # rad
    phi                :: Float64   # rad
    area               :: Quantity{Float64, ldim^2, typeof(u"m^2")}
    rho                :: Quantity{Float64, mdim/ldim^3, typeof(u"g/cm^3")}  # density at vertex
    cd_cap             :: Quantity{Float64, mdim/ldim^2, typeof(u"g/cm^2")}  # cd of τ-decay-range sampling cap
    n_e_vertex         :: Quantity{Float64, ldim^-3, typeof(u"cm^-3")}       # electron number density at vertex
    Ne_entry_to_vertex :: Quantity{Float64, ldim^-2, typeof(u"cm^-2")}       # electron column from Earth-entry to vertex
    sigma_glashow      :: Quantity{Float64, ldim^2, typeof(u"cm^2")}         # total Glashow σ at E_ν
    dsigma_dEtau       :: Quantity{Float64, ldim^2/edim, typeof(u"cm^2/GeV")}# Glashow dσ/dE_τ at (E_ν, E_τ)
end

# --- Cosmic-ray injection (surface sampling) ---

struct CosmicRayInjectionPS <: PhaseSpace
    geometry_hash :: UInt
    pdg           :: Int
    emin     :: Quantity{Float64, edim, typeof(u"GeV")}
    emax     :: Quantity{Float64, edim, typeof(u"GeV")}
    gamma    :: Float64
    thetamin :: Float64   # rad
    thetamax :: Float64   # rad
    phimin   :: Float64   # rad
    phimax   :: Float64   # rad
    nevent   :: Int
end

struct SurfaceCRPoint <: PhaseSpacePoint
    E        :: Quantity{Float64, edim, typeof(u"GeV")}
    theta    :: Float64   # rad
    phi      :: Float64   # rad
    area     :: Quantity{Float64, ldim^2, typeof(u"m^2")}
end

# =============================================================================
# Compatibility guards
# =============================================================================

# Campaign-level: does this PS describe the same geometry + species as the
# campaign that produced events under M? Used to filter the PS list before
# weighting any single Q.
function _compatible(m::Frame, ps::PhaseSpace; prefix::String="injection")
    haskey(m.data, prefix) || return false
    cfg = m[prefix]
    UInt(cfg["geometry_hash"]) == ps.geometry_hash || return false
    Int(cfg["pdg"])            == ps.pdg           || return false
    return true
end

# Per-event: is this point inside this PS's sampler bounds? Geometry and pdg
# are not checked here — the caller (`_oneweight_from_ps`) filters by M↔PS
# first, so by the time we reach the functor those facts already agree.
function _compatible(ps::PhaseSpace, pt::PhaseSpacePoint)
    # Half-open intervals on the upper bound: adjacent campaigns sharing
    # a boundary value are disjoint, not double-counted.
    !(ps.emin     <= pt.E     < ps.emax)     && return false
    !(ps.thetamin <= pt.theta < ps.thetamax) && return false
    # φ wraparound: pt.phi may live in [-π, π] (cart_to_sph convention) while
    # ps.phimin/phimax can sit on a different branch. Compare modulo 2π so a
    # range like [90°, 290°] still admits an event at φ = -π/2 == 3π/2.
    !(mod2pi(pt.phi - ps.phimin) < (ps.phimax - ps.phimin)) && return false
    return true
end

const _zero_iow = 0.0u"GeV^-1 * m^-2 * sr^-1"

# =============================================================================
# Surface pdf helper (shared by upstream-converted neutrino and CR cases)
# =============================================================================

function _surface_pdf(ps::PhaseSpace, pt::PhaseSpacePoint)
    norm = pl_norm(ps.gamma, ps.emin, ps.emax)
    p    = norm * (pt.E / ps.emin)^(-ps.gamma)
    Ω    = (cos(ps.thetamin) - cos(ps.thetamax)) * (ps.phimax - ps.phimin) * u"sr"
    p   /= Ω
    p   /= pt.area
    return uconvert(u"GeV^-1 * m^-2 * sr^-1", p)
end

# =============================================================================
# Functor methods
# =============================================================================

function (ps::NeutrinoInjectionPS)(pt::ForcedNeutrinoInteractionPoint)
    _compatible(ps, pt) || return _zero_iow

    # Monte Carlo phase-space density (energy × angular × area × interaction)
    norm = pl_norm(ps.gamma, ps.emin, ps.emax)
    mc   = norm * (pt.E / ps.emin)^(-ps.gamma)
    Ω    = (cos(ps.thetamin) - cos(ps.thetamax)) * (ps.phimax - ps.phimin) * u"sr"
    mc  /= Ω
    mc  /= pt.area
    mc  *= pt.rho / pt.cd
    mc  *= pt.dsigma / pt.sigma

    # Physical interaction probability density along the trajectory
    miso = speedoflight^(-2) * (938.27208816u"MeV" + 939.5654133u"MeV") / 2
    phys  = pt.cd / miso
    phys *= pt.rho / pt.cd
    phys *= pt.dsigma

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

# Weight functor for Glashow-resonance ν̄_e injection.
#
# Returns the inverse-one-weight density in [GeV⁻¹ m⁻² sr⁻¹] = p_mc / p_phys,
# matching the convention used by `ForcedNeutrinoInteractionPoint`.
#
# Sampled MC variables and densities:
#   E_ν   : p_pl(E_ν)              (1/GeV)
#   Ω     : uniform on Ω-box        (1/sr)
#   A     : area-weighted point     (1/m^2)
#   y     : p_mc(y) = 3(1-y)^2      (dimensionless)  ; y = E_τ/E_ν
#   x     : uniform in cd on        (1/(g/cm^2))
#           [0, cd_cap]
#
# y → E_τ Jacobian:  p_mc(E_τ) = 3(1-y)^2 / E_ν
# cd → x Jacobian:   p_mc(x)   = ρ / cd_cap
#
# Physical density (per (E_ν, Ω, A, E_τ, x)):
#   p_phys = n_e(x) · dσ/dE_τ · exp(-N_e(0→x) · σ_glashow)
# (CC/NC absorption on nucleons intentionally omitted; survival factor uses
# Glashow σ only — see project plan.)
function (ps::GlashowPS)(pt::GlashowInteractionPoint)
    _compatible(ps, pt) || return _zero_iow

    norm = pl_norm(ps.gamma, ps.emin, ps.emax)
    mc   = norm * (pt.E / ps.emin)^(-ps.gamma)
    Ω    = (cos(ps.thetamin) - cos(ps.thetamax)) * (ps.phimax - ps.phimin) * u"sr"
    mc  /= Ω
    mc  /= pt.area
    mc  *= pt.rho / pt.cd_cap
    y    = pt.E_tau / pt.E
    mc  *= 3 * (1 - y)^2 / pt.E

    phys = pt.n_e_vertex * pt.dsigma_dEtau * exp(-pt.Ne_entry_to_vertex * pt.sigma_glashow)

    return uconvert(u"GeV^-1 * m^-2 * sr^-1", mc / phys)
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

function _oneweight_from_ps(
    q::Frame,
    phase_spaces::Vector{<:PhaseSpace};
    prefix::String="injection",
)
    if !haskey(q.data, "phase_space_point")
        eid = get(q.data, "event_id", "unknown")
        @warn "Q frame (event_id=$eid) has no phase_space_point key — returning zero weight."
        return _zero_ow
    end
    pt       = q["phase_space_point"]
    m        = q.m_frame
    matching = filter(ps -> _compatible(m, ps; prefix), phase_spaces)
    isempty(matching) && return _zero_ow
    for ps in matching
        if ps.nevent == 0
            eid = get(q.data, "event_id", "unknown")
            @warn "Compatible PhaseSpace ($(typeof(ps)), pdg=$(ps.pdg)) has nevent=0 — this campaign will contribute zero weight. Check your injection config (event_id=$eid)."
        end
    end
    total = sum(ps -> ps(pt) * ps.nevent, matching)
    iszero(ustrip(total)) && return _zero_ow
    return uconvert(_one_weight_units, inv(total))
end

"""
    oneweight(tf::TamboFrames, q::Frame; prefix="injection") -> Quantity

Per-event one-weight in units of `GeV·m²·sr`. Returns zero if `q` has no
`"phase_space_point"` key (failed injection) with a warning, or if no M frame
contributes a non-zero phase-space density.
"""
function oneweight(tf::TamboFrames, q::Frame; prefix::String="injection")
    phase_spaces = [build_phase_space(m; prefix) for m in tf.m_frames]
    return _oneweight_from_ps(q, phase_spaces; prefix)
end

"""
    oneweights(tf::TamboFrames; prefix="injection") -> Vector{<:Quantity}

Compute one-weights for all Q frames in `tf`. Phase-space functors are
constructed once per M frame and reused across all Q frames.
"""
function oneweights(tf::TamboFrames; prefix::String="injection")
    phase_spaces = [build_phase_space(m; prefix) for m in tf.m_frames]
    return map(tf.q_frames) do q
        _oneweight_from_ps(q, phase_spaces; prefix)
    end
end

"""
    oneweights!(tf::TamboFrames; key="oneweight", prefix="injection")

Compute one-weights for all Q frames in `tf` and store the result in each Q
frame under `key`. Phase-space functors are constructed once per M frame and
reused across all Q frames.
"""
function oneweights!(tf::TamboFrames; key::String="oneweight", prefix::String="injection")
    phase_spaces = [build_phase_space(m; prefix) for m in tf.m_frames]
    for q in tf.q_frames
        q[key] = _oneweight_from_ps(q, phase_spaces; prefix)
    end
end

# =============================================================================
# PhaseSpace factory
# =============================================================================

"""
    build_phase_space(m::Frame; prefix::String="injection") -> PhaseSpace

Construct the appropriate `PhaseSpace` subtype from an M frame's injection
config. The config table at `m[prefix]` must declare `strategy`, set to
one of `"NeutrinoInjection"` or `"CosmicRayInjection"`, and must carry the
`geometry_hash` snapshot that `_setup_injection` writes at injection time.
"""
function build_phase_space(m::Frame; prefix::String="injection")
    cfg = m[prefix]
    args = (
        UInt(cfg["geometry_hash"]),
        Int(cfg["pdg"]),
        Float64(cfg["emin"]) * u"GeV",
        Float64(cfg["emax"]) * u"GeV",
        Float64(cfg["gamma"]),
        deg2rad(Float64(cfg["thetamin"])),
        deg2rad(Float64(cfg["thetamax"])),
        deg2rad(Float64(cfg["phimin"])),
        deg2rad(Float64(cfg["phimax"])),
        Int(cfg["nevent"]),
    )
    haskey(cfg, "strategy") || error(
        "build_phase_space: M frame config (prefix=\"$prefix\") is missing " *
        "required `strategy` field. Set it to one of \"NeutrinoInjection\" " *
        "or \"CosmicRayInjection\". See resources/configuration_examples/ " *
        "for the current schema."
    )
    strategy = cfg["strategy"]
    if strategy == "NeutrinoInjection"
        return NeutrinoInjectionPS(args...)
    elseif strategy == "CosmicRayInjection"
        return CosmicRayInjectionPS(args...)
    elseif strategy == "GlashowInjection"
        return GlashowPS(args...)
    else
        error(
            "build_phase_space: unknown strategy \"$strategy\". " *
            "Known strategies: \"NeutrinoInjection\", \"CosmicRayInjection\", \"GlashowInjection\"."
        )
    end
end
