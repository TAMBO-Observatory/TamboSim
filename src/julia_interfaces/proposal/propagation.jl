"""
    proposal_propagate(particle::Particle, prem, bvh::BVHTree, seed=nothing) -> Tuple

Propagates a particle through the Earth using the PROPOSAL.jl library.

# Arguments
- `particle::Particle`: The initial particle state.
- `prem`: PREM sphere layers for ray tracing.
- `bvh`: BVH acceleration structure over the topography mesh.
- `seed`: An optional seed for the random number generator.

# Returns
- A tuple: `(losses, continuous_e, secondaries, final_state)`. If the
  particle's forward trajectory crosses no medium — it has already exited
  all PREM layers and the topography mesh — nothing is propagated:
  `losses`/`secondaries` are empty, `continuous_e` is zero, and
  `final_state` is a null `Particle` (NaN energy).
"""
function proposal_propagate(
    particle::Particle{T},
    prem,
    bvh::BVHTree{T},
    seed=nothing
) where {T<:Real}

    if !is_proposal_available()
        error("PROPOSAL not available. Call init_proposal(config) first.")
    end

    # Set random seed if provided
    seed = isnothing(seed) ? rand(Int32) : Int32(mod(seed, typemax(Int32)))
    PP.set_random_seed(seed)

    losses, continuous_e, secondaries, final_state, _ =
        _run_proposal_segments(particle, prem, bvh)
    return losses, continuous_e, secondaries, final_state
end

"""
    _run_proposal_segments(particle, prem, bvh; max_distance=nothing)
        -> (losses, continuous_e, secondaries, final_state, stop_reason)

Step `particle` forward through the rock/air segments its trajectory crosses,
propagating each with the cached PROPOSAL propagator for the local medium.

If `max_distance` (a length) is given, propagation stops once the cumulative
propagated distance reaches it — the trajectory's detector-side box edge.
`stop_reason` is one of:

- `:decayed`      — PROPOSAL reported a decay; `secondaries` holds the products.
- `:reached_cap`  — hit `max_distance` without decaying (only when bounded).
- `:exited`       — traversed every segment to the trajectory exit without
                    decaying or hitting the cap.
- `:no_medium`    — the trajectory crossed no medium at all (empty segment list);
                    `final_state` is a null `Particle`.
"""
function _run_proposal_segments(
    particle::Particle{T},
    prem,
    bvh::BVHTree{T};
    max_distance::Union{Nothing,Quantity}=nothing,
    deep::Bool=false,
) where {T<:Real}
    cache = deep ? _deep_propagator_cache : _propagator_cache

    cs = particle.position.coordinate_system
    ray = Ray(particle)
    ixs = intersect_all(prem, bvh, ray)

    densities = compute_density(ixs, particle.direction)
    lengths = compute_lengths(ixs)
    lepton_id = Int(particle.pdg)

    losses = Particle{T}[]
    secondaries = Particle{T}[]
    current_e = particle.energy
    continuous_e = 0.0u"GeV"
    accrued_d = 0.0u"m"
    accrued_t = particle.time

    # Null particle by default. If `ixs` is empty (particle already in air),
    # the loop below never runs and we signal a culled event via NaN energy.
    final_state = Particle(T)
    stop_reason = :no_medium   # no segments crossed (loop body never runs)

    for (l, density) in zip(lengths, densities)
        # Under a distance cap, the box edge may fall inside this segment.
        seg_len = l
        capped_here = false
        if max_distance !== nothing
            remaining = max_distance - accrued_d
            if remaining <= 0.0u"m"
                stop_reason = :reached_cap
                break
            end
            if remaining <= l
                seg_len = remaining
                capped_here = true
            end
        end

        medium = density > 1u"g/cm^3" ? "StandardRock" : "Air"

        propagator = cache[(lepton_id, medium)]

        # Create PROPOSAL particle state
        # PROPOSAL uses MeV for energy and cm for distance
        particle_type = pdg_to_proposal_type(lepton_id)
        dir = particle.direction.point
        state = PP.ParticleState(
            particle_type,
            0.0, 0.0, 0.0,      # position (cm)
            dir[1], dir[2], dir[3],  # direction
            ustrip(current_e |> u"MeV");  # energy (MeV)
            time=0.0,
            propagated_distance=0.0
        )

        # Propagate through this segment
        max_dist_cm = ustrip(seg_len |> u"cm")
        propped_result = PP.propagate(propagator, state; max_distance=max_dist_cm, min_energy=0.0)

        # Get final state
        pp_final_state = PP.get_final_state(propped_result)
        current_e = PP.get_energy(pp_final_state) * u"MeV"

        # Process stochastic losses
        n_stochastic = PP.get_stochastic_losses_count(propped_result)
        for i in 0:(n_stochastic - 1)
            loss = PP.get_stochastic_loss_at(propped_result, i)

            int_type = PP.get_type(loss)
            loss_e = PP.get_energy(loss) * u"MeV"
            prop_dist = PP.get_propagated_distance(loss) * u"cm"
            loss_time = PP.get_time(loss) * u"s"

            dist = accrued_d + prop_dist
            loss_t = accrued_t + T(ustrip(loss_time |> u"s")) * u"s"
            p = dist * particle.direction + particle.position

            pp_dir = PP.get_direction(loss)
            dir_vec = [PP.get_x(pp_dir), PP.get_y(pp_dir), PP.get_z(pp_dir)]
            dir = Direction(dir_vec, cs)

            l_particle = Particle(ParticleType(int_type), loss_e, p, dir, loss_t)
            push!(losses, l_particle)
        end

        # Get continuous energy loss directly from PROPOSAL
        continuous_e += PP.get_total_continuous_energy_loss(propped_result) * u"MeV"

        # Update final state
        final_dist = accrued_d + PP.get_propagated_distance(pp_final_state) * u"cm"
        final_t = accrued_t + T(PP.get_time(pp_final_state)) * u"s"
        p = final_dist * particle.direction + particle.position
        final_state = Particle(ParticleType(lepton_id), current_e, p, particle.direction, final_t)

        # Extract decay products if PROPOSAL reports a decay
        if PP.has_decay(propped_result)
            max_products = 10
            types_arr = zeros(Int32, max_products)
            energies_arr = zeros(Float64, max_products)
            dx_arr = zeros(Float64, max_products)
            dy_arr = zeros(Float64, max_products)
            dz_arr = zeros(Float64, max_products)

            n_products = PP.get_decay_products_to_array(
                propped_result, types_arr, energies_arr,
                dx_arr, dy_arr, dz_arr
            )

            for j in 1:n_products
                dp_dir = Direction([dx_arr[j], dy_arr[j], dz_arr[j]], cs)
                dp = Particle(
                    ParticleType(types_arr[j]),
                    energies_arr[j] * u"MeV",
                    final_state.position,
                    dp_dir,
                    final_state.time
                )
                push!(secondaries, dp)
            end
            stop_reason = :decayed
            break
        end

        accrued_d = final_dist
        accrued_t = final_t

        if capped_here
            stop_reason = :reached_cap
            break
        end

        stop_reason = :exited   # a full segment traversed; loop completion => exhaustion
    end

    return losses, continuous_e, secondaries, final_state, stop_reason
end

"""
    proposal_propagation!(
        frames::TamboFrames,
        config::Dict;
        prefix::String="proposal",
        inkey::String="injection_final_state"
    )

Propagate the leptons produced by `inject!` through PREM + topography
using PROPOSAL. Mutates `frames` by snapshotting `config` onto the
existing M frame under `prefix`, then iterating over Q frames that
contain `inkey` and writing four new keys per event:

- `<prefix>_stochastic_losses`   — `Vector{Particle}` of discrete losses
  (bremsstrahlung, pair-production, hadronic, decay-tagged).
- `<prefix>_continuous_losses`   — total continuous (ionization) energy.
- `<prefix>_decay_products`      — `Vector{Particle}` of daughters from
  decay; empty if the lepton ranged out without decaying.
- `<prefix>_final_state`         — the lepton at the end of its tracked
  path (decay vertex or trajectory exit).

# Arguments
- `frames::TamboFrames`: must already have an M frame (run `inject!`
  first).
- `config::Dict`: parsed `[proposal]` TOML table. Consults
  `"seed"` (RNG seed) and any cross-section / parametrization
  settings that `init_proposal` knows about.

# Keyword arguments
- `prefix::String`: namespace for the config snapshot and per-Q-frame
  output keys. Default `"proposal"`.
- `inkey::String`: which Q-frame key carries the input lepton state.
  Default `"injection_final_state"`.

Q frames whose `inkey` particle has total energy at or below the
particle's rest energy (`particle_mass(pdg) * c²`) are skipped with a
warning: PROPOSAL requires kinetic energy > 0. The threshold is
per-PDG, so the same call can correctly handle electron, muon, and
tau injections.

Q frames whose lepton's forward trajectory crosses no medium — it has
already exited all PREM layers and the topography mesh (e.g. a very
high-energy near-horizontal event whose forced interaction vertex lands
off the mesh / above the atmosphere) — are likewise skipped, leaving no
`<prefix>_*` keys, so downstream stages drop them.
"""
function proposal_propagation!(
    frames::TamboFrames,
    config::Dict;
    prefix::String="proposal",
    inkey::String="injection_final_state"
)
    m_frame = _get_last_frame(frames, 'M')
    g_frame = m_frame.g_frame

    m_frame[prefix] = config
    init_proposal(config)

    prem = g_frame["prem"]
    bvh  = g_frame["bvh"]

    if !haskey(config, "seed")
        @warn "Deciding seed via RNG and adding to configuration"
        config["seed"] = rand(UInt32)
    end
    Random.seed!(config["seed"])

    q_frames = filter(f -> f.stream == 'Q', frames)

    @llama_showprogress "Propagating" for frame in q_frames
        haskey(frame, inkey) || continue
        final_state = frame[inkey]
        rest_energy = particle_mass(final_state.pdg) * speedoflight^2
        if final_state.energy <= rest_energy
            @warn "Skipping Q frame: $(final_state.pdg) energy $(final_state.energy) ≤ rest energy $(rest_energy)" maxlog=5
            continue
        end
        ls, contls, decay_products, propped_state = proposal_propagate(
            final_state, prem, bvh, rand(Int32)
        )
        # Lepton exited all media without propagating (vertex landed off-mesh /
        # above the atmosphere). Drop the event: leave no `proposal_*` keys so
        # downstream stages skip it via the missing-key convention.
        isnan(propped_state.energy) && continue
        frame["$(prefix)_stochastic_losses"] = ls
        frame["$(prefix)_continuous_losses"] = contls
        frame["$(prefix)_decay_products"] = decay_products
        frame["$(prefix)_final_state"] = propped_state
    end
end
