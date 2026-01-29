"""
    proposal_propagate(particle::Particle, earth::Earth, seed=nothing) -> Tuple

Propagates a particle through the Earth using the PROPOSAL.jl library.

The function calculates the particle's path and the densities it encounters. It then propagates
the particle through these segments, collecting information about stochastic losses, continuous
energy loss, and decay products.

# Arguments
- `particle::Particle`: The initial particle state.
- `earth::Earth`: The Earth model.
- `seed`: An optional seed for the random number generator.

# Returns
- A tuple containing:
    - `losses`: A vector of `Particle` objects representing stochastic losses.
    - `continuous_e`: The total continuous energy loss.
    - `secondaries`: A vector of `Particle` objects representing decay products.
    - `final_state`: The final `Particle` state after propagation.
"""
function proposal_propagate(
    particle::Particle{T},
    earth::Earth{T},
    seed=nothing
) where {T<:Real}

    if !is_proposal_available()
        error("PROPOSAL not available. Call init_proposal(config) first.")
    end

    cs = CoordinateSystem(earth)
    ray = Ray(particle)
    ixs = intersect_all(earth, ray)

    # Set random seed if provided
    seed = isnothing(seed) ? rand(Int32) : Int32(mod(seed, typemax(Int32)))
    PP.set_random_seed(seed)

    densities = compute_density(ixs, particle.direction)
    lengths = compute_lengths(ixs)
    lepton_id = Int(particle.pdg)

    losses = Particle{T}[]
    secondaries = Particle{T}[]
    current_e = particle.energy
    continuous_e = 0.0u"GeV"
    accrued_d = 0.0u"m"
    accrued_t = particle.time
    final_state = nothing

    for (l, density) in zip(lengths, densities)
        medium = density > 1u"g/cm^3" ? "StandardRock" : "Air"

        propagator = _propagator_cache[(lepton_id, medium)]

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
        max_distance = ustrip(l |> u"cm")
        propped_result = PP.propagate(propagator, state; max_distance=max_distance, min_energy=0.0)

        # Get final state
        pp_final_state = PP.get_final_state(propped_result)
        current_e = PP.get_energy(pp_final_state) * u"MeV"

        # Process track for stochastic losses
        track_length = PP.get_track_length(propped_result)
        stochastic_loss_total = 0.0u"MeV"
        for i in 1:track_length
            track_state = PP.track_state_at(propped_result, i - 1)  # 0-indexed

            # Get interaction type and energy
            int_type = PP.get_type(track_state)
            loss_e = PP.get_energy(track_state) * u"MeV"
            stochastic_loss_total += loss_e
            prop_dist = PP.get_propagated_distance(track_state) * u"cm"
            loss_time = PP.get_time(track_state) * u"s"

            dist = accrued_d + prop_dist
            loss_t = accrued_t + T(ustrip(loss_time)) * u"s"
            p = dist * particle.direction + particle.position

            # Get direction from track state
            pp_dir = PP.get_direction(track_state)
            dir_vec = [PP.get_x(pp_dir), PP.get_y(pp_dir), PP.get_z(pp_dir)]
            dir = Direction(dir_vec, cs)

            l_particle = Particle(ParticleType(int_type), loss_e, p, dir, loss_t)
            push!(losses, l_particle)
        end

        # Compute continuous energy loss: initial - final - stochastic
        segment_initial_e = PP.get_energy(state) * u"MeV"
        continuous_e += segment_initial_e - current_e - stochastic_loss_total

        # Update final state
        final_dist = accrued_d + PP.get_propagated_distance(pp_final_state) * u"cm"
        final_t = accrued_t + T(PP.get_time(pp_final_state)) * u"s"
        p = final_dist * particle.direction + particle.position
        final_state = Particle(ParticleType(lepton_id), current_e, p, particle.direction, final_t)

        # Check for decay: particle stopped before reaching max_distance with energy remaining
        pp_prop_dist = PP.get_propagated_distance(pp_final_state)
        if pp_prop_dist < max_distance && ustrip(current_e |> u"MeV") > 0.0
            # Particle decayed — no decay product info available from this API
            break
        end

        accrued_d += PP.get_propagated_distance(pp_final_state) * u"cm"
        accrued_t += T(PP.get_time(pp_final_state)) * u"s"
    end

    return losses, continuous_e, secondaries, final_state
end
