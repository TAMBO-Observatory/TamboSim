# Glashow resonance ν̄_e + e⁻ → W⁻ → τ⁻ + ν̄_τ injection.
#
# Differs from the tau-neutrino injection path in two ways:
#   1. No TauRunner. Earth absorption on the ν̄_e is ignored except through
#      the survival factor in the per-event weight (using Glashow σ only,
#      per project convention).
#   2. The forced interaction is the Glashow resonance on atomic electrons,
#      so the cross sections are computed analytically here rather than
#      sampled from a CSMS HDF5 table.

# ---------------------------------------------------------------------------
# Glashow cross sections
# ---------------------------------------------------------------------------

const _GLASHOW_HBAR_C = 1.97327e-5 * u"eV*cm"
const _GLASHOW_GF     = 1.16639e-23 * u"eV^-2"
const _GLASHOW_M_E    = 0.51099895e6 * u"eV"
const _GLASHOW_M_TAU  = 1776.86e6 * u"eV"
const _GLASHOW_M_W    = 80.4e9 * u"eV"
const _GLASHOW_GAMMA_W = 2.09e9 * u"eV"

# Standard-rock Z/A · N_A: electrons per gram. Multiply by density (g/cm^3)
# to get electron number density (1/cm^3), or by column depth (g/cm^2) to
# get electron column (1/cm^2).
const _ELECTRONS_PER_GRAM = 0.5 * 6.02214076e23 / u"g"

"""
    glashow_dsigma_dy_tau(E_nu::Quantity, y::Real) -> Quantity{cm^2}

Differential cross section dσ/dy for ν̄_e + e⁻ → W⁻ → τ⁻ + ν̄_τ with
y = E_τ / E_ν, evaluated using the exact Breit–Wigner propagator on s = 2 m_e E_ν.
Returns zero below threshold or outside y ∈ [0, 1].
"""
function glashow_dsigma_dy_tau(E_nu::Quantity, y::Real)
    s = 2 * _GLASHOW_M_E * uconvert(u"eV", E_nu)
    threshold = _GLASHOW_M_TAU^2 - _GLASHOW_M_E^2
    if s <= threshold || y < 0.0 || y > 1.0
        return 0.0u"cm^2"
    end
    phase = (1.0 - threshold / s)^2
    propagator = (1.0 - s / _GLASHOW_M_W^2)^2 + (_GLASHOW_GAMMA_W / _GLASHOW_M_W)^2
    pref = _GLASHOW_HBAR_C^2 * _GLASHOW_GF^2 * _GLASHOW_M_E * uconvert(u"eV", E_nu) / (2π)
    return uconvert(u"cm^2", pref * 4.0 * (1.0 - y)^2 * phase / propagator)
end

"""
    glashow_sigma_tau_total(E_nu::Quantity) -> Quantity{cm^2}

Integrated cross section for ν̄_e + e⁻ → W⁻ → τ⁻ + ν̄_τ. Uses
∫₀¹ 4(1−y)² dy = 4/3.
"""
function glashow_sigma_tau_total(E_nu::Quantity)
    s = 2 * _GLASHOW_M_E * uconvert(u"eV", E_nu)
    threshold = _GLASHOW_M_TAU^2 - _GLASHOW_M_E^2
    if s <= threshold
        return 0.0u"cm^2"
    end
    phase = (1.0 - threshold / s)^2
    propagator = (1.0 - s / _GLASHOW_M_W^2)^2 + (_GLASHOW_GAMMA_W / _GLASHOW_M_W)^2
    pref = _GLASHOW_HBAR_C^2 * _GLASHOW_GF^2 * _GLASHOW_M_E * uconvert(u"eV", E_nu) / (2π)
    return uconvert(u"cm^2", pref * (4.0 / 3.0) * phase / propagator)
end

# ---------------------------------------------------------------------------
# Per-event injection
# ---------------------------------------------------------------------------

"""
    inject_glashow_event(prem, bvh, cs, detector_region, as, pl, detector_props;
                        epsilon=1e-6*u"m")

Inject a single ν̄_e → Glashow → τ⁻ event. Mirrors `inject_neutrino_event`
through detector-point sampling and trajectory validation, then skips
TauRunner: the outgoing τ energy is drawn from the Glashow dσ/dy distribution
(p(y) ∝ (1-y)² ⇒ y = 1 − u^{1/3}), and the vertex is sampled along the rock
chord up to the τ-decay range cap exactly as in the existing CC code path.

Returns `(initial_state, close_state, final_state, point)` where
`close_state == initial_state` (no Earth propagation is modelled) and
`final_state` is a `TauMinus` at the interaction vertex.
"""
function inject_glashow_event(
    prem,
    bvh::BVHTree{T},
    cs::CoordinateSystem{T},
    detector_region,
    as::UniformAngularSampler,
    pl::UnitfulPowerLawSampler,
    detector_props::DetectorProperties{T};
    epsilon=1e-6*u"m",
) where {T<:Real}
    return _inject_glashow_event_impl(
        prem, bvh, cs, detector_region, as, pl,
        detector_props.triangles, detector_props.normals,
        detector_props.bvh, detector_props.areas,
        epsilon,
    )
end

function _inject_glashow_event_impl(
    prem,
    bvh::BVHTree{T},
    cs::CoordinateSystem{T},
    detector_region,
    as::UniformAngularSampler,
    pl::UnitfulPowerLawSampler,
    detector_triangles::Vector{Triangle{T}},
    detector_normals::Vector{Direction{T}},
    detector_bvh::BVHTree{T},
    detector_areas::Vector{Quantity{T,ldim^2,typeof(u"m^2")}},
    epsilon,
) where {T<:Real}

    pdg = Int(NuEBar)

    d = rand(as, cs)
    p, visible_areas = sample_detector_point(
        detector_triangles, detector_normals, detector_areas,
        detector_bvh, d, cs, epsilon
    )
    if isnothing(p)
        return _create_null_neutrino_result(pdg, INJECTION_ERROR_NO_VISIBLE_TRIANGLES, d, cs, T)
    end

    revd = reverse(d)
    intersections, error_code = validate_earth_trajectory(prem, bvh, detector_region, p, revd)
    if isnothing(intersections)
        return _create_null_neutrino_result(pdg, error_code, d, cs, T)
    end

    initial_energy = rand(pl)
    initial_state = Particle(NuEBar, initial_energy, p, d)

    try
        # Sample y ~ 3(1-y)^2 on [0,1] via inverse CDF (CDF = 1 - (1-y)^3).
        y = 1 - rand()^(1/3)
        e_tau = y * initial_energy

        # Vertex sampling: uniform in column depth within the τ-decay range cap,
        # exactly as `force_interaction_vertex` does for CC τ output.
        tau_range = particle_vacuum_range(TauMinus, e_tau)
        distance, cd_to_vertex, cd_cap, density = find_vertex_distance_by_distance_with_cd_to_vertex(
            revd, tau_range, intersections
        )

        # Electron column from first Earth entry (= farthest intersection along
        # the backward ray) to the vertex, along the actual forward ν̄_e path.
        # cd_to_vertex above is measured from intersections[1] (the detector
        # surface point) outward along revd, so the "from Earth-entry along
        # forward path" column is total_path_cd − cd_to_vertex.
        densities_all = @views compute_density(intersections, revd)[2:end]
        lengths_all   = @views compute_lengths(intersections)[2:end]
        total_path_cd = sum(l * ρ for (l, ρ) in zip(lengths_all, densities_all))
        cd_entry_to_vertex = total_path_cd - cd_to_vertex
        Ne_entry_to_vertex = cd_entry_to_vertex * _ELECTRONS_PER_GRAM

        n_e_vertex = density * _ELECTRONS_PER_GRAM

        sigma         = glashow_sigma_tau_total(initial_energy)
        dsigma_dy     = glashow_dsigma_dy_tau(initial_energy, y)
        dsigma_dEtau  = dsigma_dy / initial_energy

        pout = Coordinate(first(intersections).point.point + revd.point * distance, cs)
        final_state = Particle(TauMinus, e_tau, pout, d)

        # No Earth propagation modelled: close_state = initial_state.
        close_state = initial_state

        theta, phi = cart_to_sph(d)
        area = sum(visible_areas)
        point = GlashowInteractionPoint(
            initial_energy,
            e_tau,
            theta, phi,
            area,
            uconvert(u"g/cm^3", density),
            uconvert(u"g/cm^2", cd_cap),
            uconvert(u"cm^-3", n_e_vertex),
            uconvert(u"cm^-2", Ne_entry_to_vertex),
            uconvert(u"cm^2", sigma),
            uconvert(u"cm^2/GeV", dsigma_dEtau),
        )
        return initial_state, close_state, final_state, point
    catch e
        @warn "Runtime error during Glashow event injection, returning null result" exception=(e, catch_backtrace())
        return _create_null_neutrino_result(pdg, INJECTION_ERROR_RUNTIME, d, cs, T)
    end
end

# ---------------------------------------------------------------------------
# Top-level Glashow-injection loop
# ---------------------------------------------------------------------------

"""
    inject_glashow!(frames::TamboFrames, config::Dict; prefix::String="injection")

Inject ν̄_e (PDG -12) primaries that interact through the Glashow resonance
to produce τ⁻ leptons in the rock. Mirrors `inject_neutrinos!` but uses the
Glashow-specific event generator and does not load a CC cross-section table.

Required config keys: `nevent`, `gamma`, `emin`, `emax`, `thetamin`,
`thetamax`, `phimin`, `phimax`, `pinecone`. `pdg` (if present) must be -12.
"""
function inject_glashow!(
    frames::TamboFrames,
    config::Dict;
    prefix::String="injection"
)
    if haskey(config, "pdg") && Int(config["pdg"]) != Int(NuEBar)
        error("inject_glashow!: GlashowInjection requires pdg = -12 (ν̄_e); got $(config["pdg"]).")
    end
    config = merge(config, Dict("pdg" => Int(NuEBar)))

    g_frame, m_frame, q_frames = _setup_injection(frames, config, prefix, "inject_glashow!")
    d_frame = m_frame.d_frame

    prem            = g_frame["prem"]
    bvh             = g_frame["bvh"]
    cs              = g_frame["cs"]
    topography      = g_frame["topography"]
    detector_region = d_frame["detector_region"]

    pl = UnitfulPowerLawSampler(
        config["gamma"],
        config["emin"] * u"GeV",
        config["emax"] * u"GeV"
    )
    as = UniformAngularSampler(
        deg2rad(config["thetamin"]),
        deg2rad(config["thetamax"]),
        deg2rad(config["phimin"]),
        deg2rad(config["phimax"]),
    )
    detector_props = precompute_detector_properties(topography, detector_region)
    Random.seed!(config["pinecone"])

    @llama_showprogress "Injecting (Glashow)" for frame in q_frames
        istate, cstate, fstate, point = inject_glashow_event(
            prem, bvh, cs, detector_region, as, pl, detector_props
        )
        frame["$(prefix)_initial_state"] = istate
        if !isnan(cstate.energy)
            frame["$(prefix)_close_state"] = cstate
        end
        if !isnan(fstate.energy)
            frame["$(prefix)_final_state"] = fstate
        end
        point === nothing || (frame["phase_space_point"] = point)
    end
end
